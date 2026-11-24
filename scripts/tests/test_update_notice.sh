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
# #190: the update records the CI mode; #195: no post-merge test phase; the proof is one local update.
assert_contains "$notice" ".github/ci-mode" "the notice asks to record the CI mode in the update PR"
assert_not_contains "$notice" "fase \`test\`" "the notice does not ask for a post-merge test phase"
assert_not_contains "$notice" "três" "the notice does not ask for three proofs"
assert_contains "$notice" "uma prova local" "the notice asks one local proof"
assert_contains "$notice" "fecha no merge" "the update issue closes at the merge"
assert_contains "$notice" "primeira fase normal" "the first normal phase is the proof"
assert_contains "$notice" "needs-gate-review" "the notice names the label of the gate class"
readme="$(cat "$REPO/README.md")"
upd="$(printf '%s\n' "$readme" | sed -n '/^## Atualizar um repositório que já usa o método/,/^## Rodar e testar/p')"
assert_contains "$upd" ".github/ci-mode" "the update guide records the CI mode"
assert_contains "$upd" "docs/repo-notes.md" "the update guide creates docs/repo-notes.md (#193)"
assert_contains "$upd" ".github/method-files.txt" "the update guide says a script only of the repo goes in the manifest (#188)"
assert_not_contains "$upd" "fase \`test\`" "the update guide asks for no post-merge test phase (#195)"
finish
