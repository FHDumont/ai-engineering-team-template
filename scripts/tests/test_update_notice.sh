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
# #207: every new step reaches the repository through the notice (its README is its own).
for f in required-checks headless update-notice.md label-areas.tsv ci-extra-jobs; do
  assert_contains "$notice" ".github/$f" "the notice names $f"
done
assert_contains "$notice" "trazer o padrão do template quando faltar" "the notice brings the default of repository files"
assert_contains "$notice" "o job \`tests\` roda em todo PR" "the notice names the old STATE sentence"
assert_contains "$notice" "check-docs.sh" "the notice cites the check-docs message"
assert_contains "$notice" "missing-label" "the notice adds the missing method labels"
assert_contains "$notice" "scripts/tests/template/" "the notice leaves the template-only tests out"
assert_contains "$notice" ".claude/settings.json" "the notice says the new settings.json comes after the owner ok"
assert_contains "$notice" "suíte fica vermelha" "the notice warns the suite fails without the new settings.json"
assert_contains "$notice" "validate.sh --full" "the notice asks for the full suite"
finish
