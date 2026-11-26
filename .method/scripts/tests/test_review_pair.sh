#!/usr/bin/env bash
# A self-reported reviewer pair is replaced by the pair in the trace (issue #127).
# shellcheck source=scripts/tests/close_phase_common.sh
source "$(dirname "$0")/close_phase_common.sh"

handler "type:feature" success
printf '## Revisão independente\n\nVeredito: aprovado\n\nModelo do revisor: sonnet · esforço: baixo\n' >"$TMP/review.md"
export PROCESS_EVENTS_FILE="$TMP/events.jsonl"
reset_phase_evidence
push_ev "$SHA"
round_ev
jq -cn '{event:"SubagentStop", session_id:"child", agent_type:"close-reviewer", model:"claude-sonnet-9", effort:"medium"}' >>"$TRACE"
mkdir -p "$repo/.process"
cp "$TMP/review.md" "$repo/.process/reviewer-$SHA.md"
: >"$FAKE_GH_LOG"
assert_status 0 "publishes the review" sh -c "cd '$repo' && '$CLOSE' --publish-review '$TMP/review.md' --verdict success --round 1"
body="$(sed -n 's/.*--body-file //p' "$FAKE_GH_LOG" | head -1)"
text="$(cat "$body")"
assert_not_contains "$text" "baixo" "the self-reported effort is not published"
assert_contains "$text" "Modelo do revisor: claude-sonnet-9 · esforço: medium" "the published pair is the one in the trace"
assert_contains "$(cat "$TMP/review.md")" "baixo" "the saved reviewer output is not rewritten"

finish
