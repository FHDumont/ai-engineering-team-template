#!/usr/bin/env bash
# Progress of the long scripts, for the owner and the dashboard (never for the agent).
# Load with: source "$HERE/lib/progress.sh". Bash 3.2 compatible. Never fails the caller.
#
# One JSON line per event, append only, in
#   ~/.cache/ai-method/progress/<repo>-<issue>.jsonl   (no phase: <repo>-main.jsonl)
# (AI_METHOD_CACHE overrides the folder). Fields: ts (UTC ISO), repo, issue (number or
# null), script, pid, step, done, total (numbers or null), elapsed_s (since the start of
# this script), state (start, step, end, fail). Format in docs/process-design.md §6.4.
# The agent does not read these files: the scripts print only the result.
#
# Use: progress_start <script> [issue]; progress_step <step> [done total]; the end is
# recorded by progress_end <rc> (call it from the EXIT trap of the script).
# A file untouched for 7 days goes away (progress_prune, run at every start).
#
# Optional fields: log (absolute path of the output of the script, only when the script
# asks for it with progress_start <script> <issue> log; the file is
# <cache>/logs/<repo>-<issue|main>-<script without .sh>-<pid>.log, pruned like the progress)
# and parent_pid (pid of the method script that called this one, taken from the exported
# AI_METHOD_PARENT_PID; absent with no such parent).

PROGRESS_SCRIPT="" PROGRESS_ISSUE="" PROGRESS_REPO="" PROGRESS_T0=0 PROGRESS_FILE="" PROGRESS_ON=0
PROGRESS_LOG="" PROGRESS_PARENT=""

progress_dir() { printf '%s\n' "${AI_METHOD_CACHE:-$HOME/.cache/ai-method}/progress"; }
progress_log_dir() { printf '%s\n' "${AI_METHOD_CACHE:-$HOME/.cache/ai-method}/logs"; }

# Removes the files untouched for more than 7 days.
progress_prune() {
  find "$(progress_dir)" -name '*.jsonl' -type f -mtime +7 -exec rm -f {} + 2>/dev/null || true
  find "$(progress_log_dir)" -name '*.log' -type f -mtime +7 -exec rm -f {} + 2>/dev/null || true
}

progress_emit() { # progress_emit <state> <step> <done> <total>
  [ "$PROGRESS_ON" = 1 ] || return 0
  local now
  now="$(date +%s)"
  jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg repo "$PROGRESS_REPO" --arg issue "$PROGRESS_ISSUE" \
    --arg script "$PROGRESS_SCRIPT" --argjson pid "$$" --arg step "$2" --arg "done" "$3" --arg total "$4" \
    --argjson el "$((now - PROGRESS_T0))" --arg state "$1" --arg log "$PROGRESS_LOG" --arg parent "$PROGRESS_PARENT" \
    '{ts: $ts, repo: $repo, issue: (if $issue == "" then null else ($issue | tonumber) end), script: $script,
      pid: $pid, step: $step, done: (if $done == "" then null else ($done | tonumber) end),
      total: (if $total == "" then null else ($total | tonumber) end), elapsed_s: $el, state: $state}
      + (if $log == "" then {} else {log: $log} end)
      + (if $parent == "" then {} else {parent_pid: ($parent | tonumber)} end)' \
    >>"$PROGRESS_FILE" 2>/dev/null || true
}

progress_start() { # progress_start <script> [issue] [log]
  command -v jq >/dev/null 2>&1 || return 0
  local common
  PROGRESS_SCRIPT="$1" PROGRESS_ISSUE="${2:-}" PROGRESS_T0="$(date +%s)"
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || common="$PWD/.git"
  PROGRESS_REPO="$(basename "$(dirname "$common")")"
  PROGRESS_FILE="$(progress_dir)/$PROGRESS_REPO-${PROGRESS_ISSUE:-main}.jsonl"
  mkdir -p "$(progress_dir)" 2>/dev/null || return 0
  PROGRESS_ON=1
  progress_prune
  # The caller (a method script that exported its pid) is the parent; we become the parent of ours.
  PROGRESS_PARENT=""
  case "${AI_METHOD_PARENT_PID:-}" in ''|*[!0-9]*) ;; "$$") ;; *) PROGRESS_PARENT="$AI_METHOD_PARENT_PID" ;; esac
  export AI_METHOD_PARENT_PID="$$"
  PROGRESS_LOG=""
  if [ "${3:-}" = log ] && mkdir -p "$(progress_log_dir)" 2>/dev/null; then
    PROGRESS_LOG="$(progress_log_dir)/$PROGRESS_REPO-${PROGRESS_ISSUE:-main}-${PROGRESS_SCRIPT%.sh}-$$.log"
    : >"$PROGRESS_LOG" 2>/dev/null || PROGRESS_LOG=""
  fi
  progress_emit start "" "" ""
}

progress_step() { # progress_step <step> [done total]
  progress_emit step "$1" "${2:-}" "${3:-}"
}

progress_end() { # progress_end <exit status>
  [ "$PROGRESS_ON" = 1 ] || return 0
  if [ "${1:-0}" = 0 ]; then progress_emit end "" "" ""; else progress_emit fail "exit $1" "" ""; fi
  PROGRESS_ON=0
}
