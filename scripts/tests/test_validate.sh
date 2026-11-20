#!/usr/bin/env bash
# Tests of the re-entry lock of validate.sh: the suite never runs from inside itself.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

# The real validate.sh in a temporary repo whose whole suite is one probe test: the
# real suite never runs from here, with or without the lock.
repo="$(make_repo)"
mkdir -p "$repo/scripts/lib" "$repo/scripts/tests"
cp "$SCRIPTS/validate.sh" "$repo/scripts/validate.sh"
cp "$SCRIPTS/lib/common.sh" "$repo/scripts/lib/common.sh"
PROBE="$TMP/probe.out"
cat >"$repo/scripts/tests/test_probe.sh" <<P
#!/usr/bin/env bash
echo "mark=\${PROCESS_VALIDATE_RUNNING:-}" >"$PROBE"
P

# First call: the tests run with the mark in their environment.
assert_status 0 "validate.sh runs the suite when nothing is running" env -u PROCESS_VALIDATE_RUNNING "$repo/scripts/validate.sh" --tests
assert_eq "mark=1" "$(cat "$PROBE" 2>/dev/null || true)" "the tests see the mark of the running validate.sh"

# Called again with the mark: refuses at once, before any test.
rm -f "$PROBE"
for args in "--tests" "--lint" ""; do
  # shellcheck disable=SC2086  # $args is an option list, empty on purpose in one round
  assert_status 3 "validate.sh $args refuses to run inside its own tests" env PROCESS_VALIDATE_RUNNING=1 "$repo/scripts/validate.sh" $args
  assert_contains "$(last_output)" "already running" "validate.sh $args says why it refuses"
done
assert_eq "" "$(cat "$PROBE" 2>/dev/null || true)" "no test runs under the mark"
assert_status 0 "--help still answers under the mark" env PROCESS_VALIDATE_RUNNING=1 "$repo/scripts/validate.sh" --help

# Every copy of scripts/ into a temporary repo carries stubs of validate.sh and
# check-docs.sh from the start (copy_scripts), and no test copies scripts/ by hand.
copy="$(make_repo)"
copy_scripts "$copy"
assert_eq "ok: stub --tests" "$("$copy/scripts/validate.sh" --tests)" "copy_scripts leaves a stub of validate.sh"
assert_eq "ok: stub " "$("$copy/scripts/check-docs.sh")" "copy_scripts leaves a stub of check-docs.sh"
assert_eq "close-phase.sh" "$(basename "$(ls "$copy/scripts/close-phase.sh")")" "copy_scripts copies the other scripts"
by_hand="$(grep -lE 'cp +-[A-Za-z]+ +"?\$\{?(SCRIPTS|REPO/scripts)' "$TESTS_DIR"/test_*.sh "$REPO"/.claude/hooks/tests/test_*.sh 2>/dev/null | grep -v "/$(basename "$0")\$" || true)"
assert_eq "" "$by_hand" "no test copies scripts/ without copy_scripts"

# The session-opener lock of close-phase.sh turned off on purpose: test_close_phase.sh
# fails in seconds and leaves no process behind. The mark is forced, so a real
# validate.sh reached by mistake refuses at once instead of running the suite. This is
# the one copy by hand: it needs the real scripts, with only the lock changed.
broken="$TMP/broken"
mkdir -p "$broken/.github"
cp -R "$SCRIPTS" "$broken/scripts"
cp "$REPO/.github/sensitive-paths" "$REPO/.github/labels.tsv" "$broken/.github/"
sed 's/= opener ]; then/= lock-off ]; then/' "$SCRIPTS/close-phase.sh" >"$broken/scripts/close-phase.sh"
assert_eq 1 "$(grep -c '= lock-off ]; then' "$broken/scripts/close-phase.sh")" "the lock of the copy is off"
start="$(date +%s)"
assert_status 1 "test_close_phase.sh fails with the lock off" env PROCESS_VALIDATE_RUNNING=1 perl -e 'alarm 120; exec @ARGV' bash "$broken/scripts/tests/test_close_phase.sh"
took=$(( $(date +%s) - start ))
assert_contains "$(last_output)" "not ok: the opening session cannot run --prepare" "the failure is the lock that did not fire"
[ "$took" -lt 120 ] && ok || bad "test_close_phase.sh with the lock off took ${took}s"
assert_eq "" "$(pgrep -f "$broken/scripts" || true)" "no process of the broken copy is left alive"

finish
