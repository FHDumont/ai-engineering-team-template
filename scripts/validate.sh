#!/usr/bin/env bash
#: validate.sh: lint and tests of the project and of the method's scripts.
#:
#: Usage: validate.sh [--lint] [--tests]   (no option: both)
#:
#: --lint: shellcheck on every Bash script (the only place it runs) and a
#:         Python syntax check.
#: --tests: runs scripts/tests/test_*.sh, scripts/tests/test_*.py and
#:          .claude/hooks/tests/test_*.sh. App tests join here once there is an app.
#:
#: Never runs from inside its own tests: it sets PROCESS_VALIDATE_RUNNING=1 in the
#: environment and, called again with the mark, exits 3 at once.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"
ROOT="$(cd "$HERE/.." && pwd)"
cd "$ROOT"

lint=0 tests=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --lint) lint=1; shift ;;
    --tests) tests=1; shift ;;
    *) die "unknown option: $1 (see --help)" 2 ;;
  esac
done
[ "$lint" = 1 ] || [ "$tests" = 1 ] || { lint=1; tests=1; }

# Re-entry lock: a test that reaches validate.sh again (through close-phase.sh
# --prepare, check-env.sh or directly) would run the suite inside the suite, without
# end. The mark travels in the environment of every test.
if [ -n "${PROCESS_VALIDATE_RUNNING:-}" ]; then
  die "validate.sh is already running: a test called it again (PROCESS_VALIDATE_RUNNING is set); stub scripts/validate.sh in the temporary repo of the test" 3
fi
export PROCESS_VALIDATE_RUNNING=1

fail=0
if [ "$lint" = 1 ]; then
  require_cmd shellcheck python3
  # Every file with a bash shebang, including hooks without an extension.
  files="$(git ls-files -co --exclude-standard | while read -r f; do
    [ -f "$f" ] && head -1 "$f" | grep -qE '^#!.*\bbash' && echo "$f"; true
  done)"
  # shellcheck disable=SC2086
  if shellcheck -x -S warning $files; then
    echo "ok: shellcheck ($(echo "$files" | wc -l | tr -d ' ') files)"
  else
    fail=1
  fi
  pyfiles="$(git ls-files -co --exclude-standard '*.py')"
  # shellcheck disable=SC2086
  if python3 -c 'import ast, sys
for f in sys.argv[1:]:
    ast.parse(open(f, encoding="utf-8").read(), f)' $pyfiles; then
    echo "ok: python syntax"
  else
    fail=1
  fi
fi

if [ "$tests" = 1 ]; then
  passed=0 failed=0
  for t in scripts/tests/test_*.sh .claude/hooks/tests/test_*.sh; do
    [ -e "$t" ] || continue
    if out="$(bash "$t" 2>&1)"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1)); fail=1
      echo "FAIL $t"; echo "$out" | tail -20 | sed 's/^/  /'
    fi
  done
  for t in scripts/tests/test_*.py; do
    [ -e "$t" ] || continue
    if out="$(python3 "$t" 2>&1)"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1)); fail=1
      echo "FAIL $t"; echo "$out" | tail -20 | sed 's/^/  /'
    fi
  done
  echo "tests: $passed passed, $failed failed"
fi
exit "$fail"
