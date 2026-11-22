#!/usr/bin/env bash
# Tests of the process cleanup of the end of a phase (lib/procs.sh) and of
# sessions.sh, with fake processes: scripts named claude and server that only sleep,
# and a parent whose path says Claude.app. Every process is spawned by the test, in
# a temporary directory, and stopped by it at the end.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPTS/lib/common.sh"
# shellcheck source=scripts/lib/procs.sh
source "$SCRIPTS/lib/procs.sh"

assert_eq 90 "$(etime_seconds 01:30)" "etime mm:ss"
assert_eq 3723 "$(etime_seconds 01:02:03)" "etime hh:mm:ss"
assert_eq 90061 "$(etime_seconds 1-01:01:01)" "etime dd-hh:mm:ss"

mkdir -p "$TMP/fake" "$TMP/wt/sub" "$TMP/Claude.app/Contents" "$TMP/other"
# The child of the fake claude lives in / (a candidate only by its parent).
printf '#!/usr/bin/env bash\n(cd /; exec sleep 300)\n' >"$TMP/fake/claude"
printf '#!/usr/bin/env bash\ncd "$1"; exec sleep 300\n' >"$TMP/fake/server"
printf '#!/usr/bin/env bash\ncd "$1"; "$2" -p task --session-id sid-app >/dev/null 2>&1\n' >"$TMP/Claude.app/Contents/app.sh"
chmod +x "$TMP/fake/"* "$TMP/Claude.app/Contents/app.sh"
PIDS=""
trap 'kill $PIDS 2>/dev/null || true; test_sweep; rm -rf "$TMP"' EXIT
spawn() { "$@" >/dev/null 2>&1 & PIDS="$PIDS $!"; }
export PROCS_APP_MARK="$TMP/Claude.app"
# A zombie of this shell counts as dead.
alive() { case "$(ps -o stat= -p "$1" 2>/dev/null)" in ""|Z*) echo dead ;; *) echo alive ;; esac; }

# Own process group, same session, so cleanup still stops it (issue #120).
python3 -c 'import os,sys; os.setpgid(0,0); os.execvp(sys.argv[1], sys.argv[1:])' \
  "$TMP/fake/server" "$TMP/wt/sub" >/dev/null 2>&1 &
srv=$!; PIDS="$PIDS $srv"
spawn "$TMP/fake/server" "$TMP/other"; elsewhere=$!    # a process of another directory
spawn "$TMP/Claude.app/Contents/app.sh" "$TMP/wt" "$TMP/fake/claude"; appchild=$! # claude of the app, cwd in the worktree
(cd "$TMP/other" || exit; exec "$TMP/fake/claude" -p task --session-id sid-123 >/dev/null 2>&1) &
head=$!; PIDS="$PIDS $head"
sleep 1
# The claude of the app is the child of the script that has Claude.app in its path.
appclaude="$(ps -axo pid=,ppid= | awk -v p="$appchild" '$2 == p { print $1; exit }')"

# Worktree sweep: stops the server, keeps the other directory and the app session.
out="$(procs_cleanup_worktree "$TMP/wt" 11 "")"
assert_eq dead "$(alive "$srv")" "the process inside the worktree is stopped"
assert_eq alive "$(alive "$elsewhere")" "a process of another directory stays"
assert_eq alive "$(alive "$appclaude")" "a claude of the Claude.app stays"
assert_contains "$out" "stopped process $srv" "says what it stopped"

# Headless child of the trace: a wrong session id is not stopped; the right one is.
echo "{\"event\":\"phase_headless\",\"issue\":\"11\",\"pid\":\"$head\",\"child_session\":\"sid-999\"}" >"$TMP/trace.jsonl"
procs_cleanup_worktree "$TMP/wt" 11 "$TMP/trace.jsonl" >/dev/null
assert_eq alive "$(alive "$head")" "a pid whose command lacks the session id is not stopped"
echo "{\"event\":\"phase_headless\",\"issue\":\"11\",\"pid\":\"$head\",\"child_session\":\"sid-123\"}" >"$TMP/trace.jsonl"
procs_cleanup_worktree "$TMP/wt" 11 "$TMP/trace.jsonl" >/dev/null
sleep 1
assert_eq dead "$(alive "$head")" "the headless child of the trace is stopped"
assert_eq alive "$(alive "$appclaude")" "the app session still stays"

