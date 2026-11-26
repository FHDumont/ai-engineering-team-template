#!/usr/bin/env bash
#: sessions.sh: Claude Code sessions and their MCPs on this machine.
#:
#: Usage: sessions.sh --list | --stale | --close-idle [--older-than <hours>] [--under <dir>] [--dry-run]
#:
#: --list: one line per claude process (not the app helper Helpers/disclaimer): repository, kind (app = child of the
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
#: --close-idle: stops the headless sessions of this checkout and its worktrees
#:   (never a child of the Claude.app, never this process or its ancestors) whose
#:   age is more than N hours (ps etime, not time since the last activity) and
#:   whose CPU is under 1%, with their MCPs. --under only narrows that set; the
#:   directory is canonicalized and a path outside this repository is refused
#:   (exit 2) before any signal. --dry-run lists what it would stop.
#: N: --older-than, else AI_METHOD_IDLE_HOURS of ~/.config/ai-method/machine-limits.env
#:   (default 4).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=.method/scripts/lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=.method/scripts/lib/slots.sh
source "$HERE/lib/slots.sh"
# shellcheck source=.method/scripts/lib/procs.sh
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
# A pid that exits between ps and the cwd lookup is skipped; do not fail the script.
proc_cwd() { proc_cwd_of "$1"; }
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
    printf '%s\n' "$cmd" | stdin_grep -Eq '(^|[ /])claude( |$)' || continue
    # The app helper (…/Helpers/disclaimer … -- …/claude) is not a session.
    printf '%s\n' "$cmd" | stdin_grep -q 'Helpers/disclaimer' && continue
    case "$cmd" in *"mcp "*|*"--mcp"*) continue ;; esac
    if proc_in_app "$pid"; then kind=app
    elif printf '%s\n' "$cmd" | stdin_grep -Eq ' (-p|--print)( |$)'; then kind=headless
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
      [ -n "$cwd" ] || continue
      mark=""
      if [ "$(proc_ppid "$pid")" = 1 ] && orphan_cwd_match "$cwd"; then mark=" orphan"; fi
      printf '%-44s %-9s %7s %9s %5s %7s %s\n' "$(repo_of "$cwd")" "$kind" "$pid" "$et" "$cpu" \
        "$(rss_mb "$rss")" "$n (+$(rss_mb "$kr") MB)$mark"
    done ;;
  --close-idle)
    # Default scope is this checkout and its worktrees. --under only narrows, and
    # a path outside the repository is refused before the loop that signals.
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "--close-idle runs inside a repository" 2
    roots=""
    while IFS= read -r line; do
      case "$line" in
        "worktree "*)
          canon="$(cd "${line#worktree }" 2>/dev/null && pwd -P)" || continue
          roots="${roots}${roots:+$'\n'}${canon}"
          ;;
      esac
    done < <(git worktree list --porcelain)
    [ -n "$roots" ] || die "cannot list the worktrees of this repository" 2
    if [ -n "$under" ]; then
      under="$(cd "$under" 2>/dev/null && pwd -P)" || die "--under is not a directory" 2
      ok=0
      while IFS= read -r r; do
        [ -n "$r" ] || continue
        case "$under" in "$r"|"$r"/*) ok=1 ;; esac
      done <<<"$roots"
      [ "$ok" = 1 ] || die "--under is outside this repository" 2
    fi
    stopped=0
    prot="$(proc_chain "$$" | tr '\n' ' ')"
    while IFS=$'\t' read -r pid et cpu rss kind; do
      [ "$kind" = headless ] || continue
      c="$(proc_cwd "$pid")"
      [ -n "$c" ] || continue
      c="$(cd "$c" 2>/dev/null && pwd -P)" || continue
      ok=0
      while IFS= read -r r; do
        [ -n "$r" ] || continue
        case "$c" in "$r"|"$r"/*) ok=1 ;; esac
      done <<<"$roots"
      [ "$ok" = 1 ] || continue
      if [ -n "$under" ]; then
        case "$c" in "$under"|"$under"/*) ;; *) continue ;; esac
      fi
      # shellcheck disable=SC2086
      proc_stoppable "$pid" $prot || continue
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
