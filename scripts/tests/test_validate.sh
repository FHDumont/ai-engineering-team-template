#!/usr/bin/env bash
# Tests of the re-entry lock of validate.sh: the suite never runs from inside itself.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

# The real validate.sh in a temporary repo whose whole suite is one probe test: the
# real suite never runs from here, with or without the lock.
repo="$(make_repo)"
mkdir -p "$repo/scripts/lib" "$repo/scripts/tests"
cp "$SCRIPTS/validate.sh" "$repo/scripts/validate.sh"
cp "$SCRIPTS/lib/common.sh" "$SCRIPTS/lib/slots.sh" "$SCRIPTS/lib/progress.sh" "$SCRIPTS/lib/procs.sh" "$SCRIPTS/lib/machine-limits.env.example" "$repo/scripts/lib/"
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

# The time limit is a parameter that grows with the load (issue #71), never a fixed number.
assert_eq 600 "$(AI_METHOD_TEST_TIMEOUT_SECONDS=600 AI_METHOD_FAKE_LOAD1=3 slots_test_timeout)" "the limit is the parameter on a free machine"
assert_eq 1800 "$(AI_METHOD_TEST_TIMEOUT_SECONDS=600 AI_METHOD_WARN_LOAD1=8 AI_METHOD_FAKE_LOAD1=20 slots_test_timeout)" "the limit triples with load1 20 over warn 8"
assert_eq 7 "$(AI_METHOD_TEST_TIMEOUT_SECONDS=7 AI_METHOD_WARN_LOAD1=8 AI_METHOD_FAKE_LOAD1=8 slots_test_timeout)" "the limit does not grow at the warn load"
# shellcheck disable=SC2016  # the script of bash -c expands in the child shell
assert_status 142 "an alarm of the limit kills a slow command" env AI_METHOD_TEST_TIMEOUT_SECONDS=1 AI_METHOD_FAKE_LOAD1=1 bash -c 'source "$1/lib.sh"; test_limited sleep 5' _ "$TESTS_DIR"
# shellcheck disable=SC2016
assert_status 0 "the same slow command passes when the load stretches the limit" env AI_METHOD_TEST_TIMEOUT_SECONDS=1 AI_METHOD_WARN_LOAD1=1 AI_METHOD_FAKE_LOAD1=9 bash -c 'source "$1/lib.sh"; test_limited sleep 2' _ "$TESTS_DIR"
# test_close_phase.sh never runs from here (issue #71): it runs once, in the normal suite.
# A stub in its place stands for it, and the real validate.sh refuses under the mark, so
# a test that reached validate.sh from inside the suite would fail at once, not nest it.
nested="$(make_repo)"
mkdir -p "$nested/scripts/lib" "$nested/scripts/tests"
cp "$SCRIPTS/validate.sh" "$nested/scripts/validate.sh"
cp "$SCRIPTS/lib/common.sh" "$SCRIPTS/lib/slots.sh" "$SCRIPTS/lib/progress.sh" "$SCRIPTS/lib/procs.sh" "$SCRIPTS/lib/machine-limits.env.example" "$nested/scripts/lib/"
# shellcheck disable=SC2016  # the stub expands in its own shell
printf '#!/usr/bin/env bash\n"$(dirname "$0")/../validate.sh" --tests\n' >"$nested/scripts/tests/test_close_phase.sh"
assert_status 1 "a test that reaches validate.sh from the suite fails at once" test_limited env -u PROCESS_VALIDATE_RUNNING "$nested/scripts/validate.sh" --tests
assert_contains "$(last_output)" "already running" "the nested validate.sh says why it refuses"

# Missing product dependency: outside the CI the failure names the folder, the module
# and the install command; in the CI nothing changes.
dep="$(make_repo)"
mkdir -p "$dep/scripts/lib" "$dep/scripts/tests" "$dep/dashboard" "$dep/web"
cp "$SCRIPTS/validate.sh" "$dep/scripts/validate.sh"
cp "$SCRIPTS/lib/common.sh" "$SCRIPTS/lib/slots.sh" "$SCRIPTS/lib/progress.sh" "$SCRIPTS/lib/procs.sh" "$SCRIPTS/lib/machine-limits.env.example" "$dep/scripts/lib/"
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
LIMIT="$(slots_test_timeout)"   # the wait of the peer follows the parameter, not a fixed 5 s
mkdir -p "$par/scripts/lib" "$par/scripts/tests"
cp "$SCRIPTS/validate.sh" "$par/scripts/validate.sh"
cp "$SCRIPTS/lib/common.sh" "$SCRIPTS/lib/slots.sh" "$SCRIPTS/lib/progress.sh" "$SCRIPTS/lib/procs.sh" "$SCRIPTS/lib/machine-limits.env.example" "$par/scripts/lib/"
for n in a b; do
  cat >"$par/scripts/tests/test_$n.sh" <<P
#!/usr/bin/env bash
touch "$TMP/started-$n"
end=\$(( \$(date +%s) + $LIMIT )); while [ "\$(date +%s)" -lt "\$end" ]; do [ -e "$TMP/started-$([ $n = a ] && echo b || echo a)" ] && exit 0; sleep 0.1; done
echo "no peer: test_$n ran alone"; exit 1
P
done
assert_status 0 "two tests wait for each other: they run in parallel" env -u PROCESS_VALIDATE_RUNNING AI_METHOD_TEST_JOBS=2 "$par/scripts/validate.sh" --tests
assert_contains "$(last_output)" "tests: 2 passed, 0 failed" "the parallel run counts every test"
rm -f "$TMP"/started-*
assert_status 1 "with one job the same tests run in series and fail" env -u PROCESS_VALIDATE_RUNNING AI_METHOD_TEST_JOBS=1 "$par/scripts/validate.sh" --tests
assert_contains "$(last_output)" "FAIL scripts/tests/test_a.sh" "a failing test is reported by name"

finish
