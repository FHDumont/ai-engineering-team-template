#!/usr/bin/env bash
# Tests of the mandatory setup: setup-repo.sh --check, and the refusal of
# phase-start.sh and open-issue.sh on a repository that is not configured.
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
assert_contains "$(last_output)" "missing: protection of main" "plan: names the missing mode"
assert_contains "$(last_output)" 'say "configurar o repo"' "plan: tells to run the setup"
assert_eq "" "$(gh_calls | grep -E '\-X (PUT|PATCH)|variable set' || true)" "plan: check writes nothing"
fake_setup unprotected
assert_status 0 "check passes in the unprotected mode" "$SETUP" --check
assert_contains "$(last_output)" "is configured for the method" "unprotected: configured"
assert_contains "$(last_output)" "mode: unprotected" "unprotected: says the mode"

# phase-start.sh refuses before anything else, and --no-check does not skip it.
repo="$(make_repo)"
copy_scripts "$repo"
# phase-start.sh checks the setup against the labels file of the repository.
mkdir -p "$repo/.github" && cp "$REPO/.github/labels.tsv" "$repo/.github/labels.tsv"
printf '.worktrees/\n.process/\n' >"$repo/.gitignore"
git -C "$repo" add scripts .gitignore .github
git -C "$repo" commit --quiet -m "chore: scripts"
export PROCESS_EVENTS_FILE="$repo/.process/events.jsonl"
git clone --quiet --bare "$repo" "$TMP/remote.git"
git -C "$repo" remote add origin "$TMP/remote.git"
cat >"$TMP/handler.sh" <<'H'
case "$*" in
  "issue view "*"--json state,title,labels"*) echo '{"state":"OPEN","title":"Listar issues","labels":[{"name":"type:feature"}]}' ;;
esac
H
use_fake_gh "$TMP/handler.sh"
mkdir -p "$repo/docs/specs"
printf '# Spec\n\n## Fase #7 — x\n\n1. Etapa. modelo: sonnet · esforço: low · motivo: leve\n' >"$repo/docs/specs/seven.md"
for state in nolabels noprotection offer; do
  fake_setup "$state"
  for flags in "--no-check" "--dry-run" ""; do
    assert_status 7 "phase-start refuses ($state, '$flags')" sh -c "cd '$repo' && scripts/phase-start.sh 7 $flags"
    assert_contains "$(last_output)" 'say "configurar o repo"' "phase-start says the phrase ($state, '$flags')"
    assert_contains "$(last_output)" "missing:" "phase-start says what is missing ($state, '$flags')"
  done
done
fake_setup freeplan
assert_status 7 "phase-start refuses on a plan without branch protection and no recorded mode" sh -c "cd '$repo' && scripts/phase-start.sh 7 --no-check"
assert_contains "$(last_output)" "missing: protection of main" "phase-start: plan message"
assert_eq "" "$(ls "$repo/.worktrees" 2>/dev/null || true)" "no worktree is created before the setup"
assert_eq "" "$(git -C "$repo" branch --list '*issue-*')" "no branch is created before the setup"
assert_eq "" "$(cat "$PROCESS_EVENTS_FILE" 2>/dev/null || true)" "no event is recorded before the setup"
fake_setup ok
assert_status 0 "phase-start opens the phase on a configured repository" sh -c "cd '$repo' && scripts/phase-start.sh 7 --no-check"
assert_eq "issue-7" "$(ls "$repo/.worktrees")" "the worktree is created after the setup"

# open-issue.sh: labels of the method missing give the same message, not the raw gh error.
create=("$SCRIPTS/open-issue.sh" --type finding --title x --section Objetivo o
  --section "Pronto quando" "- [ ] y" --section "Arquivos ou áreas afetadas" "docs/"
  --section "Achado em" "PR #6 · tamanho: small")
fake_setup nolabels
assert_status 7 "open-issue refuses when the labels do not exist" env FAKE_GH_FAIL='^issue create' \
  FAKE_GH_FAIL_MSG="could not add label: 'finding' not found" "${create[@]}"
assert_contains "$(last_output)" 'say "configurar o repo"' "open-issue says the phrase"
assert_contains "$(last_output)" "missing: labels" "open-issue says the labels are missing"
fake_setup ok
assert_status 1 "open-issue keeps its own error when the labels exist" env FAKE_GH_FAIL='^issue create' "${create[@]}"
assert_contains "$(last_output)" "gh issue create failed" "open-issue: own error"
assert_not_contains "$(last_output)" "configurar o repo" "open-issue: no setup message when the labels exist"
finish
