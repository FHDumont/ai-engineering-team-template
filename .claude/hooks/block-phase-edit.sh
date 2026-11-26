#!/usr/bin/env bash
# block-phase-edit.sh: PreToolUse (Edit, Write, NotebookEdit) hook that stops the session
# that opened a phase (phase_opened in the trace) from editing files inside
# .worktrees/issue-<n> (also issue-<n>-r<k>): the child session executes the phase.
# Blocks with exit 2. Fails closed: a path in a phase worktree is blocked when the hook
# cannot tell who opened the phase (no session_id, no trace, a trace line that is not
# JSON, no phase_opened of the issue, not a git checkout).
# For every session it also blocks .process/events.jsonl: only hooks and scripts record the trace.
set -euo pipefail

deny() {
  echo "blocked by block-phase-edit: $1" >&2
  exit 2
}

here="$(cd "$(dirname "$0")" && pwd)"
input="$(cat)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')" || deny "invalid hook input"
sid="$(printf '%s' "$input" | jq -r '.session_id // empty')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
[ -n "$file" ] || exit 0
# Absolute path without "..", so a detour through another folder is still the worktree.
file="$(python3 -I -c 'import os, sys; print(os.path.normpath(os.path.join(sys.argv[1] or os.getcwd(), sys.argv[2])))' "$cwd" "$file")" ||
  deny "could not resolve the path"

case "$file" in
  */.process/events.jsonl) deny "never write .process/events.jsonl by hand: only the hooks and scripts record the trace" ;;
esac

# shellcheck source=.method/scripts/lib/common.sh
source "$here/../../.method/scripts/lib/common.sh"
phase="$(phase_of_path "$file")"
[ -n "$phase" ] || exit 0
issue="${phase%%	*}"
case "$(phase_opener_state "$issue" "$sid" "${phase#*	}")" in
  other) exit 0 ;;
  opener) deny "this session opened phase #$issue and must not edit its worktree; the child session executes it (process-design §4.3)" ;;
  *) deny "cannot tell which session opened phase #$issue (session id, .process/events.jsonl of the main checkout and its phase_opened event are required): no edit in its worktree" ;;
esac
