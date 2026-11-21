#!/usr/bin/env bash
# Tests of the registry and the remote branch at the end of a phase:
# close-phase.sh --cleanup takes the line out of .worktrees/parallel-active.tsv and
# deletes the remote branch; open-parallel.sh refuses a registry with leftovers and
# never leaves half a group.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

repo="$(make_repo)"
copy_scripts "$repo"
printf '.worktrees/\n.process/\n' >"$repo/.gitignore"
mkdir -p "$repo/docs/specs"
printf '# Spec\n\nFases #7, #8, #21 e #22.\n' >"$repo/docs/specs/base.md"
git -C "$repo" add scripts .gitignore docs
git -C "$repo" commit --quiet -m "chore: scripts"
git clone --quiet --bare "$repo" "$TMP/remote.git"
git -C "$repo" remote add origin "$TMP/remote.git"
git -C "$repo" fetch --quiet origin
git -C "$repo" branch --quiet --set-upstream-to=origin/main main
REGISTRY="$repo/.worktrees/parallel-active.tsv"

cat >"$TMP/handler.sh" <<'H'
case "$*" in
  "issue view"*"--json state,title,labels"*) echo '{"state":"OPEN","title":"Fase teste","labels":[{"name":"type:chore"}]}' ;;
  "pr list"*"--state merged"*) echo 12 ;;
esac
H
use_fake_gh "$TMP/handler.sh"

# --cleanup after the merge: the line of the phase leaves the registry, the line of a
# phase still open stays, a line whose worktree is gone leaves, the remote branch is deleted.
phase() { # phase <issue>: worktree and branch pushed
  git -C "$repo" worktree add --quiet -b "feat/issue-$1-x" "$repo/.worktrees/issue-$1" main
  git -C "$repo/.worktrees/issue-$1" push --quiet origin "feat/issue-$1-x"
}
phase 7; phase 8
printf '7\tfeat/issue-7-x\t%s\n8\tfeat/issue-8-x\t%s\n9\tfeat/issue-9-x\t%s\n' \
  "$repo/.worktrees/issue-7" "$repo/.worktrees/issue-8" "$repo/.worktrees/issue-9" >"$REGISTRY"
assert_status 0 "cleanup of a merged phase" sh -c "cd '$repo/.worktrees/issue-7' && scripts/close-phase.sh --cleanup"
assert_eq "8	feat/issue-8-x	$repo/.worktrees/issue-8" "$(cat "$REGISTRY")" "only the line of the phase still open stays in the registry"
assert_eq "" "$(git -C "$repo" ls-remote --heads origin feat/issue-7-x)" "cleanup deletes the remote branch"
assert_contains "$(last_output)" "deleted remote branch feat/issue-7-x" "says the remote branch was deleted"
assert_eq "" "$(git -C "$repo" branch --list 'feat/issue-7-x')" "cleanup deletes the local branch"
assert_eq 1 "$(git -C "$repo" ls-remote --heads origin feat/issue-8-x | wc -l | tr -d ' ')" "the remote branch of another phase stays"
assert_status 0 "cleanup of the last phase" sh -c "cd '$repo/.worktrees/issue-8' && scripts/close-phase.sh --cleanup"
assert_eq "" "$(cat "$REGISTRY")" "the registry is empty after the last cleanup"

