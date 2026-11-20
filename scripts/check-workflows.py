#!/usr/bin/env python3
"""check-workflows.py: check the workflow standard (design §9), beyond actionlint.

Usage: check-workflows.py [file.yml ...]   (default: .github/workflows/*.yml)

Rules: file name `ci.yml` or `<category>-<purpose>.yml` (categories deploy,
issues, release, bot); top-level `name` and `run-name`; top-level
`permissions: {}`; `concurrency` set; every job with `name`, `runs-on` and
`timeout-minutes` between 5 and 30; every step with `name`; `ci.yml` runs
only on `pull_request` (no CI on push to main). A deploy workflow
(`deploy-*.yml`) runs only on `workflow_dispatch` (never `pull_request`,
`push` or `schedule`), has a `# deploy-paths:` line (what it deploys, read by
scripts/deploy.sh) and a job that runs `scripts/validate.sh` which every
other job needs. Reads YAML with `yq` (or PyYAML). Exits 1 and lists the
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


def needs_of(job):
    needs = job.get("needs") or []
    return [needs] if isinstance(needs, str) else list(needs)


def check_deploy(path, wf, triggers):
    """Rules of a deploy workflow: dispatched only by scripts/deploy.sh, main tested first."""
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
                  if any("scripts/validate.sh" in str(step.get("run") or "") for step in job.get("steps") or [])}
    if not validators:
        problems.append("deploy workflow needs a job that runs scripts/validate.sh before the build")
        return problems

    def reaches(job_id, seen=()):
        if job_id in validators:
            return True
        return any(reaches(n, seen + (job_id,)) for n in needs_of(jobs.get(job_id) or {}) if n not in seen)

    for job_id in jobs:
        if not reaches(job_id):
            problems.append("job %s: must need the job that runs scripts/validate.sh" % job_id)
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
    if base == "ci.yml" and triggers != {"pull_request"}:
        problems.append("ci.yml must run only on pull_request (got %s)" % ", ".join(sorted(map(str, triggers))))
    if "push" in triggers and not base.startswith("release-"):
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
    for f in files:
        for p in check(f):
            print("%s: %s" % (f, p))
            fail = 1
    if not fail:
        print("ok: %d workflows follow the standard" % len(files))
    return fail


if __name__ == "__main__":
    sys.exit(main(sys.argv))
