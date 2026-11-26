#!/usr/bin/env bash
# Tests of the single phase entry, the wait for the CI of the base commit.
# shellcheck source=.method/scripts/tests/phase_start_common.sh
source "$(dirname "$0")/phase_start_common.sh"

# running or absent refuse, name the run, and leave no branch, worktree, registry or phase_opened.
spec seven.md 7
# The wait for a running CI of main is short here; the default is minutes (see phase-start.sh).
export PHASE_START_CI_WAIT=2 PHASE_START_CI_POLL=1
# #59: two PRs merged in a row by rebase. The base commit is the sum of both (its tree is the
# head of no PR) and ci.yml runs on push to main: the check CI of the base is still running when
# the phase opens. It waits for that run instead of refusing, and opens when it turns green.
rm -f "$TMP/ci.count"
assert_status 0 "phase-start waits for the CI of main (two merges in a row) and opens" env FAKE_BASE_CI=wait FAKE_BASE_CI_COUNT="$TMP/ci.count" FAKE_BASE_PR=tree PHASE_START_CI_WAIT=30 PHASE_START_CI_POLL=1 CLAUDE_CODE_SESSION_ID=manager sh -c "cd '$repo' && .method/scripts/phase-start.sh 7 --dry-run"
assert_contains "$(last_output)" "is green" "says the CI of the base turned green"
assert_eq 1 "$(($(cat "$TMP/ci.count") > 1))" "it read the check again while the run was going"
# #62: right after a merge the run of main has Tests going and no job CI yet. The gate looks at the
# workflow run of the commit, waits, and opens when the CI turns green.
rm -f "$TMP/ci.count"
assert_status 0 "phase-start waits while Tests runs and the job CI does not exist yet" env FAKE_BASE_CI=jobwait FAKE_BASE_CI_COUNT="$TMP/ci.count" FAKE_BASE_PR=tree PHASE_START_CI_WAIT=30 PHASE_START_CI_POLL=1 CLAUDE_CODE_SESSION_ID=manager sh -c "cd '$repo' && .method/scripts/phase-start.sh 7 --dry-run"
assert_contains "$(last_output)" "is green" "says the CI turned green after the job was born"
assert_not_contains "$(last_output)" "no check 'CI'" "does not refuse for the absent job"
# A finished run without a green CI refuses as before.
assert_status 1 "phase-start refuses a finished run without the check CI" env FAKE_BASE_CI=absent FAKE_BASE_RUNS=done sh -c "cd '$repo' && .method/scripts/phase-start.sh 7 --no-check"
assert_contains "$(last_output)" "no check 'CI' on the base commit" "a finished run keeps the absent message"
# The wait has a deadline: a run that does not finish refuses, creating nothing.
assert_status 1 "phase-start refuses when the CI of main does not finish before the deadline" env FAKE_BASE_CI=running sh -c "cd '$repo' && .method/scripts/phase-start.sh 7 --no-check"
assert_contains "$(last_output)" "did not finish" "says the run did not finish in time"
assert_contains "$(last_output)" "warn: over-expected ci-wait" "a live run past the expected wait warns and the hang limit still refuses"
assert_contains "$(last_output)" "nothing was created" "says nothing was created after the wait"
# No run on the base: there is nothing to wait for, it refuses at once.
rm -f "$TMP/ci.count"
assert_status 1 "phase-start does not wait when there is no run of main" env FAKE_BASE_CI=absent FAKE_BASE_PR=tree PHASE_START_CI_WAIT=30 sh -c "cd '$repo' && .method/scripts/phase-start.sh 7 --no-check"
assert_not_contains "$(last_output)" "did not finish" "no wait without a run"
rm "$repo/docs/specs/seven.md"
finish
