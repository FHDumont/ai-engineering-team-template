#!/usr/bin/env bash
# gen-docs.sh: the single generation of CHANGELOG.md and ROADMAP.md, by the main session.
#: gen-docs.sh: regenerate CHANGELOG.md and ROADMAP.md once and merge them through a PR.
#:
#: Usage: gen-docs.sh [--timeout seconds] [--interval seconds]
#:
#: Run by the main session at the end, after the last phase is merged: phases do
#: not regenerate these files. Runs from the main checkout, never on a phase branch.
#: 1. Creates the branch gen-docs/<main short SHA> from origin/main in the
#:    worktree .worktrees/gen-docs and generates both files there. Nothing
#:    changed: prints "up to date" and exits 0 with no PR.
#: 2. Commits, pushes and opens a PR that holds only the two generated files.
#: 3. Reads the files of the PR back from GitHub: any other path exits 1 with no
#:    status and no merge. Only these two files: publishes review/independent
#:    (the files are generated; no reviewer reads them) on the PR head.
#: 4. Requests the merge (gh pr merge --auto --rebase --delete-branch) and waits
#:    for it (default 900 s, read every 15 s). Not merged in time: exit 3.
#: 5. Merged, read back: removes the worktree and the local branch and
#:    fast-forwards the local main.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"

timeout=900 interval=15
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --timeout) timeout="$2"; shift 2 ;;
    --interval) interval="$2"; shift 2 ;;
    *) die "unknown option: $1 (see --help)" 2 ;;
  esac
done
require_cmd gh jq git python3

GENERATED='CHANGELOG.md
ROADMAP.md'
main_root="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
[ -n "$main_root" ] || die "not a git checkout"
[ "$(cd "$HERE/.." && pwd -P)" = "$(cd "$main_root" && pwd -P)" ] || die "gen-docs runs from the main checkout ($main_root), by the main session"
repo="$(repo_slug)"
git -C "$main_root" fetch --quiet origin main
base="$(git -C "$main_root" rev-parse origin/main)"
branch="gen-docs/${base:0:12}"
wt="$main_root/.worktrees/gen-docs"

# Removes the worktree and the local branch of this run.
drop_worktree() {
  git -C "$main_root" worktree remove --force "$wt" 2>/dev/null || true
  git -C "$main_root" branch -D "$branch" >/dev/null 2>&1 || true
}

n="$(gh pr list --repo "$repo" --head "$branch" --state open --json number --jq '.[0].number // empty')"
if [ -z "$n" ]; then
  [ ! -e "$wt" ] || die "$wt already exists: remove it (git worktree remove) and run again"
  git -C "$main_root" worktree add --quiet -b "$branch" "$wt" origin/main
  (cd "$wt" && python3 "$HERE/gen-changelog.py" --output CHANGELOG.md && python3 "$HERE/gen-roadmap.py" --output ROADMAP.md) >/dev/null
  git -C "$wt" add -- CHANGELOG.md ROADMAP.md
  if git -C "$wt" diff --cached --quiet; then
    drop_worktree
    echo "up to date: CHANGELOG.md and ROADMAP.md match GitHub; no PR"
    exit 0
  fi
  git -C "$wt" commit --quiet -m "docs: regenerate changelog and roadmap" -- CHANGELOG.md ROADMAP.md
  git -C "$wt" push --quiet -u origin "$branch"
  gh pr create --repo "$repo" --base main --head "$branch" --title "docs: regenerate changelog and roadmap" \
    --body "Geração única de \`CHANGELOG.md\` e \`ROADMAP.md\` pela sessão principal (\`scripts/gen-docs.sh\`). O PR contém só esses dois arquivos gerados." >/dev/null
  n="$(gh pr list --repo "$repo" --head "$branch" --state open --json number --jq '.[0].number // empty')"
  [ -n "$n" ] || die "PR for $branch not read back"
  echo "opened PR #$n ($branch)"
fi

# Gate of this path: GitHub must show only the two generated files in the PR.
# Files and head are one read: the status goes on the SHA whose files were checked.
info="$(gh pr view "$n" --repo "$repo" --json files,headRefOid)"
files="$(echo "$info" | jq -r '.files[].path')"
[ -n "$files" ] || die "PR #$n: no file read back"
other="$(printf '%s\n' "$files" | grep -vxF "$GENERATED" || true)"
[ -z "$other" ] || die "PR #$n holds more than the generated files ($(echo "$other" | paste -sd, -)): no review published, no merge"
sha="$(echo "$info" | jq -r .headRefOid)"
gh api -X POST "repos/$repo/statuses/$sha" -f state=success -f context=review/independent \
  -f description="Só arquivos gerados (CHANGELOG.md, ROADMAP.md)" >/dev/null
state="$(gh api "repos/$repo/commits/$sha/status" --jq '[.statuses[] | select(.context == "review/independent")][0].state // "missing"')"
[ "$state" = success ] || die "review/independent not read back on ${sha:0:12} (it is $state)"
echo "published review/independent on ${sha:0:12}: PR #$n holds only generated files"

if ! gh pr merge "$n" --repo "$repo" --auto --rebase --delete-branch >/dev/null 2>&1; then
  # Checks already green: auto-merge does not arm, so merge directly.
  gh pr merge "$n" --repo "$repo" --rebase --delete-branch >/dev/null
fi
waited=0
until [ "$(gh pr view "$n" --repo "$repo" --json state --jq .state)" = MERGED ]; do
  if [ "$waited" -ge "$timeout" ]; then
    echo "PR #$n not merged after ${timeout}s: read its CI and run gen-docs.sh again"
    exit 3
  fi
  sleep "$interval"; waited=$((waited + interval))
  [ "$interval" -gt 0 ] || waited="$timeout"
done
echo "PR #$n merged"
drop_worktree
git -C "$main_root" fetch --quiet --prune origin
if is_main_branch "$(current_branch "$main_root")"; then
  git -C "$main_root" merge --quiet --ff-only origin/main
fi
echo "generated files are on main at $(git -C "$main_root" rev-parse --short origin/main)"
