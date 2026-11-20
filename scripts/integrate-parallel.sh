#!/usr/bin/env bash
#: integrate-parallel.sh: wait for all parallel phases to merge and leave main ready for the end step.
#:
#: Usage: integrate-parallel.sh [--timeout seconds] [--interval seconds] [--dry-run]
#:
#: Reads .worktrees/parallel-active.tsv (written by open-parallel.sh;
#: close-phase.sh --cleanup takes out the line of each phase that merges), waits
#: until the PR of each branch is merged, updates the local main, removes the
#: worktrees that are left and clears the registry. Only then runs
#: scripts/build.sh, if it exists. An empty registry means nothing to wait for.
#: It never deploys: the end step belongs to the main session (gen-docs.sh,
#: deploy.sh, archiving the child sessions, end-check.sh), the same for a solo
#: and a parallel group. It only waits: a conflicting PR is redone by the phase
#: session (close-phase.sh --check calls redo-phase.sh, which rewrites the
#: registry line). Exits 3 on timeout.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"

timeout=7200 interval=60 dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --timeout) timeout="$2"; shift 2 ;;
    --interval) interval="$2"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) die "unknown option: $1 (see --help)" 2 ;;
  esac
done

main_root="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
registry="$main_root/.worktrees/parallel-active.tsv"
# close-phase.sh --cleanup takes each merged phase out of the registry: an empty
# registry means there is nothing left to wait for.
if [ ! -s "$registry" ]; then
  echo "no parallel phase registered: nothing to wait for"
  registry=/dev/null
fi
repo="$(repo_slug)"

start="$(date +%s)"
while :; do
  pending=0
  # The registry is only read here: redo-phase.sh rewrites the line of a redone phase.
  while IFS="$(printf '\t')" read -r n branch path; do
    state="$(gh pr list --repo "$repo" --head "$branch" --state all --json state --jq '.[0].state // "NONE"')"
    if [ "$state" != MERGED ]; then
      pending=$((pending + 1))
      echo "waiting: #$n ($branch) is $state"
    fi
  done <"$registry"
  [ "$pending" -gt 0 ] || break
  [ $(( $(date +%s) - start )) -lt "$timeout" ] || { echo "timeout: $pending phases not merged"; exit 3; }
  sleep "$interval"
done
echo "all parallel phases merged"

if [ "$dry" = 1 ]; then
  echo "dry-run: would update main, remove worktrees and build"
  exit 0
fi
git -C "$main_root" switch --quiet main
git -C "$main_root" fetch --quiet origin main
git -C "$main_root" merge --quiet --ff-only origin/main
while IFS="$(printf '\t')" read -r n branch path; do
  git -C "$main_root" worktree remove "$path" 2>/dev/null || true
  git -C "$main_root" branch -D "$branch" 2>/dev/null || true
done <"$registry"
[ "$registry" = /dev/null ] || rm -f "$registry"
echo "main updated, worktrees removed"

# The group's single deploy: every phase is in through the gate.
if [ -x "$main_root/scripts/build.sh" ]; then
  "$main_root/scripts/build.sh"
fi
echo "next, by the main session, once: scripts/gen-docs.sh, scripts/deploy.sh, archive the child sessions, scripts/end-check.sh"
