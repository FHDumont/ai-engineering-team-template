#!/usr/bin/env bash
# Tests of the refusal of phase-start.sh and open-issue.sh on a repository that is not
# configured (setup-repo.sh --check is in test_setup_check.sh).
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"
: >"$TMP/none.sh"
use_fake_gh "$TMP/none.sh"

# phase-start.sh refuses before anything else, and --no-check does not skip it.
repo="$(make_repo)"
copy_scripts "$repo"
# phase-start.sh checks the setup against the labels file of the repository.
mkdir -p "$repo/.github" && cp "$REPO/.github/labels.tsv" "$repo/.github/labels.tsv"
printf '.worktrees/\n.process/\n' >"$repo/.gitignore"
git -C "$repo" add .method .gitignore .github
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
    assert_status 7 "phase-start refuses ($state, '$flags')" sh -c "cd '$repo' && .method/scripts/phase-start.sh 7 $flags"
    assert_contains "$(last_output)" 'say "configurar o repo"' "phase-start says the phrase ($state, '$flags')"
    assert_contains "$(last_output)" "missing:" "phase-start says what is missing ($state, '$flags')"
  done
done
fake_setup freeplan
assert_status 7 "phase-start refuses on a plan without branch protection and no recorded mode" sh -c "cd '$repo' && .method/scripts/phase-start.sh 7 --no-check"
assert_contains "$(last_output)" "missing: protection of main" "phase-start: plan message"
assert_eq "" "$(ls "$repo/.worktrees" 2>/dev/null || true)" "no worktree is created before the setup"
assert_eq "" "$(git -C "$repo" branch --list '*issue-*')" "no branch is created before the setup"
assert_eq "" "$(cat "$PROCESS_EVENTS_FILE" 2>/dev/null || true)" "no event is recorded before the setup"
fake_setup ok
assert_status 0 "phase-start opens the phase on a configured repository" sh -c "cd '$repo' && .method/scripts/phase-start.sh 7 --no-check"
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
