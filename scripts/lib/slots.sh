#!/usr/bin/env bash
# Machine-wide slots, limits, load warning and history of the method.
# Load with: source "$HERE/lib/slots.sh"   (after lib/common.sh). Bash 3.2 compatible.
#
# State lives in ~/.cache/ai-method (AI_METHOD_CACHE overrides it):
#   slots/<class>/<n>/info   one directory per slot (mkdir is the lock); the info file
#                            has tab-separated: repo, issue, pid, start, worktree, wait
#   locks/                   one lock per worktree for validate.sh
#   history.tsv              wait and duration of every validation and phase.
#                            A phase duration is wall time minus the wait for the owner.
# Limits: ~/.config/ai-method/machine-limits.env (AI_METHOD_CONFIG overrides the folder).

SLOTS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLOT_DIR=""
SLOT_WAIT=0

slots_home() { printf '%s\n' "${AI_METHOD_CACHE:-$HOME/.cache/ai-method}"; }

# Loads the limits: creates the file from the .example on the first run, then reads
# NAME=value lines that the environment does not set, then fills the defaults.
slots_load_limits() {
  local dir="${AI_METHOD_CONFIG:-$HOME/.config/ai-method}" f line name val cpus
  f="$dir/machine-limits.env"
  if [ ! -f "$f" ] && [ -f "$SLOTS_LIB_DIR/machine-limits.env.example" ]; then
    mkdir -p "$dir" 2>/dev/null && cp "$SLOTS_LIB_DIR/machine-limits.env.example" "$f" 2>/dev/null || true
  fi
  if [ -f "$f" ]; then
    while IFS= read -r line; do
      case "$line" in AI_METHOD_[A-Z0-9_]*=*) ;; *) continue ;; esac
      name="${line%%=*}"; val="${line#*=}"
      eval "[ -n \"\${$name+x}\" ]" || export "$name=$val"
    done <"$f"
  fi
  : "${AI_METHOD_SLOTS_VALIDATE:=2}" "${AI_METHOD_SLOTS_FASE:=3}"
  : "${AI_METHOD_WAIT_TIMEOUT_SECONDS:=1200}" "${AI_METHOD_POLL_SECONDS:=2}"
  : "${AI_METHOD_WARN_LOAD1:=8}" "${AI_METHOD_WARN_FREE_MEM_MB:=1024}" "${AI_METHOD_WARN_SWAP_MB:=2048}"
  if [ -z "${AI_METHOD_TEST_JOBS:-}" ]; then
    cpus="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
    AI_METHOD_TEST_JOBS=$(( cpus / AI_METHOD_SLOTS_VALIDATE ))
    [ "$AI_METHOD_TEST_JOBS" -ge 1 ] || AI_METHOD_TEST_JOBS=1
  fi
  export AI_METHOD_TEST_JOBS
  : "${AI_METHOD_TEST_TIMEOUT_SECONDS:=600}"
  : "${AI_METHOD_LINT_BASE:=main}" "${AI_METHOD_IDLE_HOURS:=4}"
}

# Time limit of a test that waits or sets an alarm: AI_METHOD_TEST_TIMEOUT_SECONDS times
# the load factor, so a loaded machine never fails a test by time (issue #71). The factor
# is 1 up to AI_METHOD_WARN_LOAD1 and grows with the load above it (load1 / warn, rounded up).
slots_test_timeout() {
  local load free swap
  read -r load free swap <<<"$(slots_load_numbers)"
  awk -v base="$AI_METHOD_TEST_TIMEOUT_SECONDS" -v l="$load" -v w="$AI_METHOD_WARN_LOAD1" 'BEGIN {
    f = 1
    if (w + 0 > 0 && l + 0 > w + 0) { f = int(l / w); if (f < l / w) f++ }
    print base * f }'
}

# Number of slots of a class.
slots_limit() { # slots_limit <class>
  case "$1" in
    validate) echo "$AI_METHOD_SLOTS_VALIDATE" ;;
    fase) echo "$AI_METHOD_SLOTS_FASE" ;;
    *) echo "error: unknown slot class: $1" >&2; return 2 ;;
  esac
}

# Name of the repository: the folder of its main checkout.
slots_repo_name() {
  local common
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || { basename "$PWD"; return; }
  basename "$(dirname "$common")"
}

now_epoch() { date +%s; }

pid_alive() { [ -n "$1" ] && [ "$1" -gt 0 ] 2>/dev/null && kill -0 "$1" 2>/dev/null; }

# Appends a line to history.tsv: class, repo, issue, wait seconds, duration seconds.
history_add() { # history_add <class> <repo> <issue> <wait> <duration>
  local f
  f="$(slots_home)/history.tsv"
  mkdir -p "$(dirname "$f")" 2>/dev/null || return 0
  [ -f "$f" ] || printf 'ts\tclass\trepo\tissue\twait_s\tduration_s\n' >"$f" 2>/dev/null || return 0
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(now_epoch)" "$1" "$2" "$3" "$4" "$5" >>"$f" 2>/dev/null || true
}

