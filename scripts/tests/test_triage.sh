#!/usr/bin/env bash
# Tests for triage.sh.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

cat >"$TMP/handler.sh" <<'H'
case "$1 $2" in
  "issue list") cat <<'J'
[{"number":3,"title":"Bug","labels":[{"name":"type:bug"},{"name":"priority:high"},{"name":"area:ci"}]},
 {"number":1,"title":"Sem label","labels":[]},
 {"number":2,"title":"Teste","labels":[{"name":"test"}]}]
J
  ;;
esac
H
use_fake_gh "$TMP/handler.sh"
out="$("$SCRIPTS/triage.sh")"
assert_eq '[{"n":1,"t":"Sem label","l":[],"unlabeled":true,"needs":["type","priority","area"]},{"n":3,"t":"Bug","l":["type:bug","priority:high","area:ci"],"unlabeled":false,"needs":[]}]' "$out" "short JSON, sorted, test excluded"
out="$("$SCRIPTS/triage.sh" --include-test)"
assert_contains "$out" '"n":2' "--include-test keeps test issues"
# An issue asked for by number is listed even with the test label.
assert_status 0 "--issue is accepted" "$SCRIPTS/triage.sh" --issue 2
assert_eq '[{"n":2,"t":"Teste","l":["test"],"unlabeled":false,"needs":["type","priority","area"]}]' "$("$SCRIPTS/triage.sh" --issue 2 2>/dev/null || true)" "--issue lists the test issue asked for"
assert_eq '[2,3]' "$("$SCRIPTS/triage.sh" --issue 3 --issue 2 2>/dev/null | jq -c 'map(.n)' || true)" "--issue repeats and lists only what was asked"
# A closed issue asked for by number is said, not silently dropped.
assert_eq '[]' "$("$SCRIPTS/triage.sh" --issue 9 2>/dev/null)" "--issue of a closed issue lists nothing"
assert_contains "$("$SCRIPTS/triage.sh" --issue 9 2>&1 >/dev/null)" "warn: issue #9 is not open" "--issue of a closed issue warns on stderr"
assert_eq "" "$("$SCRIPTS/triage.sh" --issue 3 2>&1 >/dev/null)" "--issue of an open issue warns nothing"
# Runner re-offer trigger (pure logic).
# shellcheck source=scripts/lib/runner_offer.sh
source "$SCRIPTS/lib/runner_offer.sh"
d() { runner_offer_decision "$@"; }
assert_contains "$(d true 0 360 10)" "offer" "avg 6 min offers"
assert_contains "$(d true 0 240 30)" "skip" "avg 4 min and quota 30% does not offer"
assert_contains "$(d true 0 240 60)" "offer" "quota 60% offers"
assert_contains "$(d true 0 240 '')" "skip" "unknown quota is ignored"
assert_contains "$(d true 0 '' 60)" "offer" "unknown average is ignored"
assert_contains "$(d false 0 900 90)" "skip" "public repo never offers"
assert_contains "$(d true 1 900 90)" "skip" "CI_RUNS_ON set never offers"

# Same rule through triage.sh --runner-offer (fake gh; the API returns the value already filtered).
cat >"$TMP/runner.sh" <<'H'
case "$*" in
  "variable list"*) printf '%s\n' $R_VARS ;;
  "api repos/owner/repo --jq"*) echo "${R_PRIVATE:-true}" ;;
  "api repos/owner/repo/actions/runs"*) [ "${R_FAIL:-0}" = 1 ] && exit 1; echo "${R_AVG:-}" ;;
  "api users/owner/settings/billing/actions"*) [ "${R_FAIL:-0}" = 1 ] && exit 1; echo "${R_QUOTA:-}" ;;
esac
H
use_fake_gh "$TMP/runner.sh"
assert_contains "$(R_AVG=400 R_QUOTA=10 "$SCRIPTS/triage.sh" --runner-offer)" "offer" "script offers on slow CI"
assert_contains "$(R_AVG=100 R_QUOTA=30 "$SCRIPTS/triage.sh" --runner-offer)" "skip" "script skips under thresholds"
assert_contains "$(R_AVG=100 R_QUOTA=60 "$SCRIPTS/triage.sh" --runner-offer)" "offer" "script offers on quota"
assert_contains "$(R_PRIVATE=false R_AVG=900 "$SCRIPTS/triage.sh" --runner-offer)" "skip" "script skips public repo"
assert_contains "$(R_VARS=CI_RUNS_ON R_AVG=900 "$SCRIPTS/triage.sh" --runner-offer)" "skip" "script skips with CI_RUNS_ON"
assert_contains "$(R_VARS=PROCESS_OFFER_RUNNER R_AVG=900 "$SCRIPTS/triage.sh" --runner-offer)" "offer" "setup decline does not block the trigger"
assert_contains "$(R_VARS=PROCESS_OFFER_RUNNER_TRIGGER R_AVG=900 "$SCRIPTS/triage.sh" --runner-offer)" "skip" "trigger decline blocks the offer"
assert_contains "$(R_FAIL=1 "$SCRIPTS/triage.sh" --runner-offer)" "skip" "API failure does not break triage"
finish
