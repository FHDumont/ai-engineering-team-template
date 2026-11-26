#!/usr/bin/env bash
# The update guide of the template README (FHDumont/ai-engineering-team-template#207); each adopter has its own README, so this stays template-only.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/../lib.sh"
readme="$(cat "$REPO/README.md")"
assert_contains "$readme" "trazer o padrão do template quando faltar" "the guide brings the default of repository-owned files"
assert_contains "$readme" "o job \`tests\` roda em todo PR" "the guide names the old STATE sentence"
assert_contains "$readme" "missing-label" "the guide adds the missing method labels"
assert_contains "$readme" "suíte fica vermelha" "the guide warns about the old settings.json"
finish
