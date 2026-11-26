#!/usr/bin/env bash
# Tests of the re-entry lock of validate.sh: the suite never runs from inside itself.
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

# The real validate.sh in a temporary repo whose whole suite is one probe test: the
# real suite never runs from here, with or without the lock.
repo="$(make_repo)"
mkdir -p "$repo/.method/scripts/lib" "$repo/.method/scripts/tests"
cp "$SCRIPTS/validate.sh" "$repo/.method/scripts/validate.sh"
cp "$SCRIPTS/lib/common.sh" "$SCRIPTS/lib/slots.sh" "$SCRIPTS/lib/progress.sh" "$SCRIPTS/lib/procs.sh" "$SCRIPTS/lib/machine-limits.env.example" "$repo/.method/scripts/lib/"
PROBE="$TMP/probe.out"
cat >"$repo/.method/scripts/tests/test_probe.sh" <<P
#!/usr/bin/env bash
echo "mark=\${PROCESS_VALIDATE_RUNNING:-}" >"$PROBE"
P

# First call: the tests run with the mark in their environment.
assert_status 0 "validate.sh runs the suite when nothing is running" env -u PROCESS_VALIDATE_RUNNING "$repo/.method/scripts/validate.sh" --tests
assert_eq "mark=1" "$(cat "$PROBE" 2>/dev/null || true)" "the tests see the mark of the running validate.sh"

# Called again with the mark: refuses at once, before any test.
rm -f "$PROBE"
for args in "--tests" "--lint" ""; do
  # shellcheck disable=SC2086  # $args is an option list, empty on purpose in one round
  assert_status 3 "validate.sh $args refuses to run inside its own tests" env PROCESS_VALIDATE_RUNNING=1 "$repo/.method/scripts/validate.sh" $args
  assert_contains "$(last_output)" "already running" "validate.sh $args says why it refuses"
done
assert_eq "" "$(cat "$PROBE" 2>/dev/null || true)" "no test runs under the mark"
assert_status 0 "--help still answers under the mark" env PROCESS_VALIDATE_RUNNING=1 "$repo/.method/scripts/validate.sh" --help

# Every copy of .method/scripts/ into a temporary repo carries stubs of validate.sh and
# check-docs.sh from the start (copy_scripts), and no test copies .method/scripts/ by hand.
copy="$(make_repo)"
copy_scripts "$copy"
assert_eq "ok: stub --tests" "$("$copy/.method/scripts/validate.sh" --tests)" "copy_scripts leaves a stub of validate.sh"
assert_eq "ok: stub " "$("$copy/.method/scripts/check-docs.sh")" "copy_scripts leaves a stub of check-docs.sh"
assert_eq "close-phase.sh" "$(basename "$(ls "$copy/.method/scripts/close-phase.sh")")" "copy_scripts copies the other scripts"
by_hand="$(grep -lE 'cp +-[A-Za-z]+ +"?\$\{?(SCRIPTS|REPO/\.method/scripts)' "$TESTS_DIR"/test_*.sh "$REPO"/.claude/hooks/tests/test_*.sh 2>/dev/null | grep -v "/$(basename "$0")\$" || true)"
assert_eq "" "$by_hand" "no test copies .method/scripts/ without copy_scripts"

# The time limit is a parameter that grows with the load (issue #71), never a fixed number.
assert_status 0 "a performance overrun warns and does not fail" env -u CI bash -c 'source "$1/lib/common.sh"; warn_over_expected demo 14 10; exit 0' _ "$SCRIPTS"
assert_eq "warn: over-expected demo 14 10" "$(last_output)" "the warning names what, the measurement and the expectation"
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
mkdir -p "$nested/.method/scripts/lib" "$nested/.method/scripts/tests"
cp "$SCRIPTS/validate.sh" "$nested/.method/scripts/validate.sh"
cp "$SCRIPTS/lib/common.sh" "$SCRIPTS/lib/slots.sh" "$SCRIPTS/lib/progress.sh" "$SCRIPTS/lib/procs.sh" "$SCRIPTS/lib/machine-limits.env.example" "$nested/.method/scripts/lib/"
# shellcheck disable=SC2016  # the stub expands in its own shell
printf '#!/usr/bin/env bash\n"$(dirname "$0")/../validate.sh" --tests\n' >"$nested/.method/scripts/tests/test_close_phase.sh"
assert_status 1 "a test that reaches validate.sh from the suite fails at once" test_limited env -u PROCESS_VALIDATE_RUNNING "$nested/.method/scripts/validate.sh" --tests
assert_contains "$(last_output)" "already running" "the nested validate.sh says why it refuses"

# Missing product dependency: outside the CI the failure names the folder, the module
# and the install command; in the CI nothing changes.
dep="$(make_repo)"
mkdir -p "$dep/.method/scripts/lib" "$dep/.method/scripts/tests" "$dep/dashboard" "$dep/web"
cp "$SCRIPTS/validate.sh" "$dep/.method/scripts/validate.sh"
cp "$SCRIPTS/lib/common.sh" "$SCRIPTS/lib/slots.sh" "$SCRIPTS/lib/progress.sh" "$SCRIPTS/lib/procs.sh" "$SCRIPTS/lib/machine-limits.env.example" "$dep/.method/scripts/lib/"
printf 'fastapi==0.110\nuvicorn\n' >"$dep/dashboard/requirements.txt"
printf '{}\n' >"$dep/web/package.json"
cat >"$dep/.method/scripts/tests/test_dep.sh" <<'P'
#!/usr/bin/env bash
echo "ModuleNotFoundError: No module named 'fastapi.routing'"
echo "Error: Cannot find module 'left-pad'"
exit 1
P
assert_status 1 "a missing module fails the suite" env -u CI -u PROCESS_VALIDATE_RUNNING "$dep/.method/scripts/validate.sh" --tests
assert_contains "$(last_output)" "missing dependency: module fastapi (folder dashboard): pip install -r dashboard/requirements.txt" "the Python module line has folder, module and command"
assert_contains "$(last_output)" "missing dependency: module left-pad (folder web): cd web && npm install" "the Node module line has folder, module and command"
assert_status 1 "the CI run still fails" env -u PROCESS_VALIDATE_RUNNING CI=true "$dep/.method/scripts/validate.sh" --tests
case "$(last_output)" in *"missing dependency"*) bad "the CI output has no dependency line" ;; *) ok ;; esac

