#!/usr/bin/env bash
#: progress.sh: what the long scripts are doing now, for the owner and the dashboard.
#:
#: Usage: progress.sh [--repo <name>] [--issue <n>] [--all] [--follow]
#:
#: Reads ~/.cache/ai-method/progress/<repo>-<issue>.jsonl (written by lib/progress.sh;
#: format in docs/process-design.md §6.4) and prints one line per script still running:
#:   <repo> #<issue> <script>: <step> [<done>/<total>] <elapsed>
#: A run whose process is gone and never wrote its end is shown as "(died)" with --all.
#: --all also lists the last run of each script that already ended ("ok" or "failed").
#: --follow streams the new events (tail -f), one formatted line each, until Ctrl-C.
#: --repo and --issue narrow the files; --issue alone means the repository of the
#: current directory. The agent does not read this output: it is for the owner.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=.method/scripts/lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=.method/scripts/lib/progress.sh
source "$HERE/lib/progress.sh"
require_cmd jq

repo="" issue="" all=0 follow=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --repo) [ $# -ge 2 ] || die "--repo needs a name" 2; repo="$2"; shift 2 ;;
    --issue) [ $# -ge 2 ] || die "--issue needs a number" 2; issue="$2"; shift 2 ;;
    --all) all=1; shift ;;
    --follow) follow=1; shift ;;
    *) die "unknown option: $1 (see --help)" 2 ;;
  esac
done
case "$issue" in *[!0-9]*) die "--issue must be a number" 2 ;; esac
if [ -n "$issue" ] && [ -z "$repo" ]; then
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || die "--issue without --repo needs a git repository" 2
  repo="$(basename "$(dirname "$common")")"
fi

dir="$(progress_dir)"
files=()
if [ -d "$dir" ]; then
  for f in "$dir"/*.jsonl; do
    [ -f "$f" ] || continue
    b="$(basename "$f" .jsonl)"
    [ -z "$repo" ] || case "$b" in "$repo"-[0-9]*|"$repo"-main) ;; *) continue ;; esac
    [ -z "$issue" ] || case "$b" in *-"$issue") ;; *) continue ;; esac
    files+=("$f")
  done
fi

# Formats a duration in seconds as 1h02m, 3m10s or 12s.
fmt_secs() {
  local s="$1"
  if [ "$s" -ge 3600 ]; then printf '%dh%02dm' $((s / 3600)) $((s % 3600 / 60))
  elif [ "$s" -ge 60 ]; then printf '%dm%02ds' $((s / 60)) $((s % 60))
  else printf '%ds' "$s"; fi
}

# jq program: one event as the line of the owner.
LINE='"\(.repo) \(if .issue == null then "main" else "#\(.issue)" end) \(.script)\(if .step != "" then ": \(.step)" else "" end)\(if .done != null then " \(.done)/\(.total)" else "" end)"'

if [ "$follow" = 1 ]; then
  [ ${#files[@]} -gt 0 ] || die "no progress file yet (nothing ran); try again later" 1
  tail -n 0 -F "${files[@]}" 2>/dev/null |
    jq -R --unbuffered -r "fromjson? | select(.state != null) | \"\(.ts) \" + ($LINE) + \" [\(.state)] \(.elapsed_s)s\""
  exit 0
fi

now="$(date +%s)"
shown=0
[ ${#files[@]} -gt 0 ] || { echo "nothing running"; exit 0; }
TAB="$(printf '\t')"
rows="$(jq -rs "[.[] | select(type == \"object\")] | group_by([.repo, .issue, .pid, .script]) | map(last)[]
  | [.state, .pid, (.ts | fromdateiso8601), .elapsed_s, ($LINE)] | @tsv" "${files[@]}" 2>/dev/null | sort -t "$TAB" -k3,3n || true)"
while IFS="$TAB" read -r st pid ts el line; do
  [ -n "$st" ] || continue
  case "$st" in
    start|step)
      if kill -0 "$pid" 2>/dev/null; then
        echo "$line  $(fmt_secs $((el + now - ts)))"; shown=1
      elif [ "$all" = 1 ]; then
        echo "$line  (died)"; shown=1
      fi ;;
    end) [ "$all" = 0 ] || { echo "$line  ok $(fmt_secs "$el")"; shown=1; } ;;
    fail) [ "$all" = 0 ] || { echo "$line  failed $(fmt_secs "$el")"; shown=1; } ;;
  esac
done <<<"$rows"
[ "$shown" = 1 ] || echo "nothing running"
