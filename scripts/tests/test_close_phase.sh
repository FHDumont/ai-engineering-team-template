#!/usr/bin/env bash
# Tests of close-phase.sh --merge, part 1: child session gate and notes to the phase.
# shellcheck source=scripts/tests/close_phase_common.sh
source "$(dirname "$0")/close_phase_common.sh"

# Barrier: the phase needs a child session; a test issue follows the same path.
reset_phase_evidence
handler "type:feature" success
assert_status 1 "refuses merge without child session" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(last_output)" "no phase_opened" "says the phase was never opened"
assert_not_contains "$(gh_calls)" "pr merge" "never merges a phase without a child session"
child_session 5 plan
assert_status 1 "the planning session itself does not count as a child session" sh -c "cd '$repo' && '$CLOSE' --merge"
child_session 9
assert_status 1 "a child session of another issue does not count" sh -c "cd '$repo' && '$CLOSE' --merge"
reset_phase_evidence
# A line in .process/subagent-phases opens nothing: the announced subagent is gone.
printf '5\tstep too small for a session\n' >"$TMP/subagent-phases"
assert_status 1 "a subagent-phases line does not replace the child session" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_not_contains "$(gh_calls)" "pr merge" "never merges on a subagent-phases line"

# Fails closed: every way around the child session is refused.
merge_refused() { # merge_refused <description> [env assignments and close-phase.sh arguments...]
  local what="$1"
  shift
  handler "type:feature" success
  assert_status 1 "$what" env "$@" sh -c "cd '$repo' && '$CLOSE' --merge \$CLOSE_ARGS"
  assert_not_contains "$(gh_calls)" "pr merge" "no merge: $what"
}
reset_phase_evidence
ev SessionStart child
ev phase_session child 5
merge_refused "phase_session without phase_opened does not open" CLOSE_ARGS=
reset_phase_evidence
child_session 9
handler "type:feature" success
assert_status 2 "--issue of another phase does not open" sh -c "cd '$repo' && '$CLOSE' --merge --issue 9"
assert_not_contains "$(gh_calls)" "pr merge" "no merge with --issue of another phase"
assert_contains "$(last_output)" "--issue 9" "says --issue differs from the branch"
reset_phase_evidence
ev phase_opened plan 5
ev phase_session forged 5
merge_refused "a forged CLAUDE_CODE_SESSION_ID does not open" CLAUDE_CODE_SESSION_ID=forged CLOSE_ARGS=
reset_phase_evidence
child_session 5 other
merge_refused "the phase_session of another session does not cover this one" CLOSE_ARGS=
reset_phase_evidence
child_session 5
merge_refused "no session id does not open" CLAUDE_CODE_SESSION_ID= CLOSE_ARGS=
echo '{"event": "phase_ses' >>"$TRACE"
merge_refused "a corrupted trace line does not open" CLOSE_ARGS=
reset_phase_evidence
jq -cn '{event: "phase_opened", session_id: "plan", issue: "5"}, {event: "SessionStart", session_id: "child"}, {event: "phase_session", session_id: "child", issue: "5"}' >"$TMP/forged.jsonl"
merge_refused "a forged PROCESS_EVENTS_FILE does not open" PROCESS_EVENTS_FILE="$TMP/forged.jsonl" CLOSE_ARGS=
# The session that opened the phase does not close it: every step refuses, with exit 9.
reset_phase_evidence
child_session 5
handler "type:feature" success
echo "Closes #5" >"$TMP/opener-body.md"
for step in "--check" "--merge" "--prepare --title x --body-file $TMP/opener-body.md" "--publish-review $TMP/opener-body.md --verdict success"; do
  assert_status 9 "the opening session cannot run $step" env CLAUDE_CODE_SESSION_ID=plan sh -c "cd '$repo' && '$CLOSE' $step"
done
assert_contains "$(last_output)" "child session" "points to the child session"
assert_eq "" "$(gh_calls)" "the opening session reaches nothing on GitHub"
reset_phase_evidence
child_session 5
handler "type:feature,test" success
assert_status 0 "a test issue closes through the same gate" env FAKE_ISSUE_LABELS="type:feature,test" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(gh_calls)" "pr merge 12" "merges a test issue like any other"
child_session 5
assert_status 0 "merges with the child session present" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(gh_calls)" "pr merge 12" "requests the merge"

child_session 5
handler "type:feature,needs-owner-ok" success
assert_status 5 "refuses merge with needs-owner-ok" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(last_output)" "needs-owner-ok" "says why"
assert_not_contains "$(gh_calls)" "pr merge" "never calls merge when refused"

# Notes to the phase (#74): a comment "Para: fase #5" with no later comment of the phase refuses.
note() { printf '**De:** gerenciadora · **Para:** fase #%s · **Pedido:** %s · **Responde a:** —\nmedir a suíte' "${1:-5}" "${2:-medir}"; }
reply() { printf '**De:** fase #5 · **Para:** gerenciadora · **Pedido:** %s · **Responde a:** https://x/1\nfeito' "${1:-medir}"; }
comments() { # comments <body>...: writes the comments of the issue, oldest first
  for b in "$@"; do jq -cn --arg b "$b" --arg u "https://github.com/owner/repo/issues/5#c$RANDOM" '{body: $b, url: $u}'; done |
    jq -s '{comments: .}' >"$TMP/comments.json"
}
child_session 5
handler "type:feature" success
comments "$(note)"
assert_status 12 "refuses merge with a note to the phase without answer" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(last_output)" "issues/5#c" "names the unanswered note"
assert_not_contains "$(gh_calls)" "pr merge" "no merge with a note pending"
comments "$(note)" "$(reply)"
assert_status 0 "merges when the phase answered the note" sh -c "cd '$repo' && '$CLOSE' --merge"
comments "$(note)" "$(reply)" "$(note 5 outro)"
assert_status 12 "a note after the answer is pending again" sh -c "cd '$repo' && '$CLOSE' --merge"
comments "$(note 6)" "$(note 50)" "owner comment with no header"
assert_status 0 "a note to another phase (#6, #50, not a prefix of #5) or a comment with no header does not block" sh -c "cd '$repo' && '$CLOSE' --merge"
rm -f "$TMP/comments.json"
handler "type:feature" success
assert_status 1 "an unreadable issue refuses the merge" env FAKE_GH_FAIL="issue view 5.*--json comments" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_not_contains "$(gh_calls)" "pr merge" "no merge when the comments cannot be read"

finish
