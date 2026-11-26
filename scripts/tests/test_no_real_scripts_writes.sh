#!/usr/bin/env bash
# No test writes into the real scripts/ (#281): a file created there is seen by a test that runs
# at the same time (a copy of scripts/, a git ls-files, a count) and fails it under parallel load.
# A test builds what it needs in a copy (copy_scripts), never in $SCRIPTS or $REPO/scripts.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

real='"?\$(\{)?(SCRIPTS|REPO/scripts|REPO\}/scripts)'
writers="(>>?|touch|chmod( [-+a-z]+)?|mkdir( -p)?|rm( -[a-zA-Z]+)?|sentinel=) *"
hits="$(cd "$TESTS_DIR" && grep -nE "${writers}${real}" test_*.sh test_*.py phase_start_common.sh close_phase_common.sh 2>/dev/null | grep -v '^test_no_real_scripts_writes.sh:' || true)"
assert_eq "" "$hits" "no test writes into the real scripts/"
finish
