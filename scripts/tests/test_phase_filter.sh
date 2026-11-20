#!/usr/bin/env bash
# Tests of the filter of the Project view "Fase atual": new-phase.sh sets the group,
# close-phase.sh --cleanup clears it or puts back that of another active phase. Without a board, nothing
# happens; with a board, a write that fails exits != 0 with the cause and the fix command.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

repo="$(make_repo)"
copy_scripts "$repo"
printf '.worktrees/\n' >"$repo/.gitignore"
# Every phase needs a spec that cites the issue (new-phase.sh refuses without it).
mkdir -p "$repo/docs/specs"
printf '# Spec\n\nFases #20, #21, #22 e #23.\n' >"$repo/docs/specs/base.md"
git -C "$repo" add scripts .gitignore docs
git -C "$repo" commit --quiet -m "chore: scripts"
git clone --quiet --bare "$repo" "$TMP/remote.git"
git -C "$repo" remote add origin "$TMP/remote.git"
git -C "$repo" fetch --quiet origin
git -C "$repo" branch --quiet --set-upstream-to=origin/main main

# Fake gh: the view filter lives in $TMP/filter; the mutation writes it.
cat >"$TMP/handler.sh" <<'H'
case "$*" in
  "auth status"*) printf "  - Token scopes: %s\n" "${FAKE_SCOPES-'gist', 'project', 'read:project', 'repo'}" ;;
  "variable list"*) [ -n "${FAKE_NO_BOARD:-}" ] || echo 7 ;;
  "issue view"*"--json state,title,labels"*) echo '{"state":"OPEN","title":"Fase teste","labels":[{"name":"type:chore"}]}' ;;
  "issue view 20 --json labels"*|"issue view 22 --json labels"*|"issue view 23 --json labels"*) echo alpha ;;
  "issue view 21 --json labels"*) echo beta ;;
  "pr list"*) echo 99 ;;
  "project item-add"*) echo ITEM ;;
  "project view"*) echo PID ;;
  "project field-list"*) echo '{"fields":[{"name":"Status","id":"FID","options":[{"name":"In Progress","id":"OP"},{"name":"Done","id":"OD"},{"name":"Todo","id":"OT"}]}]}' ;;
  "project item-edit"*)
    [ -z "${FAKE_STATUS_LOST:-}" ] || exit 0
    case "$*" in *"option-id OT"*) echo Todo ;; *"option-id OP"*) echo "In Progress" ;; *"option-id OD"*) echo Done ;; esac >"$TMP/status" ;;
  "api graphql"*"fieldValueByName"*) cat "$TMP/status" 2>/dev/null || true ;;
  "api users/owner --jq .type") echo User ;;
  "api graphql"*"nodes{id name filter}"*)
    jq -cn --arg f "$(cat "$TMP/filter" 2>/dev/null || true)" '{data: {user: {projectV2: {views: {nodes: [{id: "VID", name: "Fase atual", filter: $f}, {id: "V2", name: "Outra", filter: "x"}]}}}}}' ;;
  "api graphql"*"updateProjectV2View"*)
    [ -z "${FAKE_REFUSE:-}" ] || exit 1
    [ -z "${FAKE_NOREAD:-}" ] || exit 0
    for a in "$@"; do case "$a" in f=*) printf '%s' "${a#f=}" >"$TMP/filter" ;; esac; done ;;
esac
H
export TMP
use_fake_gh "$TMP/handler.sh"
filter() { cat "$TMP/filter" 2>/dev/null || true; }
mutations() { gh_calls | grep -c "updateProjectV2View" || true; }

# Solo phase: the filter becomes the group of the issue; the last line is still the path.
out="$(cd "$repo" && scripts/new-phase.sh 20 --no-check 2>&1)"
assert_eq "$repo/.worktrees/issue-20" "$(echo "$out" | tail -1)" "worktree path stays the last line"
assert_eq 'label:"group:alpha"' "$(filter)" "new-phase sets the phase group filter"
assert_contains "$out" "filter is now" "success is announced after reading back"
assert_contains "$(gh_calls)" "--single-select-option-id OP" "new-phase still sets In Progress"

# Parallel phases: the filter joins the groups of all active ones, without duplicates.
rm -rf "$TMP/filter"
git -C "$repo" worktree remove --force "$repo/.worktrees/issue-20"
git -C "$repo" branch -D chore/issue-20-fase-teste >/dev/null
rm -f "$repo/.worktrees/parallel-active.tsv"
out="$(cd "$repo" && scripts/open-parallel.sh 21 22 --no-check 2>&1)"
assert_eq 'label:"group:beta","group:alpha"' "$(filter)" "parallel phases list every active group"
out="$(cd "$repo" && scripts/new-phase.sh 23 --no-check 2>&1)"
assert_eq 'label:"group:beta","group:alpha"' "$(filter)" "a repeated group is not duplicated"

# Close: the group of the closing phase leaves; those of the other active ones stay; at the end it goes back to neutral.
(cd "$repo/.worktrees/issue-23" && scripts/close-phase.sh --cleanup >/dev/null 2>&1)
assert_eq 'label:"group:beta","group:alpha"' "$(filter)" "alpha stays while issue 22 is active"
(cd "$repo/.worktrees/issue-22" && scripts/close-phase.sh --cleanup >/dev/null 2>&1)
assert_eq 'label:"group:beta"' "$(filter)" "closing 22 leaves only the group of 21"
(cd "$repo/.worktrees/issue-21" && scripts/close-phase.sh --cleanup >/dev/null 2>&1)
assert_eq 'is:open' "$(filter)" "closing the last phase resets the neutral filter"
assert_contains "$(gh_calls)" "--single-select-option-id OD" "close-phase still sets Done"

