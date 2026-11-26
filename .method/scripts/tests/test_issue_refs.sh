#!/usr/bin/env bash
# A copied method file must not cite a bare #n (#147).
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"
out="$(python3 - "$REPO" <<'PY'
import os, re, sys
root = sys.argv[1]
pat = re.compile(r"(?<![A-Za-z0-9_/])#([0-9]{1,4})(?![0-9A-Za-z])")
skip = ("/.method/scripts/tests/", "/.claude/hooks/tests/")
bad = []
# Only the files of the method: the manifest, .method/scripts/lib/ and the two workflows. A repo
# that adopts the method has scripts of its own that may cite #n (#245).
manifest = set()
mf = os.path.join(root, ".github", "method-files.txt")
if os.path.exists(mf):
    for l in open(mf, encoding="utf-8"):
        l = l.strip()
        if l and not l.startswith("#"):
            manifest.add(l.rstrip("/"))
def in_method(rel):
    if rel.startswith(".method/scripts/lib/") or rel in ("docs/process-design.md", ".github/workflows/ci.yml", ".github/workflows/issues-label.yml"):
        return True
    return rel in manifest or any(rel.startswith(m + "/") for m in manifest)
for dirpath, _, files in os.walk(root):
    for name in files:
        path = os.path.join(dirpath, name)
        rel = os.path.relpath(path, root)
        if any(s in "/" + rel for s in skip):
            continue
        if not rel.startswith(("docs/process-design.md", ".method/scripts/", ".github/workflows/")):
            continue
        if not in_method(rel):
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
