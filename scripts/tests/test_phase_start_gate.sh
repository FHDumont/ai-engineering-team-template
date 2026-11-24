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

spec seven.md 7
# #190: the refusal for a private repository with no recorded CI mode names the way out that needs no
# commit on main, and --check of the setup says the same text.
assert_status 1 "phase-start refuses a private repository with no recorded CI mode" env -u PROCESS_CI_MODE FAKE_PRIVATE=true sh -c "cd '$repo' && scripts/phase-start.sh 7 --no-check"
refusal="$(last_output)"
assert_contains "$refusal" "PROCESS_CI_MODE" "the refusal cites the variable"
assert_contains "$refusal" "the next PR tests the sum" "the refusal says the guarantee of mode pr"
assert_contains "$refusal" "deploy runs validate.sh" "the refusal says the deploy runs validate.sh"
assert_contains "$refusal" "setup-repo.sh --ci-mode" "the refusal cites the setup step"
assert_eq "" "$(ls "$repo/.worktrees" 2>/dev/null || true)" "nothing is created by that refusal"
assert_status 0 "the variable PROCESS_CI_MODE lets the phase open" env PROCESS_CI_MODE=push FAKE_PRIVATE=true CLAUDE_CODE_SESSION_ID=manager sh -c "cd '$repo' && scripts/phase-start.sh 7 --dry-run"

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
# A completed/skipped check is not an absent one. GitHub skips CI on main when the same
# tree was already green on the merged PR. Accept that voucher only when the trees match.
# A red PR, or a different tree, still refuses — including when ci-mode is pr.
assert_status 0 "phase-start accepts a skipped CI whose merged PR is green on the same tree" env FAKE_BASE_CI=skipped FAKE_BASE_PR=green CLAUDE_CODE_SESSION_ID=manager sh -c "cd '$repo' && scripts/phase-start.sh 7 --dry-run"
assert_contains "$(last_output)" "skipped" "says the check is skipped"
assert_contains "$(last_output)" "PR #30" "names the PR that vouches for the skipped check"
assert_contains "$(last_output)" "same tree" "says the trees match"
assert_not_contains "$(last_output)" "no check 'CI'" "a skipped check is not reported as absent"
git -C "$repo" worktree list | grep -q issue-7 && git -C "$repo" worktree remove --force "$repo/.worktrees/issue-7" || true
for pr in none red tree open; do
  assert_status 1 "phase-start refuses a skipped CI when the PR is $pr" env FAKE_BASE_CI=skipped FAKE_BASE_PR=$pr sh -c "cd '$repo' && scripts/phase-start.sh 7 --no-check"
  assert_contains "$(last_output)" "nothing was created" "says nothing was created (skipped, PR $pr)"
  assert_contains "$(last_output)" "skipped" "names the skipped check (PR $pr)"
  assert_eq "" "$(ls "$repo/.worktrees" 2>/dev/null || true)" "no worktree (skipped, PR $pr)"
done
mkdir -p "$repo/.github"
printf 'pr\n' >"$repo/.github/ci-mode"
assert_status 1 "phase-start refuses a skipped CI whose tree differs even in pr mode" env FAKE_BASE_CI=skipped FAKE_BASE_PR=tree sh -c "cd '$repo' && scripts/phase-start.sh 7 --no-check"
assert_contains "$(last_output)" "nothing was created" "says nothing was created (skipped, different tree, pr mode)"
assert_not_contains "$(last_output)" "warn:" "a different tree is not a warning when the check was skipped"
rm -f "$repo/.github/ci-mode"
assert_eq "" "$(ls "$repo/.worktrees" 2>/dev/null || true)" "no worktree when the skipped tree differs"
finish
