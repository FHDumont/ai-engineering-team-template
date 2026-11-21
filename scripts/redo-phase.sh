#!/usr/bin/env bash
#: redo-phase.sh: redo the phase of the current branch on top of the updated main.
#:
#: Usage: redo-phase.sh
#:
#: Runs in the phase worktree, on the phase branch, with every step committed.
#: close-phase.sh --check calls it when the PR conflicts with main; nobody is asked.
#: 1. Creates <branch>-r<k> from origin/main in this worktree and cherry-picks the
#:    phase commits, oldest first. A commit that is already on main is dropped. A
#:    conflict in a generated file (CHANGELOG.md, ROADMAP.md) keeps the file of
#:    main. Any other conflict is real: exit 4 with the cherry-pick stopped and
#:    the files listed; resolve them, git add them by name, run
#:    git cherry-pick --continue and run redo-phase.sh again (it resumes). A
#:    resolution that leaves nothing to commit (the change is already on main):
#:    git add the files and run redo-phase.sh again, with the cherry-pick still
#:    stopped; it checks that nothing is left and drops the commit itself. A
#:    git cherry-pick --skip by hand is refused: the script cannot tell it from a
#:    lost commit.
#:    The new branch is <branch>-r<k>; only a whole -r<k> suffix of a branch
#:    already redone is replaced.
#: 2. Pushes the new branch (no force) and opens a new PR with the title, body and
#:    labels of the old one, "Closes #n" included.
#: 3. Closes the old PR with a comment and deletes the old remote branch.
#: 4. Rewrites the line of the issue in .worktrees/parallel-active.tsv.
#: 5. Deletes the old local branch.
#: Every step with an effect on GitHub is read back; a step that did not take
#: exits 1. The new HEAD has no CI run and no review yet: both run again.
#: Exits 9 in the session that opened the phase (the child session redoes it).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"
ROOT="$(cd "$HERE/.." && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    *) die "unknown option: $1 (see --help)" 2 ;;
  esac
done
require_cmd gh jq git
cd "$ROOT"

GENERATED='CHANGELOG.md ROADMAP.md'
branch="$(current_branch)"
[ -n "$branch" ] && ! is_main_branch "$branch" || die "redo-phase runs on the phase branch"
issue="$(issue_from_branch "$branch")"
[ -n "$issue" ] || die "cannot tell the phase issue from branch $branch"
if [ "$(phase_opener_state "$issue" "${CLAUDE_CODE_SESSION_ID:-}" "$ROOT")" = opener ]; then
  die "this session opened phase #$issue: the child session redoes the phase" 9
fi
repo="$(repo_slug)"
main_root="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
# Progress of a redo stopped by a real conflict: old branch, old PR, new branch;
# the commits still to pick are in $state.todo and the ones that must end as a
# commit of the new branch in $state.kept.
state="$(git rev-parse --absolute-git-dir)/redo-phase"

