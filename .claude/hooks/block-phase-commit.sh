#!/usr/bin/env bash
# block-phase-commit.sh: PreToolUse (Bash) hook that stops the session that opened a
# phase (phase_opened in the trace) from writing with git inside .worktrees/issue-<n>
# (also issue-<n>-r<k> and the git dir of the worktree).
# The manager session never executes a phase; the git hooks (.githooks) and
# close-phase.sh are the durable locks.
#
# The command is read by the parser of block-dangerous-git.sh (--git-writes): every git
# command outside its read-only list counts, in whatever directory it would run (cwd,
# cd/pushd, -C, --git-dir, --work-tree, GIT_DIR, GIT_WORK_TREE), through wrappers, blocks,
# nested shells, eval and line continuations.
#
# Blocks with exit 2. Fails closed: a git write in a phase worktree is blocked when the hook
# cannot tell who opened the phase (no session_id, no trace, a trace line that is not JSON,
# no phase_opened of the issue, not a git checkout) or cannot read the command.
# For every session it also blocks a command that sets or unsets CLAUDE_CODE_SESSION_ID or
# PROCESS_EVENTS_FILE, or that writes .process/events.jsonl: the locks read them.
set -euo pipefail

deny() {
  echo "blocked by block-phase-commit: $1" >&2
  exit 2
}

here="$(cd "$(dirname "$0")" && pwd)"
input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')" || deny "invalid hook input"
sid="$(printf '%s' "$input" | jq -r '.session_id // empty')"
[ -n "$cmd" ] || exit 0

findings="$(printf '%s' "$input" | "$here/block-dangerous-git.sh" --git-writes)" ||
  deny "could not read this command"

forged="$(printf '%s\n' "$findings" | sed -n 's/^forge	//p' | head -1)"
[ -z "$forged" ] || deny "never set or unset $forged in a command: the phase locks read it"
if printf '%s' "$cmd" | grep -qE "(>|tee[^|;&]*[[:space:]])[[:space:]]*[\"']?[^[:space:];|&\"']*\.process/events\.jsonl[\"']?([[:space:];|&)]|\$)"; then
  deny "never write .process/events.jsonl by hand: only the hooks and scripts record the trace"
fi

# shellcheck source=scripts/lib/common.sh
source "$here/../../scripts/lib/common.sh"
unreadable=0
printf '%s\n' "$findings" | grep -qx unreadable && unreadable=1
while IFS= read -r dir; do
  [ -n "$dir" ] || continue
  phase="$(phase_of_path "$dir")"
  [ -n "$phase" ] || continue
  issue="${phase%%	*}"
  case "$(phase_opener_state "$issue" "$sid" "${phase#*	}")" in
    other) ;;
    opener) deny "this session opened phase #$issue and must not write to its worktree; the child session executes it (process-design §4.3)" ;;
    *) deny "cannot tell which session opened phase #$issue (session id, .process/events.jsonl of the main checkout and its phase_opened event are required): no git write in its worktree" ;;
  esac
done <<EOF
$(printf '%s\n' "$findings" | sed -n 's/^write	//p')
EOF
[ "$unreadable" = 0 ] || deny "could not parse this git/gh command safely; simplify the quoting"
exit 0
