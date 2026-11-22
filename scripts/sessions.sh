#!/usr/bin/env bash
#: sessions.sh: Claude Code sessions and their MCPs on this machine.
#:
#: Usage: sessions.sh --list | --stale | --close-idle [--older-than <hours>] [--under <dir>] [--dry-run]
#:
#: --list: one line per claude process: repository, kind (app = child of the
#:   Claude.app, headless = "claude -p"), pid, age, CPU %, RAM MB and the MCPs it
#:   holds (its descendants: count and RAM MB).
#: --stale: sessions of this repository the app still shows as not archived and
#:   that have been idle for more than N hours (the files of the app under
#:   ~/Library/Application Support/Claude/claude-code-sessions, read only; the
#:   AI_METHOD_SESSIONS_DIR variable overrides the folder). Only the owner frees
#:   those: app menu, Archive (not Delete: the history is lost).
#:   A session whose parent is 1 (the creator is gone) and whose directory is a
#:   temporary folder of a test or a worktree that no longer exists gets the mark
#:   "orphan" at the end of its line. The mark only informs: close-phase.sh
#:   --cleanup does not stop an orphan outside the phase worktree.
#: --close-idle: stops the headless sessions (never a child of the Claude.app,
#:   never this process or its ancestors) idle for more than N hours (CPU under 1%)
#:   with their MCPs. --under limits it to sessions whose directory is <dir> or
#:   inside it. --dry-run lists what it would stop.
#: N: --older-than, else AI_METHOD_IDLE_HOURS of ~/.config/ai-method/machine-limits.env
#:   (default 4).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=scripts/lib/slots.sh
source "$HERE/lib/slots.sh"
# shellcheck source=scripts/lib/procs.sh
source "$HERE/lib/procs.sh"

[ $# -gt 0 ] || { print_help "$0"; exit 2; }
require_cmd ps awk
slots_load_limits
mode="" hours="$AI_METHOD_IDLE_HOURS" dry=0 under=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --list|--stale|--close-idle) mode="$1"; shift ;;
    --older-than) hours="${2:?--older-than needs a number of hours}"; shift 2 ;;
    --under) under="${2:?--under needs a directory}"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) die "unknown option: $1 (see --help)" 2 ;;
  esac
done
case "$hours" in ''|*[!0-9.]*) die "hours must be a number" 2 ;; esac
[ -n "$mode" ] || { print_help "$0"; exit 2; }

# Directory of a pid, repository root of it (the part before /.worktrees/).
proc_cwd() { lsof -a -d cwd -Fn -p "$1" 2>/dev/null | sed -n 's/^n//p' | head -1; }
repo_of() {
  local d="$1"
  case "$d" in */.worktrees/*) d="${d%%/.worktrees/*}" ;; esac
  printf '%s\n' "${d:--}"
}
rss_mb() { awk -v k="${1:-0}" 'BEGIN { printf "%d", k / 1024 }'; }

# Claude processes: "pid<TAB>etime<TAB>cpu<TAB>rss<TAB>kind".
claude_rows() {
  local pid et cpu rss cmd kind
  ps -axo pid=,etime=,pcpu=,rss=,command= | while read -r pid et cpu rss cmd; do
    [ "$pid" != "$$" ] || continue
    printf '%s\n' "$cmd" | grep -Eq '(^|[ /])claude( |$)' || continue
    case "$cmd" in *"mcp "*|*"--mcp"*) continue ;; esac
    if proc_in_app "$pid"; then kind=app
    elif printf '%s\n' "$cmd" | grep -Eq ' (-p|--print)( |$)'; then kind=headless
    else kind=cli; fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$pid" "$et" "$cpu" "$rss" "$kind"
  done
}

case "$mode" in
  --list)
    printf '%-44s %-9s %7s %9s %5s %7s %s\n' repo kind pid age cpu ramMB mcps
    claude_rows | while IFS=$'\t' read -r pid et cpu rss kind; do
      n=0 kr=0
      for k in $(proc_descendants "$pid"); do
        n=$((n + 1)); kr=$((kr + $(ps -o rss= -p "$k" 2>/dev/null | tr -d ' ' || echo 0)))
      done
      cwd="$(proc_cwd "$pid")"
      mark=""
      if [ "$(proc_ppid "$pid")" = 1 ] && orphan_cwd_match "$cwd"; then mark=" orphan"; fi
      printf '%-44s %-9s %7s %9s %5s %7s %s\n' "$(repo_of "$cwd")" "$kind" "$pid" "$et" "$cpu" \
        "$(rss_mb "$rss")" "$n (+$(rss_mb "$kr") MB)$mark"
    done ;;
  --close-idle)
    stopped=0
    prot="$(proc_chain "$$" | tr '\n' ' ')"
    while IFS=$'\t' read -r pid et cpu rss kind; do
      [ "$kind" = headless ] || continue
      # shellcheck disable=SC2086
      proc_stoppable "$pid" $prot || continue
      if [ -n "$under" ]; then
        c="$(proc_cwd "$pid")"
        case "$c" in "${under%/}"|"${under%/}"/*) ;; *) continue ;; esac
      fi
      awk -v s="$(etime_seconds "$et")" -v h="$hours" -v c="$cpu" 'BEGIN { exit !(s > h * 3600 && c < 1) }' || continue
      all="$pid $(proc_descendants "$pid" | tr '\n' ' ')"
      echo "idle headless session $pid ($et, $(rss_mb "$rss") MB): $(proc_cmd "$pid" | cut -c1-80)"
      if [ "$dry" = 0 ]; then
        # shellcheck disable=SC2086
        proc_stop $all
        stopped=$((stopped + 1))
      fi
    done < <(claude_rows)
    [ "$dry" = 1 ] && echo "dry-run: nothing stopped" || echo "stopped $stopped headless session(s)" ;;
  --stale)
    require_cmd jq git
    root="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
    dir="${AI_METHOD_SESSIONS_DIR:-$HOME/Library/Application Support/Claude/claude-code-sessions}"
    [ -d "$dir" ] || exit 0
    now_ms=$(($(date +%s) * 1000))
    find "$dir" -maxdepth 3 -name 'local_*.json' 2>/dev/null | while IFS= read -r f; do
      jq -r --arg root "$root" --argjson now "$now_ms" --argjson h "$hours" '
        select(.isArchived == false and ((.cwd // "") | (. == $root or startswith($root + "/")))
          and ($now - (.lastActivityAt // $now)) > ($h * 3600000))
        | "\(.title // "?")\t\(.sessionId)\t\((($now - .lastActivityAt) / 3600000 * 10 | floor) / 10)"' "$f" 2>/dev/null || true
    done | while IFS=$'\t' read -r title sid age; do
      echo "- $title (idle ${age} h, $sid)"
    done ;;
esac
