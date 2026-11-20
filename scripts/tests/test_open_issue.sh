#!/usr/bin/env bash
# Tests of open-issue.sh: template body, required sections and labels.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"
OPEN="$SCRIPTS/open-issue.sh"

full=(--section "Objetivo" "Corrigir o fuso." --section "Pronto quando" "- [ ] teste"
      --section "Arquivos ou áreas afetadas" "area:app" --section "Prioridade sugerida" "média"
      --section "Como reproduzir" "Abrir a página; esperado BRT, atual UTC.")

out="$("$OPEN" --type bug --title "Datas no fuso errado" "${full[@]}" --end auto-close --dry-run)"
assert_contains "$out" "## Como reproduzir" "keeps template titles"
assert_contains "$out" "labels: type:bug,area:app,priority:medium,end:auto-close" "labels from template, body and options"
assert_not_contains "$out" "<!--" "guide comments are replaced"

out="$("$OPEN" --type bug --title x "${full[@]}" --priority high --dry-run)"
assert_contains "$out" "priority:high" "explicit priority wins"
assert_not_contains "$out" "priority:medium" "body priority dropped when explicit"

# With no label option: it must work (regression: it used to exit 1 silently).
assert_status 0 "works without label options" "$OPEN" --type finding --title x --section Objetivo o \
  --section "Pronto quando" "- [ ] y" --section "Arquivos ou áreas afetadas" "docs/" --section "Achado em" "PR #6 · tamanho: small" --dry-run
assert_contains "$(last_output)" "labels: finding,area:docs,size:small" "labels from template and body only"

assert_status 1 "refuses missing required section" "$OPEN" --type bug --title x --section Objetivo y --dry-run
assert_contains "$(last_output)" "missing required sections" "names the missing sections"
assert_status 1 "refuses unknown section" "$OPEN" --type feature --title x --section Inventada y --dry-run
assert_status 2 "needs --type" "$OPEN" --title x --dry-run

# Fake gh: the created issue keeps its labels in $TMP/labels; no board by default.
cat >"$TMP/handler.sh" <<'H'
case "$1 $2" in
  "issue create")
    [ -z "${FAKE_NO_URL:-}" ] || exit 0
    : >"$TMP/labels"
    while [ $# -gt 0 ]; do
      case "$1" in --label) [ "$2" = "${FAKE_DROP_LABEL:-}" ] || echo "$2" >>"$TMP/labels"; shift 2 ;; *) shift ;; esac
    done
    echo "https://github.com/owner/repo/issues/9" ;;
  "issue view") cat "$TMP/labels" ;;
  "auth status") printf "  - Token scopes: %s\n" "${FAKE_SCOPES-'project', 'repo'}" ;;
  "variable list") [ -z "${FAKE_BOARD:-}" ] || echo "$FAKE_BOARD" ;;
  "project item-add") echo ITEM ;;
  "project view") echo PID ;;
  "project field-list") echo '{"fields":[{"name":"Status","id":"FID","options":[{"name":"Todo","id":"OT"}]}]}' ;;
  "project item-edit") [ -n "${FAKE_STATUS_LOST:-}" ] || echo Todo >"$TMP/status" ;;
  "api graphql") case "$*" in *fieldValueByName*) cat "$TMP/status" 2>/dev/null || true ;; esac ;;
esac
H
export TMP
use_fake_gh "$TMP/handler.sh"
out="$("$OPEN" --type feature --title "Filtro" --section Objetivo "Filtrar." --section "Pronto quando" "- [ ] ok" \
  --section "Arquivos ou áreas afetadas" "area:app" --section "Prioridade sugerida" "média" --group app --group novo)"
assert_eq "https://github.com/owner/repo/issues/9" "$out" "prints the issue URL"
calls="$(gh_calls)"
assert_not_contains "$calls" "label create group:app" "known group label is never recreated"
assert_not_contains "$calls" "--force" "never overwrites labels"
assert_contains "$calls" "--label type:feature --label roadmap" "applies template labels"
assert_contains "$calls" "--label group:app" "applies group label"
assert_contains "$calls" "label create group:novo --repo owner/repo --color d4c5f9 --description Grupo de afinidade" "creates an unknown group label"

# Failures: gh exiting 0 does not prove the issue exists.
create=("$OPEN" --type feature --title "Filtro" --section Objetivo "Filtrar." --section "Pronto quando" "- [ ] ok"
        --section "Arquivos ou áreas afetadas" "area:app" --section "Prioridade sugerida" "média")
assert_status 1 "fails when gh issue create returns no URL" env FAKE_NO_URL=1 "${create[@]}"
assert_contains "$(last_output)" "returned no issue URL" "says no URL came back"
assert_status 1 "fails when gh issue create fails" env FAKE_GH_FAIL='^issue create' "${create[@]}"
assert_status 1 "fails when a label is missing on read back" env FAKE_DROP_LABEL=roadmap "${create[@]}"
assert_contains "$(last_output)" "without the label roadmap" "names the missing label"

# Board: with no board configured it tries nothing and does not warn.
: >"$FAKE_GH_LOG"
assert_status 0 "no board: creates the issue" "${create[@]}"
assert_eq "https://github.com/owner/repo/issues/9" "$(last_output)" "no board: prints only the URL, no warning"
assert_not_contains "$(gh_calls)" "project " "no board: never calls gh project"
# With a board: the write is read back; a failure exits != 0 with the cause and the fix command.
rm -f "$TMP/status"
assert_status 0 "board: sets Todo and reads it back" env FAKE_BOARD=7 "${create[@]}"
assert_contains "$(gh_calls)" "--single-select-option-id OT" "board: moves the item to Todo"
assert_status 1 "board without the project scope fails" env FAKE_BOARD=7 FAKE_SCOPES="'repo'" "${create[@]}"
out="$(last_output)"
assert_contains "$out" "the gh token has no 'project' scope" "missing scope: says the cause"
assert_contains "$out" "fix: gh auth login -h github.com -p https -w -s gist,project,read:org,repo,workflow" "missing scope: says the fix command"
assert_contains "$out" "issue #9 was created, but it is not on the board" "missing scope: says the issue exists"
assert_status 1 "board write refused by the API fails" env FAKE_BOARD=7 FAKE_GH_FAIL='^project item-edit' FAKE_GH_FAIL_MSG="GraphQL: forbidden" "${create[@]}"
assert_contains "$(last_output)" "the API refused the update: GraphQL: forbidden" "refused write: says the cause"
rm -f "$TMP/status"
assert_status 1 "board write not confirmed on read back fails" env FAKE_BOARD=7 FAKE_STATUS_LOST=1 "${create[@]}"
assert_contains "$(last_output)" "not confirmed on read back" "unconfirmed write: says so"
assert_status 1 "unreadable board variable fails" env FAKE_GH_FAIL='^variable list' "${create[@]}"
assert_contains "$(last_output)" "could not read the repository variable PROCESS_PROJECT_NUMBER" "unreadable variable: says the cause"
finish
