"""Testes do check-workflows.py, do sensitive_paths.py e dos passos do ci.yml."""

import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(ROOT, "scripts", "lib"))
import sensitive_paths as sp  # noqa: E402

spec = importlib.util.spec_from_file_location("check_workflows", os.path.join(ROOT, "scripts", "check-workflows.py"))
cw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cw)

GOOD = """name: "Issues · Auto-label"
run-name: "Issues · #1"
on:
  issues:
    types: [opened]
permissions: {}
concurrency:
  group: x
jobs:
  label:
    name: "Auto-label"
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - name: "Hi"
        run: echo hi
"""


class WorkflowTests(unittest.TestCase):
    def write(self, name, text):
        d = tempfile.mkdtemp()
        path = os.path.join(d, name)
        open(path, "w").write(text)
        return path

    def test_method_workflows_follow_the_standard(self):
        # Only the method workflows. A project's deploy file is not the example.
        wf = os.path.join(ROOT, ".github", "workflows")
        for name in ("ci.yml", "issues-label.yml"):
            self.assertEqual(cw.check(os.path.join(wf, name)), [], name)

    DEPLOY = """# deploy-paths: app/
name: "Deploy · App"
run-name: "Deploy · App"
on:
  workflow_dispatch:
permissions: {}
concurrency:
  group: x
jobs:
  validate:
    name: "Validate main"
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - name: "Lint and tests"
        run: scripts/validate.sh
  build:
    name: "Build"
    needs: validate
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - name: "Build"
        run: echo build
  deploy:
    name: "Deploy"
    needs: build
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - name: "Deploy"
        run: echo deploy
"""

    def deploy_problems(self, text):
        return "\n".join(cw.check(self.write("deploy-app.yml", text)))

    def test_deploy_good(self):
        self.assertEqual(self.deploy_problems(self.DEPLOY), "")

    def test_deploy_only_on_workflow_dispatch(self):
        for trigger in ("pull_request", "push", "schedule"):
            body = "\n    - cron: '0 3 * * *'" if trigger == "schedule" else ""
            text = self.DEPLOY.replace("  workflow_dispatch:\n", "  workflow_dispatch:\n  %s:%s\n" % (trigger, body))
            self.assertIn("deploy workflow must run only on workflow_dispatch (got %s)" % trigger,
                          self.deploy_problems(text), trigger)
        self.assertIn("must run on workflow_dispatch",
                      self.deploy_problems(self.DEPLOY.replace("  workflow_dispatch:\n", "  push:\n")))

    def test_deploy_validates_main_before_the_build(self):
        no_validate = self.DEPLOY.replace("run: scripts/validate.sh", "run: echo skip")
        self.assertIn("needs a job that runs scripts/validate.sh", self.deploy_problems(no_validate))
        loose_build = self.DEPLOY.replace("    needs: validate\n", "")
        problems = self.deploy_problems(loose_build)
        self.assertIn("job build: must need the job that runs scripts/validate.sh", problems)
        self.assertIn("job deploy: must need", problems)

    def test_deploy_declares_its_paths(self):
        self.assertIn("deploy-paths", self.deploy_problems(self.DEPLOY.replace("# deploy-paths: app/\n", "")))

    def test_deploy_may_skip_a_suite_that_ci_already_ran(self):
        gated = self.DEPLOY.replace(
            '        run: scripts/validate.sh\n',
            '        run: scripts/ci-already-green.sh\n'
            '      - name: "Lint and tests"\n'
            '        if: steps.gate.outputs.skip != \'true\'\n'
            '        run: scripts/validate.sh\n')
        self.assertEqual(self.deploy_problems(gated), "")

    def test_good(self):
        self.assertEqual(cw.check(self.write("issues-label.yml", GOOD)), [])

    def test_bad_fixture_reports_everything(self):
        problems = "\n".join(cw.check(os.path.join(HERE, "fixtures", "workflows", "bad-name.yml")))
        for part in ("file name", "missing top-level name", "run-name", "concurrency",
                     "permissions must be {}", "push trigger", "missing name", "timeout-minutes", "step 1"):
            self.assertIn(part, problems)

    def test_ci_only_on_pull_request(self):
        # ci.yml runs on pull_request and on push to main, nothing else.
        both = GOOD.replace("issues:\n    types: [opened]", "pull_request:\n  push:\n    branches: [main]")
        self.assertEqual(cw.check(self.write("ci.yml", both)), [])
        for extra in ("schedule:\n    - cron: '0 3 * * *'", "workflow_dispatch:"):
            text = both + "\n" if False else both.replace("  push:\n", "  %s\n  push:\n" % extra)
            problems = "\n".join(cw.check(self.write("ci.yml", text)))
            self.assertIn("ci.yml must run only on pull_request and push to main", problems, extra)
        problems = "\n".join(cw.check(self.write("ci.yml", both.replace("[main]", "[dev]"))))
        self.assertIn("ci.yml must run on push only to main", problems)
        problems = "\n".join(cw.check(self.write("ci.yml", GOOD.replace("issues:\n    types: [opened]", "pull_request:"))))
        self.assertIn("ci.yml must run only on pull_request and push to main", problems)

    def test_recorded_pr_only_mode(self):
        # .github/ci-mode = pr records CI on pull requests only. Push is refused.
        # Without that record, pull_request alone stays invalid (public default).
        d = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, d, True)
        os.makedirs(os.path.join(d, ".github", "workflows"))
        mode = os.path.join(d, ".github", "ci-mode")
        path = os.path.join(d, ".github", "workflows", "ci.yml")
        only_pr = GOOD.replace("issues:\n    types: [opened]", "pull_request:")
        both = GOOD.replace("issues:\n    types: [opened]", "pull_request:\n  push:\n    branches: [main]")
        open(path, "w").write(only_pr)
        self.assertIn("pull_request and push to main", "\n".join(cw.check(path)))
        open(mode, "w").write("pr\n")
        self.assertEqual(cw.check(path), [], "pr-only ci.yml")
        open(path, "w").write(both)
        problems = "\n".join(cw.check(path))
        self.assertIn("pr-only mode must run only on pull_request", problems)
        self.assertIn("no push", problems)

    def test_ci_mode_does_not_escape_the_repository(self):
        d = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, d, True)
        os.makedirs(os.path.join(d, "outer", ".github"))
        open(os.path.join(d, "outer", ".github", "ci-mode"), "w").write("pr\n")
        repo = os.path.join(d, "outer", "repo")
        os.makedirs(os.path.join(repo, ".github", "workflows"))
        os.makedirs(os.path.join(repo, ".git"))
        path = os.path.join(repo, ".github", "workflows", "ci.yml")
        open(path, "w").write(GOOD.replace("issues:\n    types: [opened]", "pull_request:"))
        self.assertIn("pull_request and push to main", "\n".join(cw.check(path)))

    def test_timeout_bounds(self):
        problems = "\n".join(cw.check(self.write("issues-x.yml", GOOD.replace("timeout-minutes: 5", "timeout-minutes: 60"))))
        self.assertIn("timeout-minutes must be 5-30", problems)


