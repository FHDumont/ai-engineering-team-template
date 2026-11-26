#!/usr/bin/env bash
#: check-attribution.sh: fail on text with an AI attribution.
#:
#: Usage:
#:   check-attribution.sh --range <base>..<head>   # commit messages
#:   check-attribution.sh --pr <number>            # PR commits and body (gh)
#:   check-attribution.sh --text-file <file|->     # any text (hooks, tests)
#: Options can be combined. Exits 1 and lists the hits; exits 0 when clean.
#:
#: Blocked, always at the start of a line: the co-author trailer, "Generated
#: with|by Claude" and the robot emoji (alone or opening the line). The same
#: text in the middle of a sentence only cites the rule and passes.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"

# Patterns as extended regex, case-insensitive.
# A signature opens a line: the trailer, "Generated with|by Claude" (with or
# without the emoji) and the robot emoji by itself. The same words in the middle
# of a sentence only cite the rule and pass.
PATTERNS='^[[:space:]]*co-authored-by:|^[[:space:]]*(🤖[[:space:]]*)?generated (with|by) \[?claude|^[[:space:]]*🤖|^[[:space:]]*[a-z-]+:.*noreply@anthropic\.com'

found=0
check() { # check <label> <text>
  local hits
  hits="$(printf '%s\n' "$2" | grep -inE "$PATTERNS" || true)"
  if [ -n "$hits" ]; then
    found=1
    echo "AI attribution in $1:"
    printf '%s\n' "$hits" | sed 's/^/  /'
  fi
}

[ $# -gt 0 ] || { print_help "$0"; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --range)
      while read -r sha; do
        [ -n "$sha" ] || continue
        check "commit ${sha:0:12}" "$(git log -1 --format=%B "$sha")"
      done <<<"$(git rev-list "$2")"
      shift 2 ;;
    --pr)
      require_cmd gh
      check "PR #$2 body" "$(gh pr view "$2" --json body --jq .body)"
      while IFS= read -r line; do
        check "PR #$2 commit" "$line"
      done <<<"$(gh pr view "$2" --json commits --jq '.commits[] | .messageHeadline + "\n" + .messageBody')"
      shift 2 ;;
    --text-file)
      if [ "$2" = - ]; then check "text" "$(cat)"; else check "$2" "$(cat "$2")"; fi
      shift 2 ;;
    *) die "unknown option: $1 (see --help)" 2 ;;
  esac
done
[ "$found" = 0 ] && echo "ok: no AI attribution"
exit "$found"
