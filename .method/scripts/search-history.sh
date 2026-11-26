#!/usr/bin/env bash
#: search-history.sh: search a term in the history, cheapest source first.
#:
#: Usage: search-history.sh "term" [--local] [--max N]
#:
#: Order (§7.1): docs/STATE.md + docs/adr/INDEX.md -> ADRs (archived included)
#: -> git (log --grep, log -S; every commit points to its PR) -> GitHub
#: (issues, PRs and comments). --local skips GitHub. Short list.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"
ROOT="${REPO_ROOT:-$(cd "$HERE/.." && pwd)}"

[ $# -gt 0 ] || { print_help "$0"; exit 2; }
case "$1" in -h|--help) print_help "$0"; exit 0 ;; esac
term="$1"; shift
local_only=0 max=8
while [ $# -gt 0 ]; do
  case "$1" in
    --local) local_only=1; shift ;;
    --max) max="$2"; shift 2 ;;
    *) die "unknown option: $1 (see --help)" 2 ;;
  esac
done
cd "$ROOT"

section() { echo "== $1"; }

section "state + adr index"
grep -inF -- "$term" docs/STATE.md docs/adr/INDEX.md 2>/dev/null | head -n "$max" || true

section "adrs"
grep -ilF -- "$term" docs/adr/ADR-*.md docs/adr/archive/*.md 2>/dev/null | head -n "$max" || true

section "git log --grep"
git log --all -i --grep="$term" --format='%h %s' -n "$max" 2>/dev/null || true

section "git log -S"
git log --all -S"$term" --format='%h %s' -n "$max" 2>/dev/null || true

if [ "$local_only" = 0 ] && command -v gh >/dev/null 2>&1; then
  repo="$(repo_slug)"
  section "github issues"
  gh search issues "$term" --repo "$repo" --limit "$max" --json number,title,state,url \
    --jq '.[] | "#\(.number) [\(.state)] \(.title) \(.url)"' 2>/dev/null || true
  section "github prs"
  gh pr list --repo "$repo" --state all --search "$term" --limit "$max" --json number,title,state,url \
    --jq '.[] | "#\(.number) [\(.state)] \(.title) \(.url)"' 2>/dev/null || true
fi
