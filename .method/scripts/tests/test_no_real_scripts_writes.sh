#!/usr/bin/env bash
# No test writes into the real .method/scripts/ (#281): a file created there is seen by a test that runs
# at the same time (a copy of .method/scripts/, a git ls-files, a count) and fails it under parallel load.
# A test builds what it needs in a copy (copy_scripts), never in $SCRIPTS or $REPO/scripts.
# The check is a heuristic grep: redirections, touch, chmod, mkdir, rm and a sentinel= assignment aimed at the real
# .method/scripts/. A cp or tee to it is not caught (a cp FROM it is a read and common).
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

real='"?\$(\{)?(SCRIPTS|REPO/\.method/scripts|REPO\}/\.method/scripts)'
writers="(>>?|touch|chmod( [-+a-z]+)?|mkdir( -p)?|rm( -[a-zA-Z]+)?|sentinel=) *"
hits="$(cd "$TESTS_DIR" && grep -nE "${writers}${real}" test_*.sh test_*.py phase_start_common.sh close_phase_common.sh 2>/dev/null | grep -v '^test_no_real_scripts_writes.sh:' || true)"
assert_eq "" "$hits" "no test writes into the real .method/scripts/"
finish
