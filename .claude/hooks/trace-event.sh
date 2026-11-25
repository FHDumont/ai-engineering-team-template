#!/usr/bin/env bash
# trace-event.sh: hook that records the agent tree.
#
# Registered for SessionStart, SubagentStart, SubagentStop, Stop, SessionEnd,
# PreToolUse and PostToolUse (matcher Agent). Reads the hook JSON on stdin and appends a line
# to .process/events.jsonl at the root of the main checkout (outside git).
# Fields: ts, event, session_id, agent_id, agent_type, model, effort, cwd,
# branch, issue; plus source (SessionStart) and, on the Agent PreToolUse,
# tool_use_id, subagent_type and description. On PreToolUse, model and effort are
# the requests made to the subagent (tool_input), not those of the session. The Agent
# PostToolUse records tool_use_id and subagent_id (the agentId of the response), which link
# the request to the right SubagentStart/Stop when several subagents start together.
# When the hook input has no model, the model comes from the transcript: the session's
# for a session event, the subagent's for SubagentStop.
# SubagentStop of the close-reviewer also records output_sha (opinion_sha of its last text with a
# "Veredito:" line in the subagent transcript; else of last_assistant_message).
# Never blocks: always exits 0, even on error.
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$here/../../scripts/lib/common.sh" 2>/dev/null || exit 0
command -v jq >/dev/null 2>&1 || exit 0

input="$(head -c 1000000)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
# Closing a phase deletes its worktree: a cwd from the JSON or a current directory that no
# longer exists falls back to the main checkout (CLAUDE_PROJECT_DIR; else, the root of this hook).
[ -d "$cwd" ] || cwd="${CLAUDE_PROJECT_DIR:-$here/../..}"
[ -d "$cwd" ] || cwd="$PWD"
branch="$(current_branch "$cwd")"

# Model the hook input does not bring: read from the transcript. A session event takes
# the model of the session transcript; SubagentStop, the one of the subagent transcript
# (<session transcript without .jsonl>/subagents/agent-<agent_id>.jsonl).
fill_model="$(printf '%s' "$input" | jq -r '
  if (.model // "") != "" or (.transcript_path // "") == "" then empty
  elif (.agent_id // "") == "" then "main\t\(.transcript_path)"
  elif .hook_event_name == "SubagentStop" then
    "\t\(.agent_transcript_path // "\(.transcript_path | sub("\\.jsonl$"; ""))/subagents/agent-\(.agent_id).jsonl")"
  else empty end' 2>/dev/null)"
[ -z "$fill_model" ] || fill_model="$(transcript_model "${fill_model#*$'\t'}" "${fill_model%%$'\t'*}")"

line="$(printf '%s' "$input" | jq -c --arg fill_model "$fill_model" \
  --arg branch "$branch" --arg issue "$(issue_from_branch "$branch")" --arg cwd "$cwd" \
  --arg env_effort "${CLAUDE_EFFORT:-}" --arg sub_effort "${CLAUDE_CODE_SUBAGENT_EFFORT:-}" '
  (.hook_event_name // "") as $ev
  | ((.effort | if type == "object" then .level else . end) // $env_effort) as $sess_effort
  | {ts: (now | todate), event: $ev, session_id: (.session_id // ""),
     agent_id: (.agent_id // ""), agent_type: (.agent_type // ""),
     model: ((.model // "") | if . == "" then $fill_model else . end), effort: ($sess_effort // ""),
     cwd: $cwd, branch: $branch, issue: $issue}
  + (if $ev == "SessionStart" then {source: (.source // "")} else {} end)
  + (if $ev == "PreToolUse" then
       {tool_use_id: (.tool_use_id // ""),
        subagent_type: (.tool_input.subagent_type // ""),
        description: (.tool_input.description // ""),
        model: (.tool_input.model // ""),
        effort: (.tool_input.effort // $sub_effort)}
     else {} end)
  + (if $ev == "PostToolUse" then
       {tool_use_id: (.tool_use_id // ""), model: "", effort: "",
        subagent_id: ((.tool_response | tostring | capture("agentId[^a-z0-9]+(?<id>[a-z0-9]+)").id) // "")}
     else {} end)' 2>/dev/null)" || exit 0
# The close-reviewer output is hashed here, when the subagent stops, so close-phase.sh can refuse
# an opinion edited after it was saved. Only the hash goes to the trace, never the text.
if [ -n "$line" ] && printf '%s' "$line" | jq -e '.event == "SubagentStop" and .agent_type == "close-reviewer"' >/dev/null 2>&1; then
  # The opinion is the last text with a "Veredito:" line in the subagent transcript: an assistant text
  # block or the message of a tool that delivers the report. Without it: last_assistant_message.
  sub_tr="$(printf '%s' "$input" | jq -r '(.agent_transcript_path // (if (.transcript_path // "") != "" and (.agent_id // "") != ""
    then "\(.transcript_path | sub("\\.jsonl$"; ""))/subagents/agent-\(.agent_id).jsonl" else empty end)) // empty' 2>/dev/null)"
  opinion=""
  [ -z "$sub_tr" ] || opinion="$(opinion_from_transcript "$sub_tr")"
  [ -n "$opinion" ] || opinion="$(printf '%s' "$input" | jq -r '.last_assistant_message // empty' 2>/dev/null)"
  out_sha="$(printf '%s' "$opinion" | opinion_sha)"
  [ "$out_sha" = "$(printf '' | opinion_sha)" ] ||
    line="$(printf '%s' "$line" | jq -c --arg h "$out_sha" '. + {output_sha: $h}' 2>/dev/null || printf '%s' "$line")"
fi
[ -n "$line" ] && append_event "$line" "$cwd"
exit 0
