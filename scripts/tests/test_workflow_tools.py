"""Testes do check-workflows.py, do sensitive_paths.py e dos passos do ci.yml."""

import importlib.util
import json
import os
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

    def test_repo_workflows_follow_the_standard(self):
        wf = os.path.join(ROOT, ".github", "workflows")
        for name in os.listdir(wf):
            self.assertEqual(cw.check(os.path.join(wf, name)), [], name)

    def test_deploy_not_run_twice_per_push(self):
        # The deploy only runs on workflow_dispatch; the build on the PR belongs to ci.yml.
        text = open(os.path.join(ROOT, ".github", "workflows", "deploy-example.yml")).read()
        on = text.split("\non:\n", 1)[1].split("\npermissions:", 1)[0]
        self.assertIn("workflow_dispatch", on)
        self.assertNotIn("push", on)
        self.assertNotIn("pull_request", on)

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

    def test_repo_deploy_validates_main_before_the_build(self):
        wf = cw.load(os.path.join(ROOT, ".github", "workflows", "deploy-example.yml"))
        steps = wf["jobs"]["validate"]["steps"]
        self.assertTrue(any(s.get("run") == "scripts/validate.sh" for s in steps))
        self.assertEqual(wf["jobs"]["build"]["needs"], "validate")
        self.assertEqual(wf["jobs"]["deploy"]["needs"], "build")

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
        for key, value in (("user.email", "t@example.org"), ("user.name", "t"), ("commit.gpgsign", "false")):
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
        env = dict(os.environ, BASE_SHA=self.base, HEAD_SHA=head, RUNNER_TEMP=self.tmp,
                   GITHUB_OUTPUT=os.path.join(self.tmp, "output"), GITHUB_REPOSITORY="owner/repo",
                   PR_NUMBER="7", **(extra_env or {}))
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
        # Generated docs, specs and the docs/ pages skip the tests job; what the tests
        # read (AGENTS.md, CLAUDE.md, the design, skills, scripts) never does.
        out = self.detect({"docs/x.md": "x\n", "docs/specs/s.md": "x\n", "README.md": "x\n"})
        self.assertEqual((out["code"], out["run_tests"]), ("false", "false"))
        # ROADMAP.md and CHANGELOG.md are generated from issue titles and PRs and a test reads
        # them (#54): a PR that only changes them still runs the tests.
        for rel in ("AGENTS.md", "CLAUDE.md", "docs/process-design.md", ".claude/skills/plan/SKILL.md",
                    "scripts/x.sh", "app/README.md"):
            self.assertEqual(self.detect({rel: "x\n"})["run_tests"], "true", rel)

    def test_generated_docs_run_the_tests(self):
        # The #44 case: the ROADMAP.md carried an issue title the text tests refuse, and the PR
        # that only changed it skipped the tests. Each file alone, in a fresh PR.
        for rel in ("ROADMAP.md", "CHANGELOG.md"):
            self.setUp()
            out = self.detect({rel: "x\n"})
            self.assertEqual((out["code"], out["run_tests"]), ("false", "true"), rel)

    def test_tests_skip_when_code_already_tested(self):
        # A docs-only push on top of a commit whose Tests passed does not run the suite again.
        first = self.commit({"scripts/x.sh": "x\n"})
        head = self.commit({"docs/x.md": "x\n"})
        fake = os.path.join(self.tmp, "bin")
        os.makedirs(fake)
        gh = os.path.join(fake, "gh")
        open(gh, "w").write('#!/bin/sh\ncase "$*" in *"commits/%s/check-runs"*) echo "$GH_TESTS" ;; *) echo 0 ;; esac\n' % first)
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

    def push_main(self, files, pr_head_tree_of=None, ci="success", tests="success"):
        """Runs the detect step as a push to main: BASE is the previous main, HEAD the new one.
        A fake gh answers the merged PR that holds HEAD; its head is pr_head_tree_of (a commit
        whose tree is the PR head tree), with the CI and Tests conclusions given."""
        head = self.commit(files)
        fake = os.path.join(self.tmp, "binpush")
        os.makedirs(fake, exist_ok=True)
        pr_tree = git(self.repo, "rev-parse", (pr_head_tree_of or head) + "^{tree}")
        gh = os.path.join(fake, "gh")
        open(gh, "w").write("""#!/bin/sh
case "$*" in
  *"/commits/%s/pulls"*) echo prhead ;;
  *"/git/commits/prhead"*) echo %s ;;
  *"/commits/prhead/check-runs"*)
    case "$*" in *'.name == "CI"'*) echo %d ;; *) echo %d ;; esac ;;
  *) echo 0 ;;
esac
""" % (head, pr_tree, 1 if ci == "success" else 0, 1 if tests == "failure" else 0))
        os.chmod(gh, 0o755)
        env = {"PATH": fake + os.pathsep + os.environ["PATH"], "EVENT_NAME": "push"}
        r = self.run_step("changes", "Detect changed paths", head, env)
        self.assertEqual(r.returncode, 0, r.stderr)
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

    def test_push_main_skips_inert_docs(self):
        out = self.push_main({"docs/x.md": "x\n"}, pr_head_tree_of=self.base)
        self.assertEqual((out["run_tests"], out["code"]), ("false", "false"))

    def test_ci_runs_on_push_to_main_without_policy(self):
        wf = cw.load(os.path.join(ROOT, ".github", "workflows", "ci.yml"))
        self.assertEqual(wf["on"]["push"], {"branches": ["main"]})
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

    def test_filter_page(self):
        self.assertEqual(self.detect({"app/README.md": "x\n"})["app"], "true")

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
        self.assertIn("labels[]=needs-owner-ok", open(log).read())

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
        # policy and ci check the base commit out at base/, after the PR checkout.
        wf = cw.load(os.path.join(ROOT, ".github", "workflows", "ci.yml"))
        for job in ("policy", "ci"):
            steps = wf["jobs"][job]["steps"]
            base = [s for s in steps if (s.get("with") or {}).get("path") == "base"]
            self.assertEqual(len(base), 1, job)
            want = "${{ github.event.pull_request.base.sha }}" if job == "policy" else \
                "${{ github.event.pull_request.base.sha || github.event.before }}"
            self.assertEqual(base[0]["with"]["ref"], want, job)
            self.assertFalse(base[0]["with"].get("persist-credentials", True), job)


if __name__ == "__main__":
    unittest.main(verbosity=0)