unmerged() { git diff --name-only --diff-filter=U; }
is_generated() { case " $GENERATED " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

if [ -f "$state" ]; then
  old="$(sed -n 1p "$state")"; old_pr="$(sed -n 2p "$state")"; new="$(sed -n 3p "$state")"
  [ "$branch" = "$new" ] || die "a redo of $old is stopped on branch $new: switch to it or delete $state"
  if stopped="$(git rev-parse -q --verify CHERRY_PICK_HEAD)" && [ -z "$(unmerged)" ] &&
     git diff --quiet && git diff --cached --quiet; then
    # Resolved to exactly what main has: nothing of the commit is left to apply. The
    # script drops it here, checked, so the count of kept commits still holds.
    git cherry-pick --skip >/dev/null 2>&1
    grep -vxF "$stopped" "$state.kept" >"$state.kept.tmp" || true
    mv "$state.kept.tmp" "$state.kept"
    echo "dropped ${stopped:0:12}: the resolution left nothing to apply on main"
  elif [ -n "$stopped" ] || [ -n "$(unmerged)" ]; then
    die "the cherry-pick is still stopped: resolve the files, git add them by name and run git cherry-pick --continue (nothing left to commit: run scripts/redo-phase.sh again without it)" 4
  fi
  echo "resuming the redo of $old on $new"
else
  git diff --quiet && git diff --cached --quiet || die "uncommitted changes: commit each step first"
  old="$branch"
  old_pr="$(gh pr list --repo "$repo" --head "$old" --state open --json number --jq '.[0].number // empty')"
  [ -n "$old_pr" ] || die "no open PR for $old: nothing to redo"
  git fetch --quiet origin main
  git rev-list --reverse "origin/main..$old" >"$state.todo"
  : >"$state.kept"
  [ -s "$state.todo" ] || { rm -f "$state.todo" "$state.kept"; die "$old has no commit ahead of origin/main"; }
  # Only a whole -r<k> suffix is a redo mark: feat/issue-5-r2d2-support keeps its name.
  base="$(printf '%s\n' "$old" | sed -E 's/-r[0-9]+$//')"
  k=2; new="$base-r$k"
  while git show-ref --verify --quiet "refs/heads/$new" || [ -n "$(git ls-remote --heads origin "$new")" ]; do
    k=$((k + 1)); new="$base-r$k"
  done
  printf '%s\n%s\n%s\n' "$old" "$old_pr" "$new" >"$state"
  git switch --quiet --no-track -c "$new" origin/main
  echo "redoing PR #$old_pr: $old -> $new, from origin/main"
fi

while [ -s "$state.todo" ]; do
  c="$(sed -n 1p "$state.todo")"
  sed 1d "$state.todo" >"$state.todo.tmp" && mv "$state.todo.tmp" "$state.todo"
  if git cherry-pick "$c" >/dev/null 2>&1; then echo "$c" >>"$state.kept"; continue; fi
  # Generated files are not the phase's: the version of main wins.
  for f in $(unmerged); do
    is_generated "$f" || continue
    if git cat-file -e "HEAD:$f" 2>/dev/null; then git checkout --quiet HEAD -- "$f"; else git rm --quiet -f -- "$f"; fi
    echo "generated file $f: kept the version of main (commit ${c:0:12})"
  done
  if [ -n "$(unmerged)" ]; then
    echo "$c" >>"$state.kept"
    echo "real conflict: cherry-pick of ${c:0:12} ($(git log -1 --format=%s "$c")) stopped on branch $new" >&2
    unmerged | sed 's/^/  conflict: /' >&2
    echo "resolve these files, git add them by name, run git cherry-pick --continue, then run scripts/redo-phase.sh again" >&2
    echo "nothing left to commit after the resolution (the change is already on main): git add the files and run scripts/redo-phase.sh again; it drops the commit. Never git cherry-pick --skip by hand" >&2
    exit 4
  fi
  git rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null || die "cherry-pick of $c failed without a conflict: see git status"
  if git diff --cached --quiet; then
    # Nothing left of the commit: it is already on main, or it only touched generated files.
    git cherry-pick --skip >/dev/null 2>&1
    echo "dropped ${c:0:12}: nothing left to apply on main"
  else
    git -c core.editor=true cherry-pick --continue >/dev/null
    echo "$c" >>"$state.kept"
  fi
done
# No commit is lost in silence: a cherry-pick that was aborted or skipped by hand shows here.
kept="$(wc -l <"$state.kept" | tr -d ' ')"
have="$(git rev-list --count origin/main..HEAD)"
[ "$have" = "$kept" ] || die "branch $new has $have commit(s) on top of origin/main, expected $kept: a cherry-pick was aborted or skipped by hand; nothing was pushed (a commit whose resolution is empty is dropped by redo-phase.sh itself, run with the cherry-pick still stopped). Switch back to $old, delete branch $new and $state*, and run redo-phase.sh again"
[ "$(git rev-list --count origin/main..HEAD)" -gt 0 ] || die "nothing of $old is left on top of origin/main: branch $new is empty"

git push --quiet -u origin "$new"
head_sha="$(git rev-parse HEAD)"
[ "$(git ls-remote --heads origin "$new" | cut -f1)" = "$head_sha" ] || die "push of $new not read back on origin"
trace_event phase_push sha="$head_sha"
echo "pushed $new at ${head_sha:0:12}"

new_pr="$(gh pr list --repo "$repo" --head "$new" --state open --json number --jq '.[0].number // empty')"
if [ -z "$new_pr" ]; then
  info="$(gh pr view "$old_pr" --repo "$repo" --json title,body,labels)"
  body_file="$(mktemp)"
  echo "$info" | jq -r '.body // ""' >"$body_file"
  grep -qiE "(close[sd]?|fix(e[sd])?|resolve[sd]?) +#$issue([^0-9]|\$)" "$body_file" || printf '\nCloses #%s\n' "$issue" >>"$body_file"
  printf '\nRefaz o PR #%s sobre a main atualizada, por cherry-pick.\n' "$old_pr" >>"$body_file"
  args=(pr create --repo "$repo" --base main --head "$new" --title "$(echo "$info" | jq -r .title)" --body-file "$body_file")
  while IFS= read -r l; do [ -z "$l" ] || args+=(--label "$l"); done <<<"$(echo "$info" | jq -r '.labels[].name')"
  gh "${args[@]}" >/dev/null
  new_pr="$(gh pr list --repo "$repo" --head "$new" --state open --json number --jq '.[0].number // empty')"
  [ -n "$new_pr" ] || die "new PR for $new not read back"
  echo "opened PR #$new_pr (Closes #$issue)"
fi

gh pr close "$old_pr" --repo "$repo" --comment "Refeito sobre a main atualizada no PR #$new_pr (branch \`$new\`, cherry-pick, sem push forçado)." >/dev/null
[ "$(gh pr view "$old_pr" --repo "$repo" --json state --jq .state)" = CLOSED ] || die "old PR #$old_pr not read back as CLOSED"
echo "closed PR #$old_pr"

if [ -n "$(git ls-remote --heads origin "$old")" ]; then
  git push --quiet origin --delete "$old"
fi
[ -z "$(git ls-remote --heads origin "$old")" ] || die "old remote branch $old is still on origin"
echo "deleted remote branch $old"

registry="$main_root/.worktrees/parallel-active.tsv"
if [ -f "$registry" ] && cut -f1 "$registry" | grep -qxF "$issue"; then
  awk -F '\t' -v OFS='\t' -v n="$issue" -v b="$new" '$1 == n { $2 = b } { print }' "$registry" >"$registry.redo"
  mv "$registry.redo" "$registry"
  [ "$(awk -F '\t' -v n="$issue" '$1 == n { print $2 }' "$registry")" = "$new" ] || die "registry line of #$issue not read back with $new"
  echo "registry: #$issue -> $new"
fi

git branch -D "$old" >/dev/null 2>&1 || true
rm -f "$state" "$state.todo" "$state.kept"
echo "redone: PR #$new_pr (branch $new) replaces PR #$old_pr; CI and the independent review run again on ${head_sha:0:12}"
