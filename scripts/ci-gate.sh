#!/usr/bin/env bash
#: ci-gate.sh: decide the result of the `CI` aggregator job (the check required by protection).
#:
#: Usage (in the workflow, job `ci` with if: always()):
#:   NEEDS='${{ toJSON(needs) }}' ci-gate.sh
#:
#: `changes` must succeed and `policy` too on every PR (on push to main, event "push", policy
#: does not run); `tests` must too, unless the
#: `changes` output run_tests is exactly "false" (only docs that tests do not
#: read changed, or the code was already tested on an earlier commit of the PR;
#: a missing output requires the tests). The other jobs follow the outputs:
#:   lint <- code (everything that is not a doc); workflows <- workflows.
#: `code` only waives lint when it is exactly "false": a missing output proves
#: nothing and requires lint. A required job must succeed in this
#: run (skipped, cancelled or failed fails the gate). CI only runs on code
#: events (opened, synchronize, reopened, ready_for_review). The workflow reads
#: this script from the base commit of the PR. Exits 1 on failure.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"
case "${1:-}" in -h|--help) print_help "$0"; exit 0 ;; esac

: "${NEEDS:?NEEDS (toJSON(needs)) is required}"

result() { echo "$NEEDS" | jq -r --arg j "$1" '.[$j].result // "missing"'; }
output() { echo "$NEEDS" | jq -r --arg j "$1" '.changes.outputs[$j] // "missing"'; }

fail=0
check() { # check <job>
  local r; r="$(result "$1")"
  if [ "$r" = success ]; then echo "ok: $1"; else echo "fail: $1 is $r"; fail=1; fi
}

check changes
# Policy judges a PR: on push to main (output event exactly "push") it does not run.
[ "$(output event)" = push ] || check policy

required="tests"
[ "$(output run_tests)" != false ] || required=""
[ "$(output code)" = false ] || required="lint $required"
[ "$(output workflows)" = true ] && required="$required workflows"

for job in $required; do
  check "$job"
done

[ "$fail" = 0 ] && echo "CI passed"
exit "$fail"