# An untracked file of the main checkout identical to the one the merge brings (the
# spec written by the planning on main and committed on the phase branch) does not
# abort the update of main; a different one is never removed.
phase 9
printf '# Spec\n\nFase #9.\n' >"$repo/docs/specs/nine.md"
mkdir -p "$repo/.worktrees/issue-9/docs/specs"
cp "$repo/docs/specs/nine.md" "$repo/.worktrees/issue-9/docs/specs/nine.md"
git -C "$repo/.worktrees/issue-9" add docs/specs/nine.md
git -C "$repo/.worktrees/issue-9" commit --quiet -m "docs(specs): add the spec of issue #9"
git -C "$repo/.worktrees/issue-9" push --quiet origin feat/issue-9-x:main
: >"$REGISTRY"
assert_status 0 "cleanup with an identical untracked spec in the main checkout" sh -c "cd '$repo/.worktrees/issue-9' && scripts/close-phase.sh --cleanup"
assert_contains "$(last_output)" "removed the untracked copy of docs/specs/nine.md" "says the loose copy left"
assert_eq "$(git -C "$repo" rev-parse origin/main)" "$(git -C "$repo" rev-parse main)" "main is updated past the loose copy"
assert_eq "" "$(git -C "$repo" status --porcelain)" "the spec is tracked and clean after the update"
phase 10
echo other >"$repo/loose.txt"
echo mine >"$repo/.worktrees/issue-10/loose.txt"
git -C "$repo/.worktrees/issue-10" add loose.txt
git -C "$repo/.worktrees/issue-10" commit --quiet -m "feat: loose"
git -C "$repo/.worktrees/issue-10" push --quiet origin feat/issue-10-x:main
assert_status 1 "cleanup keeps an untracked file that differs from main" sh -c "cd '$repo/.worktrees/issue-10' && scripts/close-phase.sh --cleanup"
assert_eq "other" "$(cat "$repo/loose.txt")" "the different file is left as it was"
rm "$repo/loose.txt"
assert_status 0 "cleanup goes on once the file is out of the way" sh -c "cd '$repo/.worktrees/issue-10' && scripts/close-phase.sh --cleanup"

# --cleanup on main: only prunes the lines whose worktree is gone.
printf '9\tfeat/issue-9-x\t%s\n' "$repo/.worktrees/issue-9" >"$REGISTRY"
assert_status 0 "cleanup on main" sh -c "cd '$repo' && scripts/close-phase.sh --cleanup"
assert_eq "" "$(cat "$REGISTRY")" "cleanup on main drops the leftover line"

# open-parallel.sh refuses a registry with a leftover line and opens nothing.
printf '9\tfeat/issue-9-x\t%s\n' "$repo/.worktrees/issue-9" >"$REGISTRY"
assert_status 1 "open-parallel refuses a registry with leftovers" sh -c "cd '$repo' && scripts/open-parallel.sh 21 22 --no-check"
assert_contains "$(last_output)" "leftover lines (#9)" "names the leftover line"
assert_contains "$(last_output)" "close-phase.sh --cleanup" "says how to clean it"
assert_eq "" "$(git -C "$repo" branch --list '*issue-2*')" "no branch is created with leftovers"
: >"$REGISTRY"

# Half a group never stays: the second phase fails to open, the first is undone.
mkdir -p "$repo/.worktrees/issue-22"
assert_status 1 "open-parallel fails when one phase does not open" sh -c "cd '$repo' && scripts/open-parallel.sh 21 22 --no-check"
assert_contains "$(last_output)" "the group was not opened" "says the group was not opened"
assert_eq 0 "$([ -d "$repo/.worktrees/issue-21" ] && echo 1 || echo 0)" "the phase already opened is undone"
assert_eq "" "$(git -C "$repo" branch --list '*issue-21*')" "its branch is deleted"
assert_eq "" "$(cat "$REGISTRY")" "nothing is registered for half a group"
rmdir "$repo/.worktrees/issue-22"

# The whole group opens: one line per phase.
assert_status 0 "open-parallel opens the group" sh -c "cd '$repo' && scripts/open-parallel.sh 21 22 --no-check"
assert_eq "21 22" "$(cut -f1 "$REGISTRY" | paste -sd' ' -)" "one registry line per phase"
# A second group while the first is open is not a leftover.
assert_status 0 "another group opens beside an active one" sh -c "cd '$repo' && scripts/open-parallel.sh 7 8 --no-check"
assert_eq "21 22 7 8" "$(cut -f1 "$REGISTRY" | paste -sd' ' -)" "the active lines stay"
# An issue that is already registered is refused.
assert_status 1 "open-parallel refuses an issue already registered" sh -c "cd '$repo' && scripts/open-parallel.sh 21 9 --no-check"

# integrate-parallel.sh with an empty registry has nothing to wait for.
: >"$REGISTRY"
assert_status 0 "integrate with an empty registry" sh -c "cd '$repo' && scripts/integrate-parallel.sh --dry-run --interval 0"
assert_contains "$(last_output)" "nothing to wait for" "says there is nothing to wait for"
finish
