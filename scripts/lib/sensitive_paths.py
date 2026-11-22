"""Match paths against method globs plus .github/sensitive-paths.

The method paths live in this file. The repo file only adds globs; an
update of the method adds new method paths without deleting repo ones.

Usage: sensitive_paths.py <globs-file> < list-of-paths
Prints the sensitive paths, one per line; always exits 0 (empty = none).
"""

import os
import re
import sys

# Locks, agent settings, git hooks, Actions, and scripts that kill processes,
# open sessions or change protection. Workflows with a write token are matched
# by content, not by this list.
METHOD_GLOBS = (
    ".claude/hooks/**",
    ".claude/settings.json",
    ".githooks/**",
    ".github/actions/**",
    "scripts/lib/procs.sh",
    "scripts/sessions.sh",
    "scripts/start-headless.sh",
    "scripts/setup-repo.sh",
)
WRITE_PERM = re.compile(r"(?m)^\s+[A-Za-z-]+:\s+write\s*$")


def glob_to_regex(glob):
    """Converts a glob with `**` (any number of folders) into an anchored regex."""
    out, i = [], 0
    while i < len(glob):
        c = glob[i]
        if glob.startswith("**/", i):
            out.append("(?:.*/)?")
            i += 3
            continue
        if glob.startswith("**", i):
            out.append(".*")
            i += 2
            continue
        if c == "*":
            out.append("[^/]*")
        elif c == "?":
            out.append("[^/]")
        else:
            out.append(re.escape(c))
        i += 1
    return re.compile("^" + "".join(out) + "$")


def load_globs(path):
    with open(path, encoding="utf-8") as f:
        return [l.strip() for l in f if l.strip() and not l.lstrip().startswith("#")]


def merged_globs(repo_globs):
    out = list(METHOD_GLOBS)
    for g in repo_globs:
        if g not in out:
            out.append(g)
    return out


def workflow_has_write_token(path, root="."):
    if not re.match(r"^\.github/workflows/[^/]+\.ya?ml$", path):
        return False
    try:
        text = open(os.path.join(root, path), encoding="utf-8").read()
    except OSError:
        return True
    return bool(WRITE_PERM.search(text))


def sensitive(paths, globs, root="."):
    regs = [glob_to_regex(g) for g in merged_globs(globs)]
    hits = []
    for p in paths:
        if any(r.match(p) for r in regs) or workflow_has_write_token(p, root):
            hits.append(p)
    return hits


def main(argv):
    if len(argv) != 2 or argv[1] in ("-h", "--help"):
        print(__doc__.strip())
        return 0 if len(argv) == 2 else 2
    paths = [l.strip() for l in sys.stdin if l.strip()]
    root = os.getcwd()
    for p in sensitive(paths, load_globs(argv[1]), root=root):
        print(p)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
