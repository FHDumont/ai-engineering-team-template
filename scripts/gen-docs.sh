#!/usr/bin/env bash
# gen-docs.sh: the single generation of CHANGELOG.md and ROADMAP.md, by the main session.
#: gen-docs.sh: regenerate CHANGELOG.md and ROADMAP.md once, remove the specs of
#: closed issues and merge both through one PR.
#:
#: Usage: gen-docs.sh [--timeout seconds] [--interval seconds]
#:
#: Run by the main session at the end, after the last phase is merged: phases do
#: not regenerate these files. Runs from the main checkout, never on a phase branch.
#: 1. Creates the branch gen-docs/<main short SHA> from origin/main in the
#:    worktree .worktrees/gen-docs, generates both files there and removes
#:    every docs/specs/*.md that cites no open issue (the spec a group left on
#:    main: close-phase.sh removes it only when the closing phase can). Nothing
#:    generated and no spec to remove: prints "up to date" and exits 0 with no PR.
#: 2. Commits, pushes and opens a PR that holds only the two generated files
#:    and those removals.
#: 3. Reads the files of the PR back from GitHub. It accepts CHANGELOG.md,
#:    ROADMAP.md and docs/specs/*.md files whose status is "removed" and whose
#:    cited issues are all closed. Any other path, a spec added or modified, or
#:    a removed spec that cites an open issue: exits 1 with no status and no
#:    merge. Accepted: publishes review/independent (the files are generated
#:    and the removals follow one rule; no reviewer reads them) on the PR head.
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
SPEC_PATH='^docs/specs/[^/]+\.md$'
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
# Numbers of the open issues, one per line, read from GitHub.
open_issues() {
  gh issue list --repo "$repo" --state open --limit 1000 --json number --jq '.[].number'
}

n="$(gh pr list --repo "$repo" --head "$branch" --state open --json number --jq '.[0].number // empty')"
if [ -z "$n" ]; then
  [ ! -e "$wt" ] || die "$wt already exists: remove it (git worktree remove) and run again"
  git -C "$main_root" worktree add --quiet -b "$branch" "$wt" origin/main
  (cd "$wt" && python3 "$HERE/gen-changelog.py" --output CHANGELOG.md && python3 "$HERE/gen-roadmap.py" --output ROADMAP.md) >/dev/null
  git -C "$wt" add -- CHANGELOG.md ROADMAP.md
  # Specs whose issues are all closed leave main here (the rule of end-check.sh).
  open="$(open_issues)" || die "open issues not read back: no spec removed, no PR"
  for f in "$wt"/docs/specs/*.md; do
    [ -f "$f" ] || continue
    [ -n "$(spec_open_issues "$f" "$open")" ] || git -C "$wt" rm --quiet -- "docs/specs/$(basename "$f")"
  done
  if git -C "$wt" diff --cached --quiet; then
    drop_worktree
    echo "up to date: CHANGELOG.md and ROADMAP.md match GitHub and no spec of closed issues is left; no PR"
    exit 0
  fi
  git -C "$wt" commit --quiet -m "docs: regenerate changelog and roadmap"
  git -C "$wt" push --quiet -u origin "$branch"
  gh pr create --repo "$repo" --base main --head "$branch" --title "docs: regenerate changelog and roadmap" \
    --body "Geração única de \`CHANGELOG.md\` e \`ROADMAP.md\` pela sessão principal (\`scripts/gen-docs.sh\`). O PR contém só esses dois arquivos gerados e a remoção das specs de \`docs/specs/\` cujas issues estão todas fechadas." >/dev/null
  n="$(gh pr list --repo "$repo" --head "$branch" --state open --json number --jq '.[0].number // empty')"
  [ -n "$n" ] || die "PR for $branch not read back"
  echo "opened PR #$n ($branch)"
fi

# Gate of this path: GitHub must show in the PR only the two generated files and
# removals of specs whose issues are all closed.
# Files and head are one read: the status goes on the SHA whose files were checked.
info="$(gh pr view "$n" --repo "$repo" --json files,headRefOid)"
files="$(echo "$info" | jq -r '.files[].path')"
[ -n "$files" ] || die "PR #$n: no file read back"
other="$(printf '%s\n' "$files" | grep -vxF "$GENERATED" | grep -vE "$SPEC_PATH" || true)"
[ -z "$other" ] || die "PR #$n holds more than the generated files and specs ($(echo "$other" | paste -sd, -)): no review published, no merge"
sha="$(echo "$info" | jq -r .headRefOid)"
specs="$(printf '%s\n' "$files" | grep -E "$SPEC_PATH" || true)"
if [ -n "$specs" ]; then
  # The status of each spec comes from the diff of that same SHA; its text, from
  # the base of the PR (origin/main, fetched above).
  changes="$(gh api "repos/$repo/compare/main...$sha" --jq '.files[] | "\(.status)\t\(.filename)"')" ||
    die "PR #$n: diff of ${sha:0:12} not read back: no review published, no merge"
  open="$(open_issues)" || die "open issues not read back: no review published, no merge"
  text="$(mktemp)"
  trap 'rm -f "$text"' EXIT
  while IFS= read -r spec; do
    status="$(printf '%s\n' "$changes" | awk -F '\t' -v p="$spec" '$2 == p { print $1 }')"
    [ -n "$status" ] || die "PR #$n: spec $spec is not in the diff of ${sha:0:12}: no review published, no merge"
    [ "$status" = removed ] || die "PR #$n: spec $spec is $status, and this path only removes specs: no review published, no merge"
    git -C "$main_root" show "$base:$spec" >"$text" 2>/dev/null ||
      die "PR #$n: spec $spec not read from main: no review published, no merge"
    cited="$(spec_open_issues "$text" "$open" | sed 's/^/#/' | paste -sd' ' -)"
    [ -z "$cited" ] || die "PR #$n: removed spec $spec still cites open issue(s) $cited: no review published, no merge"
  done <<EOF
$specs
EOF
fi
gh api -X POST "repos/$repo/statuses/$sha" -f state=success -f context=review/independent \
  -f description="Só arquivos gerados e remoção de specs de issues fechadas" >/dev/null
state="$(gh api "repos/$repo/commits/$sha/status" --jq '[.statuses[] | select(.context == "review/independent")][0].state // "missing"')"
[ "$state" = success ] || die "review/independent not read back on ${sha:0:12} (it is $state)"
echo "published review/independent on ${sha:0:12}: PR #$n holds only generated files and removals of specs of closed issues"

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
echo "generated files and spec removals are on main at $(git -C "$main_root" rev-parse --short origin/main)"