class SensitivePathsTests(unittest.TestCase):
    def test_repo_globs(self):
        globs = sp.load_globs(os.path.join(ROOT, ".github", "sensitive-paths"))
        paths = ["src/auth/login.py", "auth/x.py", "db/migrations/001.sql", ".env", ".env.local",
                 "web/package-lock.json", "package-lock.json", "app/billing/api.ts",
                 "README.md", "scripts/setup-repo.sh", "docs/auth.md", "authors.txt"]
        hits = sp.sensitive(paths, globs)
        self.assertEqual(hits, paths[:8] + ["scripts/setup-repo.sh"])

    def test_gate_files_sensitive(self):
        globs = sp.load_globs(os.path.join(ROOT, ".github", "sensitive-paths"))
        paths = [".github/workflows/deploy-example.yml", "scripts/close-phase.sh", "scripts/status.sh"]
        self.assertEqual(sp.sensitive(paths, globs), paths[:2])

    def test_gate_verifiers_sensitive(self):
        # A PR that changes the CI workflow, a verifier of the gate or the list
        # itself needs the owner's ok (check-docs.sh, read from the base by the
        # policy job, is one of them).
        globs = sp.load_globs(os.path.join(ROOT, ".github", "sensitive-paths"))
        paths = [".github/workflows/ci.yml", "scripts/ci-gate.sh", "scripts/check-attribution.sh",
                 "scripts/check-docs.sh", "scripts/lib/sensitive_paths.py", ".github/sensitive-paths"]
        self.assertEqual(sp.sensitive(paths, globs), paths)
        for rel in paths:
            self.assertTrue(os.path.isfile(os.path.join(ROOT, rel)), rel)

    def test_classes_of_the_list(self):
        # owner-ok: migrations, secrets, auth, billing and the like. gate: dependencies,
        # deploy workflows and the gate itself. A list with no class header is all owner-ok.
        globs = os.path.join(ROOT, ".github", "sensitive-paths")
        owner = [".env", "db/migrations/1.sql", "x/secrets/k", "x/credentials/k", "app/auth/a.py",
                 "app/billing/b.py", "app/payments/p.py", "infra/production/m.tf", "scripts/setup-repo.sh"]
        gate = ["package-lock.json", "uv.lock", "requirements-dev.txt", ".github/workflows/deploy-x.yml",
                ".github/workflows/ci.yml", "scripts/ci-gate.sh", "scripts/check-attribution.sh",
                "scripts/check-docs.sh", "scripts/close-phase.sh", "scripts/lib/sensitive_paths.py",
                ".github/sensitive-paths"]
        paths = owner + gate + ["README.md"]
        self.assertEqual(sp.sensitive_class(paths, globs, "owner-ok"), owner)
        self.assertEqual(sp.sensitive_class(paths, globs, "gate"), gate)
        d = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, d, True)
        old = os.path.join(d, "old")
        open(old, "w").write("**/auth/**\nscripts/close-phase.sh\n")
        # The method's gate paths are gate by code, even in an old single-class list (FHDumont/ai-engineering-team-template#207).
        self.assertEqual(sp.sensitive_class(["a/auth/x", "scripts/close-phase.sh", "package-lock.json"], old, "owner-ok"),
                         ["a/auth/x"])
        self.assertEqual(sp.sensitive_class(["a/auth/x", "scripts/close-phase.sh", "package-lock.json"], old, "gate"),
                         ["scripts/close-phase.sh", "package-lock.json"])
        # A path in both classes is owner-ok (the stricter one).
        both = os.path.join(d, "both")
        open(both, "w").write("# class: gate\nx/**\n# class: owner-ok\nx/y\n")
        self.assertEqual(sp.sensitive_class(["x/y", "x/z"], both, "owner-ok"), ["x/y"])
        self.assertEqual(sp.sensitive_class(["x/y", "x/z"], both, "gate"), ["x/z"])

    def test_cli_lists_by_class_and_reads_lines_or_nul(self):
        script = os.path.join(ROOT, "scripts", "lib", "sensitive_paths.py")
        globs = os.path.join(ROOT, ".github", "sensitive-paths")
        def run(stdin, cls=None):
            env = dict(os.environ)
            env.pop("SENSITIVE_CLASS", None)
            if cls:
                env["SENSITIVE_CLASS"] = cls
            return subprocess.run(["python3", script, globs], input=stdin, text=True, capture_output=True,
                                  env=env, cwd=ROOT).stdout.split()
        lines = ".env\nscripts/close-phase.sh\nREADME.md\n"
        self.assertEqual(run(lines), [".env", "scripts/close-phase.sh"])
        self.assertEqual(run(lines, "owner-ok"), [".env"])
        self.assertEqual(run(lines, "gate"), ["scripts/close-phase.sh"])
        self.assertEqual(run(lines.replace("\n", "\0"), "gate"), ["scripts/close-phase.sh"])

    def test_double_star(self):
        r = sp.glob_to_regex("**/auth/**")
        self.assertTrue(r.match("a/b/auth/c/d"))
        self.assertFalse(r.match("a/authx/c"))

    def test_method_paths_in_code(self):
        paths = [".claude/hooks/block-dangerous-git.sh", ".claude/settings.json",
                 ".githooks/pre-push", ".github/actions/x/action.yml",
                 "scripts/lib/procs.sh", "scripts/sessions.sh",
                 "scripts/start-headless.sh", "scripts/setup-repo.sh", "README.md"]
        hits = sp.sensitive(paths, [])
        self.assertEqual(hits, paths[:-1])

    def test_repo_file_only_adds(self):
        hits = sp.sensitive(["app/custom/secret.txt", "README.md"], ["app/custom/**"])
        self.assertEqual(hits, ["app/custom/secret.txt"])
        hits = sp.sensitive(["scripts/setup-repo.sh", "app/custom/secret.txt"], ["app/custom/**"])
        self.assertEqual(hits, ["scripts/setup-repo.sh", "app/custom/secret.txt"])

    def test_write_token_workflow_is_sensitive(self):
        d = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, d, True)
        os.makedirs(os.path.join(d, ".github", "workflows"))
        open(os.path.join(d, ".github", "workflows", "write.yml"), "w").write(
            "on: push\njobs:\n  x:\n    permissions:\n      issues: write\n")
        open(os.path.join(d, ".github", "workflows", "read.yml"), "w").write(
            "on: push\njobs:\n  x:\n    permissions:\n      contents: read\n")
        paths = [".github/workflows/write.yml", ".github/workflows/read.yml"]
        self.assertEqual(sp.sensitive(paths, [], root=d), [".github/workflows/write.yml"])
        self.assertIn(".github/workflows/ci.yml",
                      sp.sensitive([".github/workflows/ci.yml"], [], root=ROOT))
        self.assertIn(".github/workflows/issues-label.yml",
                      sp.sensitive([".github/workflows/issues-label.yml"], [], root=ROOT))



def ci_step(job, name):
    """The step <name> of the job <job> of the repo's ci.yml."""
    wf = cw.load(os.path.join(ROOT, ".github", "workflows", "ci.yml"))
    return next(s for s in wf["jobs"][job]["steps"] if s["name"] == name)


def ci_mode():
    """What .github/ci-mode of this repo records: push (default) or pr."""
    try:
        return open(os.path.join(ROOT, ".github", "ci-mode"), encoding="utf-8").read().strip() or "push"
    except OSError:
        return "push"


def app_filter_sample():
    """A path the app filter of this repo's ci.yml matches, read from the filter itself."""
    text = open(os.path.join(ROOT, ".github", "workflows", "ci.yml"), encoding="utf-8").read()
    m = re.search(r"echo \"app=\$\(has '\^\(([^)]*)\)'\)\"", text)
    first = m.group(1).split("|")[0].replace("\\.", ".")
    return first + ("README.md" if first.endswith("/") else "")


def git(repo, *args):
    return subprocess.run(["git", "-C", repo] + list(args), check=True, text=True,
                          capture_output=True).stdout.strip()


