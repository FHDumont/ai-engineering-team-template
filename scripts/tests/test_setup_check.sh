#!/usr/bin/env bash
# Tests of setup-repo.sh --check (the setup is mandatory): 0 only when everything is in place.
# The refusal of phase-start.sh and open-issue.sh is in test_setup_refusal.sh.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"
SETUP="$SCRIPTS/setup-repo.sh"
: >"$TMP/none.sh"
use_fake_gh "$TMP/none.sh"

# --check: 0 only when labels, settings, protection and offers are all in place.
fake_setup ok
assert_status 0 "check passes on a configured repository" "$SETUP" --check
assert_contains "$(last_output)" "is configured for the method" "check: says the repository is configured"
assert_eq "" "$(gh_calls | sort | uniq -d)" "check: no gh call is repeated"
assert_eq "4" "$(gh_calls | wc -l | tr -d ' ')" "check: four reads in one run"
assert_eq "" "$(gh_calls | grep -E 'label (create|edit|delete)|-X (PUT|PATCH)|variable set' || true)" "check: writes nothing"

for state in nolabels noprotection offer; do
  : >"$FAKE_GH_LOG"
  fake_setup "$state"
  assert_status 7 "check exits 7 ($state)" "$SETUP" --check
  out="$(last_output)"
  assert_contains "$out" 'say "configurar o repo"' "check says the phrase ($state)"
  assert_contains "$out" "setup skill" "check points to the setup skill ($state)"
  assert_eq "" "$(gh_calls | sort | uniq -d)" "check repeats no gh call ($state)"
  assert_eq "" "$(gh_calls | grep -E 'label (create|edit|delete)|-X (PUT|PATCH)|variable set' || true)" "check writes nothing ($state)"
done
fake_setup nolabels;     "$SETUP" --check >"$TMP/o" 2>&1 || true
assert_contains "$(cat "$TMP/o")" "missing: labels" "check names the missing labels"
assert_not_contains "$(cat "$TMP/o")" "missing: protection" "check names only what is missing"
fake_setup noprotection; "$SETUP" --check >"$TMP/o" 2>&1 || true
assert_contains "$(cat "$TMP/o")" "missing: protection of main" "check names the missing protection"
fake_setup offer;        "$SETUP" --check >"$TMP/o" 2>&1 || true
assert_contains "$(cat "$TMP/o")" "missing: answer to offer:project" "check names the unanswered offer"

# A plan without branch protection: pending until the mode is recorded, then configured.
fake_setup freeplan
assert_status 7 "check exits 7 on a plan without branch protection and no recorded mode" "$SETUP" --check
assert_contains "$(last_output)" "missing: owner ok to enter unprotected" "plan: names the missing owner ok"
assert_contains "$(last_output)" 'say "configurar o repo"' "plan: tells to run the setup"
assert_eq "" "$(gh_calls | grep -E '\-X (PUT|PATCH)|variable set' || true)" "plan: check writes nothing"
fake_setup unprotected
assert_status 0 "check passes in the unprotected mode" "$SETUP" --check
assert_contains "$(last_output)" "is configured for the method" "unprotected: configured"
assert_contains "$(last_output)" "mode: unprotected" "unprotected: says the mode"
finish
