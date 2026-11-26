#!/usr/bin/env bash
# Tests of the filter of the Project view "Fase atual": new-phase.sh sets the group,
# close-phase.sh --cleanup clears it or puts back that of another active phase. The failures
# of the board are in test_phase_filter_errors.sh.
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

# shellcheck source=.method/scripts/tests/fixtures/phase_filter_setup.sh
source "$TESTS_DIR/fixtures/phase_filter_setup.sh"

# Solo phase: the filter becomes the group of the issue; the last line is still the path.
out="$(cd "$repo" && .method/scripts/new-phase.sh 20 --no-check 2>&1)"
assert_eq "$repo/.worktrees/issue-20" "$(echo "$out" | tail -1)" "worktree path stays the last line"
assert_eq 'label:"group:alpha"' "$(filter)" "new-phase sets the phase group filter"
assert_contains "$out" "filter is now" "success is announced after reading back"
assert_contains "$(gh_calls)" "--single-select-option-id OP" "new-phase still sets In Progress"

# Parallel phases: the filter joins the groups of all active ones, without duplicates.
rm -rf "$TMP/filter"
git -C "$repo" worktree remove --force "$repo/.worktrees/issue-20"
git -C "$repo" branch -D chore/issue-20-fase-teste >/dev/null
rm -f "$repo/.worktrees/parallel-active.tsv"
out="$(cd "$repo" && .method/scripts/open-parallel.sh 21 22 --no-check 2>&1)"
assert_eq 'label:"group:beta","group:alpha"' "$(filter)" "parallel phases list every active group"
out="$(cd "$repo" && .method/scripts/new-phase.sh 23 --no-check 2>&1)"
assert_eq 'label:"group:beta","group:alpha"' "$(filter)" "a repeated group is not duplicated"

# Close: the group of the closing phase leaves; those of the other active ones stay; at the end it goes back to neutral.
(cd "$repo/.worktrees/issue-23" && .method/scripts/close-phase.sh --cleanup >/dev/null 2>&1)
assert_eq 'label:"group:beta","group:alpha"' "$(filter)" "alpha stays while issue 22 is active"
(cd "$repo/.worktrees/issue-22" && .method/scripts/close-phase.sh --cleanup >/dev/null 2>&1)
assert_eq 'label:"group:beta"' "$(filter)" "closing 22 leaves only the group of 21"
(cd "$repo/.worktrees/issue-21" && .method/scripts/close-phase.sh --cleanup >/dev/null 2>&1)
assert_eq 'is:open' "$(filter)" "closing the last phase resets the neutral filter"
assert_contains "$(gh_calls)" "--single-select-option-id OD" "close-phase still sets Done"

# Abort: the issue goes back to Todo, the group leaves the filter, and worktree, branch and registry line go away.
rm -f "$TMP/filter" "$repo/.worktrees/parallel-active.tsv"; : >"$FAKE_GH_LOG"
(cd "$repo" && .method/scripts/open-parallel.sh 21 22 --no-check >/dev/null 2>&1)
assert_eq 'label:"group:beta","group:alpha"' "$(filter)" "abort setup: two active groups"
rc=0; out="$(cd "$repo/.worktrees/issue-22" && .method/scripts/close-phase.sh --abort 2>&1)" || rc=$?
assert_eq 0 "$rc" "abort succeeds"
assert_eq 'label:"group:beta"' "$(filter)" "abort takes the group out of the filter"
assert_contains "$(gh_calls)" "--single-select-option-id OT" "abort sets the issue back to Todo"
assert_not_contains "$(cat "$repo/.worktrees/parallel-active.tsv")" "issue-22" "abort removes the registry line"
assert_eq 0 "$([ -d "$repo/.worktrees/issue-22" ] && echo 1 || echo 0)" "abort removes the worktree"
assert_eq "" "$(git -C "$repo" branch --list '*issue-22*')" "abort deletes the branch"
(cd "$repo/.worktrees/issue-21" && .method/scripts/close-phase.sh --abort >/dev/null 2>&1)
assert_eq 'is:open' "$(filter)" "aborting the last phase resets the neutral filter"
finish
