#!/usr/bin/env bash
# Tests of the affected-tests selection of validate.sh: in a phase it runs the tests
# the diff against the base reaches, plus the gate tests; anything unmapped runs all.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

repo="$(make_repo)"
mkdir -p "$repo/scripts/lib" "$repo/scripts/tests"
cp "$SCRIPTS/validate.sh" "$repo/scripts/validate.sh"
cp "$SCRIPTS/lib/common.sh" "$SCRIPTS/lib/slots.sh" "$SCRIPTS/lib/progress.sh" "$SCRIPTS/lib/procs.sh" "$SCRIPTS/lib/machine-limits.env.example" "$repo/scripts/lib/"
RAN="$TMP/ran.log"
# Each test appends its own name to the log; alpha reads foo.sh, beta reads bar.sh,
# gamma_gate is a gate test, delta reads wrapper.sh, which calls foo.sh.
for t in alpha:foo.sh beta:bar.sh gamma_gate:gate.sh delta:wrapper.sh; do
  name="${t%%:*}"; target="${t#*:}"
  cat >"$repo/scripts/tests/test_$name.sh" <<P
#!/usr/bin/env bash
# reads $target
echo $name >>"$RAN"
P
done
printf '#!/usr/bin/env bash\necho foo\n' >"$repo/scripts/foo.sh"
printf '#!/usr/bin/env bash\necho bar\n' >"$repo/scripts/bar.sh"
printf '#!/usr/bin/env bash\necho gate\n' >"$repo/scripts/gate.sh"
printf '#!/usr/bin/env bash\n./foo.sh\n' >"$repo/scripts/wrapper.sh"
printf '#!/usr/bin/env bash\necho lonely\n' >"$repo/scripts/lonely.sh"
git -C "$repo" add scripts
git -C "$repo" commit --quiet -m "chore: scripts"
git -C "$repo" checkout --quiet -b fix/issue-9-demo

run() { # run <args...>: validate.sh --tests; the names of the tests that ran, sorted
  rm -f "$RAN"
  (cd "$repo" && env -u CI -u PROCESS_VALIDATE_RUNNING scripts/validate.sh "$@") >"$TMP/v.out" 2>&1 || true
  sort "$RAN" 2>/dev/null | tr '\n' ' '
}

# A diff of one script: its test, the tests of the scripts that call it, and the gate tests.
echo "# edit" >>"$repo/scripts/foo.sh"
git -C "$repo" commit --quiet -am "fix: foo"
assert_eq "alpha delta gamma_gate " "$(run --tests)" "a diff of foo.sh runs its test, its caller's test and the gate tests"
assert_contains "$(cat "$TMP/v.out")" "affected" "the output says the run is partial"

# --full runs everything, so does the CI.
assert_eq "alpha beta delta gamma_gate " "$(run --tests --full)" "--full runs every test"
rm -f "$RAN"
(cd "$repo" && env -u PROCESS_VALIDATE_RUNNING CI=true scripts/validate.sh --tests) >/dev/null 2>&1 || true
assert_eq "alpha beta delta gamma_gate " "$(sort "$RAN" | tr '\n' ' ')" "the CI runs every test"

# A changed file no test reads: no map, run everything.
echo "# edit" >>"$repo/scripts/lonely.sh"
git -C "$repo" commit --quiet -am "fix: lonely"
assert_eq "alpha beta delta gamma_gate " "$(run --tests)" "a changed file without a map runs everything"

# The main branch is never partial.
git -C "$repo" checkout --quiet main
assert_eq "alpha beta delta gamma_gate " "$(run --tests)" "outside a phase every test runs"
git -C "$repo" checkout --quiet fix/issue-9-demo

# Inert files (the spec in docs/) need no test.
git -C "$repo" reset --quiet --hard HEAD~1
mkdir -p "$repo/docs/specs"
echo spec >"$repo/docs/specs/s.md"
git -C "$repo" add docs
git -C "$repo" commit --quiet -m "docs(specs): add"
assert_eq "alpha delta gamma_gate " "$(run --tests)" "a spec under docs/ does not widen the selection"

# A partial green run is recorded for --prepare (scope=affected), a full one as full.
assert_status 0 "the partial run is green" env -u CI -u PROCESS_VALIDATE_RUNNING bash -c 'cd "$1" && scripts/validate.sh --lint --tests' _ "$repo"
