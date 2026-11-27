#!/usr/bin/env bash
# Tests of setup-repo.sh --check (the setup is mandatory): 0 only when everything is in place.
# The refusal of phase-start.sh and open-issue.sh is in test_setup_refusal.sh.
# shellcheck source=.method/scripts/tests/lib.sh
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

# #190: a private repository that has not recorded the CI mode is not configured, with the
# text phase-start.sh refuses with; recording it (variable) makes --check pass again.
fake_setup nocimode
# An updated repository has .github/ci-mode: run in a copy without it (FHDumont/ai-engineering-team-template#207).
nocm="$(make_repo)"
copy_scripts "$nocm"
mkdir -p "$nocm/.github"
cp "$REPO"/.github/labels.tsv "$REPO"/.github/bots.tsv "$nocm/.github/"
rm -f "$nocm/.github/ci-mode"
assert_status 7 "check exits 7 when the CI mode is not recorded" env -u PROCESS_CI_MODE "$nocm/.method/scripts/setup-repo.sh" --check
# The script reads its own repository, not the one of the cwd (issue #209): a cwd with .github/ci-mode must not hide the missing one.
cwdrepo="$(make_repo)"
mkdir -p "$cwdrepo/.github"
: >"$cwdrepo/.github/ci-mode"
assert_status 7 "check exits 7 when only the cwd repository has ci-mode" sh -c "cd '$cwdrepo' && env -u PROCESS_CI_MODE '$nocm/.method/scripts/setup-repo.sh' --check"
assert_contains "$(last_output)" "missing: CI mode" "check names the missing CI mode"
assert_contains "$(last_output)" "PROCESS_CI_MODE" "check cites the variable"
assert_contains "$(last_output)" "setup-repo.sh --ci-mode" "check cites the setup step that records it"
assert_eq "" "$(gh_calls | grep -E 'variable set' || true)" "check writes nothing for the CI mode"
: >"$FAKE_GH_LOG"
assert_status 0 "--ci-mode pr records the variable" "$SETUP" --ci-mode pr
assert_contains "$(gh_calls)" "variable set PROCESS_CI_MODE" "records PROCESS_CI_MODE"
assert_status 2 "--ci-mode refuses a value that is not push or pr" "$SETUP" --ci-mode weekly
fake_setup ok

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

# FHDumont/ai-engineering-team-template#335: .gitignore must have .worktrees/ and .process/; --check names the missing line, the setup appends only those.
fake_setup ok
gic="$(make_repo)"
copy_scripts "$gic"
mkdir -p "$gic/.github"
cp "$REPO"/.github/labels.tsv "$REPO"/.github/bots.tsv "$gic/.github/"
: >"$gic/.github/ci-mode"
gi="$gic/.gitignore"; GSETUP="$gic/.method/scripts/setup-repo.sh"
printf '.process/\n' >"$gi"
assert_status 7 "check exits 7 when .gitignore lacks .worktrees/" "$GSETUP" --check
assert_contains "$(last_output)" "missing: .gitignore line .worktrees/" "check names .worktrees/"
assert_not_contains "$(last_output)" ".gitignore line .process/" "check does not name the line that is there"
printf '.worktrees/\n' >"$gi"
assert_status 7 "check exits 7 when .gitignore lacks .process/" "$GSETUP" --check
assert_contains "$(last_output)" "missing: .gitignore line .process/" "check names .process/"
printf 'keep-me' >"$gi"
assert_status 0 "setup appends the missing lines" "$GSETUP" --only gitignore
assert_eq "keep-me
.worktrees/
.process/" "$(cat "$gi")" "only the missing lines are appended at the end, nothing removed"
cp "$gi" "$TMP/gi.after"
assert_status 0 "setup on a complete .gitignore" "$GSETUP" --only gitignore
assert_eq "$(cat "$TMP/gi.after")" "$(cat "$gi")" "a .gitignore that has both lines does not change"
finish
