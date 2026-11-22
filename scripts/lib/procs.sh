#!/usr/bin/env bash
# Process helpers of the method: who runs where, who may be stopped. Load with:
#   source "$HERE/lib/procs.sh"
# Bash 3.2 compatible. Never stops a claude process of the Claude.app (an app
# session) nor this process and its ancestors; the app owns those (Archive in the
# app). PROCS_APP_MARK (default Claude.app) is what the command of the app has.

# Seconds of a ps etime ([[dd-]hh:]mm:ss).
etime_seconds() { # etime_seconds <etime>
  printf '%s\n' "$1" | awk '{
    d = 0; t = $0
    if (index(t, "-")) { split(t, a, "-"); d = a[1]; t = a[2] }
    n = split(t, p, ":")
    s = 0; for (i = 1; i <= n; i++) s = s * 60 + p[i]
    print d * 86400 + s }'
}

proc_ppid() { ps -o ppid= -p "$1" 2>/dev/null | tr -d ' '; }
proc_cmd() { ps -o command= -p "$1" 2>/dev/null; }
proc_alive() { kill -0 "$1" 2>/dev/null; }

# Prints the pid and its ancestors, one per line.
proc_chain() { # proc_chain <pid>
  local p="$1" n=0
  while [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null && [ "$n" -lt 64 ]; do
    echo "$p"
    p="$(proc_ppid "$p")"
    n=$((n + 1))
  done
}

# True when the pid or an ancestor runs from the Claude.app.
proc_in_app() { # proc_in_app <pid>
  local p
  for p in $(proc_chain "$1"); do
    case "$(proc_cmd "$p")" in *"${PROCS_APP_MARK:-Claude.app}"*) return 0 ;; esac
  done
  return 1
}

# True when the command of the pid is a claude CLI.
proc_is_claude() { # proc_is_claude <pid>
  proc_cmd "$1" | grep -Eq '(^|[ /])claude( |$)'
}

# Prints the descendants of the pid (not the pid), one per line.
proc_descendants() { # proc_descendants <pid>
  ps -axo pid=,ppid= | awk -v root="$1" '
    { kid[$2] = kid[$2] " " $1 }
    END { q[1] = root; h = 1; t = 1
      while (h <= t) { n = split(kid[q[h]], a, " "); for (i = 1; i <= n; i++) { print a[i]; q[++t] = a[i] } h++ } }'
}

# Pids whose current directory is <dir> or inside it.
procs_in_dir() { # procs_in_dir <absolute dir>
  lsof -a -d cwd -Fpn 2>/dev/null | awk -v d="${1%/}" '
    /^p/ { pid = substr($0, 2) }
    /^n/ { p = substr($0, 2); if (p == d || index(p, d "/") == 1) print pid }' | sort -un
}

# TERM, up to 3 seconds of grace, then KILL.
proc_stop() { # proc_stop <pid>...
  local p n=0 left
  for p in "$@"; do kill -TERM "$p" 2>/dev/null || true; done
  while [ "$n" -lt 6 ]; do
    left=0
    for p in "$@"; do if proc_alive "$p"; then left=1; fi; done
    [ "$left" = 1 ] || return 0
    sleep 0.5
    n=$((n + 1))
  done
  for p in "$@"; do if proc_alive "$p"; then kill -KILL "$p" 2>/dev/null || true; fi; done
}

# Stoppable = not this process or an ancestor, not a claude of the Claude.app.
proc_stoppable() { # proc_stoppable <pid> <protected pids...>
  local p="$1" q
  shift
  for q in "$@"; do [ "$p" != "$q" ] || return 1; done
  proc_alive "$p" || return 1
  if proc_is_claude "$p" && proc_in_app "$p"; then return 1; fi
  return 0
}

# Every claude of the Claude.app and its ancestors (the app wrappers), one line of pids.
app_claude_chains() {
  local p
  for p in $(ps -axo pid=,command= | awk '$0 ~ /(^|[ \/])claude( |$)/ { print $1 }'); do
    proc_in_app "$p" && proc_chain "$p" | tr '\n' ' '
  done
  return 0
}

# Orphan = parent 1 (the creator is gone). Temporary folder of a test or of validate.sh:
# a path with a component tmp.*, validate-tests.* or validate.* under a temp root
# (/tmp, /var/folders and TMPDIR; AI_METHOD_ORPHAN_ROOT replaces the roots, for tests).
proc_tmp_roots() {
  if [ -n "${AI_METHOD_ORPHAN_ROOT:-}" ]; then echo "${AI_METHOD_ORPHAN_ROOT%/}"; return; fi
  printf '%s\n' /tmp /private/tmp /var/folders /private/var/folders
  [ -z "${TMPDIR:-}" ] || echo "${TMPDIR%/}"
}

