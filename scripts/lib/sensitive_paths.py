"""Match paths against the globs in .github/sensitive-paths.

Usage: sensitive_paths.py <globs-file> < list-of-paths
Prints the sensitive paths, one per line; always exits 0 (empty = none).
"""

import re
import sys


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


def sensitive(paths, globs):
    regs = [glob_to_regex(g) for g in globs]
    return [p for p in paths if any(r.match(p) for r in regs)]


def main(argv):
    if len(argv) != 2 or argv[1] in ("-h", "--help"):
        print(__doc__.strip())
        return 0 if len(argv) == 2 else 2
    paths = [l.strip() for l in sys.stdin if l.strip()]
    for p in sensitive(paths, load_globs(argv[1])):
        print(p)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
