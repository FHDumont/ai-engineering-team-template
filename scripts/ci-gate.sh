#!/usr/bin/env bash
#: ci-gate.sh: decide the result of the `CI` aggregator job (the check required by protection).
#:
#: Usage (in the workflow, job `ci` with if: always()):
#:   NEEDS='${{ toJSON(needs) }}' ci-gate.sh
#:
#: `changes` and `policy` must succeed. Code jobs (lint, tests, workflows) are
#: required according to the `changes` outputs:
#:   lint and tests <- code (everything that is not a doc); tests <- app;
#:   workflows <- workflows.
#: `code` only waives lint and tests when it is exactly "false": a missing
#: output proves nothing and requires both. A required job must succeed in this
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
check policy

required=""
[ "$(output code)" = false ] || required="lint tests"
[ "$(output app)" = true ] && [ -z "$required" ] && required="tests"
[ "$(output workflows)" = true ] && required="$required workflows"
[ -n "$required" ] || echo "ok: no code jobs required (docs only)"

for job in $required; do
  check "$job"
done

[ "$fail" = 0 ] && echo "CI passed"
exit "$fail"