# sessions.sh: --list, --close-idle (headless only), --stale.
# --close-idle runs inside a temporary repository: --under only narrows there.
export AI_METHOD_IDLE_HOURS=4
S="$SCRIPTS/sessions.sh"
repo_s="$(make_repo)"
mkdir -p "$repo_s/other"
(cd "$repo_s/other" || exit; exec "$TMP/fake/claude" -p idle >/dev/null 2>&1) &
hl=$!; PIDS="$PIDS $hl"
sleep 1
assert_status 0 "sessions.sh --list" "$S" --list
assert_contains "$(last_output)" "headless" "--list shows the headless session"
assert_contains "$(last_output)" " app " "--list shows the app session"
assert_status 0 "--close-idle with the default hours" \
  bash -c 'cd "$1" && exec "$2" --close-idle --under "$1"' _ "$repo_s" "$S"
assert_eq alive "$(alive "$hl")" "a young headless session stays"
assert_status 0 "--close-idle --dry-run" \
  bash -c 'cd "$1" && exec "$2" --close-idle --older-than 0 --under "$1" --dry-run' _ "$repo_s" "$S"
assert_eq alive "$(alive "$hl")" "dry-run stops nothing"
assert_status 0 "--close-idle --older-than 0 stops it" \
  bash -c 'cd "$1" && exec "$2" --close-idle --older-than 0 --under "$1"' _ "$repo_s" "$S"
sleep 1
assert_eq dead "$(alive "$hl")" "an idle headless session is stopped"
assert_eq alive "$(alive "$appclaude")" "--close-idle never stops a child of the Claude.app"

repo="$(make_repo)"
d="$TMP/sessions/acct/org"; mkdir -p "$d"
now=$(($(date +%s) * 1000))
mk() { printf '{"title":"%s","sessionId":"%s","cwd":"%s","isArchived":%s,"lastActivityAt":%s}\n' "$1" "$2" "$3" "$4" "$5" >"$d/$2.json"; }
mk "Old phase" local_old "$repo/.worktrees/issue-1" false $((now - 10 * 3600000))
mk "Archived" local_arch "$repo" true $((now - 10 * 3600000))
mk "Fresh" local_new "$repo" false "$now"
mk "Other repo" local_oth "$TMP/other" false $((now - 10 * 3600000))
out="$(cd "$repo" && AI_METHOD_SESSIONS_DIR="$TMP/sessions" "$S" --stale)"
assert_contains "$out" "Old phase" "--stale lists a parked, not archived session of the repo"
assert_not_contains "$out" "Archived" "--stale skips an archived session"
assert_not_contains "$out" "Fresh" "--stale skips a recent session"
assert_not_contains "$out" "Other repo" "--stale skips another repository"
assert_status 2 "unknown option" "$S" --bogus

#  close-idle (issue #91): the default, with no --under, is this checkout. A directory
# outside it is refused before any signal. ps, lsof and kill are fakes; BASH_ENV
# turns off the kill builtin so the script uses the fake on PATH.
# case-91-start
repo91="$(make_repo)"
mkdir -p "$repo91/sub" "${repo91}2"
ln -s / "$repo91/link-out"
bin91="$TMP/bin91"
mkdir -p "$bin91"
: >"$TMP/dead91"
: >"$TMP/kill91"
printf 'enable -n kill\n' >"$bin91/disable-kill"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "8101" "1" "10-00:00:00" "0.0" "1024" "/opt/fake/claude -p outside" \
  "8102" "1" "10-00:00:00" "0.0" "1024" "/opt/fake/claude -p inside" >"$TMP/ps91.tab"
printf '%s\t%s\n' "8101" "${repo91}2" "8102" "$repo91/sub" >"$TMP/lsof91.tab"
export FAKE_PS_TAB="$TMP/ps91.tab" FAKE_PS_DEAD="$TMP/dead91"
export FAKE_LSOF_TAB="$TMP/lsof91.tab" FAKE_KILL_LOG="$TMP/kill91"
cat >"$bin91/ps" <<'PS'
#!/bin/sh
tab="${FAKE_PS_TAB:?}"
dead="${FAKE_PS_DEAD:?}"
spec="" pid=""
while [ $# -gt 0 ]; do
  case "$1" in
    -p) pid="$2"; shift 2 ;;
    -o|-axo) spec="$2"; shift 2 ;;
    *) shift ;;
  esac
