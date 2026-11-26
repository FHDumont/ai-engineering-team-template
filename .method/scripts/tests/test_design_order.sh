#!/usr/bin/env bash
# The design matches the scripts (issue #107): check-env.sh does not run the
# suite, and section 5.2 comes before 5.3.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

design="$(cat "$REPO/docs/process-design.md")"
line52="$(printf '%s\n' "$design" | grep -n '^### 5.2 ' | head -1 | cut -d: -f1)"
line53="$(printf '%s\n' "$design" | grep -n '^### 5.3 ' | head -1 | cut -d: -f1)"
assert_eq 1 "$((line52 < line53))" "section 5.2 comes before section 5.3"
row="$(printf '%s\n' "$design" | grep '| `scripts/check-env.sh` |')"
assert_not_contains "$row" "testes rodando" "the check-env row does not say the suite is running"
assert_contains "$row" "não roda a suíte" "the check-env row says the suite is not run"

finish
