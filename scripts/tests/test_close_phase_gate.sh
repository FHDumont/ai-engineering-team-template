#!/usr/bin/env bash
# Tests of close-phase.sh --merge: pre-review, owner ok, review evidence, protection, unprotected mode.
# shellcheck source=scripts/tests/close_phase_common.sh
source "$(dirname "$0")/close_phase_common.sh"

reset_phase_evidence
child_session 5
handler "type:feature" success
# Pre-review (#75): --pre-review records the event; --prepare warns, never refuses, without it.
assert_status 2 "pre-review needs a clean or findings verdict" sh -c "cd '$repo' && '$CLOSE' --pre-review --verdict success"
assert_status 0 "pre-review records clean" sh -c "cd '$repo' && '$CLOSE' --pre-review --verdict clean --round 2"
assert_eq "clean 2 $SHA" "$(jq -r 'select(.event == "pre_review") | [.verdict, .round, .sha] | join(" ")' "$PROCESS_EVENTS_FILE" | tail -1)" "pre_review lands in the trace with verdict, round and HEAD"
assert_contains "$(jq -r 'select(.event == "pre_review") | .branch' "$PROCESS_EVENTS_FILE")" "feat/issue-5-x" "pre_review names the branch"

handler "type:feature,area:auth" success
assert_status 5 "refuses merge with sensitive area label" sh -c "cd '$repo' && '$CLOSE' --merge"

handler "type:feature" missing
assert_status 1 "refuses merge without review/independent" sh -c "cd '$repo' && '$CLOSE' --merge"

handler "type:feature" success
assert_status 0 "merges when clean and reviewed" sh -c "cd '$repo' && '$CLOSE' --merge"
calls="$(gh_calls)"
assert_contains "$calls" "pr merge 12 --repo owner/repo --auto --rebase --delete-branch" "merges with --auto --rebase --delete-branch"
assert_not_contains "$calls" "--admin" "never as admin"
assert_not_contains "$calls" "--squash" "never squash"
assert_contains "$calls" "pr view 12 --json body" "checks the final PR body before merging"

handler "type:feature" success
assert_status 1 "refuses merge when the final PR body is signed" \
  env FAKE_PR_BODY="Co-Authored-By: Claude <noreply@anthropic.com>" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(last_output)" "AI attribution" "says why"
assert_not_contains "$(gh_calls)" "pr merge" "never merges a signed PR"

handler "type:feature,needs-owner-ok" success
assert_status 2 "--owner-ok without a SHA is refused" sh -c "cd '$repo' && '$CLOSE' --merge --owner-ok"
assert_contains "$(last_output)" "--owner-ok needs the SHA" "says the SHA is required"
assert_not_contains "$(gh_calls)" "pr merge" "never merges on --owner-ok without a SHA"
handler "type:feature,needs-owner-ok" success
assert_status 5 "--owner-ok for another SHA is refused" sh -c "cd '$repo' && '$CLOSE' --merge --owner-ok deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
assert_contains "$(last_output)" "does not match" "says the SHA does not match HEAD"
assert_not_contains "$(gh_calls)" "pr merge" "never merges on an ok bound to another SHA"
handler "type:feature,needs-owner-ok" success
assert_status 0 "merges with --owner-ok after the owner's choice" sh -c "cd '$repo' && '$CLOSE' --merge --owner-ok '$SHA'"
assert_contains "$(gh_calls)" "<!-- owner-ok sha:$SHA -->" "records the owner's ok on the PR"

# --owner-ok only counts with needs-owner-ok already on the PR: a refusal
# puts the label there, read back, so the owner sees the PR waiting before any ok.
handler "type:feature,area:auth" success
assert_status 5 "--owner-ok without the label on the PR is refused" sh -c "cd '$repo' && '$CLOSE' --merge --owner-ok '$SHA'"
assert_contains "$(last_output)" "--owner-ok does not count" "says the flag did not count"
assert_not_contains "$(gh_calls)" "pr merge" "never merges on --owner-ok without the label"
assert_not_contains "$(gh_calls)" "<!-- owner-ok" "records no owner's ok without the label"
assert_contains "$(gh_calls)" "issue edit 12 --repo owner/repo --add-label needs-owner-ok" "puts needs-owner-ok on the PR"
assert_contains "$(last_output)" "needs-owner-ok is now on PR #12 (read back)" "the label is read back"
handler "type:feature,area:auth" success
assert_status 5 "a refusal without --owner-ok also puts the label" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(gh_calls)" "--add-label needs-owner-ok" "refusal labels the PR"
handler "type:feature,area:auth" success
assert_status 1 "a label that does not stick fails the refusal" env FAKE_GH_FAIL='^issue edit 12' sh -c "cd '$repo' && '$CLOSE' --merge"
assert_not_contains "$(gh_calls)" "pr merge" "never merges when the label cannot be put"

