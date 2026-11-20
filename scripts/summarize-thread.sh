#!/usr/bin/env bash
#: summarize-thread.sh: keep the pinned summary comment (<!-- agreed-summary -->) of an issue.
#:
#: Usage:
#:   summarize-thread.sh <issue> --check              # tells if it is past 10 comments
#:   summarize-thread.sh <issue> --summary-file F     # creates or edits the summary in place
#:
#: Claude writes the summary; the script only finds the marked comment and
#: updates it (or creates it the first time). --check exits 0 if a summary is
#: needed, 1 if not.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"

MARK="<!-- agreed-summary -->"
[ $# -gt 0 ] || { print_help "$0"; exit 2; }
case "$1" in -h|--help) print_help "$0"; exit 0 ;; esac
issue="$1"; shift
mode="" file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check) mode=check; shift ;;
    --summary-file) mode="write"; file="$2"; shift 2 ;;
    *) die "unknown option: $1 (see --help)" 2 ;;
  esac
done
[ -n "$mode" ] || die "use --check or --summary-file" 2
repo="$(repo_slug)"
comments="$(gh api "repos/$repo/issues/$issue/comments" --paginate --slurp | jq -c 'add // []')"

if [ "$mode" = check ]; then
  n="$(echo "$comments" | jq --arg m "$MARK" '[.[] | select(.body | contains($m) | not)] | length')"
  if [ "$n" -ge 10 ]; then echo "summary needed: $n comments"; exit 0; fi
  echo "no summary needed: $n comments"; exit 1
fi

[ -f "$file" ] || die "summary file not found: $file"
body="$(printf '%s\n%s\n' "$MARK" "$(cat "$file")")"
existing="$(echo "$comments" | jq -r --arg m "$MARK" '[.[] | select(.body | contains($m))] | last | .id // empty')"
if [ -n "$existing" ]; then
  gh api -X PATCH "repos/$repo/issues/comments/$existing" -f body="$body" --jq .html_url
  echo "updated summary"
else
  printf '%s' "$body" | gh issue comment "$issue" --repo "$repo" --body-file -
  echo "created summary"
fi
