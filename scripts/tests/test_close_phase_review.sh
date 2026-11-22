#!/usr/bin/env bash
# Tests of close-phase.sh --publish-review.
# shellcheck source=scripts/tests/close_phase_common.sh
source "$(dirname "$0")/close_phase_common.sh"

handler "type:feature" success
# Publish the review: comment + status on the HEAD SHA + review_round in the trace,
# only with a reviewer round of this session after the last push of the branch.
printf 'Revisão: aprovado.\n' >"$TMP/review.md"
export PROCESS_EVENTS_FILE="$TMP/events.jsonl"
review_refused() { # review_refused <description> <text expected in the output>
  : >"$FAKE_GH_LOG"
  assert_status 1 "$1" sh -c "cd '$repo' && '$CLOSE' --publish-review '$TMP/review.md' --verdict success --round 1"
  assert_contains "$(last_output)" "$2" "says why: $1"
  assert_not_contains "$(gh_calls)" "pr comment" "no comment: $1"
  assert_not_contains "$(gh_calls)" "statuses" "no status: $1"
}
reset_phase_evidence
review_refused "refuses a review with no trace" "no trace"
round_ev
review_refused "refuses a review without a recorded push" "no phase_push"
push_ev "$SHA"
review_refused "refuses a review whose reviewer round came before the last push" "no close-reviewer round after the last push"
round_ev other
round_ev child general-purpose
review_refused "the round of another session or of another agent does not count" "no close-reviewer round after the last push"
round_ev
push_ev 0000000000000000000000000000000000000000
review_refused "refuses when the last recorded push is not the PR head" "is not the PR head"
push_ev "$SHA"
review_refused "a new push asks for a new reviewer round" "no close-reviewer round after the last push"
round_ev
: >"$FAKE_GH_LOG"
assert_status 0 "publishes review" sh -c "cd '$repo' && '$CLOSE' --publish-review '$TMP/review.md' --verdict success --round 1"
assert_eq "review_round 1 success 12" "$(jq -r '[.event, .round, .verdict, .pr] | join(" ")' "$PROCESS_EVENTS_FILE")" "records review_round in the trace"
calls="$(gh_calls)"
assert_contains "$calls" "pr comment 12 --repo owner/repo --body-file $TMP/review.md" "posts the review comment"
assert_contains "$calls" "api -X POST repos/owner/repo/statuses/$SHA -f state=success -f context=review/independent" "sets the status on HEAD"
printf 'Co-Authored-By: Claude <noreply@anthropic.com>\n' >"$TMP/signed.md"
assert_status 1 "refuses a signed review" sh -c "cd '$repo' && '$CLOSE' --publish-review '$TMP/signed.md' --verdict success"

# No session id: the push of this branch at HEAD plus a clean pre_review of that SHA
# is enough to publish and to merge. A set session id still needs the harness round.
reset_phase_evidence
push_ev "$SHA"
jq -cn --arg sha "$SHA" --arg b feat/issue-5-x '{event: "pre_review", verdict: "clean", sha: $sha, branch: $b}' >>"$TRACE"
handler "type:feature" success
: >"$FAKE_GH_LOG"
assert_status 0 "publishes without a session id when HEAD was pushed and pre-reviewed clean" \
  env -u CLAUDE_CODE_SESSION_ID sh -c "cd '$repo' && '$CLOSE' --publish-review '$TMP/review.md' --verdict success --round 1"
assert_contains "$(gh_calls)" "api -X POST repos/owner/repo/statuses/$SHA -f state=success -f context=review/independent" "sets review/independent without a session id"
assert_status 0 "merges without a session id when HEAD was pushed and pre-reviewed clean" \
  env -u CLAUDE_CODE_SESSION_ID sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(gh_calls)" "pr merge 12" "merges without a session id"

finish
