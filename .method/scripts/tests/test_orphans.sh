#!/usr/bin/env bash
# Tests that no process of the method outlives whoever created it (issue #66): the
# sweep of tests/lib.sh, the orphan check at the end of validate.sh, the orphan mark of
# sessions.sh and the cleanup of a phase (issue #88), which must not stop an orphan
# outside that phase. Every process here is spawned on purpose and stopped by this test
# at the end, whatever fails. The cleanup case uses fake ps, lsof and kill only.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=scripts/lib/procs.sh
source "$SCRIPTS/lib/procs.sh"

export AI_METHOD_ORPHAN_ROOT="$TMP"
PIDF="$TMP/pids"
: >"$PIDF"
trap 'xargs kill -KILL <"$PIDF" 2>/dev/null || true; test_sweep; rm -rf "$TMP"' EXIT
alive() { case "$(ps -o stat= -p "$1" 2>/dev/null)" in ""|Z*) echo dead ;; *) echo alive ;; esac; }
# A detached process (parent 1) with its cwd in <dir>; its pid goes to $PIDF.
orphan() { # orphan <dir> [command...]
  local d="$1"; shift
  [ $# -gt 0 ] || set -- sleep 300
  bash -c 'cd "$1"; shift; nohup "$@" </dev/null >/dev/null 2>&1 & echo $! >>"$0"' "$PIDF" "$d" "$@"
  tail -1 "$PIDF"
}

# 1. tests/lib.sh: a test that leaves a process behind, even with an assertion failing,
# does not leave it alive: the trap of lib.sh stops the process of its folder.
cat >"$TMP/leaver.sh" <<L
source "$TESTS_DIR/lib.sh"
mkdir -p "\$TMP/wt"
(cd "\$TMP/wt" && exec sleep 300) >/dev/null 2>&1 &
echo \$! >"$TMP/leaver.pid"
sleep 5 & echo \$! >"$TMP/leaver-child.pid"
bad "an assertion that fails on purpose"
finish
L
bash "$TMP/leaver.sh" >/dev/null 2>&1 || true
sleep 1
assert_eq dead "$(alive "$(cat "$TMP/leaver.pid")")" "lib.sh stops the process the test left in its folder"
assert_eq dead "$(alive "$(cat "$TMP/leaver-child.pid")")" "lib.sh stops the background child of the test"
# Same when the test is stopped by a signal.
cat >"$TMP/killed.sh" <<L
source "$TESTS_DIR/lib.sh"
(cd "\$TMP" && exec sleep 300) >/dev/null 2>&1 &
echo \$! >"$TMP/killed.pid"
sleep 100 & wait
L
bash "$TMP/killed.sh" >/dev/null 2>&1 &
kp=$!
sleep 1
kill -TERM "$kp"; wait "$kp" 2>/dev/null || true
sleep 1
assert_eq dead "$(alive "$(cat "$TMP/killed.pid")")" "lib.sh stops the process when the test gets TERM"

# 2. procs_orphans: parent 1 and the directory (or command line) inside the given folder.
mkdir -p "$TMP/d1" "$TMP/d2"
o1="$(orphan "$TMP/d1")"
sleep 300 & mine=$!; echo "$mine" >>"$PIDF"          # child of this test: not an orphan
o2="$(orphan "$TMP/d2")"                               # another folder
sleep 1
found="$(procs_orphans "$TMP/d1" | tr '\n' ' ')"
assert_contains "$found" "$o1" "procs_orphans finds the detached process of the folder"
assert_not_contains "$found" "$mine" "a process with a live parent is not an orphan"
assert_not_contains "$found" "$o2" "a process of another folder is not listed"

# 3. validate.sh: a test that leaves an orphan fails the suite, which stops and lists it.
vrepo="$(make_repo)"
mkdir -p "$vrepo/scripts/tests" "$vrepo/scripts/lib"
cp "$SCRIPTS/validate.sh" "$vrepo/scripts/validate.sh"
cp "$SCRIPTS"/lib/*.sh "$SCRIPTS"/lib/*.tsv "$SCRIPTS"/lib/*.example "$vrepo/scripts/lib/" 2>/dev/null || true
cat >"$vrepo/scripts/tests/test_leaves.sh" <<L
#!/usr/bin/env bash
d="\$(mktemp -d "\${TMPDIR:-/tmp}/tmp.XXXXXX")"
cd "\$d"
nohup sleep 300 </dev/null >/dev/null 2>&1 &
echo \$! >"$TMP/leaves.pid"
L
git -C "$vrepo" add scripts
git -C "$vrepo" commit --quiet -m "chore: scripts"
assert_status 1 "validate.sh fails when a test leaves an orphan" \
  sh -c "cd '$vrepo' && env -u PROCESS_VALIDATE_RUNNING scripts/validate.sh --tests"
assert_contains "$(last_output)" "orphan process" "validate.sh lists the orphan"
assert_contains "$(last_output)" "$(cat "$TMP/leaves.pid")" "validate.sh names the pid"
sleep 1
assert_eq dead "$(alive "$(cat "$TMP/leaves.pid")")" "validate.sh stops the orphan"
# A test that loads lib.sh (issue #83): what it leaves detached in its folder is stopped by
# its own sweep (the search by cwd looks at the detached processes), so the suite is green
# and nothing stays alive.
rm "$vrepo/scripts/tests/test_leaves.sh"
cp "$TESTS_DIR/lib.sh" "$vrepo/scripts/tests/lib.sh"
cat >"$vrepo/scripts/tests/test_leaves_lib.sh" <<L
#!/usr/bin/env bash
source "\$(dirname "\$0")/lib.sh"
mkdir -p "\$TMP/wt"
# Detached (parent 1) with its cwd in the folder: only the search by cwd finds it.
bash -c 'cd "\$1"; nohup sleep 300 </dev/null >/dev/null 2>&1 & echo \$! >"\$2"' _ "\$TMP/wt" "$TMP/leaves-lib.pid"
finish
L
assert_status 0 "validate.sh is green when a lib.sh test leaves a detached process in its folder" \
  sh -c "cd '$vrepo' && env -u PROCESS_VALIDATE_RUNNING scripts/validate.sh --tests"
sleep 1
assert_eq dead "$(alive "$(cat "$TMP/leaves-lib.pid")")" "the sweep of lib.sh stops the process left in the folder of its test"
rm "$vrepo/scripts/tests/test_leaves_lib.sh" "$vrepo/scripts/tests/lib.sh"
# A clean suite stays green.
printf '#!/usr/bin/env bash\nexit 0\n' >"$vrepo/scripts/tests/test_clean.sh"
assert_status 0 "validate.sh is green without orphans" \
  sh -c "cd '$vrepo' && env -u PROCESS_VALIDATE_RUNNING scripts/validate.sh --tests"
assert_not_contains "$(last_output)" "orphan process" "no orphan line on a clean run"

# 4. sessions.sh --list marks an orphan claude; a claude with a live parent has no mark.
# Fake ps and lsof: the case does not read the machine's real sessions (issue #109).
mkdir -p "$TMP/bin109" "$TMP/tmp.list"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "9101" "1" "00:10" "0.0" "1024" "/opt/fake/claude -p orphan" \
  "9102" "999" "00:10" "0.0" "1024" "/opt/fake/claude -p live" >"$TMP/ps109.tab"
printf '%s\t%s\n' "9101" "$TMP/tmp.list" "9102" "$TMP/d2" >"$TMP/lsof109.tab"
export FAKE_PS_TAB="$TMP/ps109.tab" FAKE_LSOF_TAB="$TMP/lsof109.tab" FAKE_PS_DEAD="$TMP/dead109"
: >"$TMP/dead109"
cat >"$TMP/bin109/ps" <<'PS'
#!/bin/sh
tab="${FAKE_PS_TAB:?}"
spec="" pid="" prev=""
for arg in "$@"; do
  if [ "$prev" = "-p" ]; then pid="$arg"; fi
  if [ "$prev" = "-o" ] || [ "$prev" = "-axo" ]; then spec="$arg"; fi
  prev="$arg"
done
row_of() { awk -F '\t' -v p="$1" '$1 == p { print; exit }' "$tab"; }
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
    rss=) printf '%s\n' "$frss" ;;
    "pid=,ppid=") printf '%s %s\n' "$fpid" "$fppid" ;;
    "pid=,etime=,pcpu=,rss=,command=") printf '%s %s %s %s %s\n' "$fpid" "$fet" "$fcpu" "$frss" "$fcmd" ;;
    *) printf '%s %s\n' "$fpid" "$fcmd" ;;
  esac
}
if [ -n "$pid" ]; then
  row=$(row_of "$pid")
  [ -n "$row" ] || exit 0
  emit "$row"
  exit 0
fi
while IFS= read -r row; do
  [ -n "$row" ] || continue
  emit "$row"
done <"$tab"
exit 0
PS
cat >"$TMP/bin109/lsof" <<'LSOF'
#!/bin/sh
tab="${FAKE_LSOF_TAB:?}"
[ "${FAKE_LSOF_EXIT:-0}" = 0 ] || exit 1
awk -F '\t' '{ printf "p%s\nn%s\n", $1, $2 }' "$tab"
exit 0
LSOF
chmod +x "$TMP/bin109/ps" "$TMP/bin109/lsof"
assert_status 0 "sessions.sh --list" env PATH="$TMP/bin109:$PATH" "$SCRIPTS/sessions.sh" --list
list="$(last_output)"
assert_contains "$(printf '%s\n' "$list" | grep -E '[ ]9101 ' || true)" "orphan" "--list marks the orphan claude"
assert_not_contains "$(printf '%s\n' "$list" | grep -E '[ ]9102 ' || true)" "orphan" "a claude with a live parent is not marked"
# A process that disappears between ps and lsof (lsof exits 1) is skipped (issue #109).
repo109="$(make_repo)"
assert_status 0 "sessions.sh --list survives lsof exit 1" \
  env PATH="$TMP/bin109:$PATH" FAKE_LSOF_EXIT=1 "$SCRIPTS/sessions.sh" --list
assert_status 0 "sessions.sh --close-idle survives lsof exit 1" \
  env PATH="$TMP/bin109:$PATH" FAKE_LSOF_EXIT=1 \
  bash -c 'cd "$1" && exec "$2" --close-idle --older-than 0' _ "$repo109" "$SCRIPTS/sessions.sh"

# 5. cleanup (issue #88): two orphans that are not of this phase stay alive. ps, lsof
# and kill are fakes, so the case never signals a real process. One cwd is a tmp.*
# folder; the other is a worktree directory that is already gone.
# case-88-start
bin88="$TMP/bin88"
mkdir -p "$bin88" "$TMP/tmp.alien"
: >"$TMP/dead88"
: >"$TMP/kill88"
printf '%s\n' "7101 1 05:00 sleep 300" "7102 1 05:00 sleep 300" >"$TMP/ps88.tab"
printf '%s\t%s\n' "7101" "$TMP/tmp.alien" "7102" "$TMP/gone/.worktrees/issue-9" >"$TMP/lsof88.tab"
export FAKE_PS_TAB="$TMP/ps88.tab" FAKE_PS_DEAD="$TMP/dead88"
export FAKE_LSOF_TAB="$TMP/lsof88.tab" FAKE_KILL_LOG="$TMP/kill88"
cat >"$bin88/ps" <<'PS'
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
  row="$1"
  fpid=$(printf '%s\n' "$row" | awk '{ print $1 }')
  fppid=$(printf '%s\n' "$row" | awk '{ print $2 }')
  fet=$(printf '%s\n' "$row" | awk '{ print $3 }')
  fcmd=$(printf '%s\n' "$row" | awk '{ $1=$2=$3=""; sub(/^ +/, ""); print }')
  case "$spec" in
    ppid=) printf '%s\n' "$fppid" ;;
    command=) printf '%s\n' "$fcmd" ;;
    stat=) printf 'S\n' ;;
    "pid=,command=") printf '%s %s\n' "$fpid" "$fcmd" ;;
    "pid=,ppid=") printf '%s %s\n' "$fpid" "$fppid" ;;
    "pid=,ppid=,etime=,command=") printf '%s %s %s %s\n' "$fpid" "$fppid" "$fet" "$fcmd" ;;
    *) printf '%s\n' "$row" ;;
  esac
}
if [ -n "$pid" ]; then
  if [ -f "$dead" ] && grep -qx "$pid" "$dead"; then exit 0; fi
  row=$(awk -v p="$pid" '$1 == p { print; exit }' "$tab")
  [ -n "$row" ] || exit 0
  emit "$row"
  exit 0
fi
while IFS= read -r row; do
  [ -n "$row" ] || continue
  fpid=$(printf '%s\n' "$row" | awk '{ print $1 }')
  if [ -f "$dead" ] && grep -qx "$fpid" "$dead"; then continue; fi
  emit "$row"
done <"$tab"
exit 0
PS
cat >"$bin88/lsof" <<'LSOF'
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
cat >"$bin88/kill" <<'KILL'
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
chmod +x "$bin88/ps" "$bin88/lsof" "$bin88/kill"
# kill is a shell builtin: without this, the fake on PATH never runs.
enable -n kill
out="$(PATH="$bin88:$PATH" AI_METHOD_ORPHAN_MIN_AGE=0 procs_cleanup_worktree "$TMP/nowhere" 88 "")" || true
enable kill
assert_eq alive "$(PATH="$bin88:$PATH" alive 7101)" "an orphan in tmp.* outside the phase stays"
assert_eq alive "$(PATH="$bin88:$PATH" alive 7102)" "an orphan in a deleted worktree outside the phase stays"
assert_contains "$out" "no process left in the worktree" "cleanup of a missing worktree reports no process left"
assert_not_contains "$out" "stopped orphan" "cleanup does not say it stopped an outside orphan"
alien88="$(mktemp -d "${TMPDIR:-/tmp}/alien.XXXXXX")"
rc88=0
orphan_cwd_match "$alien88/.worktrees/issue-3" || rc88=$?
rm -rf "$alien88"
assert_eq 1 "$rc88" "AI_METHOD_ORPHAN_ROOT rejects a deleted worktree outside that root"
# case-88-end
# 6. cost (issue #71): the scan of the orphans spawns a fixed number of processes, however
# many processes hang from init (some 600 on a Mac). Fake ps and lsof list 800 of them
# and a counting awk shows the scan does not start one process per row.
mkdir -p "$TMP/scan"
{ i=1000; while [ "$i" -lt 1800 ]; do echo "$i 1 05:00 sleep 300"; i=$((i + 1)); done; } >"$TMP/scan/ps.out"
{ i=1000; while [ "$i" -lt 1799 ]; do printf 'p%s\nn/somewhere/else\n' "$i"; i=$((i + 1)); done; echo "p1799"; echo "n$TMP/scan/wt"; } >"$TMP/scan/lsof.out"
printf '#!/bin/sh\ncat "%s/scan/ps.out"\n' "$TMP" >"$TMP/scan/ps"
printf '#!/bin/sh\ncat "%s/scan/lsof.out"\n' "$TMP" >"$TMP/scan/lsof"
printf '#!/bin/sh\necho x >>"%s/scan/awk.count"\nexec /usr/bin/awk "$@"\n' "$TMP" >"$TMP/scan/awk"
chmod +x "$TMP/scan/ps" "$TMP/scan/lsof" "$TMP/scan/awk"
found="$(PATH="$TMP/scan:$PATH" procs_orphans "$TMP/scan/wt")"
assert_eq 1799 "$found" "the scan still finds the one orphan of the folder among 800"
[ "$(wc -l <"$TMP/scan/awk.count" | tr -d ' ')" -le 12 ] && ok || bad "the scan started $(wc -l <"$TMP/scan/awk.count" | tr -d ' ') awk processes for 800 rows"
finish
