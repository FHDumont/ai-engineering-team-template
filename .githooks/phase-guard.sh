#!/usr/bin/env bash
# phase-guard.sh: sourced by the git hooks (pre-commit, pre-merge-commit, pre-rebase,
# reference-transaction). The session that recorded phase_opened of a phase (the
# manager) never writes to it; the child session does. The session is
# CLAUDE_CODE_SESSION_ID; without it (terminal, another tool) a commit reports
# the lack of phase_session and proceeds.

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

# phase_require_session <issue> <hook name>: on a phase branch, a session with an
# id must have recorded phase_session of that issue before a commit. Without a
# session id the lack is reported and the commit proceeds. A phase that updates
# check-env.sh keeps the phase_session already recorded; the commit that changes
# that script does not have to run the new one first.
phase_require_session() {
  local top trace sid="${CLAUDE_CODE_SESSION_ID:-}"
  [ -n "$1" ] || return 0
  top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -f "$top/scripts/lib/common.sh" ] || return 0
  # shellcheck source=scripts/lib/common.sh
  source "$top/scripts/lib/common.sh"
  if [ -z "$sid" ]; then
    echo "$2: no session id: phase_session of #$1 was not checked (run scripts/check-env.sh in the child session)" >&2
    return 0
  fi
  [ "$(phase_opener_state "$1" "$sid" "$top")" = opener ] && return 0
  trace="$(phase_trace_file "$top")" || {
    echo "$2: cannot locate the trace: no commit in phase #$1 without phase_session" >&2
    return 1
  }
  [ -f "$trace" ] || {
    echo "$2: this session has no phase_session of issue #$1: run scripts/check-env.sh in the phase worktree" >&2
    return 1
  }
  jq -e -rs --arg s "$sid" --arg i "$1" '
    any(.[]; type == "object" and .event == "phase_session" and .session_id == $s and ((.issue | tostring) == $i))
  ' "$trace" >/dev/null 2>&1 || {
    echo "$2: this session has no phase_session of issue #$1: run scripts/check-env.sh in the phase worktree" >&2
    return 1
  }
  return 0
}
