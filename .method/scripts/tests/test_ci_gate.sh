#!/usr/bin/env bash
# Tests of ci-gate.sh (CI aggregator).
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"
GATE="$SCRIPTS/ci-gate.sh"

needs() { # needs <code> <app> <workflows> <lint> <tests> <workflows-result> [policy] [run_tests]
  jq -cn --arg c "$1" --arg pg "$2" --arg w "$3" --arg l "$4" --arg t "$5" --arg wr "$6" --arg p "${7:-success}" --arg rt "${8:-}" '{
    changes: {result: "success", outputs: ({code: $c, app: $pg, workflows: $w, docs_only: "false"} + (if $rt == "" then {} else {run_tests: $rt} end))},
    policy: {result: $p}, lint: {result: $l}, tests: {result: $t}, workflows: {result: $wr}}'
}
gate() { NEEDS="$1" "$GATE"; }

# Without the run_tests output the tests job is required (a missing output proves nothing).
assert_status 1 "docs-only PR fails when tests are skipped" gate "$(needs false false false skipped skipped skipped)"
assert_status 0 "docs-only PR passes with tests run and lint skipped" gate "$(needs false false false skipped success skipped)"
assert_status 1 "docs-only PR fails when tests fail" gate "$(needs false false false skipped failure skipped)"
assert_status 0 "code PR passes when lint and tests pass" gate "$(needs true false false success success skipped)"
assert_status 1 "fails when tests fail" gate "$(needs true false false success failure skipped)"
assert_status 1 "fails when a required job is skipped" gate "$(needs true false false skipped skipped skipped)"
assert_status 1 "fails when lint is skipped" gate "$(needs true false false skipped success skipped)"
assert_status 1 "fails when policy fails" gate "$(needs false false false skipped success skipped failure)"
assert_status 1 "fails when workflows job is cancelled" gate "$(needs false false true skipped success cancelled)"
# The app output alone (a doc inside app/) requires the tests job, which builds the app.
assert_status 0 "app PR requires only tests" gate "$(needs false true false skipped success skipped)"
assert_status 1 "app PR fails when tests are skipped" gate "$(needs false true false skipped skipped skipped)"
assert_status 1 "app PR fails when tests fail" gate "$(needs false true false skipped failure skipped)"
# A run whose changes job has no outputs at all cannot prove anything: code jobs are required.
assert_status 1 "fails when the changes outputs are missing" gate '{"changes": {"result": "success", "outputs": {}}, "policy": {"result": "success"}, "lint": {"result": "skipped"}, "tests": {"result": "skipped"}, "workflows": {"result": "skipped"}}'
assert_status 1 "fails when NEEDS is missing" env -u NEEDS "$GATE"

# run_tests=false (only inert docs, or code already tested on an earlier commit): tests may be skipped.
assert_status 0 "inert docs PR passes with tests skipped" gate "$(needs false false false skipped skipped skipped success false)"
assert_status 1 "inert docs PR still fails when policy fails" gate "$(needs false false false skipped skipped skipped failure false)"
assert_status 1 "run_tests=true requires the tests" gate "$(needs false false false skipped skipped skipped success true)"
assert_status 0 "code already tested: lint runs, tests skipped" gate "$(needs true false false success skipped skipped success false)"
assert_status 1 "code already tested: lint still required" gate "$(needs true false false skipped skipped skipped success false)"

# Push to main (output event "push"): policy does not run and is not required; on a PR it is.
needs_push() { needs "$@" | jq -c '.changes.outputs.event = "push"'; }
assert_status 0 "push to main passes with policy skipped and the tests skipped by run_tests=false" gate "$(needs_push false false false skipped skipped skipped skipped false)"
assert_status 0 "push to main passes with the suite run on the sum" gate "$(needs_push true false false success success skipped skipped true)"
assert_status 1 "push to main still fails when the tests fail" gate "$(needs_push true false false success failure skipped skipped true)"
assert_status 1 "a PR still requires policy" gate "$(needs false false false skipped skipped skipped skipped false)"

# A repository job listed in the extra-jobs file is required even when run_tests=false (#101).
extra="$TMP/ci-extra-jobs"
printf 'app-tests\n' >"$extra"
waived="$(needs false false false skipped skipped skipped success false | jq -c '. + {"app-tests": {result: "skipped"}}')"
assert_status 1 "an extra repo job skipped is not waived by run_tests=false" env CI_EXTRA_JOBS_FILE="$extra" NEEDS="$waived" "$GATE"
green="$(needs false false false skipped skipped skipped success false | jq -c '. + {"app-tests": {result: "success"}}')"
assert_status 0 "an extra repo job that succeeded passes" env CI_EXTRA_JOBS_FILE="$extra" NEEDS="$green" "$GATE"
finish
