#!/usr/bin/env bash
# phase-guard.sh: sourced by the git hooks (pre-commit, pre-merge-commit, pre-rebase,
# reference-transaction). The session that recorded phase_opened of a phase (the
# manager) never writes to it; the child session does. The session is
# CLAUDE_CODE_SESSION_ID; without it (terminal, another tool) nothing is refused here.

# Issue of this checkout: from the worktree path (.worktrees/issue-<n>[-r<k>]), else from the branch.
phase_guard_issue() {
  local top issue
  top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  issue="$(printf '%s\n' "$top" | sed -n -E 's#.*/\.worktrees/issue-([0-9]+)(-r[0-9]+)?$#\1#p')"
  [ -n "$issue" ] || issue="$(git branch --show-current 2>/dev/null | sed -n -E 's/.*issue-([0-9]+).*/\1/p')"
  echo "$issue"
}

# phase_guard <issue> <hook name>: returns 1, with the reason, when this session opened the phase.
phase_guard() {
  local top
  [ -n "$1" ] && [ -n "${CLAUDE_CODE_SESSION_ID:-}" ] || return 0
  top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -f "$top/scripts/lib/common.sh" ] || return 0
  # shellcheck source=scripts/lib/common.sh
  source "$top/scripts/lib/common.sh"
  [ "$(phase_opener_state "$1" "$CLAUDE_CODE_SESSION_ID" "$top")" = opener ] || return 0
  echo "$2: this session opened phase #$1 and must not write to it; the child session executes it (process-design §4.3)" >&2
  return 1
}
