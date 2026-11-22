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
# It also stops that session from pushing the branch of the phase from any directory, the
# main checkout included: a git push whose refspec destination (or current branch, when it
# names none) is a branch of the phase (issue-<n> in its name), and --all, --mirror,
# --branches or a pattern while such a branch exists. Only the child session pushes it.
#
# Blocks with exit 2. Fails closed: a git write in a phase worktree is blocked when the hook
# cannot tell who opened the phase (no session_id, no trace, a trace line that is not JSON,
# no phase_opened of the issue, not a git checkout) or cannot read the command; the same
# holds for a push of a phase branch.
# For every session it also blocks a command that sets or unsets CLAUDE_CODE_SESSION_ID or
# PROCESS_EVENTS_FILE, or that writes .process/events.jsonl: the locks read them.
set -euo pipefail

deny() {
  echo "blocked by block-phase-commit: $1" >&2
  exit 2
}

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$here/../../scripts/lib/common.sh"
input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')" || deny "invalid hook input"
sid="$(printf '%s' "$input" | jq -r '.session_id // empty')"
[ -n "$cmd" ] || exit 0

findings="$(printf '%s' "$input" | "$here/block-dangerous-git.sh" --git-writes)" ||
  deny "could not read this command"

forged="$(printf '%s\n' "$findings" | sed -n 's/^forge	//p' | head -1)"
[ -z "$forged" ] || deny "never set or unset $forged in a command: the phase locks read it"
if printf '%s' "$cmd" | stdin_grep -qE "(>|tee[^|;&]*[[:space:]])[[:space:]]*[\"']?[^[:space:];|&\"']*\.process/events\.jsonl[\"']?([[:space:];|&)]|\$)"; then
  deny "never write .process/events.jsonl by hand: only the hooks and scripts record the trace"
fi

unreadable=0
printf '%s\n' "$findings" | stdin_grep -qx unreadable && unreadable=1
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

# A push of the branch of a phase, from any directory (the main checkout included).
while IFS='	' read -r dir dest; do
  [ -n "$dir" ] || continue
  if [ "$dest" = "*" ]; then
    branches="$(git -C "$dir" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null || true)"
  else
    branches="$dest"
  fi
  while IFS= read -r branch; do
    issue="$(printf '%s\n' "$branch" | sed -n -E 's/.*issue-([0-9]+).*/\1/p')"
    [ -n "$issue" ] || continue
    case "$(phase_opener_state "$issue" "$sid" "$dir")" in
      other) ;;
      opener) deny "this session opened phase #$issue and must not push its branch ($branch) from any directory; the child session pushes it (process-design §4.3)" ;;
      *) deny "cannot tell which session opened phase #$issue (session id, .process/events.jsonl of the main checkout and its phase_opened event are required): no push of its branch ($branch)" ;;
    esac
  done <<EOF
$branches
EOF
done <<EOF
$(printf '%s\n' "$findings" | sed -n 's/^push	//p')
EOF
[ "$unreadable" = 0 ] || deny "could not parse this git/gh command safely; simplify the quoting"
exit 0
