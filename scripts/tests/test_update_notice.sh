#!/usr/bin/env bash
# The update notice has the sections auto-label requires (#149).
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"
notice="$(cat "$REPO/.github/update-notice.md")"
for section in "Objetivo" "Pronto quando" "Arquivos ou áreas afetadas" "Prioridade sugerida" "Decisões do dono"; do
  assert_contains "$notice" "## $section" "the notice has $section"
done
assert_contains "$notice" "Commit de origem" "the notice names the origin commit"
assert_contains "$notice" "Commit de destino" "the notice names the destination commit"
assert_contains "$notice" "Permissões novas" "the notice lists new permissions"
assert_contains "$notice" "Gasto" "the notice lists cost"
assert_contains "$notice" "Ações destrutivas" "the notice lists destructive actions"
finish
