#!/usr/bin/env bash
# Tests of ci-gate.sh (CI aggregator).
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"
GATE="$SCRIPTS/ci-gate.sh"

needs() { # needs <code> <app> <workflows> <lint> <tests> <workflows-result> [policy]
  jq -cn --arg c "$1" --arg pg "$2" --arg w "$3" --arg l "$4" --arg t "$5" --arg wr "$6" --arg p "${7:-success}" '{
    changes: {result: "success", outputs: {code: $c, app: $pg, workflows: $w, docs_only: "false"}},
    policy: {result: $p}, lint: {result: $l}, tests: {result: $t}, workflows: {result: $wr}}'
}
gate() { NEEDS="$1" "$GATE"; }

assert_status 0 "docs-only PR passes with jobs skipped" gate "$(needs false false false skipped skipped skipped)"
assert_status 0 "code PR passes when lint and tests pass" gate "$(needs true false false success success skipped)"
assert_status 1 "fails when tests fail" gate "$(needs true false false success failure skipped)"
assert_status 1 "fails when a required job is skipped" gate "$(needs true false false skipped skipped skipped)"
assert_status 1 "fails when lint is skipped" gate "$(needs true false false skipped success skipped)"
assert_status 1 "fails when policy fails" gate "$(needs false false false skipped skipped skipped failure)"
assert_status 1 "fails when workflows job is cancelled" gate "$(needs false false true skipped skipped cancelled)"
# The app output alone (a doc inside app/) requires the tests job, which builds the app.
assert_status 0 "app PR requires only tests" gate "$(needs false true false skipped success skipped)"
assert_status 1 "app PR fails when tests are skipped" gate "$(needs false true false skipped skipped skipped)"
assert_status 1 "app PR fails when tests fail" gate "$(needs false true false skipped failure skipped)"
# A run whose changes job has no outputs at all cannot prove anything: code jobs are required.
assert_status 1 "fails when the changes outputs are missing" gate '{"changes": {"result": "success", "outputs": {}}, "policy": {"result": "success"}, "lint": {"result": "skipped"}, "tests": {"result": "skipped"}, "workflows": {"result": "skipped"}}'
assert_status 1 "fails when NEEDS is missing" env -u NEEDS "$GATE"
finish