# Tests run in parallel: AI_METHOD_TEST_JOBS at once, each one in its own folder, and the
# report keeps the order. Two tests that wait for each other only pass when concurrent.
par="$(make_repo)"
LIMIT="$(slots_test_timeout)"   # the wait of the peer follows the parameter, not a fixed 5 s
mkdir -p "$par/.method/scripts/lib" "$par/.method/scripts/tests"
cp "$SCRIPTS/validate.sh" "$par/.method/scripts/validate.sh"
cp "$SCRIPTS/lib/common.sh" "$SCRIPTS/lib/slots.sh" "$SCRIPTS/lib/progress.sh" "$SCRIPTS/lib/procs.sh" "$SCRIPTS/lib/machine-limits.env.example" "$par/.method/scripts/lib/"
# The peer wait is a parameter of the generated tests: long in parallel, short in series.
gen_pair() {
  for n in a b; do
    cat >"$par/.method/scripts/tests/test_$n.sh" <<P
#!/usr/bin/env bash
touch "$TMP/started-$n"
end=\$(( \$(date +%s) + $1 )); while [ "\$(date +%s)" -lt "\$end" ]; do [ -e "$TMP/started-$([ $n = a ] && echo b || echo a)" ] && exit 0; sleep 0.1; done
echo "no peer: test_$n ran alone"; exit 1
P
  done
}
gen_pair "$LIMIT"
assert_status 0 "two tests wait for each other: they run in parallel" env -u PROCESS_VALIDATE_RUNNING AI_METHOD_TEST_JOBS=2 "$par/.method/scripts/validate.sh" --tests
assert_contains "$(last_output)" "tests: 2 passed, 0 failed" "the parallel run counts every test"
rm -f "$TMP"/started-*
gen_pair 3   # series only proves the failure: a short explicit wait, not the parameter
t0=$(date +%s)
assert_status 1 "with one job the same tests run in series and fail" env -u PROCESS_VALIDATE_RUNNING AI_METHOD_TEST_JOBS=1 "$par/.method/scripts/validate.sh" --tests
[ $(( $(date +%s) - t0 )) -lt "$LIMIT" ] && ok || bad "the series case does not wait for the parameter limit"
assert_contains "$(last_output)" "FAIL .method/scripts/tests/test_a.sh" "a failing test is reported by name"

