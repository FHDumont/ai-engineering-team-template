#!/usr/bin/env python3
"""check-workflows.py: check the workflow standard (design §9), beyond actionlint.

Usage: check-workflows.py [file.yml ...]   (default: .github/workflows/*.yml)

Only the method workflows are checked: ci.yml and the categories deploy,
issues, release and bot. Any other file in the folder is an application
workflow (scheduled jobs, image retention, a pull-request scan) and is
skipped. A scan that must block the merge belongs in ci.yml.

Rules: file name `ci.yml` or `<category>-<purpose>.yml` (categories deploy,
issues, release, bot); top-level `name` and `run-name`; top-level
`permissions: {}`; `concurrency` set; every job with `name`, `runs-on` and
`timeout-minutes` between 5 and 30; every step with `name`; `ci.yml` runs
on `pull_request` and push to `main`, or only on `pull_request` when the
recorded mode is `pr` (a `.github/ci-mode` file, else PROCESS_CI_MODE). A deploy workflow
(`deploy-*.yml`) runs only on `workflow_dispatch` (never `pull_request`,
`push` or `schedule`), has a `# deploy-paths:` line (what it deploys, read by
.method/scripts/deploy.sh) and a job that runs `.method/scripts/validate.sh` which every
other job needs; that job first runs `.method/scripts/ci-already-green.sh` (with
`permissions: checks: read`) and runs `.method/scripts/validate.sh` only when the gate
says `skip != 'true'`. Reads YAML with `yq` (or PyYAML). Exits 1 and lists the
problems.
"""

import glob
import json
import os
import re
import subprocess
import sys

NAME_RE = re.compile(r"^(ci\.yml|(deploy|issues|release|bot)-[a-z0-9-]+\.yml)$")


def load(path):
    try:
        import yaml  # type: ignore
        data = yaml.safe_load(open(path, encoding="utf-8"))
        if True in data and "on" not in data:  # PyYAML reads `on` as True
            data["on"] = data.pop(True)
        return data
    except ImportError:
        out = subprocess.run(["yq", "-o=json", ".", path], check=True,
                             text=True, capture_output=True).stdout
        return json.loads(out)


def recorded_ci_mode(path):
    """push (CI on main) or pr (pull requests only). The file wins over the variable."""
    d = os.path.dirname(os.path.abspath(path))
    while True:
        candidate = os.path.join(d, ".github", "ci-mode")
        if os.path.isfile(candidate):
            with open(candidate, encoding="utf-8") as fh:
                return fh.read().strip() or "push"
        if os.path.isdir(os.path.join(d, ".git")):
            break
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    return os.environ.get("PROCESS_CI_MODE", "").strip() or "push"


def ci_trigger_problems(path, on, triggers):
    mode = recorded_ci_mode(path)
    if mode not in ("push", "pr"):
        return ["ci mode must be push or pr (got %s)" % mode]
    if mode == "pr":
        if triggers != {"pull_request"}:
            return ["ci.yml in pr-only mode must run only on pull_request, with no push (got %s)"
                    % ", ".join(sorted(map(str, triggers)))]
        return []
    problems = []
    if triggers != {"pull_request", "push"}:
        problems.append("ci.yml must run only on pull_request and push to main (got %s)"
                        % ", ".join(sorted(map(str, triggers))))
    push = on.get("push") if isinstance(on, dict) else None
    if (push or {}).get("branches") != ["main"]:
        problems.append("ci.yml must run on push only to main")
    return problems


def needs_of(job):
    needs = job.get("needs") or []
    return [needs] if isinstance(needs, str) else list(needs)


