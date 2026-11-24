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
# #213 (#216, #217): the notice is generated from the interval; the gate label comes from close-phase.sh.
assert_contains "$notice" "method-diff.sh --notice" "the notice points to the generated list"
assert_contains "$notice" '`check-docs.sh` da origem' "the notice asks to check the docs with the origin limits"
assert_contains "$notice" "close-phase.sh" "the notice says the gate label enters at the merge"
out="$(cd "$REPO" && "$SCRIPTS/method-diff.sh" --template "$REPO" --from HEAD --to HEAD | grep ' .github/update-notice.md$' || true)"
assert_not_contains "$out" "repo-owned" "the notice is text of the method, not repo-owned"
assert_contains "$(cat "$REPO/.github/method-files.txt")" ".github/update-notice.md" "the notice is in the method manifest"
assert_contains "$notice" ".process/template" "the notice says where the template checkout is (#215)"
assert_contains "$notice" "fetch-template.sh" "the notice names fetch-template.sh"
finish
