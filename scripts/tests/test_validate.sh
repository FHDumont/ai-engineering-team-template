#!/usr/bin/env bash
# Tests of the re-entry lock of validate.sh: the suite never runs from inside itself.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

# The real validate.sh in a temporary repo whose whole suite is one probe test: the
# real suite never runs from here, with or without the lock.
repo="$(make_repo)"
mkdir -p "$repo/scripts/lib" "$repo/scripts/tests"
cp "$SCRIPTS/validate.sh" "$repo/scripts/validate.sh"
cp "$SCRIPTS/lib/common.sh" "$SCRIPTS/lib/slots.sh" "$SCRIPTS/lib/progress.sh" "$SCRIPTS/lib/machine-limits.env.example" "$repo/scripts/lib/"
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

# Missing product dependency: outside the CI the failure names the folder, the module
# and the install command; in the CI nothing changes.
dep="$(make_repo)"
mkdir -p "$dep/scripts/lib" "$dep/scripts/tests" "$dep/dashboard" "$dep/web"
cp "$SCRIPTS/validate.sh" "$dep/scripts/validate.sh"
cp "$SCRIPTS/lib/common.sh" "$SCRIPTS/lib/slots.sh" "$SCRIPTS/lib/progress.sh" "$SCRIPTS/lib/machine-limits.env.example" "$dep/scripts/lib/"
printf 'fastapi==0.110\nuvicorn\n' >"$dep/dashboard/requirements.txt"
printf '{}\n' >"$dep/web/package.json"
cat >"$dep/scripts/tests/test_dep.sh" <<'P'
#!/usr/bin/env bash
echo "ModuleNotFoundError: No module named 'fastapi.routing'"
echo "Error: Cannot find module 'left-pad'"
exit 1
P
assert_status 1 "a missing module fails the suite" env -u CI -u PROCESS_VALIDATE_RUNNING "$dep/scripts/validate.sh" --tests
assert_contains "$(last_output)" "missing dependency: module fastapi (folder dashboard): pip install -r dashboard/requirements.txt" "the Python module line has folder, module and command"
assert_contains "$(last_output)" "missing dependency: module left-pad (folder web): cd web && npm install" "the Node module line has folder, module and command"
assert_status 1 "the CI run still fails" env -u PROCESS_VALIDATE_RUNNING CI=true "$dep/scripts/validate.sh" --tests
case "$(last_output)" in *"missing dependency"*) bad "the CI output has no dependency line" ;; *) ok ;; esac

# Tests run in parallel: AI_METHOD_TEST_JOBS at once, each one in its own folder, and the
# report keeps the order. Two tests that wait for each other only pass when concurrent.
par="$(make_repo)"
mkdir -p "$par/scripts/lib" "$par/scripts/tests"
cp "$SCRIPTS/validate.sh" "$par/scripts/validate.sh"
cp "$SCRIPTS/lib/common.sh" "$SCRIPTS/lib/slots.sh" "$SCRIPTS/lib/progress.sh" "$SCRIPTS/lib/machine-limits.env.example" "$par/scripts/lib/"
for n in a b; do
  cat >"$par/scripts/tests/test_$n.sh" <<P
#!/usr/bin/env bash
touch "$TMP/started-$n"
for i in \$(seq 1 50); do [ -e "$TMP/started-$([ $n = a ] && echo b || echo a)" ] && exit 0; sleep 0.1; done
echo "no peer: test_$n ran alone"; exit 1
P
done
assert_status 0 "two tests wait for each other: they run in parallel" env -u PROCESS_VALIDATE_RUNNING AI_METHOD_TEST_JOBS=2 "$par/scripts/validate.sh" --tests
assert_contains "$(last_output)" "tests: 2 passed, 0 failed" "the parallel run counts every test"
rm -f "$TMP"/started-*
assert_status 1 "with one job the same tests run in series and fail" env -u PROCESS_VALIDATE_RUNNING AI_METHOD_TEST_JOBS=1 "$par/scripts/validate.sh" --tests
assert_contains "$(last_output)" "FAIL scripts/tests/test_a.sh" "a failing test is reported by name"

finish
