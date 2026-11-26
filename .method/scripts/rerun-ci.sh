#!/usr/bin/env bash
#: rerun-ci.sh: rerun only the failed jobs of one ci.yml run on the PR head.
#:
#: Usage: rerun-ci.sh <run-id>
#:
#: Refuses any other workflow, a run whose SHA is not the head of its open pull
#: request, and a run with no failed job (failure, timed_out or cancelled). After RERUN_CI_LIMIT reruns (default 2)
#: it stops and offers an issue; it does not rerun again.
#:
#: A raw `gh run rerun` stays blocked by the hook and by the deny list, including
#: a deploy rerun. This script is the only rerun of an intermittent CI job.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"
ROOT="$(cd "$HERE/.." && pwd)"

[ "${1:-}" != -h ] && [ "${1:-}" != --help ] || { print_help "$0"; exit 0; }
[ $# -eq 1 ] || die "usage: rerun-ci.sh <run-id>" 2
case "$1" in
  *[!0-9]*) die "run id must be a number" 2 ;;
esac
run="$1"
slug="$(repo_slug)"
meta="$(gh api "repos/$slug/actions/runs/$run")" || die "could not read run $run; nothing was rerun"
path="$(printf '%s' "$meta" | jq -r '.path // empty')"
head="$(printf '%s' "$meta" | jq -r '.head_sha // empty')"
[ "$path" = ".github/workflows/ci.yml" ] ||
  die "refuses run $run of ${path:-an unknown workflow}: only .github/workflows/ci.yml; nothing was rerun"
[ -n "$head" ] || die "run $run has no head SHA; nothing was rerun"
pr="$(printf '%s' "$meta" | jq -r '.pull_requests[0].number // empty')"
if [ -z "$pr" ]; then
  pr="$(gh api "repos/$slug/commits/$head/pulls" --jq '[.[] | select(.state == "open")][0].number // empty' 2>/dev/null || true)"
fi
[ -n "$pr" ] || die "run $run is not on an open pull request; nothing was rerun"
pr_head="$(gh pr view "$pr" --repo "$slug" --json headRefOid --jq .headRefOid)" ||
  die "could not read the head of PR #$pr; nothing was rerun"
[ "$pr_head" = "$head" ] || die "run $run is not the HEAD of PR #$pr; nothing was rerun"
jobs="$(gh api "repos/$slug/actions/runs/$run/jobs")" || die "could not read the jobs of run $run; nothing was rerun"
failed="$(printf '%s' "$jobs" | jq '[.jobs[]? | select(.conclusion == "failure" or .conclusion == "timed_out" or .conclusion == "cancelled")] | length')"
[ "${failed:-0}" -gt 0 ] || die "run $run has no failed job; nothing was rerun"
limit="${RERUN_CI_LIMIT:-2}"
case "$limit" in ''|*[!0-9]*) die "RERUN_CI_LIMIT must be a number" 2 ;; esac
dir="$ROOT/.process/rerun-ci"
mkdir -p "$dir"
count=0
[ -f "$dir/$run" ] && count="$(tr -dc '0-9' <"$dir/$run" || true)"
count="${count:-0}"
if [ "$count" -ge "$limit" ]; then
  echo "offer: the failed jobs of ci.yml run $run failed again after $count reruns; open an issue with scripts/open-issue.sh --type finding --size small"
  exit 1
fi
n=$((count + 1))
printf '%s\n' "$n" >"$dir/$run"
gh run rerun "$run" --failed --repo "$slug"
echo "reran the failed jobs of ci.yml run $run (attempt $n of $limit)"