done
emit() {
  fpid=$(printf '%s' "$1" | awk -F '\t' '{ print $1 }')
  fppid=$(printf '%s' "$1" | awk -F '\t' '{ print $2 }')
  fet=$(printf '%s' "$1" | awk -F '\t' '{ print $3 }')
  fcpu=$(printf '%s' "$1" | awk -F '\t' '{ print $4 }')
  frss=$(printf '%s' "$1" | awk -F '\t' '{ print $5 }')
  fcmd=$(printf '%s' "$1" | awk -F '\t' '{ print $6 }')
  case "$spec" in
    ppid=) printf '%s\n' "$fppid" ;;
    command=) printf '%s\n' "$fcmd" ;;
    stat=) printf 'S\n' ;;
    rss=) printf '%s\n' "$frss" ;;
    "pid=,command=") printf '%s %s\n' "$fpid" "$fcmd" ;;
    "pid=,ppid=") printf '%s %s\n' "$fpid" "$fppid" ;;
    "pid=,etime=,pcpu=,rss=,command=") printf '%s %s %s %s %s\n' "$fpid" "$fet" "$fcpu" "$frss" "$fcmd" ;;
    *) printf '%s\n' "$fpid $fppid $fet $fcpu $frss $fcmd" ;;
  esac
}
if [ -n "$pid" ]; then
  if [ -f "$dead" ] && grep -qx "$pid" "$dead"; then exit 0; fi
  row=$(awk -F '\t' -v p="$pid" '$1 == p { print; exit }' "$tab")
  [ -n "$row" ] || exit 0
  emit "$row"
  exit 0
fi
while IFS= read -r row; do
  [ -n "$row" ] || continue
  fpid=$(printf '%s' "$row" | awk -F '\t' '{ print $1 }')
  if [ -f "$dead" ] && grep -qx "$fpid" "$dead"; then continue; fi
  emit "$row"
done <"$tab"
exit 0
PS
cat >"$bin91/lsof" <<'LSOF'
#!/bin/sh
tab="${FAKE_LSOF_TAB:?}"
dead="${FAKE_PS_DEAD:-}"
pids=""
while [ $# -gt 0 ]; do
  case "$1" in
    -p) pids="$2"; shift 2 ;;
    *) shift ;;
  esac
done
awk -F '\t' -v pids="$pids" -v deadfile="$dead" '
  FILENAME == deadfile { if ($0 != "") dead[$0] = 1; next }
  {
    if ($1 in dead) next
    if (pids != "") {
      hit = 0
      n = split(pids, a, ",")
      for (i = 1; i <= n; i++) if (a[i] == $1) hit = 1
      if (!hit) next
    }
    printf "p%s\nn%s\n", $1, $2
  }
' "$dead" "$tab"
exit 0
LSOF
cat >"$bin91/kill" <<'KILL'
#!/bin/sh
log="${FAKE_KILL_LOG:?}"
dead="${FAKE_PS_DEAD:?}"
sig=""
for arg in "$@"; do
  case "$arg" in
    -*) sig="${arg#-}" ;;
    *)
      if [ "$sig" = "0" ]; then
        if [ -f "$dead" ] && grep -qx "$arg" "$dead"; then exit 1; fi
        exit 0
      fi
      printf '%s\n' "$arg" >>"$dead"
      printf '%s %s\n' "${sig:-TERM}" "$arg" >>"$log"
      ;;
  esac
done
exit 0
KILL
chmod +x "$bin91/ps" "$bin91/lsof" "$bin91/kill"
run91() { # run91 <expected> <description> <sessions args...>
  : >"$TMP/dead91"
  : >"$TMP/kill91"
  local want="$1" what="$2"
  shift 2
  assert_status "$want" "$what" env PATH="$bin91:$PATH" BASH_ENV="$bin91/disable-kill" \
    bash -c 'cd "$1" && shift && exec "$@"' _ "$repo91" "$SCRIPTS/sessions.sh" "$@"
}
state91() {
  case "$(PATH="$bin91:$PATH" ps -o stat= -p "$1" 2>/dev/null)" in
    ""|Z*) echo dead ;; *) echo alive ;;
  esac
}
run91 2 "--close-idle --under / is outside the repository" --close-idle --under /
assert_eq "" "$(cat "$TMP/kill91")" "--under / signals nobody"
run91 2 "--close-idle --under .. is outside the repository" --close-idle --under "$repo91/.."
assert_eq "" "$(cat "$TMP/kill91")" "--under .. signals nobody"
run91 2 "--close-idle --under a symlink to / is outside" --close-idle --under "$repo91/link-out"
assert_eq "" "$(cat "$TMP/kill91")" "a symlink under --under signals nobody"
run91 2 "--close-idle --under a sibling prefix is outside" --close-idle --under "${repo91}2"
assert_eq "" "$(cat "$TMP/kill91")" "a sibling directory with the same prefix signals nobody"
run91 0 "--close-idle with no --under" --close-idle
assert_eq alive "$(state91 8101)" "a headless session outside this repository stays"
assert_eq dead "$(state91 8102)" "an idle headless session of this repository is stopped"
# case-91-end
finish
