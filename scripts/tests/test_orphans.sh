#!/usr/bin/env bash
# Tests that no process of the method outlives whoever created it (issue #66): the
# sweep of tests/lib.sh, the orphan check at the end of validate.sh, the orphan mark of
# sessions.sh and the orphan stop of close-phase.sh --cleanup. Every process here is
# spawned on purpose and stopped by this test at the end, whatever fails.
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
# A clean suite stays green.
rm "$vrepo/scripts/tests/test_leaves.sh"
printf '#!/usr/bin/env bash\nexit 0\n' >"$vrepo/scripts/tests/test_clean.sh"
assert_status 0 "validate.sh is green without orphans" \
  sh -c "cd '$vrepo' && env -u PROCESS_VALIDATE_RUNNING scripts/validate.sh --tests"
assert_not_contains "$(last_output)" "orphan process" "no orphan line on a clean run"

# 4. sessions.sh --list marks an orphan claude; a claude with a live parent has no mark.
mkdir -p "$TMP/fake" "$TMP/tmp.orph"
printf '#!/usr/bin/env bash\nsleep 300\n' >"$TMP/fake/claude"
chmod +x "$TMP/fake/claude"
oc="$(orphan "$TMP/tmp.orph" "$TMP/fake/claude" -p task)"
(cd "$TMP/d2" && exec "$TMP/fake/claude" -p live >/dev/null 2>&1) &
lc=$!; echo "$lc" >>"$PIDF"
sleep 1
assert_status 0 "sessions.sh --list" "$SCRIPTS/sessions.sh" --list
list="$(last_output)"
assert_contains "$(printf '%s\n' "$list" | grep -E "[ ]$oc " || true)" "orphan" "--list marks the orphan claude"
assert_not_contains "$(printf '%s\n' "$list" | grep -E "[ ]$lc " || true)" "orphan" "a claude with a live parent is not marked"

# 5. cleanup: procs_cleanup_worktree stops the orphans of temporary folders, and only
# those at least AI_METHOD_ORPHAN_MIN_AGE seconds old; the live-parent process stays.
out="$(AI_METHOD_ORPHAN_MIN_AGE=0 procs_cleanup_worktree "$TMP/nowhere" 66 "")"
sleep 1
assert_eq dead "$(alive "$oc")" "--cleanup stops the orphan claude of a temporary folder"
assert_contains "$out" "orphan" "--cleanup says it stopped an orphan"
assert_eq alive "$(alive "$lc")" "--cleanup keeps the claude with a live parent"
assert_eq alive "$(alive "$mine")" "--cleanup keeps the process of its own test"
o3="$(orphan "$TMP/tmp.orph")"
sleep 1
AI_METHOD_ORPHAN_MIN_AGE=3600 procs_cleanup_worktree "$TMP/nowhere" 66 "" >/dev/null
assert_eq alive "$(alive "$o3")" "a young orphan stays below the minimum age"
finish
