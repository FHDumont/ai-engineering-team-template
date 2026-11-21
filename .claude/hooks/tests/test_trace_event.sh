#!/usr/bin/env bash
# Tests for the trace-event.sh hook and the trace_event function of the scripts.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/../../../scripts/tests/lib.sh"
HOOK="$REPO/.claude/hooks/trace-event.sh"
# Here the default destination (main checkout of the temporary repo) is what is tested.
unset PROCESS_EVENTS_FILE

repo="$(make_repo)"
git -C "$repo" switch --quiet -c feat/issue-42-x
mkdir -p "$repo/.worktrees"
git -C "$repo" worktree add --quiet -b chore/issue-7-y "$repo/.worktrees/issue-7"
EV="$repo/.process/events.jsonl"

field() { sed -n "${1}p" "$EV" | jq -r ".$2"; }

# SessionStart with model, effort (object) and source.
jq -cn --arg d "$repo" '{hook_event_name: "SessionStart", session_id: "s1", cwd: $d,
  source: "startup", model: "opus", effort: {level: "high"}}' | "$HOOK"
assert_eq 1 "$(wc -l <"$EV" | tr -d ' ')" "writes one line per event"
assert_eq SessionStart "$(field 1 event)" "event name"
assert_eq s1 "$(field 1 session_id)" "session id"
assert_eq opus "$(field 1 model)" "session model"
assert_eq high "$(field 1 effort)" "effort from the effort object"
assert_eq startup "$(field 1 source)" "source"
assert_eq feat/issue-42-x "$(field 1 branch)" "branch"
assert_eq 42 "$(field 1 issue)" "issue from the branch"
assert_contains "$(field 1 ts)" "T" "ISO timestamp"

# PreToolUse of Agent: model and effort requested in tool_input.
jq -cn --arg d "$repo" '{hook_event_name: "PreToolUse", session_id: "s1", cwd: $d,
  tool_name: "Agent", tool_use_id: "toolu_1", effort: {level: "high"},
  tool_input: {description: "step 2", subagent_type: "general-purpose", model: "sonnet", effort: "medium"}}' | "$HOOK"
assert_eq sonnet "$(field 2 model)" "requested model from tool_input"
assert_eq medium "$(field 2 effort)" "requested effort from tool_input"
assert_eq "step 2" "$(field 2 description)" "agent description"
assert_eq toolu_1 "$(field 2 tool_use_id)" "tool use id"

# PostToolUse of Agent: the agentId of the response links the request to the subagent.
jq -cn --arg d "$repo" '{hook_event_name: "PostToolUse", session_id: "s1", cwd: $d, tool_name: "Agent",
  tool_use_id: "toolu_1", tool_response: [{type: "text", text: "Async agent launched successfully.\nagentId: a1b2c3 (internal ID)"}]}' | "$HOOK"
assert_eq a1b2c3 "$(sed -n 3p "$EV" | jq -r .subagent_id)" "subagent id from the Agent response"
assert_eq toolu_1 "$(sed -n 3p "$EV" | jq -r .tool_use_id)" "tool use id on PostToolUse"
sed -i.bak 3d "$EV"

# No effort in tool_input: the default of the subagents applies.
jq -cn --arg d "$repo" '{hook_event_name: "PreToolUse", session_id: "s1", cwd: $d,
  tool_name: "Agent", tool_input: {description: "x"}}' | CLAUDE_CODE_SUBAGENT_EFFORT=low "$HOOK"
assert_eq low "$(field 3 effort)" "subagent effort default from the env"

# Inside a worktree: writes to the main checkout, with the branch of the worktree.
jq -cn --arg d "$repo/.worktrees/issue-7" '{hook_event_name: "SubagentStart", session_id: "s2",
  cwd: $d, agent_id: "a1", agent_type: "Explore"}' | CLAUDE_EFFORT=low "$HOOK"
assert_eq 4 "$(wc -l <"$EV" | tr -d ' ')" "worktree event lands in the main checkout"
assert_eq a1 "$(field 4 agent_id)" "agent id"
assert_eq Explore "$(field 4 agent_type)" "agent type"
assert_eq 7 "$(field 4 issue)" "issue from the worktree branch"
assert_eq low "$(field 4 effort)" "effort from CLAUDE_EFFORT"
[ ! -e "$repo/.worktrees/issue-7/.process" ] && ok || bad "no trace file inside the worktree"

# Invalid input or outside a repo: never blocks.
assert_status 0 "invalid JSON exits 0" bash -c "echo 'not json' | '$HOOK'"
assert_status 0 "outside a repo exits 0" bash -c "echo '{\"hook_event_name\":\"Stop\",\"cwd\":\"$TMP\"}' | '$HOOK'"
assert_eq 4 "$(wc -l <"$EV" | tr -d ' ')" "bad input writes nothing"

