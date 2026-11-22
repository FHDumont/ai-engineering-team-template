#!/usr/bin/env bash
# Tests of the single phase entry, refusals: no spec, red/running/absent CI and the merged PR that vouches.
# shellcheck source=scripts/tests/phase_start_common.sh
source "$(dirname "$0")/phase_start_common.sh"

# No spec citing #n: nothing opens, by any of the three scripts.
spec other.md 70
assert_status 1 "phase-start refuses an issue without a spec" sh -c "cd '$repo' && scripts/phase-start.sh 7 --no-check"
assert_contains "$(last_output)" "no spec" "says the spec is missing"
assert_status 1 "new-phase refuses an issue without a spec" sh -c "cd '$repo' && scripts/new-phase.sh 7 --no-check"
assert_status 1 "new-phase --dry-run refuses too" sh -c "cd '$repo' && scripts/new-phase.sh 7 --dry-run"
spec eight.md 8
assert_status 1 "open-parallel refuses when one issue has no spec" sh -c "cd '$repo' && scripts/open-parallel.sh 8 7 --no-check"
assert_eq "" "$(ls "$repo/.worktrees" 2>/dev/null || true)" "no worktree is created without a spec"
assert_eq "" "$(git -C "$repo" branch --list '*issue-*')" "no branch is created without a spec"
assert_not_contains "$(events)" "phase_opened" "no phase_opened without a spec"
rm "$repo/docs/specs/eight.md" "$repo/docs/specs/other.md"

# The check CI of the base commit of main decides before anything is created: red, still
# running or absent refuse, name the run, and leave no branch, worktree, registry or phase_opened.
spec seven.md 7
# The wait for a running CI of main is short here; the default is minutes (see phase-start.sh).
export PHASE_START_CI_WAIT=2 PHASE_START_CI_POLL=1
for ci in red running absent; do
  assert_status 1 "phase-start refuses a base with CI $ci" env FAKE_BASE_CI=$ci sh -c "cd '$repo' && scripts/phase-start.sh 7 --no-check"
  assert_contains "$(last_output)" "no phase opens" "says why ($ci)"
  assert_contains "$(last_output)" "nothing was created" "says nothing was created ($ci)"
  assert_eq "" "$(ls "$repo/.worktrees" 2>/dev/null || true)" "no worktree with CI $ci"
  assert_eq "" "$(git -C "$repo" branch --list '*issue-*')" "no branch with CI $ci"
  assert_not_contains "$(events)" "phase_opened" "no phase_opened with CI $ci"
done
# #32: a failure of the GitHub API is not an absent check: the message says the check was not read.
assert_status 1 "phase-start refuses when the API fails reading the check CI" env FAKE_GH_FAIL='commits/.*/check-runs' FAKE_GH_FAIL_MSG='gh: network down' sh -c "cd '$repo' && scripts/phase-start.sh 7 --no-check"
assert_contains "$(last_output)" "could not read the check 'CI'" "says it did not read the check"
assert_contains "$(last_output)" "network down" "carries the error of gh"
assert_not_contains "$(last_output)" "no check 'CI' on the base" "does not say the check is absent"
assert_eq "" "$(ls "$repo/.worktrees" 2>/dev/null || true)" "no worktree when the API fails"
assert_status 1 "an absent check keeps its own message" env FAKE_BASE_CI=absent sh -c "cd '$repo' && scripts/phase-start.sh 7 --no-check"
assert_contains "$(last_output)" "no check 'CI' on the base commit" "absent check message is unchanged"
assert_not_contains "$(last_output)" "could not read" "absent is not reported as a read failure"
assert_status 1 "a red base refuses the group too" env FAKE_BASE_CI=red sh -c "cd '$repo' && scripts/phase-start.sh 7 8 --no-check"
assert_eq "" "$(ls "$repo/.worktrees" 2>/dev/null || true)" "the group creates nothing on a red base"
assert_contains "$(last_output)" "actions/runs/3" "names the run of the red CI"
assert_status 1 "a red base refuses --dry-run" env FAKE_BASE_CI=red sh -c "cd '$repo' && scripts/phase-start.sh 7 --dry-run"
# The ci.yml runs only on pull_request and the rebase merge creates commits without a check: a base
# with no check CI is accepted when the merged PR that holds it had CI green on its head with the same tree.
assert_status 0 "phase-start accepts a base without CI whose merged PR has green CI and the same tree" env FAKE_BASE_CI=absent FAKE_BASE_PR=green CLAUDE_CODE_SESSION_ID=manager sh -c "cd '$repo' && scripts/phase-start.sh 7 --dry-run"
assert_contains "$(last_output)" "PR #30" "says the PR that vouches for the base"
git -C "$repo" worktree list | grep -q issue-7 && git -C "$repo" worktree remove --force "$repo/.worktrees/issue-7" || true
for pr in none red tree open; do
  assert_status 1 "phase-start refuses a base without CI when the PR is $pr" env FAKE_BASE_CI=absent FAKE_BASE_PR=$pr sh -c "cd '$repo' && scripts/phase-start.sh 7 --no-check"
  assert_contains "$(last_output)" "nothing was created" "says nothing was created (PR $pr)"
  assert_eq "" "$(ls "$repo/.worktrees" 2>/dev/null || true)" "no worktree (PR $pr)"
done
finish
