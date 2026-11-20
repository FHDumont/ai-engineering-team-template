"""Tests of check-workflows.py, sensitive_paths.py and the steps of ci.yml."""

import importlib.util
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
        # The deploy only runs by workflow_dispatch; the build on the PR belongs to ci.yml.
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
        text = GOOD.replace("issues:\n    types: [opened]", "pull_request:\n  push:\n    branches: [main]")
        problems = "\n".join(cw.check(self.write("ci.yml", text)))
        self.assertIn("ci.yml must run only on pull_request", problems)

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
        self.assertEqual(hits, paths[:8])

    def test_gate_files_sensitive(self):
        globs = sp.load_globs(os.path.join(ROOT, ".github", "sensitive-paths"))
        paths = [".github/workflows/deploy-example.yml", "scripts/close-phase.sh", "scripts/status.sh"]
        self.assertEqual(sp.sensitive(paths, globs), paths[:2])

    def test_double_star(self):
        r = sp.glob_to_regex("**/auth/**")
        self.assertTrue(r.match("a/b/auth/c/d"))
        self.assertFalse(r.match("a/authx/c"))



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

    def test_filter_issue_template_is_code(self):
        out = self.detect({".github/ISSUE_TEMPLATE/bug.md": "x\n"})
        self.assertEqual((out["code"], out["docs_only"]), ("true", "false"))

    def test_filter_app(self):
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
            self.assertEqual(base[0]["with"]["ref"], "${{ github.event.pull_request.base.sha }}", job)
            self.assertFalse(base[0]["with"].get("persist-credentials", True), job)


if __name__ == "__main__":
    unittest.main(verbosity=0)
