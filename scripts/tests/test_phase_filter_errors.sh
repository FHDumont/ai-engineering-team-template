#!/usr/bin/env bash
# Tests of the board failures of the filter of the Project view "Fase atual": no scope, no
# board, refused or unconfirmed writes (the happy path is in test_phase_filter.sh).
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=scripts/tests/fixtures/phase_filter_setup.sh
source "$TESTS_DIR/fixtures/phase_filter_setup.sh"

# No scope, with a board: the phase does not open (nothing is created) and the output says the cause and the fix.
: >"$FAKE_GH_LOG"; rm -f "$TMP/filter"
rc=0; out="$(cd "$repo" && FAKE_SCOPES="'gist', 'repo'" scripts/new-phase.sh 20 --no-check 2>&1)" || rc=$?
assert_eq 1 "$rc" "missing scope fails new-phase"
assert_contains "$out" "the gh token has no 'project' scope" "missing scope: says the cause"
assert_contains "$out" "fix: gh auth login -h github.com -p https -w -s gist,project,read:org,repo,workflow" "missing scope: says the fix command"
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
