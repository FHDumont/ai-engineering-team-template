#!/usr/bin/env bash
#: ci-already-green.sh: say whether this SHA, or the same tree, already has green CI.
#:
#: Usage: ci-already-green.sh [sha]
#:
#: Prints skip=true when the check CI of the SHA is success, or when it is
#: missing or skipped and a merged pull request of the same tree had CI success.
#: Prints skip=false when the check is absent, red, or the API cannot be read:
#: the suite runs. Always exits 0.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=.method/scripts/lib/common.sh
source "$HERE/lib/common.sh"

[ "${1:-}" != -h ] && [ "${1:-}" != --help ] || { print_help "$0"; exit 0; }
sha="${1:-HEAD}"
slug="$(repo_slug)"
say() { printf 'skip=%s\n' "$1"; exit 0; }

ci_of() { # ci_of <sha> -> status/conclusion, or empty when the API fails
  local json
  json="$(gh api "repos/$slug/commits/$1/check-runs?per_page=100" 2>/dev/null)" || return 1
  printf '%s' "$json" | jq -r '[.check_runs[]? | select(.name == "CI")] | sort_by(.started_at // "") | last
    | if . == null then "absent" else "\(.status)/\(.conclusion // "none")" end'
}

ci="$(ci_of "$sha")" || say false
[ "$ci" = "completed/success" ] && say true

tree="$(git rev-parse "$sha^{tree}" 2>/dev/null || true)"
if [ -z "$tree" ]; then
  tree="$(gh api "repos/$slug/git/commits/$sha" 2>/dev/null | jq -r '.tree.sha // empty' || true)"
fi
[ -n "$tree" ] || say false
prs="$(gh api "repos/$slug/commits/$sha/pulls" 2>/dev/null | jq -r '.[]? | select(.merged_at != null) | "\(.number) \(.head.sha)"' || true)"
[ -n "$prs" ] || say false
while read -r _ head; do
  [ -n "$head" ] || continue
  hci="$(ci_of "$head" || true)"
  [ "$hci" = "completed/success" ] || continue
  htree="$(gh api "repos/$slug/git/commits/$head" 2>/dev/null | jq -r '.tree.sha // empty' || true)"
  [ "$htree" = "$tree" ] && say true
done <<EOF
$prs
EOF
say false
