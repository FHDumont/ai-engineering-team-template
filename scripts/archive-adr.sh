#!/usr/bin/env bash
#: archive-adr.sh: mark an ADR as replaced in the index and move it to adr/archive/.
#:
#: Usage: archive-adr.sh <NNN> --by <MMM> [--dry-run]
#:
#: Example: archive-adr.sh 001 --by 004 moves docs/adr/ADR-001-*.md (or
#: ADR-001.md, when the name has no title) to docs/adr/archive/ (git mv),
#: fixes the link in docs/adr/INDEX.md and marks the line "substituída por
#: ADR-004". Does not commit. Without the line of the ADR in the index it
#: exits 1 and moves nothing; at the end it reads the file and the line back.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"

[ $# -gt 0 ] || { print_help "$0"; exit 2; }
case "$1" in -h|--help) print_help "$0"; exit 0 ;; esac
old="$1"; shift
by="" dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --by) by="$2"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) die "unknown option: $1 (see --help)" 2 ;;
  esac
done
[ -n "$by" ] || die "--by is required" 2
ROOT="${REPO_ROOT:-$(cd "$HERE/.." && pwd)}"
cd "$ROOT"

# ADR-NNN-title.md or ADR-NNN.md. A repository that already numbered its
# decisions as ADR-NNN.md does not have to rename them.
adr_path() { # adr_path <NNN>
  local n="$1" f
  f="$(ls docs/adr/ADR-"$n"-*.md 2>/dev/null | head -1 || true)"
  if [ -n "$f" ]; then
    printf '%s\n' "$f"
    return 0
  fi
  if [ -f "docs/adr/ADR-$n.md" ]; then
    printf '%s\n' "docs/adr/ADR-$n.md"
    return 0
  fi
  return 1
}
file="$(adr_path "$old" || true)"
[ -n "$file" ] || die "ADR-$old not found in docs/adr/"
adr_path "$by" >/dev/null || die "ADR-$by not found (create the new ADR first)"
name="$(basename "$file")"

# The index must have the line of the ADR before anything moves.
grep -qE "^\|.*ADR-$old([^0-9]|\$)" docs/adr/INDEX.md 2>/dev/null ||
  die "ADR-$old has no line in docs/adr/INDEX.md (nothing was moved)"

if [ "$dry" = 1 ]; then
  echo "would move $file to docs/adr/archive/$name and mark it substituída por ADR-$by"
  exit 0
fi
mkdir -p docs/adr/archive
if git ls-files --error-unmatch "$file" >/dev/null 2>&1; then
  git mv "$file" "docs/adr/archive/$name"
else
  mv "$file" "docs/adr/archive/$name"
fi
# Index line: link to the file and the status "substituída por ADR-MMM".
python3 - "$old" "$by" "$name" <<'PY'
import re, sys
old, by, name = sys.argv[1:]
path = "docs/adr/INDEX.md"
lines = open(path, encoding="utf-8").read().splitlines()
out = []
for line in lines:
    if re.search(r"ADR-%s\b" % old, line) and line.startswith("|"):
        line = line.replace("(%s)" % name, "(archive/%s)" % name)
        cells = line.split("|")
        cells[-2] = " substituída por ADR-%s " % by
        line = "|".join(cells)
    out.append(line)
open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
PY
# Read back: the file is in archive/, gone from docs/adr/, and the index says so.
[ -f "docs/adr/archive/$name" ] && [ ! -e "$file" ] || die "ADR-$old was not moved to docs/adr/archive/$name"
grep -F "(archive/$name)" docs/adr/INDEX.md | stdin_grep -qF "substituída por ADR-$by" ||
  die "docs/adr/INDEX.md does not show ADR-$old as archived and replaced by ADR-$by (the file was moved; fix the index line by hand)"
echo "archived ADR-$old (replaced by ADR-$by, read back)"