# True when the slot directory holds nothing alive. validate: its process is dead or
# its worktree is gone. fase: its process is dead and its worktree is gone (the
# process of new-phase.sh ends long before the phase does).
slots_is_stale() { # slots_is_stale <slot dir> <class>
  local info="$1/info" repo issue pid start wt wait
  [ -f "$info" ] || return 1
  IFS="$(printf '\t')" read -r repo issue pid start wt wait <"$info" || true
  case "$2" in
    validate) ! pid_alive "$pid" || { [ -n "$wt" ] && [ ! -d "$wt" ]; } ;;
    *) ! pid_alive "$pid" && { [ -z "$wt" ] || [ ! -d "$wt" ]; } ;;
  esac
}

# Trace the phase status is written to. Tests set PROCESS_EVENTS_FILE; otherwise
# events_file (common.sh) is the main checkout.
slots_trace_file() {
  if [ -n "${PROCESS_EVENTS_FILE:-}" ]; then
    printf '%s\n' "$PROCESS_EVENTS_FILE"
    return 0
  fi
  command -v events_file >/dev/null 2>&1 || return 1
  events_file
}

# Seconds spent waiting for the owner: phase_status "esperando" until the next
# event of that issue. Same intervals as trace-view.py --timings. 0 when unread.
slots_owner_wait() { # slots_owner_wait <issue>
  local f out
  f="$(slots_trace_file 2>/dev/null || true)"
  [ -n "$f" ] && [ -f "$f" ] || { echo 0; return 0; }
  out="$(jq -Rrs --arg i "$1" '
    [ split("\n")[] | fromjson? | select((.issue | tostring) == $i and (.ts | type) == "string") ]
    | sort_by(.ts) | . as $e
    | reduce range(0; length - 1) as $k (0;
        if ($e[$k].event == "phase_status" and ($e[$k].state | tostring | startswith("esperando")))
        then . + (($e[$k + 1].ts | fromdateiso8601) - ($e[$k].ts | fromdateiso8601))
        else . end)
    | round
  ' "$f" 2>/dev/null)" || out=0
  case "${out:-0}" in ''|*[!0-9-]*) echo 0 ;; *) echo "$out" ;; esac
}

# Wall seconds since the slot was taken, minus the wait for the owner. Never negative.
slots_phase_duration() { # slots_phase_duration <start epoch> <issue>
  local dur own
  own="$(slots_owner_wait "$2")"
  dur=$(( $(now_epoch) - ${1:-$(now_epoch)} - own ))
  [ "$dur" -ge 0 ] || dur=0
  echo "$dur"
}

# Frees the phase slot of this worktree and records its duration now.
# Called when the phase ends (close-phase.sh --cleanup and --abort), so the
# history does not wait for the next phase to open.
slots_end_phase() { # slots_end_phase <worktree>
  local d repo issue pid start wt wait want have
  want="$(cd "$1" 2>/dev/null && pwd -P || printf '%s' "$1")"
  for d in "$(slots_home)/slots/fase"/*/; do
    d="${d%/}"
    [ -f "$d/info" ] || continue
    IFS="$(printf '\t')" read -r repo issue pid start wt wait <"$d/info" || true
    have="$(cd "$wt" 2>/dev/null && pwd -P || printf '%s' "$wt")"
    [ "$have" = "$want" ] || continue
    history_add fase "$repo" "$issue" "${wait:-0}" "$(slots_phase_duration "$start" "$issue")"
    rm -rf "$d"
  done
}

# Frees the slots of a class whose holder is gone. A phase slot records its duration.
slots_reap() { # slots_reap <class>
  local d repo issue pid start wt wait
  for d in "$(slots_home)/slots/$1"/*/; do
    d="${d%/}"
    [ -d "$d" ] || continue
    slots_is_stale "$d" "$1" || continue
    if [ "$1" = fase ]; then
      IFS="$(printf '\t')" read -r repo issue pid start wt wait <"$d/info" || true
      history_add fase "$repo" "$issue" "${wait:-0}" "$(slots_phase_duration "$start" "$issue")"
    fi
    rm -rf "$d"
  done
}

# Takes a free slot of the class, or fails. Sets SLOT_DIR.
slots_try() { # slots_try <class> <issue> <worktree> [wait seconds]
  local class="$1" n limit base
  limit="$(slots_limit "$class")" || return 2
  base="$(slots_home)/slots/$class"
  mkdir -p "$base" 2>/dev/null || return 1
  slots_reap "$class"
  n=1
  while [ "$n" -le "$limit" ]; do
    if mkdir "$base/$n" 2>/dev/null; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(slots_repo_name)" "$2" "$$" "$(now_epoch)" "$3" "${4:-0}" >"$base/$n/info"
      SLOT_DIR="$base/$n"
      return 0
    fi
    n=$((n + 1))
  done
  return 1
}