# Abort: the issue goes back to Todo, the group leaves the filter, and worktree, branch and registry line go away.
rm -f "$TMP/filter" "$repo/.worktrees/parallel-active.tsv"; : >"$FAKE_GH_LOG"
(cd "$repo" && scripts/open-parallel.sh 21 22 --no-check >/dev/null 2>&1)
assert_eq 'label:"group:beta","group:alpha"' "$(filter)" "abort setup: two active groups"
rc=0; out="$(cd "$repo/.worktrees/issue-22" && scripts/close-phase.sh --abort 2>&1)" || rc=$?
assert_eq 0 "$rc" "abort succeeds"
assert_eq 'label:"group:beta"' "$(filter)" "abort takes the group out of the filter"
assert_contains "$(gh_calls)" "--single-select-option-id OT" "abort sets the issue back to Todo"
assert_not_contains "$(cat "$repo/.worktrees/parallel-active.tsv")" "issue-22" "abort removes the registry line"
assert_eq 0 "$([ -d "$repo/.worktrees/issue-22" ] && echo 1 || echo 0)" "abort removes the worktree"
assert_eq "" "$(git -C "$repo" branch --list '*issue-22*')" "abort deletes the branch"
(cd "$repo/.worktrees/issue-21" && scripts/close-phase.sh --abort >/dev/null 2>&1)
assert_eq 'is:open' "$(filter)" "aborting the last phase resets the neutral filter"

# No scope, with a board: the phase does not open (nothing is created) and the output says the cause and the fix.
: >"$FAKE_GH_LOG"; rm -f "$TMP/filter"
rc=0; out="$(cd "$repo" && FAKE_SCOPES="'gist', 'repo'" scripts/new-phase.sh 20 --no-check 2>&1)" || rc=$?
assert_eq 1 "$rc" "missing scope fails new-phase"
assert_contains "$out" "the gh token has no 'project' scope" "missing scope: says the cause"
assert_contains "$out" "fix: gh auth refresh --scopes project,read:project" "missing scope: says the fix command"
assert_eq 0 "$(mutations)" "missing scope never calls the view mutation"
assert_eq 0 "$([ -d "$repo/.worktrees/issue-20" ] && echo 1 || echo 0)" "missing scope: no worktree is created"
assert_eq "" "$(git -C "$repo" branch --list '*issue-20*')" "missing scope: no branch is created"
rc=0; (cd "$repo" && FAKE_SCOPES="'gist', 'repo'" scripts/new-phase.sh 20 --no-check --dry-run >/dev/null 2>&1) || rc=$?
assert_eq 1 "$rc" "missing scope fails the dry run too (phase-start checks before opening)"

# No board configured: does nothing (no warning, no call), even without scope.
: >"$FAKE_GH_LOG"
rc=0; out="$(cd "$repo" && FAKE_NO_BOARD=1 FAKE_SCOPES="'gist', 'repo'" scripts/new-phase.sh 20 --no-check 2>&1)" || rc=$?
assert_eq 0 "$rc" "no board: new-phase succeeds"
assert_eq 0 "$(mutations)" "no board: no view mutation"
assert_not_contains "$(gh_calls)" "project " "no board: never calls gh project"
assert_not_contains "$out" "warning" "no board: no warning"
assert_not_contains "$out" "error" "no board: no error"
assert_eq "$repo/.worktrees/issue-20" "$(echo "$out" | tail -1)" "no board: the path is the last line"
drop20() { git -C "$repo" worktree remove --force "$repo/.worktrees/issue-20"; git -C "$repo" branch -D chore/issue-20-fase-teste >/dev/null; }
drop20

# API refuses, read-back does not confirm or status unconfirmed: exits != 0, no "ok".
rm -f "$TMP/filter"
rc=0; out="$(cd "$repo" && FAKE_REFUSE=1 scripts/new-phase.sh 20 --no-check 2>&1)" || rc=$?
assert_eq 1 "$rc" "refused update fails new-phase"
assert_contains "$out" "the API refused the update" "refused update: says the cause"
assert_contains "$out" "fix: scripts/setup-repo.sh --project" "refused update: says the fix command"
assert_contains "$out" "phase #20 is open at $repo/.worktrees/issue-20, but the board was not updated" "refused update: says the phase is open"
assert_not_contains "$out" "filter is now" "refused update is not declared done"
drop20
rc=0; out="$(cd "$repo" && FAKE_NOREAD=1 scripts/new-phase.sh 20 --no-check 2>&1)" || rc=$?
assert_eq 1 "$rc" "unconfirmed filter fails new-phase"
assert_contains "$out" "not confirmed on read back" "unconfirmed read back: says so"
assert_not_contains "$out" "filter is now" "unconfirmed update is not declared done"
drop20
rm -f "$TMP/status"
rc=0; out="$(cd "$repo" && FAKE_STATUS_LOST=1 scripts/new-phase.sh 20 --no-check 2>&1)" || rc=$?
assert_eq 1 "$rc" "unconfirmed status fails new-phase"
assert_contains "$out" "could not set the board status of #20 to 'In Progress'" "unconfirmed status: names the write"

# Close with the board failing: the cleanup finishes (worktree and branch go away) and the exit is != 0.
rc=0; out="$(cd "$repo/.worktrees/issue-20" && FAKE_REFUSE=1 scripts/close-phase.sh --cleanup 2>&1)" || rc=$?
assert_eq 1 "$rc" "cleanup fails when the board write fails"
assert_contains "$out" "closed and cleaned up, but the board was not updated" "cleanup says what is left"
assert_eq 0 "$([ -d "$repo/.worktrees/issue-20" ] && echo 1 || echo 0)" "cleanup still removes the worktree"
assert_eq "" "$(git -C "$repo" branch --list '*issue-20*')" "cleanup still deletes the branch"
finish