# True when <dir> is a temporary folder of the method's tests, or a folder that is gone
# from a worktree (.worktrees/<x>).
orphan_cwd_match() { # orphan_cwd_match <cwd>
  local d="$1" r
  [ -n "$d" ] || return 1
  case "$d" in */.worktrees/*) [ -d "$d" ] || return 0 ;; esac
  case "$d" in */tmp.*|*/validate-tests.*|*/validate.*) ;; *) return 1 ;; esac
  for r in $(proc_tmp_roots); do
    case "$d" in "$r"/*) return 0 ;; esac
  done
  return 1
}

# Pids whose parent is 1 and whose cwd or command line is inside one of the dirs; with no
# dir, the ones whose cwd is a temporary folder (orphan_cwd_match) and that are at least
# AI_METHOD_ORPHAN_MIN_AGE seconds old (default 60: a process another run is still
# starting is not an orphan yet). Never this process.
# shellcheck disable=SC2120  # callers pass dirs, or none for the temporary-folder sweep
procs_orphans() { # procs_orphans [dir...]
  local rows cwds pid et cwd min="${AI_METHOD_ORPHAN_MIN_AGE:-60}" dirs=""
  local d
  for d in "$@"; do dirs="$dirs${dirs:+$'\n'}${d%/}"; done
  rows="$(ps -axo pid=,ppid=,etime=,command= | awk '$2 == 1 && $1 != 1 { print }')"
  [ -n "$rows" ] || return 0
  cwds="$(lsof -a -d cwd -Fpn -p "$(printf '%s\n' "$rows" | awk '{ printf "%s%s", (n++ ? "," : ""), $1 }')" 2>/dev/null | awk '/^p/ { pid = substr($0, 2) } /^n/ { print pid "\t" substr($0, 2) }')"
  # One pass joins the rows with their cwds; the shell only sees the candidates.
  if [ $# -gt 0 ]; then
    awk -v self="$$" -v dirs="$dirs" 'BEGIN { n = split(dirs, D, "\n") }
      NR == FNR { split($0, a, "\t"); if (!(a[1] in cwd)) cwd[a[1]] = a[2]; next }
      { pid = $1; if (pid == self) next
        line = $0; sub(/^[ ]*[0-9]+[ ]+[0-9]+[ ]+[^ ]+[ ]*/, "", line); ok = 0
        for (i = 1; i <= n; i++) { d = D[i]
          if (cwd[pid] == d || index(cwd[pid], d "/") == 1) ok = 1
          if (index(line, d "/") || (length(line) >= length(d) && substr(line, length(line) - length(d) + 1) == d)) ok = 1 }
        if (ok) print pid }' <(printf '%s\n' "$cwds") <(printf '%s\n' "$rows")
    return 0
  fi
  # No dir: only the rows whose cwd looks temporary reach the shell (orphan_cwd_match).
  awk -v self="$$" 'NR == FNR { split($0, a, "\t"); if (!(a[1] in cwd)) cwd[a[1]] = a[2]; next }
    $1 != self && ($1 in cwd) && cwd[$1] ~ /(\/tmp\.|\/validate-tests\.|\/validate\.|\/\.worktrees\/)/ { print $1 "\t" $3 "\t" cwd[$1] }' \
    <(printf '%s\n' "$cwds") <(printf '%s\n' "$rows") | while IFS=$'\t' read -r pid et cwd; do
    orphan_cwd_match "$cwd" || continue
    awk -v s="$(etime_seconds "$et")" -v m="$min" 'BEGIN { exit !(s >= m) }' && echo "$pid"
  done
  return 0
}

# Stops the orphans left by another run (temporary folders, worktrees that are gone) with
# their children. Prints one line per stopped process.
procs_stop_orphans() {
  local prot p all="" stop=""
  prot="$(proc_chain "$$" | tr '\n' ' ')$(app_claude_chains)"
  for p in $(procs_orphans); do
    # shellcheck disable=SC2086
    proc_stoppable "$p" $prot || continue
    all="$all $p $(proc_descendants "$p" | tr '\n' ' ')"
  done
  for p in $(printf '%s\n' "$all" | tr ' ' '\n' | grep . | sort -un); do
    # shellcheck disable=SC2086
    proc_stoppable "$p" $prot || continue
    stop="$stop $p"
    echo "stopped orphan process $p: $(proc_cmd "$p" | cut -c1-100)"
  done
  # shellcheck disable=SC2086
  [ -z "$stop" ] || proc_stop $stop
}

# Stops the processes of a phase worktree and the headless child of the trace.
# Prints one line per stopped process.
procs_cleanup_worktree() { # procs_cleanup_worktree <worktree> <issue> [trace file]
  local wt="$1" issue="$2" trace="${3:-}" prot cand="" p hp hs all="" stop="" line
  prot="$(proc_chain "$$" | tr '\n' ' ')$(app_claude_chains)"
  # shellcheck disable=SC2086
  cand="$(procs_in_dir "$wt")"
  if [ -n "$trace" ] && [ -f "$trace" ]; then
    line="$(jq -rs --arg i "$issue" '[.[] | select(type == "object" and .event == "phase_headless" and (.issue | tostring) == $i)] | last // empty | "\(.pid)\t\(.child_session)"' "$trace" 2>/dev/null || true)"
    hp="${line%%$'\t'*}" hs="${line#*$'\t'}"
    # The session id in the command line guards against a reused pid.
    if [ -n "$hp" ] && [ -n "$hs" ] && proc_alive "$hp" && proc_cmd "$hp" | grep -q -- "$hs"; then
      cand="$cand"$'\n'"$hp"
    fi
  fi
  for p in $cand; do
    # A protected process keeps its children too.
    # shellcheck disable=SC2086
    proc_stoppable "$p" $prot || continue
    all="$all $p $(proc_descendants "$p" | tr '\n' ' ')"
  done
  for p in $(printf '%s\n' "$all" | tr ' ' '\n' | grep . | sort -un); do
    # shellcheck disable=SC2086
    proc_stoppable "$p" $prot || continue
    stop="$stop $p"
    echo "stopped process $p: $(proc_cmd "$p" | cut -c1-100)"
  done
  # shellcheck disable=SC2086
  [ -z "$stop" ] || proc_stop $stop
  [ -n "$stop" ] || echo "no process left in the worktree"
  procs_stop_orphans
}