# Who holds the slots of a class, one line each.
slots_holders() { # slots_holders <class>
  local d repo issue pid start wt wait
  for d in "$(slots_home)/slots/$1"/*/; do
    d="${d%/}"
    [ -f "$d/info" ] || continue
    IFS="$(printf '\t')" read -r repo issue pid start wt wait <"$d/info" || true
    printf '  %s #%s (pid %s, running %ss)\n' "$repo" "${issue:--}" "$pid" "$(( $(now_epoch) - ${start:-0} ))"
  done
}

# Takes a slot, waiting in the queue up to the timeout. Sets SLOT_DIR and SLOT_WAIT.
slots_wait() { # slots_wait <class> <issue> <worktree>
  local start now last=0
  start="$(now_epoch)"
  while :; do
    now="$(now_epoch)"
    if slots_try "$1" "$2" "$3" "$((now - start))"; then
      # shellcheck disable=SC2034  # read by the scripts that source this file
      SLOT_WAIT=$((now - start))
      return 0
    fi
    if [ $((now - start)) -ge "$AI_METHOD_WAIT_TIMEOUT_SECONDS" ]; then
      echo "error: no $1 slot after $((now - start))s (timeout); held by:" >&2
      slots_holders "$1" >&2
      return 4
    fi
    if [ "$last" = 0 ] || [ $((now - last)) -ge 60 ]; then
      echo "waiting for a $1 slot (limit $(slots_limit "$1")); held by:"
      slots_holders "$1"
      last="$now"
    fi
    sleep "$AI_METHOD_POLL_SECONDS"
  done
}

slots_release() {
  [ -z "$SLOT_DIR" ] || rm -rf "$SLOT_DIR"
  SLOT_DIR=""
}

# Prints the load, free memory and swap of the machine, "load1 free_mem_mb swap_mb".
# AI_METHOD_FAKE_LOAD1, AI_METHOD_FAKE_FREE_MEM_MB and AI_METHOD_FAKE_SWAP_MB stand in (tests).
slots_load_numbers() {
  local load free swap ps
  if [ -n "${AI_METHOD_FAKE_LOAD1:-}" ]; then
    load="$AI_METHOD_FAKE_LOAD1"
  elif [ -r /proc/loadavg ]; then
    load="$(cut -d' ' -f1 /proc/loadavg)"
  else
    load="$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{print $1}')"
  fi
  if [ -n "${AI_METHOD_FAKE_FREE_MEM_MB:-}" ]; then
    free="$AI_METHOD_FAKE_FREE_MEM_MB"
  elif [ -r /proc/meminfo ]; then
    free="$(awk '/^MemAvailable:/ {printf "%d", $2/1024}' /proc/meminfo)"
  else
    ps="$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)"
    free="$(vm_stat 2>/dev/null | awk -v ps="$ps" '/Pages (free|inactive|speculative)/ {gsub(/\./,"",$NF); n+=$NF} END {printf "%d", n*ps/1048576}')"
  fi
  if [ -n "${AI_METHOD_FAKE_SWAP_MB:-}" ]; then
    swap="$AI_METHOD_FAKE_SWAP_MB"
  elif [ -r /proc/meminfo ]; then
    swap="$(awk '/^SwapTotal:/ {t=$2} /^SwapFree:/ {f=$2} END {printf "%d", (t-f)/1024}' /proc/meminfo)"
  else
    swap="$(sysctl -n vm.swapusage 2>/dev/null | sed -n 's/.*used = \([0-9.]*\)M.*/\1/p' | awk '{printf "%d", $1}')"
  fi
  echo "${load:-0} ${free:-0} ${swap:-0}"
}

# Load line plus one "warn:" line per threshold crossed. Never blocks.
slots_load_report() {
  local load free swap
  read -r load free swap <<<"$(slots_load_numbers)"
  echo "load1 $load (warn above $AI_METHOD_WARN_LOAD1), free memory ${free}MB (warn below $AI_METHOD_WARN_FREE_MEM_MB), swap in use ${swap}MB (warn above $AI_METHOD_WARN_SWAP_MB)"
  awk -v v="$load" -v t="$AI_METHOD_WARN_LOAD1" 'BEGIN { exit !(v + 0 > t + 0) }' && echo "warn: machine load is high ($load): expect slower runs"
  [ "$free" -ge "$AI_METHOD_WARN_FREE_MEM_MB" ] || echo "warn: free memory is low (${free}MB)"
  [ "$swap" -le "$AI_METHOD_WARN_SWAP_MB" ] || echo "warn: swap in use is high (${swap}MB)"
  return 0
}
