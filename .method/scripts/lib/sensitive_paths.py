"""Match paths against method globs plus .github/sensitive-paths.

The method paths live in this file. The repo file only adds globs; an
update of the method adds new method paths without deleting repo ones.

The globs file has two classes, set by comment lines `# class: owner-ok` and
`# class: gate`. A glob before any such line is owner-ok, so a file with no
class lines (an adopter's old list) is all owner-ok, except the method's
gate paths (METHOD_GATE_GLOBS), which are gate whatever the file says. A path
in both classes, or in the method paths or a write-token workflow, is owner-ok.

Usage: [SENSITIVE_CLASS=owner-ok|gate] sensitive_paths.py <globs-file> < paths
Paths come one per line, or NUL separated. Prints the sensitive paths, one per
line (only those of the class in SENSITIVE_CLASS, when set); always exits 0
(empty = none).
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
    ".method/scripts/lib/procs.sh",
    "scripts/sessions.sh",
    ".method/scripts/sessions.sh",
    "scripts/start-headless.sh",
    ".method/scripts/start-headless.sh",
    "scripts/setup-repo.sh",
    ".method/scripts/setup-repo.sh",
)
# The gate itself and the dependencies. Gate by code: a repository list in the old
# single-class format that names them as owner-ok does not call the owner back (FHDumont/ai-engineering-team-template#207).
METHOD_GATE_GLOBS = (
    ".github/workflows/deploy-*.yml",
    ".github/workflows/ci.yml",
    ".github/sensitive-paths",
    "scripts/ci-gate.sh",
    ".method/scripts/ci-gate.sh",
    "scripts/check-attribution.sh",
    ".method/scripts/check-attribution.sh",
    "scripts/check-docs.sh",
    ".method/scripts/check-docs.sh",
    "scripts/close-phase.sh",
    ".method/scripts/close-phase.sh",
    "scripts/lib/sensitive_paths.py",
    ".method/scripts/lib/sensitive_paths.py",
    "package-lock.json",
    "**/package-lock.json",
    "pnpm-lock.yaml",
    "**/pnpm-lock.yaml",
    "yarn.lock",
    "**/yarn.lock",
    "poetry.lock",
    "uv.lock",
    "requirements*.txt",
    "Gemfile.lock",
    "go.sum",
    "Cargo.lock",
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


CLASS_LINE = re.compile(r"^#\s*class:\s*(owner-ok|gate)\s*$")


def load_classed(path):
    """The globs of the file as (glob, class) pairs; the class lines are comments."""
    out, cls = [], "owner-ok"
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            m = CLASS_LINE.match(line)
            if m:
                cls = m.group(1)
            elif line and not line.startswith("#"):
                out.append((line, cls))
    return out


def sensitive_class(paths, globs_file, cls, root="."):
    """The sensitive paths of one class. owner-ok wins when a path is in both,
    except for the method's own gate paths, which are gate whatever the file says."""
    classed = load_classed(globs_file)
    owner_regs = [glob_to_regex(g) for g in METHOD_GLOBS + tuple(g for g, c in classed if c == "owner-ok")]
    method_gate = [glob_to_regex(g) for g in METHOD_GATE_GLOBS]
    gate_regs = method_gate + [glob_to_regex(g) for g, c in classed if c == "gate"]

    def hit(regs, p):
        return any(r.match(p) for r in regs)

    # A write-token workflow is owner-ok by its content, unless a gate glob names it.
    owner = {p for p in paths
             if (hit(owner_regs, p) and not hit(method_gate, p))
             or (workflow_has_write_token(p, root) and not hit(gate_regs, p))}
    allhits = [p for p in paths if p in owner or hit(gate_regs, p)]
    if cls == "owner-ok":
        return [p for p in allhits if p in owner]
    return [p for p in allhits if p not in owner]


def merged_globs(repo_globs):
    out = list(METHOD_GLOBS) + list(METHOD_GATE_GLOBS)
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


def sensitive(paths, globs, root=".", write_token=True):
    regs = [glob_to_regex(g) for g in merged_globs(globs)]
    hits = []
    for p in paths:
        if any(r.match(p) for r in regs) or (write_token and workflow_has_write_token(p, root)):
            hits.append(p)
    return hits


def main(argv):
    if len(argv) != 2 or argv[1] in ("-h", "--help"):
        print(__doc__.strip())
        return 0 if len(argv) == 2 else 2
    raw = sys.stdin.buffer.read()
    chunks = raw.split(b"\0") if b"\0" in raw else raw.splitlines()
    paths = []
    for chunk in chunks:
        line = chunk.decode("utf-8", "surrogateescape").strip()
        if line:
            paths.append(line)
    root = os.getcwd()
    cls = os.environ.get("SENSITIVE_CLASS", "")
    if cls in ("owner-ok", "gate"):
        hits = sensitive_class(paths, argv[1], cls, root=root)
    else:
        hits = sensitive(paths, load_globs(argv[1]), root=root)
    for p in hits:
        print(p)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