# review/independent only counts with the reviewer's event in the trace:
# a status posted by hand, without a close-reviewer round after the push of HEAD, opens nothing.
no_review() { # no_review <description> <text expected>
  handler "type:feature" success
  assert_status 1 "$1" sh -c "cd '$repo' && '$CLOSE' --merge"
  assert_contains "$(last_output)" "$2" "says why: $1"
  assert_not_contains "$(gh_calls)" "pr merge" "no merge: $1"
}
reset_phase_evidence; NO_REVIEW=1 child_session 5
no_review "refuses a green status without a recorded push" "no phase_push"
push_ev "$SHA"
no_review "refuses a green status without a reviewer round" "no close-reviewer round after the last push"
round_ev other; round_ev child general-purpose
no_review "the round of another session or agent does not count" "no close-reviewer round after the last push"
round_ev; push_ev "$SHA"
no_review "a push after the round asks for a new round" "no close-reviewer round after the last push"
round_ev
handler "type:feature" success
assert_status 0 "merges with the reviewer round after the push" sh -c "cd '$repo' && '$CLOSE' --merge"

# No merge without the protection of the base branch: the gate is the protection.
handler "type:feature" success
assert_status 1 "refuses merge on an unprotected branch" env FAKE_PROTECTION=none sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(last_output)" "main is not protected" "says the branch is not protected"
assert_contains "$(last_output)" "scripts/setup-repo.sh --only protection" "says the fix command"
assert_not_contains "$(gh_calls)" "pr merge" "never merges without protection"
handler "type:feature" success
assert_status 1 "refuses merge when a required check is missing" env FAKE_PROTECTION="CI" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(last_output)" "does not require review/independent" "names the missing check"
assert_not_contains "$(gh_calls)" "pr merge" "never merges with a partial protection"

# Unprotected mode (a plan with no branch protection): the merge reads CI and the review
# through the API and exits 11 when either is not success; without the mode it still refuses.
for ci in failure in_progress missing; do
  handler "type:feature" success
  assert_status 11 "unprotected mode: CI $ci refuses the merge" env FAKE_PROTECTION=none FAKE_MODE=1 FAKE_CI="$ci" sh -c "cd '$repo' && '$CLOSE' --merge"
  assert_contains "$(last_output)" "unprotected mode: CI is $ci" "unprotected mode: says CI is $ci"
  assert_not_contains "$(gh_calls)" "pr merge" "unprotected mode: never merges with CI $ci"
done
handler "type:feature" failure
assert_status 1 "unprotected mode: a review that is not success still refuses" env FAKE_PROTECTION=none FAKE_MODE=1 sh -c "cd '$repo' && '$CLOSE' --merge"
assert_not_contains "$(gh_calls)" "pr merge" "unprotected mode: never merges without the review"
handler "type:feature" success
assert_status 0 "unprotected mode: CI and review success merge" env FAKE_PROTECTION=none FAKE_MODE=1 CLOSE_PHASE_MERGEABLE_PAUSE=0 CLOSE_PHASE_CI_TIMEOUT=0 CLOSE_PHASE_CI_POLL=0 sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(last_output)" "unprotected mode: CI and review/independent are success" "unprotected mode: says what it read"
assert_contains "$(gh_calls)" "pr merge" "unprotected mode: merges when both are green"

# A check cancelled on HEAD (issue #209): --merge --wait leaves at once with the rerun command.
handler "type:feature" success
: >"$FAKE_GH_LOG"
assert_status 1 "--merge --wait leaves at once when a check on HEAD was cancelled" \
  env FAKE_CANCELLED_URL="https://github.com/owner/repo/actions/runs/777/job/9" CLOSE_PHASE_MERGE_POLL=0 sh -c "cd '$repo' && '$CLOSE' --merge --wait"
assert_contains "$(last_output)" "scripts/rerun-ci.sh 777" "names the rerun command with the run id"
assert_contains "$(last_output)" "cancelled" "names the cause"

finish
