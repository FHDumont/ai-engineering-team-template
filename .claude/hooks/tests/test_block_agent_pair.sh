#!/usr/bin/env bash
# Tests for the block-agent-pair.sh hook.
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "$0")/../../../.method/scripts/tests/lib.sh"
HOOK="$REPO/.claude/hooks/block-agent-pair.sh"

run() { # run <tool_input json>
  jq -cn --argjson i "$1" '{session_id: "s", tool_name: "Agent", tool_input: $i}' | "$HOOK"
}

assert_status 0 "allows an agent with model and effort" run '{"prompt": "x", "model": "sonnet", "effort": "low"}'
assert_status 2 "blocks an agent without model" run '{"prompt": "x", "effort": "low"}'
assert_contains "$(last_output)" "model" "names what is missing"
assert_status 2 "blocks an agent without effort" run '{"prompt": "x", "model": "sonnet"}'
assert_contains "$(last_output)" "effort" "names what is missing"
assert_status 2 "blocks an agent with neither" run '{"prompt": "x", "subagent_type": "Explore"}'
assert_status 2 "blocks empty values" run '{"prompt": "x", "model": "", "effort": ""}'
assert_status 2 "blocks invalid input" sh -c "echo 'not json' | '$HOOK'"
# The agents of the repo open only with the pair of their weight in .method/scripts/lib/weights.tsv.
reviewer="$("$SCRIPTS/weights.sh" reviewer)"
triage="$("$SCRIPTS/weights.sh" triage)"
call() { # call <subagent_type> <model> <effort>
  run "$(jq -cn --arg t "$1" --arg m "$2" --arg e "$3" '{prompt: "x", subagent_type: $t, model: $m, effort: $e}')"
}
assert_status 0 "allows the reviewer with the pair of the file" call close-reviewer "${reviewer% *}" "${reviewer#* }"
assert_status 2 "blocks the reviewer with another model" call close-reviewer other-model "${reviewer#* }"
assert_contains "$(last_output)" "reviewer weight" "names the weight"
assert_status 2 "blocks the reviewer with another effort" call close-reviewer "${reviewer% *}" max
assert_status 0 "allows the triage with the pair of the file" call triage "${triage% *}" "${triage#* }"
assert_status 2 "blocks the triage with another pair" call triage other-model max
assert_status 0 "any other agent keeps the pair of its step" call Explore other-model max
finish
