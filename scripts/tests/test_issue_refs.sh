#!/usr/bin/env bash
# A copied method file must not cite a bare #n (#147).
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"
out="$(python3 - "$REPO" <<'PY'
import os, re, sys
root = sys.argv[1]
pat = re.compile(r"(?<![A-Za-z0-9_/])#([0-9]{1,4})(?![0-9A-Za-z])")
skip = ("/scripts/tests/", "/.claude/hooks/tests/")
bad = []
for dirpath, _, files in os.walk(root):
    for name in files:
        path = os.path.join(dirpath, name)
        rel = os.path.relpath(path, root)
        if any(s in "/" + rel for s in skip):
            continue
        if not rel.startswith(("docs/process-design.md", "scripts/", ".github/workflows/")):
            continue
        if "/tests/" in "/" + rel or "__pycache__" in rel or rel.endswith(".pyc"):
            continue
        text = open(path, encoding="utf-8", errors="replace").read()
        for i, line in enumerate(text.splitlines(), 1):
            if pat.search(line):
                bad.append("%s:%d:%s" % (rel, i, line.strip()[:160]))
print("\n".join(bad))
PY
)"
assert_eq "" "$out" "method files cite issues as FHDumont/ai-engineering-team-template#n"
finish