class CiStepsTests(unittest.TestCase):
    """Runs the real steps of ci.yml in a temporary repo."""

    def setUp(self):
        self.tmp = os.path.realpath(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.repo = os.path.join(self.tmp, "repo")
        os.makedirs(self.repo)
        git(self.repo, "init", "--quiet", "-b", "main")
        for key, value in (("user.email", "t@example.org"), ("user.name", "t"),
                           ("commit.gpgsign", "false"), ("core.quotepath", "true")):
            git(self.repo, "config", key, value)
        # The base has the verifiers of this checkout.
        for rel in ("scripts/lib/sensitive_paths.py", ".github/sensitive-paths"):
            os.makedirs(os.path.dirname(os.path.join(self.repo, rel)), exist_ok=True)
            shutil.copy(os.path.join(ROOT, rel), os.path.join(self.repo, rel))
        git(self.repo, "add", "scripts", ".github")
        git(self.repo, "commit", "--quiet", "-m", "chore: seed")
        self.base = git(self.repo, "rev-parse", "HEAD")
        git(self.repo, "switch", "--quiet", "-c", "feat/x")

    def commit(self, files):
        for rel, text in files.items():
            path = os.path.join(self.repo, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, "w").write(text)
            git(self.repo, "add", rel)
        git(self.repo, "commit", "--quiet", "-m", "feat: change")
        return git(self.repo, "rev-parse", "HEAD")

    def run_step(self, job, name, head, extra_env=None):
        env = dict(os.environ)
        env.update(BASE_SHA=self.base, HEAD_SHA=head, RUNNER_TEMP=self.tmp,
                   GITHUB_OUTPUT=os.path.join(self.tmp, "output"), GITHUB_REPOSITORY="owner/repo",
                   PR_NUMBER="7")
        env.update(extra_env or {})
        open(env["GITHUB_OUTPUT"], "w").close()
        return subprocess.run(["bash", "-eo", "pipefail", "-c", ci_step(job, name)["run"]], cwd=self.repo,
                              env=env, text=True, capture_output=True)

    def detect(self, files):
        head = self.commit(files)
        r = self.run_step("changes", "Detect changed paths", head)
        self.assertEqual(r.returncode, 0, r.stderr)
        return dict(l.split("=", 1) for l in open(os.path.join(self.tmp, "output")).read().split())

    def test_filter_is_by_exclusion(self):
        # A file outside every known folder is code: lint and tests run.
        for rel in ("lib/util.py", "Makefile", "tools/x.sh", ".claude/agents/a.yml", ".github/sensitive-paths"):
            out = self.detect({rel: "x\n"})
            self.assertEqual((out["code"], out["docs_only"]), ("true", "false"), rel)

    def test_filter_docs_only(self):
        out = self.detect({"docs/x.md": "x\n", "README.md": "x\n"})
        self.assertEqual((out["code"], out["docs_only"], out["app"]), ("false", "true", "false"))

    def test_tests_skip_only_for_inert_docs(self):
        # Generated docs, specs, CHANGELOG.md, ROADMAP.md and the docs/ pages skip the
        # tests job; what the tests read (AGENTS.md, CLAUDE.md, the design, skills, scripts) never does.
        out = self.detect({"docs/x.md": "x\n", "docs/specs/s.md": "x\n", "README.md": "x\n"})
        self.assertEqual((out["code"], out["run_tests"]), ("false", "false"))
        for rel in ("AGENTS.md", "CLAUDE.md", "docs/process-design.md", ".claude/skills/plan/SKILL.md",
                    "scripts/x.sh", "app/README.md"):
            self.assertEqual(self.detect({rel: "x\n"})["run_tests"], "true", rel)

    def test_generated_docs_run_the_tests(self):
        # #54 made these two run the suite because a text test read issue titles out of
        # them. That test now excludes the files (#137), so each file alone is inert.
        for rel in ("ROADMAP.md", "CHANGELOG.md"):
            self.setUp()
            out = self.detect({rel: "x\n"})
            self.assertEqual((out["code"], out["run_tests"]), ("false", "false"), rel)

    def test_generated_docs_do_not_run_the_tests(self):
        # #137: no test reads the generated files, so a PR of only those two does not
        # run the suite. Policy still runs, because it is a pull request.
        for rel in ("ROADMAP.md", "CHANGELOG.md"):
            self.setUp()
            out = self.detect({rel: "x\n"})
            self.assertEqual((out["code"], out["run_tests"]), ("false", "false"), rel)
        wf = cw.load(os.path.join(ROOT, ".github", "workflows", "ci.yml"))
        self.assertEqual(wf["jobs"]["policy"]["if"], "github.event_name == 'pull_request'")
        self.assertNotIn("paths-ignore", wf["on"]["pull_request"])

    def test_suite_does_not_depend_on_generated_doc_content(self):
        # #137: reading CHANGELOG.md or ROADMAP.md of this checkout would bring #54 back.
        # A fixture written in a temporary repo does not count.
        bad = []
        for base in (os.path.join(ROOT, "scripts", "tests"),
                     os.path.join(ROOT, ".claude", "hooks", "tests")):
            if not os.path.isdir(base):
                continue
            for dirpath, _, names in os.walk(base):
                for name in names:
                    if not name.endswith((".sh", ".py")):
                        continue
                    path = os.path.join(dirpath, name)
                    with open(path, encoding="utf-8") as fh:
                        text = fh.read()
                    needles = (
                        "open(os.path.join(ROOT, " + '"CHANGELOG.md")',
                        "open(os.path.join(ROOT, " + '"ROADMAP.md")',
                        "$REPO/" + "CHANGELOG.md",
                        "$REPO/" + "ROADMAP.md",
                    )
                    if any(n in text for n in needles):
                        bad.append(os.path.relpath(path, ROOT))
        self.assertEqual(bad, [])

    def test_tests_skip_when_code_already_tested(self):
        # A docs-only push on top of a commit whose Tests passed does not run the suite again.
        first = self.commit({"scripts/x.sh": "x\n"})
        head = self.commit({"docs/x.md": "x\n"})
        fake = os.path.join(self.tmp, "bin")
        os.makedirs(fake)
        gh = os.path.join(fake, "gh")
        open(gh, "w").write('''#!/bin/sh
if echo "$*" | grep -q "commits/%s/check-runs"; then
  if [ "$GH_TESTS" = 1 ]; then
    printf '{"check_runs":[{"name":"Tests","status":"completed","conclusion":"success","started_at":"2020-01-01T00:00:00Z"}]}\\n'
  else
    printf '{"check_runs":[]}\\n'
  fi
else
  printf '{"check_runs":[]}\\n'
fi
''' % first)
        os.chmod(gh, 0o755)
        env = {"PATH": fake + os.pathsep + os.environ["PATH"]}
        for passed, want in (("1", "false"), ("0", "true")):
            r = self.run_step("changes", "Detect changed paths", head, dict(env, GH_TESTS=passed))
            self.assertEqual(r.returncode, 0, r.stderr)
            out = dict(l.split("=", 1) for l in open(os.path.join(self.tmp, "output")).read().split())
            self.assertEqual(out["run_tests"], want, passed)
        # Code changed after the tested commit: the suite runs, whatever the check says.
        head2 = self.commit({"scripts/y.sh": "y\n"})
        r = self.run_step("changes", "Detect changed paths", head2, dict(env, GH_TESTS="1"))
        out = dict(l.split("=", 1) for l in open(os.path.join(self.tmp, "output")).read().split())
        self.assertEqual(out["run_tests"], "true")

    def write_gh_conclusions(self, mapping, extra=""):
        """Fake gh: mapping of commit SHA to Tests conclusion (or 'apierr')."""
        fake = os.path.join(self.tmp, "binconc")
        os.makedirs(fake, exist_ok=True)
        gh = os.path.join(fake, "gh")
        clauses = []
        for sha, conc in mapping.items():
            if conc == "apierr":
                clauses.append('  *"commits/%s/check-runs"*) echo "api failed" >&2; exit 1 ;;' % sha)
            elif conc == "pending":
                body = '{"check_runs":[{"name":"Tests","status":"in_progress","conclusion":null,"started_at":"2020-01-01T00:00:00Z"}]}'
                clauses.append('  *"commits/%s/check-runs"*) body=\'%s\' ;;' % (sha, body))
            else:
                body = '{"check_runs":[{"name":"Tests","status":"completed","conclusion":"%s","started_at":"2020-01-01T00:00:00Z"}]}' % conc
                clauses.append('  *"commits/%s/check-runs"*) body=\'%s\' ;;' % (sha, body))
        open(gh, "w").write("""#!/bin/sh
body='{"check_runs":[]}'
case "$*" in
%s
  *) body='{"check_runs":[]}' ;;
esac
jq_expr=""
prev=""
for a in "$@"; do
  [ "$prev" = --jq ] && jq_expr="$a"
  prev="$a"
done
if [ -n "$jq_expr" ]; then printf '%%s\\n' "$body" | jq -r "$jq_expr"; else printf '%%s\\n' "$body"; fi
%s
""" % ("\n".join(clauses), extra))
        os.chmod(gh, 0o755)
        return {"PATH": fake + os.pathsep + os.environ["PATH"]}

    def test_tests_run_when_newer_tests_failed(self):
        # A green, B red, C docs-only: the newest Tests result is a failure, so run.
        a = self.commit({"scripts/x.sh": "x\n"})
        b = self.commit({"docs/a.md": "a\n"})
        c = self.commit({"docs/b.md": "b\n"})
        env = self.write_gh_conclusions({a: "success", b: "failure"})
        r = self.run_step("changes", "Detect changed paths", c, env)
        self.assertEqual(r.returncode, 0, r.stderr)
        out = dict(l.split("=", 1) for l in open(os.path.join(self.tmp, "output")).read().split())
        self.assertEqual(out["run_tests"], "true")

    def write_gh_runs(self, mapping):
        """Fake gh: sha to a list of Tests check runs (raw JSON; the step runs jq)."""
        fake = os.path.join(self.tmp, "binruns")
        os.makedirs(fake, exist_ok=True)
        gh = os.path.join(fake, "gh")
        clauses = []
        for sha, runs in mapping.items():
            if runs == "apierr":
                clauses.append('  *"commits/%s/check-runs"*) echo "api failed" >&2; exit 1 ;;' % sha)
            else:
                body = json.dumps({"check_runs": runs})
                clauses.append('  *"commits/%s/check-runs"*) body=%s ;;' % (sha, json.dumps(body)))
        open(gh, "w").write("""#!/bin/sh
body='{"check_runs":[]}'
case "$*" in
%s
  *) body='{"check_runs":[]}' ;;
esac
printf '%%s\\n' "$body"
""" % "\n".join(clauses))
        os.chmod(gh, 0o755)
        return {"PATH": fake + os.pathsep + os.environ["PATH"]}

    def test_newer_pending_run_is_not_hidden_by_an_older_success(self):
        # The newest run on the newer commit is still pending (no started_at). An older
        # success on that same commit must not cover it.
        a = self.commit({"scripts/x.sh": "x\n"})
        b = self.commit({"docs/a.md": "a\n"})
        c = self.commit({"docs/b.md": "b\n"})
        env = self.write_gh_runs({
            a: [{"name": "Tests", "id": 1, "status": "completed", "conclusion": "success",
                 "started_at": "2020-01-01T00:00:00Z", "app": {"slug": "github-actions"}}],
            b: [
                {"name": "Tests", "id": 1, "status": "completed", "conclusion": "success",
                 "started_at": "2020-01-02T00:00:00Z", "app": {"slug": "github-actions"}},
                {"name": "Tests", "id": 2, "status": "in_progress", "conclusion": None,
                 "started_at": None, "app": {"slug": "github-actions"}},
            ],
        })
        r = self.run_step("changes", "Detect changed paths", c, env)
        self.assertEqual(r.returncode, 0, r.stderr)
        out = dict(l.split("=", 1) for l in open(os.path.join(self.tmp, "output")).read().split())
        self.assertEqual(out["run_tests"], "true")

    def test_skipped_on_the_newer_commit_reads_the_older_success(self):
        # Only skipped may look at an older commit. A skipped Tests there, with a
        # success on the older commit and no code change, does not run again.
        a = self.commit({"scripts/x.sh": "x\n"})
        b = self.commit({"docs/a.md": "a\n"})
        c = self.commit({"docs/b.md": "b\n"})
        env = self.write_gh_conclusions({a: "success", b: "skipped"})
        r = self.run_step("changes", "Detect changed paths", c, env)
        self.assertEqual(r.returncode, 0, r.stderr)
        out = dict(l.split("=", 1) for l in open(os.path.join(self.tmp, "output")).read().split())
        self.assertEqual(out["run_tests"], "false")

    def test_other_app_success_does_not_cover_the_commit(self):
        a = self.commit({"scripts/x.sh": "x\n"})
        b = self.commit({"docs/a.md": "a\n"})
        c = self.commit({"docs/b.md": "b\n"})
        env = self.write_gh_runs({
            a: [{"name": "Tests", "id": 1, "status": "completed", "conclusion": "success",
                 "started_at": "2020-01-01T00:00:00Z", "app": {"slug": "github-actions"}}],
            b: [{"name": "Tests", "id": 2, "status": "completed", "conclusion": "success",
                 "started_at": "2020-01-02T00:00:00Z", "app": {"slug": "other"}}],
        })
        r = self.run_step("changes", "Detect changed paths", c, env)
        self.assertEqual(r.returncode, 0, r.stderr)
        out = dict(l.split("=", 1) for l in open(os.path.join(self.tmp, "output")).read().split())
        self.assertEqual(out["run_tests"], "true")

    def test_tests_run_on_cancelled_pending_or_api_error(self):
        a = self.commit({"scripts/x.sh": "x\n"})
        b = self.commit({"docs/a.md": "a\n"})
        c = self.commit({"docs/b.md": "b\n"})
        for conc in ("cancelled", "timed_out", "pending", "apierr"):
            env = self.write_gh_conclusions({a: "success", b: conc})
            r = self.run_step("changes", "Detect changed paths", c, env)
            self.assertEqual(r.returncode, 0, r.stderr + conc)
            out = dict(l.split("=", 1) for l in open(os.path.join(self.tmp, "output")).read().split())
            self.assertEqual(out["run_tests"], "true", conc)

    def test_tests_skip_only_when_success_contains_base(self):
        a = self.commit({"scripts/x.sh": "x\n"})
        b = self.commit({"docs/a.md": "a\n"})
        env = self.write_gh_conclusions({a: "success"})
        r = self.run_step("changes", "Detect changed paths", b, env)
        self.assertEqual(r.returncode, 0, r.stderr)
        out = dict(l.split("=", 1) for l in open(os.path.join(self.tmp, "output")).read().split())
        self.assertEqual(out["run_tests"], "false")
        git(self.repo, "switch", "--quiet", "main")
        new_base = self.commit({"unrelated.txt": "u\n"})
        git(self.repo, "switch", "--quiet", "feat/x")
        env = self.write_gh_conclusions({a: "success"})
        r = self.run_step("changes", "Detect changed paths", b, dict(env, BASE_SHA=new_base))
        self.assertEqual(r.returncode, 0, r.stderr)
        out = dict(l.split("=", 1) for l in open(os.path.join(self.tmp, "output")).read().split())
        self.assertEqual(out["run_tests"], "true")

    def push_main(self, files, pr_head_tree_of=None, ci="success", tests="success"):
        """Runs the detect step as a push to main: BASE is the previous main, HEAD the new one.
        A fake gh answers the merged PR that holds HEAD; its head is pr_head_tree_of (a commit
        whose tree is the PR head tree), with the CI and Tests conclusions given."""
        head = self.commit(files)
        fake = os.path.join(self.tmp, "binpush")
        os.makedirs(fake, exist_ok=True)
        pr_tree = git(self.repo, "rev-parse", (pr_head_tree_of or head) + "^{tree}")
        gh = os.path.join(fake, "gh")
        def run(name, conclusion, run_id):
            pending = conclusion == "pending"
            return {"name": name, "id": run_id,
                    "status": "in_progress" if pending else "completed",
                    "conclusion": None if pending else conclusion,
                    "started_at": "2020-01-01T00:00:00Z",
                    "app": {"slug": "github-actions"}}
        body = json.dumps({"check_runs": [run("CI", ci, 1), run("Tests", tests, 2)]})
        open(gh, "w").write("""#!/bin/sh
body=%s
case "$*" in
  *"/commits/%s/pulls"*) echo prhead; exit 0 ;;
  *"/git/commits/prhead"*) echo %s; exit 0 ;;
  *"/commits/prhead/check-runs"*) ;;
  *) echo 0; exit 0 ;;
esac
jq_expr=""
prev=""
for a in "$@"; do
  [ "$prev" = --jq ] && jq_expr="$a"
  prev="$a"
done
if [ -n "$jq_expr" ]; then printf '%%s\\n' "$body" | jq -r "$jq_expr"; else printf '%%s\\n' "$body"; fi
""" % (json.dumps(body), head, pr_tree))
        os.chmod(gh, 0o755)
        env = {"PATH": fake + os.pathsep + os.environ["PATH"], "EVENT_NAME": "push",
               "GITHUB_STEP_SUMMARY": os.path.join(self.tmp, "summary.md")}
        r = self.run_step("changes", "Detect changed paths", head, env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.last_push_stdout = r.stdout
        return dict(l.split("=", 1) for l in open(os.path.join(self.tmp, "output")).read().split())

    def test_push_main_skips_when_the_tree_is_the_head_of_a_merged_pr(self):
        # The common case, one merge: main has the tree of the head of the PR, which had CI green.
        out = self.push_main({"scripts/x.sh": "x\n"})
        self.assertEqual((out["run_tests"], out["code"], out["workflows"], out["event"]), ("false", "false", "false", "push"))

    def test_push_main_runs_the_suite_on_the_sum_of_two_merges(self):
        # PR 56 and PR 57 rebased in a row (#59): the tree of main is the head of neither PR.
        first = self.commit({"scripts/a.sh": "a\n"})
        out = self.push_main({"scripts/b.sh": "b\n"}, pr_head_tree_of=first)
        self.assertEqual((out["run_tests"], out["code"], out["event"]), ("true", "true", "push"))

    def test_push_main_runs_when_the_pr_had_no_green_ci_or_failed_tests(self):
        self.assertEqual(self.push_main({"scripts/x.sh": "x\n"}, ci="failure")["run_tests"], "true")
        self.assertEqual(self.push_main({"scripts/y.sh": "y\n"}, tests="failure")["run_tests"], "true")

    def test_push_main_uses_the_newest_tests_result(self):
        # An older success must not hide a newer timeout on the same PR head.
        self.assertEqual(self.push_main({"scripts/z.sh": "z\n"}, tests="timed_out")["run_tests"], "true")

    def test_push_main_skips_inert_docs(self):
        out = self.push_main({"docs/x.md": "x\n"}, pr_head_tree_of=self.base)
        self.assertEqual((out["run_tests"], out["code"]), ("false", "false"))

    def test_push_of_only_generated_docs_does_not_start(self):
        # #137: a push to main that changes only CHANGELOG.md and ROADMAP.md starts
        # no run. paths-ignore is enough; the pull_request trigger is untouched.
        wf = cw.load(os.path.join(ROOT, ".github", "workflows", "ci.yml"))
        if ci_mode() == "pr":
            self.assertNotIn("push", wf["on"])  # mode pr: no run on the main
            return
        self.assertEqual(sorted(wf["on"]["push"].get("paths-ignore", [])),
                         ["CHANGELOG.md", "ROADMAP.md"])
        self.assertEqual(wf["on"]["push"]["branches"], ["main"])

    def test_already_tested_push_is_one_job(self):
        # The two minimum jobs (Changes and CI) become one, and the run says why.
        wf = cw.load(os.path.join(ROOT, ".github", "workflows", "ci.yml"))
        self.assertIn("confirmed", wf["jobs"]["changes"]["outputs"])
        self.assertIn("needs.changes.outputs.confirmed", wf["jobs"]["ci"]["if"])
        out = self.push_main({"scripts/x.sh": "x\n"})
        self.assertEqual(out.get("confirmed"), "true")
        self.assertIn("already tested in the PR", self.last_push_stdout)
        summary = os.path.join(self.tmp, "summary.md")
        self.assertIn("already tested in the PR", open(summary).read())

    def test_ci_runs_on_push_to_main_without_policy(self):
        wf = cw.load(os.path.join(ROOT, ".github", "workflows", "ci.yml"))
        if ci_mode() == "pr":
            self.assertNotIn("push", wf["on"])  # mode pr: no run on the main
        else:
            self.assertEqual(wf["on"]["push"]["branches"], ["main"])
        self.assertEqual(wf["jobs"]["policy"]["if"], "github.event_name == 'pull_request'")
        # A run of main is never cancelled by the next one: phase-start.sh waits for it.
        self.assertIn("github.event_name == 'pull_request'", wf["concurrency"]["cancel-in-progress"])

    def test_tests_job_runs_unless_run_tests_is_false(self):
        wf = cw.load(os.path.join(ROOT, ".github", "workflows", "ci.yml"))
        tests = wf["jobs"]["tests"]
        self.assertEqual(tests["if"], "needs.changes.outputs.run_tests != 'false'")
        self.assertIn("scripts/validate.sh --tests", [s.get("run") for s in tests["steps"]])
        self.assertEqual(wf["jobs"]["lint"]["if"], "needs.changes.outputs.code == 'true'")

    def test_filter_issue_template_is_code(self):
        out = self.detect({".github/ISSUE_TEMPLATE/bug.md": "x\n"})
        self.assertEqual((out["code"], out["docs_only"]), ("true", "false"))

    def test_rename_to_docs_still_runs_tests(self):
        # A rename is delete+add: moving code into docs/ must not look docs-only.
        os.makedirs(os.path.join(self.repo, "db", "migrations"), exist_ok=True)
        open(os.path.join(self.repo, "db", "migrations", "001.sql"), "w").write("x\n")
        git(self.repo, "add", "db/migrations/001.sql")
        git(self.repo, "commit", "--quiet", "-m", "feat: migration")
        self.base = git(self.repo, "rev-parse", "HEAD")
        os.makedirs(os.path.join(self.repo, "docs"), exist_ok=True)
        git(self.repo, "mv", "db/migrations/001.sql", "docs/001.md")
        git(self.repo, "commit", "--quiet", "-m", "docs: move")
        head = git(self.repo, "rev-parse", "HEAD")
        r = self.run_step("changes", "Detect changed paths", head)
        self.assertEqual(r.returncode, 0, r.stderr)
        out = dict(l.split("=", 1) for l in open(os.path.join(self.tmp, "output")).read().split())
        self.assertEqual((out["code"], out["run_tests"]), ("true", "true"))

    def test_accented_path_is_code(self):
        rel = "infra/production/configuração.yml"
        out = self.detect({rel: "x\n"})
        self.assertEqual((out["code"], out["run_tests"]), ("true", "true"))

    def test_policy_sees_renamed_and_accented_sensitive_paths(self):
        os.makedirs(os.path.join(self.repo, "db", "migrations"), exist_ok=True)
        open(os.path.join(self.repo, "db", "migrations", "001.sql"), "w").write("x\n")
        git(self.repo, "add", "db/migrations/001.sql")
        git(self.repo, "commit", "--quiet", "-m", "feat: migration")
        self.base = git(self.repo, "rev-parse", "HEAD")
        os.makedirs(os.path.join(self.repo, "docs"), exist_ok=True)
        git(self.repo, "mv", "db/migrations/001.sql", "docs/001.md")
        git(self.repo, "commit", "--quiet", "-m", "docs: move")
        head = git(self.repo, "rev-parse", "HEAD")
        self.base_checkout()
        env, log = self.fake_gh()
        r = self.run_step("policy", "Label sensitive paths with needs-owner-ok", head, env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("db/migrations/001.sql", r.stdout)

        self.setUp()
        rel = "infra/production/configuração.yml"
        head = self.commit({rel: "x\n"})
        self.base_checkout()
        env, log = self.fake_gh()
        r = self.run_step("policy", "Label sensitive paths with needs-owner-ok", head, env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn(rel, r.stdout)

    def test_filter_page(self):
        # The filter is the part an adopter swaps for its own folders: read it from ci.yml.
        self.assertEqual(self.detect({app_filter_sample(): "x\n"})["app"], "true")

    def base_checkout(self):
        """What the workflow checks out at base/: the base commit of the PR."""
        git(self.repo, "worktree", "add", "--quiet", "--detach", os.path.join(self.repo, "base"), self.base)

    def fake_gh(self):
        bindir = os.path.join(self.tmp, "bin")
        os.makedirs(bindir)
        shutil.copy(os.path.join(HERE, "fakes", "gh"), os.path.join(bindir, "gh"))
        os.chmod(os.path.join(bindir, "gh"), 0o755)
        log = os.path.join(self.tmp, "gh.log")
        open(log, "w").close()
        return {"PATH": bindir + os.pathsep + os.environ["PATH"], "FAKE_GH_LOG": log}, log

    def test_sensitive_paths_are_read_from_the_base(self):
        # The PR empties the globs and the matcher, and touches a sensitive file.
        head = self.commit({".github/sensitive-paths": "# none\n",
                            "scripts/lib/sensitive_paths.py": "import sys\nsys.exit(0)\n",
                            "scripts/close-phase.sh": "echo changed\n"})
        self.base_checkout()
        env, log = self.fake_gh()
        r = self.run_step("policy", "Label sensitive paths with needs-owner-ok", head, env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("scripts/close-phase.sh", r.stdout)
        self.assertIn("labels[]=needs-gate-review", open(log).read())

    def test_policy_labels_with_a_base_verifier_that_does_not_know_nul_lists(self):
        # #186: the base of an update still has the verifier of c1b76da, which reads one
        # path per line. A PR that touches ci.yml still gets a label (the old verifier
        # cannot tell the classes, so the label is the strict one).
        shutil.copy(os.path.join(HERE, "fixtures", "sensitive_paths_c1b76da.py"),
                    os.path.join(self.repo, "scripts", "lib", "sensitive_paths.py"))
        git(self.repo, "add", "scripts")
        git(self.repo, "commit", "--quiet", "-m", "chore: old verifier")
        self.base = git(self.repo, "rev-parse", "HEAD")
        head = self.commit({".github/workflows/ci.yml": "name: CI\n", "scripts/close-phase.sh": "x\n"})
        self.base_checkout()
        env, log = self.fake_gh()
        r = self.run_step("policy", "Label sensitive paths with needs-owner-ok", head, env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn(".github/workflows/ci.yml", r.stdout)
        self.assertIn("labels[]=needs-owner-ok", open(log).read())

    def policy_labels(self, files):
        head = self.commit(files)
        self.base_checkout()
        env, log = self.fake_gh()
        r = self.run_step("policy", "Label sensitive paths with needs-owner-ok", head, env)
        self.assertEqual(r.returncode, 0, r.stderr)
        calls = open(log).read()
        return ("labels[]=needs-owner-ok" in calls, "labels[]=needs-gate-review" in calls)

    def test_policy_gate_paths_get_needs_gate_review_not_owner_ok(self):
        self.assertEqual(self.policy_labels({".github/workflows/ci.yml": "x\n"}), (False, True))
        self.setUp()
        self.assertEqual(self.policy_labels({"package-lock.json": "{}\n"}), (False, True))
        self.setUp()
        self.assertEqual(self.policy_labels({"db/migrations/001.sql": "x\n"}), (True, False))
        self.setUp()
        self.assertEqual(self.policy_labels({"db/migrations/001.sql": "x\n", "scripts/close-phase.sh": "x\n"}),
                         (True, True))
        self.setUp()
        self.assertEqual(self.policy_labels({"README.md": "x\n"}), (False, False))

    def test_docs_checker_is_read_from_the_base(self):
        os.makedirs(os.path.join(self.repo, "scripts", "lib"), exist_ok=True)
        shutil.copy(os.path.join(ROOT, "scripts", "check-docs.sh"), os.path.join(self.repo, "scripts"))
        shutil.copy(os.path.join(ROOT, "scripts", "lib", "common.sh"), os.path.join(self.repo, "scripts", "lib"))
        git(self.repo, "add", "scripts")
        git(self.repo, "commit", "--quiet", "-m", "chore: checker")
        self.base = git(self.repo, "rev-parse", "HEAD")
        # The PR replaces the checker by one that always passes and breaks a doc rule.
        head = self.commit({"scripts/check-docs.sh": "#!/usr/bin/env bash\nexit 0\n",
                            "CLAUDE.md": "read AGENTS.md\n"})
        os.chmod(os.path.join(self.repo, "scripts", "check-docs.sh"), 0o755)
        self.base_checkout()
        r = self.run_step("policy", "Check docs limits", head)
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn('CLAUDE.md must contain only "@AGENTS.md"', r.stdout)

    def test_attribution_checker_is_read_from_the_base(self):
        shutil.copy(os.path.join(ROOT, "scripts", "check-attribution.sh"), os.path.join(self.repo, "scripts"))
        shutil.copy(os.path.join(ROOT, "scripts", "lib", "common.sh"), os.path.join(self.repo, "scripts", "lib"))
        git(self.repo, "add", "scripts")
        git(self.repo, "commit", "--quiet", "-m", "chore: checker")
        self.base = git(self.repo, "rev-parse", "HEAD")
        # The PR replaces the checker by one that always passes.
        head = self.commit({"scripts/check-attribution.sh": "#!/usr/bin/env bash\nexit 0\n"})
        self.base_checkout()
        r = self.run_step("policy", "Check AI attribution in commits and PR body", head,
                          {"PR_BODY": "Resumo\n\nCo-Authored-By: Someone <noreply@anthropic.com>\n"})
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("AI attribution", r.stdout)

    def test_gate_is_read_from_the_base(self):
        os.makedirs(os.path.join(self.repo, "scripts"), exist_ok=True)
        head = self.commit({"scripts/ci-gate.sh": "#!/usr/bin/env bash\necho CI passed\n"})
        os.chmod(os.path.join(self.repo, "scripts", "ci-gate.sh"), 0o755)
        os.makedirs(os.path.join(self.repo, "base", "scripts", "lib"))
        for rel in ("ci-gate.sh", "lib/common.sh"):
            shutil.copy(os.path.join(ROOT, "scripts", rel), os.path.join(self.repo, "base", "scripts", rel))
        needs = '{"changes": {"result": "success", "outputs": {"code": "true"}}, "policy": {"result": "success"}, ' \
                '"lint": {"result": "failure"}, "tests": {"result": "success"}, "workflows": {"result": "skipped"}}'
        r = self.run_step("ci", "Aggregate required jobs", head, {"NEEDS": needs})
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("fail: lint", r.stdout)

    def test_base_checkouts(self):
        # policy reads the base of the PR at base/. On push, ci reads github.sha:
        # github.event.before is the previous main, which has no verifiers on the
        # adoption push and an old gate on an update.
        wf = cw.load(os.path.join(ROOT, ".github", "workflows", "ci.yml"))
        for job in ("policy", "ci"):
            steps = wf["jobs"][job]["steps"]
            base = [s for s in steps if "git archive" in (s.get("run") or "")]
            self.assertEqual(len(base), 1, job)
            want = "${{ github.event.pull_request.base.sha }}" if job == "policy" else \
                "${{ github.event.pull_request.base.sha || github.sha }}"
            self.assertEqual(base[0]["env"]["BASE_SHA"], want, job)
            self.assertNotIn("github.event.before", base[0]["env"]["BASE_SHA"])
            self.assertNotIn("${{", base[0]["run"], job)

    def test_first_ci_uses_the_gate_of_this_commit_when_the_base_has_none(self):
        # Adoption PR: the base commit has no ci-gate.sh. The gate of this commit
        # still fails a red lint; a missing file must not skip the gate.
        self.commit({"scripts/ci-gate.sh": open(os.path.join(ROOT, "scripts", "ci-gate.sh")).read(),
                     "scripts/lib/common.sh": open(os.path.join(ROOT, "scripts", "lib", "common.sh")).read()})
        os.chmod(os.path.join(self.repo, "scripts", "ci-gate.sh"), 0o755)
        head = git(self.repo, "rev-parse", "HEAD")
        needs = ('{"changes": {"result": "success", "outputs": {"code": "true"}}, '
                 '"policy": {"result": "success"}, "lint": {"result": "failure"}, '
                 '"tests": {"result": "success"}, "workflows": {"result": "skipped"}}')
        r = self.run_step("ci", "Aggregate required jobs", head, {"NEEDS": needs})
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("fail: lint", r.stdout)
        self.assertIn("first CI", r.stdout)

    def test_policy_does_not_run_pr_checkers_when_the_base_has_no_method(self):
        # The policy job holds pull-requests: write. When the base has no method,
        # the checkers of the pull request must not run in that job.
        marker = os.path.join(self.tmp, "pr-checker-ran")
        head = self.commit({
            "scripts/check-docs.sh": "#!/bin/sh\necho docs >>%s\nexit 1\n" % marker,
            "scripts/check-attribution.sh": "#!/bin/sh\necho attr >>%s\nexit 1\n" % marker,
            "scripts/lib/sensitive_paths.py":
                "import pathlib,sys\npathlib.Path(%r).write_text('paths')\nsys.exit(1)\n" % marker,
        })
        for name, extra in (
            ("Check docs limits", {}),
            ("Check AI attribution in commits and PR body", {"PR_BODY": "body\n"}),
            ("Label sensitive paths with needs-owner-ok", {}),
        ):
            env = {}
            if name.startswith("Label"):
                env, _log = self.fake_gh()
            env.update(extra)
            r = self.run_step("policy", name, head, env)
            self.assertEqual(r.returncode, 0, name + "\n" + r.stdout + r.stderr)
            self.assertIn("write token", r.stdout, name)
        self.assertFalse(os.path.exists(marker), "a checker from the pull request ran")

    def test_push_needs_that_an_old_gate_rejects(self):
        # Update of the method: the previous main still has a gate that requires
        # policy and tests. The push run uses the gate of github.sha, which
        # accepts policy skipped when event=push and tests skipped when run_tests=false.
        wf = cw.load(os.path.join(ROOT, ".github", "workflows", "ci.yml"))
        ref = next(s for s in wf["jobs"]["ci"]["steps"] if "git archive" in (s.get("run") or ""))["env"]["BASE_SHA"]
        self.assertEqual(ref, "${{ github.event.pull_request.base.sha || github.sha }}")
        needs = ('{"changes":{"result":"success","outputs":{"event":"push","code":"false","run_tests":"false","workflows":"false"}},'
                 '"policy":{"result":"skipped"},"lint":{"result":"skipped"},"tests":{"result":"skipped"},"workflows":{"result":"skipped"}}')
        old = os.path.join(self.tmp, "old-ci-gate.sh")
        open(old, "w").write("#!/bin/sh\necho 'fail: policy is skipped'\necho 'fail: tests is skipped'\nexit 1\n")
        os.chmod(old, 0o755)
        env = dict(os.environ, NEEDS=needs)
        old_run = subprocess.run([old], env=env, text=True, capture_output=True)
        self.assertEqual(old_run.returncode, 1, old_run.stdout)
        self.assertIn("policy is skipped", old_run.stdout)
        new_run = subprocess.run([os.path.join(ROOT, "scripts", "ci-gate.sh")], env=env, text=True, capture_output=True)
        self.assertEqual(new_run.returncode, 0, new_run.stdout + new_run.stderr)
        self.assertIn("CI passed", new_run.stdout)

    def test_red_base_tells_how_to_leave_it(self):
        script = r"""
source scripts/tests/phase_start_common.sh
spec seven.md 7
export PHASE_START_CI_WAIT=2 PHASE_START_CI_POLL=1
set +e
env FAKE_BASE_CI=red sh -c "cd '$repo' && scripts/phase-start.sh 7 --no-check" >"$TMP/red.out" 2>&1
rc=$?
set -e
printf 'RC:%s\n' "$rc"
cat "$TMP/red.out"
"""
        r = subprocess.run(["bash", "-c", script], cwd=ROOT, text=True, capture_output=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("RC:1", r.stdout)
        self.assertIn("nothing was created", r.stdout)
        self.assertIn("empty commit", r.stdout)
        self.assertIn("actions/runs/3", r.stdout)

    def test_pr_only_mode_accepts_a_different_tree_and_refuses_red(self):
        script = r"""
source scripts/tests/phase_start_common.sh
spec seven.md 7
mkdir -p "$repo/.github"
printf 'pr\n' >"$repo/.github/ci-mode"
export PHASE_START_CI_WAIT=2 PHASE_START_CI_POLL=1
run() { # run <outfile> <env...> -- <cmd>
  local out="$1"; shift
  set +e
  env "$@" >"$out" 2>&1
  local rc=$?
  set -e
  printf '%s\n' "$rc"
}
tree_rc="$(run "$TMP/tree.out" FAKE_BASE_CI=absent FAKE_BASE_PR=tree CLAUDE_CODE_SESSION_ID=manager \
  sh -c "cd '$repo' && scripts/phase-start.sh 7 --dry-run")"
red_rc="$(run "$TMP/red.out" FAKE_BASE_CI=red sh -c "cd '$repo' && scripts/phase-start.sh 7 --no-check")"
abs_rc="$(run "$TMP/abs.out" FAKE_BASE_CI=absent FAKE_BASE_PR=none \
  sh -c "cd '$repo' && scripts/phase-start.sh 7 --no-check")"
rm -f "$repo/.github/ci-mode"
push_rc="$(run "$TMP/push.out" FAKE_BASE_CI=absent FAKE_BASE_PR=tree \
  sh -c "cd '$repo' && scripts/phase-start.sh 7 --no-check")"
prred_rc="$(run "$TMP/prred.out" FAKE_BASE_CI=absent FAKE_BASE_PR=red \
  sh -c "cd '$repo' && mkdir -p .github && printf 'pr\n' >.github/ci-mode && scripts/phase-start.sh 7 --no-check")"
printf 'TREE:%s\n' "$tree_rc"
cat "$TMP/tree.out"
printf '\nRED:%s\n' "$red_rc"
cat "$TMP/red.out"
printf '\nABS:%s\n' "$abs_rc"
cat "$TMP/abs.out"
printf '\nPUSH:%s\n' "$push_rc"
cat "$TMP/push.out"
printf '\nPRRED:%s\n' "$prred_rc"
cat "$TMP/prred.out"
"""
        r = subprocess.run(["bash", "-c", script], cwd=ROOT, text=True, capture_output=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        out = r.stdout
        self.assertIn("TREE:0", out)
        self.assertIn("differs", out)
        self.assertIn("PR #30", out)
        tree = out.split("RED:", 1)[0]
        self.assertNotIn("same tree", tree)
        self.assertIn("RED:1", out)
        self.assertIn("no phase opens", out)
        self.assertIn("ABS:1", out)
        self.assertNotIn("gh workflow run", out)
        self.assertIn("nothing was created", out)
        self.assertIn("PUSH:1", out)
        self.assertIn("PRRED:1", out)

    def test_pr_mode_refuses_an_unread_tree_and_private_without_a_record(self):
        script = r"""
source scripts/tests/phase_start_common.sh
spec seven.md 7
export PHASE_START_CI_WAIT=2 PHASE_START_CI_POLL=1
mkdir -p "$TMP/wrap"
cat >"$TMP/wrap/gh" <<EOF
#!/bin/sh
case "\$*" in
  *"--jq .private"*) echo true; exit 0 ;;
  *"/git/commits/headpr1"*) printf '%s\n' '{"tree":{}}'; exit 0 ;;
esac
exec "$TMP/bin/gh" "\$@"
EOF
chmod +x "$TMP/wrap/gh"
run() {
  local out="$1"; shift
  set +e
  env "$@" >"$out" 2>&1
  local rc=$?
  set -e
  printf '%s\n' "$rc"
}
mkdir -p "$repo/.github"
printf 'pr\n' >"$repo/.github/ci-mode"
unread_rc="$(run "$TMP/unread.out" PATH="$TMP/wrap:$PATH" FAKE_BASE_CI=absent FAKE_BASE_PR=green \
  sh -c "cd '$repo' && scripts/phase-start.sh 7 --no-check")"
rm -f "$repo/.github/ci-mode"
priv_rc="$(run "$TMP/priv.out" PATH="$TMP/wrap:$PATH" FAKE_BASE_CI=green \
  sh -c "cd '$repo' && scripts/phase-start.sh 7 --no-check")"
printf 'pr\n' >"$repo/.github/ci-mode"
ok_rc="$(run "$TMP/ok.out" PATH="$TMP/wrap:$PATH" FAKE_BASE_CI=green CLAUDE_CODE_SESSION_ID=manager \
  sh -c "cd '$repo' && scripts/phase-start.sh 7 --dry-run")"
printf 'UNREAD:%s\n' "$unread_rc"
cat "$TMP/unread.out"
printf '\nPRIV:%s\n' "$priv_rc"
cat "$TMP/priv.out"
printf '\nOK:%s\n' "$ok_rc"
cat "$TMP/ok.out"
"""
        r = subprocess.run(["bash", "-c", script], cwd=ROOT, text=True, capture_output=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        out = r.stdout
        self.assertIn("UNREAD:1", out)
        self.assertIn("was not read", out)
        self.assertIn("PRIV:1", out)
        self.assertIn("private repository", out)
        self.assertIn("nothing was created", out)
        self.assertIn("OK:0", out)
        ok = out.split("OK:", 1)[1]
        self.assertNotIn("not recorded", ok)


class RunnerToolsTests(unittest.TestCase):
    def test_cwd_uses_proc_when_lsof_is_missing(self):
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp, True)
        root = os.path.join(tmp, "proc")
        os.makedirs(os.path.join(root, "42"))
        os.symlink("/work/phase", os.path.join(root, "42", "cwd"))
        bindir = os.path.join(tmp, "bin")
        os.makedirs(bindir)
        for cmd in ("readlink", "awk", "sed", "head", "sort", "ls"):
            src = shutil.which(cmd)
            if src:
                os.symlink(src, os.path.join(bindir, cmd))
        script = "source scripts/lib/procs.sh\nproc_cwd_of 42\nprocs_in_dir /work\n"
        env = dict(os.environ)
        env["PATH"] = bindir
        env["PROCS_PROC_ROOT"] = root
        r = subprocess.run([shutil.which("bash"), "-c", script], cwd=ROOT, env=env, text=True, capture_output=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        lines = [ln for ln in r.stdout.splitlines() if ln]
        self.assertEqual(lines[0], "/work/phase")
        self.assertIn("42", lines[1:])

    def test_setup_runner_check_names_what_is_missing(self):
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp, True)
        bindir = os.path.join(tmp, "bin")
        os.makedirs(bindir)
        for cmd in ("bash", "dirname", "basename", "pwd", "cat", "awk", "sed", "tr", "uname", "grep"):
            src = shutil.which(cmd)
            if src:
                os.symlink(src, os.path.join(bindir, cmd))
        env = dict(os.environ)
        env["PATH"] = bindir
        r = subprocess.run([os.path.join(bindir, "bash"), os.path.join(ROOT, "scripts", "setup-runner.sh"), "--check"],
                           cwd=ROOT, env=env, text=True, capture_output=True)
        text = r.stdout + r.stderr
        self.assertNotEqual(r.returncode, 0, text)
        self.assertIn("PyYAML", text)
        for cmd in ("yq", "lsof", "curl", "tar", "shasum"):
            os.symlink("/bin/echo", os.path.join(bindir, cmd))
        r = subprocess.run([os.path.join(bindir, "bash"), os.path.join(ROOT, "scripts", "setup-runner.sh"), "--check"],
                           cwd=ROOT, env=env, text=True, capture_output=True)
        text = r.stdout + r.stderr
        self.assertEqual(r.returncode, 0, text)
        self.assertIn(".github/gh-pin", text)


def ci_install_step(job):
    return ci_step(job, "Install pinned gh")


class GhPinTests(unittest.TestCase):
    def setUp(self):
        self.tmp = os.path.realpath(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.repo = os.path.join(self.tmp, "repo")
        os.makedirs(self.repo)

    def test_jobs_install_gh_from_the_base_pin_not_a_local_action(self):
        wf = cw.load(os.path.join(ROOT, ".github", "workflows", "ci.yml"))
        runs = []
        for job in ("changes", "policy"):
            step = ci_install_step(job)
            self.assertIn("base/.github/gh-pin", step["run"])
            self.assertNotIn(".github/actions", step["run"])
            runs.append(step["run"])
            uses = [s.get("uses") or "" for s in wf["jobs"][job]["steps"]]
            self.assertFalse(any(u.startswith("./") for u in uses), job)
        self.assertEqual(runs[0], runs[1])
        changes = wf["jobs"]["changes"]["steps"]
        pin = [s for s in changes if s.get("name") == "Read the gh pin from the base"]
        self.assertEqual(len(pin), 1)
        self.assertEqual(pin[0]["env"]["BASE_SHA"], "${{ github.event.pull_request.base.sha || github.sha }}")
        self.assertIn("git archive", pin[0]["run"])

    def test_checkout_can_be_replaced_by_a_command_of_the_repository(self):
        # #247: a runner with no actions/* sets CI_CHECKOUT_CMD. Each checkout has a twin
        # that runs the command from env, never from ${{ }} inside run.
        wf = cw.load(os.path.join(ROOT, ".github", "workflows", "ci.yml"))
        for job, body in wf["jobs"].items():
            steps = body["steps"]
            for i, st in enumerate(steps):
                if not (st.get("uses") or "").startswith("actions/checkout"):
                    continue
                self.assertEqual(st["if"], "vars.CI_CHECKOUT_CMD == ''", job)
                twin = steps[i + 1]
                self.assertEqual(twin["if"], "vars.CI_CHECKOUT_CMD != ''", job)
                self.assertEqual(twin["env"]["CI_CHECKOUT_CMD"], "${{ vars.CI_CHECKOUT_CMD }}")
                self.assertEqual(twin["run"], 'eval "$CI_CHECKOUT_CMD"')
                full = "fetch-depth" in (st.get("with") or {})
                self.assertEqual(twin["env"]["CI_CHECKOUT_FULL"], "true" if full else "false", job)
        text = open(os.path.join(ROOT, ".github", "workflows", "ci.yml"), encoding="utf-8").read()
        self.assertNotRegex(text, r"run:[^\n]*\$\{\{ *vars\.")

    def run_install(self, extra_env):
        env = dict(os.environ)
        env.update(RUNNER_TEMP=self.tmp, GITHUB_PATH=os.path.join(self.tmp, "gh.path"),
                   RUNNER_OS_NAME="Linux", RUNNER_ARCH_NAME="X64")
        env.update(extra_env)
        open(env["GITHUB_PATH"], "w").close()
        return subprocess.run([shutil.which("bash"), "-eo", "pipefail", "-c", ci_install_step("policy")["run"]],
                              cwd=self.repo, env=env, text=True, capture_output=True)

    def bindir(self, names):
        d = os.path.join(self.tmp, "bin-" + names[0])
        os.makedirs(d, exist_ok=True)
        for name in names:
            src = shutil.which(name)
            if src and not os.path.exists(os.path.join(d, name)):
                os.symlink(src, os.path.join(d, name))
        return d

    def test_missing_pin_fails_clearly_without_gh_and_uses_path_gh(self):
        bare = self.bindir(["awk", "curl", "tar", "shasum"])
        r = self.run_install({"PATH": bare})
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn(".github/gh-pin", r.stdout + r.stderr)
        self.assertIn("pull request", r.stdout + r.stderr)
        gh = os.path.join(bare, "gh")
        open(gh, "w").write("#!/bin/sh\necho 'gh version 9.test'\n")
        os.chmod(gh, 0o755)
        r = self.run_install({"PATH": bare})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("already on PATH", r.stdout)

    def test_first_ci_uses_the_pin_of_the_pull_request_when_the_base_has_no_method(self):
        # #248: adoption PR on a runner with no gh. The base has neither .github/gh-pin
        # nor .github/method-files.txt; the PR brings the pin.
        bindir = self.bindir(["awk", "curl", "tar", "shasum"])
        os.makedirs(os.path.join(self.repo, "base"))
        os.makedirs(os.path.join(self.repo, ".github"))
        payload = os.path.join(self.tmp, "payload")
        os.makedirs(os.path.join(payload, "gh_2.105.0_linux_amd64", "bin"))
        open(os.path.join(payload, "gh_2.105.0_linux_amd64", "bin", "gh"), "w").write("#!/bin/sh\n")
        archive = os.path.join(self.tmp, "gh.tgz")
        subprocess.run(["tar", "czf", archive, "-C", payload, "gh_2.105.0_linux_amd64"], check=True)
        digest = subprocess.run(["shasum", "-a", "256", archive], check=True, text=True,
                                capture_output=True).stdout.split()[0]
        curl = os.path.join(bindir, "curl")
        os.remove(curl)
        open(curl, "w").write("#!/bin/sh\nout=\nwhile [ $# -gt 0 ]; do case \"$1\" in -o) out=\"$2\"; shift 2 ;; *) shift ;; esac; done\ncp '%s' \"$out\"\n" % archive)
        os.chmod(curl, 0o755)
        open(os.path.join(self.repo, ".github", "gh-pin"), "w").write("2.105.0\nlinux-amd64 %s tar.gz\n" % digest)
        env = {"PATH": bindir + os.pathsep + "/usr/bin:/bin"}
        r = self.run_install(env)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("::notice::", r.stdout)
        self.assertIn("gh_2.105.0_linux_amd64/bin", open(os.path.join(self.tmp, "gh.path")).read())
        # A base that already has the method does not take the pin of the PR.
        open(os.path.join(self.repo, "base", ".github-method-marker"), "w").close()
        os.makedirs(os.path.join(self.repo, "base", ".github"))
        open(os.path.join(self.repo, "base", ".github", "method-files.txt"), "w").write("x\n")
        r = self.run_install(env)
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertNotIn("::notice::", r.stdout)

    def test_pin_sha256_mismatch_fails_and_a_match_installs(self):
        bindir = self.bindir(["awk", "curl", "tar", "shasum"])
        os.makedirs(os.path.join(self.repo, "base", ".github"))
        payload = os.path.join(self.tmp, "payload")
        os.makedirs(os.path.join(payload, "gh_2.105.0_linux_amd64", "bin"))
        open(os.path.join(payload, "gh_2.105.0_linux_amd64", "bin", "gh"), "w").write("#!/bin/sh\n")
        archive = os.path.join(self.tmp, "gh.tgz")
        subprocess.run(["tar", "czf", archive, "-C", payload, "gh_2.105.0_linux_amd64"], check=True)
        digest = subprocess.run(["shasum", "-a", "256", archive], check=True, text=True,
                                capture_output=True).stdout.split()[0]
        curl = os.path.join(bindir, "curl")
        os.remove(curl)
        open(curl, "w").write("#!/bin/sh\nout=\nwhile [ $# -gt 0 ]; do case \"$1\" in -o) out=\"$2\"; shift 2 ;; *) shift ;; esac; done\ncp '%s' \"$out\"\n" % archive)
        os.chmod(curl, 0o755)
        pin = os.path.join(self.repo, "base", ".github", "gh-pin")
        open(pin, "w").write("2.105.0\nlinux-amd64 %s tar.gz\n" % ("0" * 64))
        env = {"PATH": bindir + os.pathsep + "/usr/bin:/bin"}
        r = self.run_install(env)
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("sha256 mismatch", r.stdout + r.stderr)
        open(pin, "w").write("2.105.0\nlinux-amd64 %s tar.gz\n" % digest)
        r = self.run_install(env)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("gh_2.105.0_linux_amd64/bin", open(os.path.join(self.tmp, "gh.path")).read())


class NoNewFactTests(unittest.TestCase):
    def test_detection_is_named_where_the_design_table_says(self):
        # #138: the skip that proved nothing new is recorded in the existing
        # scripts, at the tokens the design table names. No new production target.
        design = open(os.path.join(ROOT, "docs", "process-design.md"), encoding="utf-8").read()
        close = open(os.path.join(ROOT, "scripts", "close-phase.sh"), encoding="utf-8").read()
        ci = open(os.path.join(ROOT, ".github", "workflows", "ci.yml"), encoding="utf-8").read()
        self.assertNotIn("scripts/repeated-work.sh", design + close + ci)
        for token in ("no-new-fact: already on origin",
                      "no-new-fact: already tested in the PR",
                      "no-new-fact: tests already passed",
                      "no-new-fact: nothing the suite reads"):
            self.assertIn(token, design, token)
            self.assertTrue(token in close or token in ci, token)


class ApplicationWorkflowTests(unittest.TestCase):
    def test_an_application_workflow_is_not_checked(self):
        # Renovate, image retention and a scheduled scan stay out of the method (#103).
        d = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, d)
        os.makedirs(os.path.join(d, ".github", "workflows"))
        path = os.path.join(d, ".github", "workflows", "renovate.yml")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write("on: schedule\n")
        old = os.getcwd()
        os.chdir(d)
        try:
            rc = cw.main([])
        finally:
            os.chdir(old)
        self.assertEqual(rc, 0)
        # A method workflow with the same gap still fails.
        self.assertTrue(cw.check(path))


if __name__ == "__main__":
    unittest.main(verbosity=0)