# trace_event of the scripts: key=value become fields.
(
  cd "$repo/.worktrees/issue-7"
  # shellcheck source=scripts/lib/common.sh
  source "$REPO/scripts/lib/common.sh"
  trace_event bot_ask bot=bot-b ask_id=abc note="a=b c"
)
assert_eq bot_ask "$(field 5 event)" "script event name"
assert_eq bot-b "$(field 5 bot)" "script event field"
assert_eq "a=b c" "$(field 5 note)" "value keeps '=' and spaces"
assert_eq 7 "$(field 5 issue)" "script event issue"

# Phase worktree deleted at close: Stop arrives with a nonexistent cwd in the JSON.
# The hook exits 0, without error, and the event goes to the main checkout.
git -C "$repo" worktree add --quiet -b chore/issue-8-z "$repo/.worktrees/issue-8"
gone="$repo/.worktrees/issue-8"
git -C "$repo" worktree remove --force "$gone"
before="$(wc -l <"$EV" | tr -d ' ')"
rc=0
(cd "$TMP" && jq -cn --arg d "$gone" '{hook_event_name: "Stop", session_id: "s3", cwd: $d}' \
  | CLAUDE_PROJECT_DIR="$repo" "$HOOK" 2>"$TMP/gone.err") || rc=$?
assert_eq 0 "$rc" "removed worktree exits 0"
assert_eq "" "$(cat "$TMP/gone.err")" "removed worktree prints nothing on stderr"
assert_eq "$((before + 1))" "$(wc -l <"$EV" | tr -d ' ')" "event survives the removed worktree"
assert_eq Stop "$(sed -n "$((before + 1))p" "$EV" | jq -r .event)" "event recorded in the main checkout"
assert_eq s3 "$(sed -n "$((before + 1))p" "$EV" | jq -r .session_id)" "session id of the removed worktree"
# Also with the current directory of the process deleted and no cwd in the JSON. Bash warns
# on its own on stderr when it starts in a nonexistent directory; only exit 0 and the event matter here.
mkdir -p "$TMP/doomed"
rc=0
(
  cd "$TMP/doomed"
  rmdir "$TMP/doomed"
  echo '{"hook_event_name":"SessionEnd","session_id":"s4"}' | CLAUDE_PROJECT_DIR="$repo" "$HOOK" 2>/dev/null
) || rc=$?
assert_eq 0 "$rc" "missing current directory exits 0"
assert_eq SessionEnd "$(sed -n "$((before + 2))p" "$EV" | jq -r .event)" "event without cwd goes to the main checkout"
# The commands of settings.json point to the main checkout, not to the worktree.
assert_eq 0 "$(jq -r '[.. | .command? // empty | select(contains("trace-event.sh")) | select(startswith("\"${CLAUDE_PROJECT_DIR}\"/") | not)] | length' "$REPO/.claude/settings.json")" "hook commands use CLAUDE_PROJECT_DIR"

# PROCESS_EVENTS_FILE redirects the trace.
jq -cn --arg d "$repo" '{hook_event_name: "Stop", session_id: "s1", cwd: $d}' | PROCESS_EVENTS_FILE="$TMP/alt.jsonl" "$HOOK"
assert_eq Stop "$(jq -r .event "$TMP/alt.jsonl")" "PROCESS_EVENTS_FILE override"
# Model the hook input does not bring: read from the transcript. A session event takes
# the model of the session transcript (never the one of a subagent line); SubagentStop,
# the one of the subagent transcript. An input with a model keeps it.
mkdir -p "$TMP/tr/s9/subagents"
{
  echo '{"type":"assistant","isSidechain":false,"message":{"model":"claude-main-1"}}'
  echo '{"type":"assistant","isSidechain":true,"message":{"model":"claude-side-1"}}'
} >"$TMP/tr/s9.jsonl"
echo '{"type":"assistant","isSidechain":true,"message":{"model":"claude-sub-1"}}' >"$TMP/tr/s9/subagents/agent-b1.jsonl"
fill() { # fill <jq object>: one event into its own trace; prints the model recorded
  : >"$TMP/fill.jsonl"
  jq -cn --arg d "$repo" --arg t "$TMP/tr/s9.jsonl" "{session_id: \"s9\", cwd: \$d, transcript_path: \$t} + $1" | PROCESS_EVENTS_FILE="$TMP/fill.jsonl" "$HOOK"
  jq -r .model "$TMP/fill.jsonl"
}
assert_eq claude-main-1 "$(fill '{hook_event_name: "Stop"}')" "session event takes the model of the session transcript"
assert_eq claude-sub-1 "$(fill '{hook_event_name: "SubagentStop", agent_id: "b1"}')" "SubagentStop takes the model of the subagent transcript"
assert_eq given "$(fill '{hook_event_name: "Stop", model: "given"}')" "a model in the hook input is kept"
assert_eq "" "$(fill '{hook_event_name: "SubagentStop", agent_id: "none"}')" "no transcript, no model"
assert_eq asked "$(fill '{hook_event_name: "PreToolUse", tool_name: "Agent", tool_input: {model: "asked", effort: "low"}}')" "PreToolUse keeps the requested model"
finish