def check_deploy(path, wf, triggers):
    """Rules of a deploy workflow: dispatched only by .method/scripts/deploy.sh, main tested first."""
    problems = []
    for t in sorted(map(str, triggers - {"workflow_dispatch"})):
        problems.append("deploy workflow must run only on workflow_dispatch (got %s)" % t)
    if "workflow_dispatch" not in triggers:
        problems.append("deploy workflow must run on workflow_dispatch")
    with open(path, encoding="utf-8") as f:
        if not re.search(r"^# deploy-paths:[ \t]*\S", f.read(), re.M):
            problems.append("deploy workflow needs a '# deploy-paths: <path> ...' line")
    jobs = wf.get("jobs") or {}
    validators = {j for j, job in jobs.items()
                  if any(".method/scripts/validate.sh" in str(step.get("run") or "") for step in job.get("steps") or [])}
    if not validators:
        problems.append("deploy workflow needs a job that runs .method/scripts/validate.sh before the build")
        return problems

    for job_id in sorted(validators):
        job = jobs[job_id]
        steps = job.get("steps") or []
        gate_at = [i for i, st in enumerate(steps) if ".method/scripts/ci-already-green.sh" in str(st.get("run") or "")]
        if not gate_at:
            problems.append("job %s: must run .method/scripts/ci-already-green.sh before .method/scripts/validate.sh" % job_id)
        else:
            gate_ids = [steps[i].get("id") for i in gate_at if steps[i].get("id")]
            for i, st in enumerate(steps):
                if ".method/scripts/validate.sh" not in str(st.get("run") or ""):
                    continue
                cond = str(st.get("if") or "")
                ok = i > gate_at[0] and any(
                    re.search(r"steps\.%s\.outputs\.skip\s*(!=\s*'true'|==\s*'false')" % re.escape(g), cond)
                    for g in gate_ids)
                if not ok:
                    problems.append("job %s: .method/scripts/validate.sh must run only when the gate says skip != true "
                                    "(if: steps.<gate id>.outputs.skip != 'true')" % job_id)
        if (job.get("permissions") or {}).get("checks") != "read":
            problems.append("job %s: needs permissions: checks: read for .method/scripts/ci-already-green.sh" % job_id)

    def reaches(job_id, seen=()):
        if job_id in validators:
            return True
        return any(reaches(n, seen + (job_id,)) for n in needs_of(jobs.get(job_id) or {}) if n not in seen)

    for job_id in jobs:
        if not reaches(job_id):
            problems.append("job %s: must need the job that runs .method/scripts/validate.sh" % job_id)
    return problems


def check(path):
    problems = []
    base = os.path.basename(path)
    if not NAME_RE.match(base):
        problems.append("file name must be ci.yml or <deploy|issues|release|bot>-<purpose>.yml")
    wf = load(path) or {}
    for key in ("name", "run-name", "concurrency"):
        if not wf.get(key):
            problems.append("missing top-level %s" % key)
    if wf.get("permissions", None) != {}:
        problems.append("top-level permissions must be {} (grant per job)")
    on = wf.get("on")
    triggers = set(on) if isinstance(on, dict) else set(on if isinstance(on, list) else [on])
    if base == "ci.yml":
        problems.extend(ci_trigger_problems(path, on, triggers))
    if "push" in triggers and not base.startswith(("release-", "ci.yml")):
        problems.append("push trigger only for release- workflows")
    if base.startswith("deploy-"):
        problems.extend(check_deploy(path, wf, triggers))
    for job_id, job in (wf.get("jobs") or {}).items():
        where = "job %s" % job_id
        if not job.get("name"):
            problems.append("%s: missing name" % where)
        if "uses" not in job and not job.get("runs-on"):
            problems.append("%s: missing runs-on" % where)
        t = job.get("timeout-minutes")
        if "uses" not in job and not (isinstance(t, int) and 5 <= t <= 30):
            problems.append("%s: timeout-minutes must be 5-30 (got %s)" % (where, t))
        for i, step in enumerate(job.get("steps") or [], 1):
            if not step.get("name"):
                problems.append("%s: step %d missing name" % (where, i))
    return problems


def main(argv):
    if len(argv) > 1 and argv[1] in ("-h", "--help"):
        print(__doc__.strip())
        return 0
    files = argv[1:] or sorted(glob.glob(".github/workflows/*.yml") + glob.glob(".github/workflows/*.yaml"))
    fail = 0
    checked = []
    for f in files:
        if not NAME_RE.match(os.path.basename(f)):
            print("skip: %s is an application workflow (not checked)" % f)
            continue
        checked.append(f)
        for p in check(f):
            print("%s: %s" % (f, p))
            fail = 1
    if not fail:
        print("ok: %d workflows follow the standard" % len(checked))
    return fail


if __name__ == "__main__":
    sys.exit(main(sys.argv))