# A waiter does not inherit a green result of a tree that changed during the run (#150).
inherit="$(make_repo)"
mkdir -p "$inherit/.method/scripts/lib" "$inherit/.method/scripts/tests"
cp "$SCRIPTS/validate.sh" "$inherit/.method/scripts/validate.sh"
cp "$SCRIPTS/lib/common.sh" "$SCRIPTS/lib/slots.sh" "$SCRIPTS/lib/progress.sh" "$SCRIPTS/lib/procs.sh" "$SCRIPTS/lib/machine-limits.env.example" "$inherit/.method/scripts/lib/"
printf 'good\n' >"$inherit/subject.txt"
cat >"$inherit/.method/scripts/tests/test_slow.sh" <<'P'
#!/usr/bin/env bash
grep -q good subject.txt
rc=$?
sleep 8
exit $rc
P
chmod +x "$inherit/.method/scripts/tests/test_slow.sh"
git -C "$inherit" add subject.txt .method >/dev/null 2>&1 || true
: >"$TMP/inherit.out"
env -u PROCESS_VALIDATE_RUNNING "$inherit/.method/scripts/validate.sh" --tests >"$TMP/inherit.first" 2>&1 &
first=$!
sleep 4
printf 'broken\n' >"$inherit/subject.txt"
second=0
env -u PROCESS_VALIDATE_RUNNING "$inherit/.method/scripts/validate.sh" --tests >"$TMP/inherit.second" 2>&1 || second=$?
wait "$first" || true
assert_eq 1 "$second" "a waiter on a changed tree does not inherit the previous green"
assert_contains "$(cat "$TMP/inherit.second")" "failed" "the second run reports the failure of the new tree"

# An empty test list (no test file at all) must not trip bash 3.2 set -u (#110).
empty="$(make_repo)"
mkdir -p "$empty/.method/scripts/lib" "$empty/.method/scripts/tests"
cp "$SCRIPTS/validate.sh" "$empty/.method/scripts/validate.sh"
cp "$SCRIPTS/lib/common.sh" "$SCRIPTS/lib/slots.sh" "$SCRIPTS/lib/progress.sh" "$SCRIPTS/lib/procs.sh" "$SCRIPTS/lib/machine-limits.env.example" "$empty/.method/scripts/lib/"
assert_status 0 "an empty test list passes" env -u PROCESS_VALIDATE_RUNNING "$empty/.method/scripts/validate.sh" --tests
assert_contains "$(last_output)" "tests: 0 passed, 0 failed" "an empty test list reports zero tests"

# The repository's own checks live in an optional script, not an edit of validate.sh (#101).
repo_check="$(make_repo)"
mkdir -p "$repo_check/.method/scripts/lib" "$repo_check/.method/scripts/tests" "$repo_check/.github"
cp "$SCRIPTS/validate.sh" "$repo_check/.method/scripts/validate.sh"
cp "$SCRIPTS/lib/common.sh" "$SCRIPTS/lib/slots.sh" "$SCRIPTS/lib/progress.sh" "$SCRIPTS/lib/procs.sh" "$SCRIPTS/lib/machine-limits.env.example" "$repo_check/.method/scripts/lib/"
printf '#!/usr/bin/env bash\necho repo-check-ran\nexit 1\n' >"$repo_check/.github/validate-repo.sh"
assert_status 1 "a failing repository validate script fails the suite" env -u PROCESS_VALIDATE_RUNNING "$repo_check/.method/scripts/validate.sh" --tests
assert_contains "$(last_output)" "repo-check-ran" "the repository script actually ran"

# The time of the repository block is its own measure in the history (#251).
rm -f "$AI_METHOD_CACHE/history.tsv"
printf '#!/usr/bin/env bash\necho repo-check-ok\nexit 0\n' >"$repo_check/.github/validate-repo.sh"
printf '#!/usr/bin/env bash\nexit 0\n' >"$repo_check/.method/scripts/tests/test_fast.sh"
assert_status 0 "a passing repository validate script passes the suite" env -u PROCESS_VALIDATE_RUNNING "$repo_check/.method/scripts/validate.sh" --tests
assert_contains "$(cat "$AI_METHOD_CACHE/history.tsv")" "$(printf 'validate-repo\t')" "the time of validate-repo.sh is recorded as the validate-repo measure"
assert_contains "$(last_output)" "slowest tests" "the end of validate.sh lists the slowest tests"
assert_contains "$(last_output)" "time: repository block" "the end of validate.sh reports the repository block time"

finish
