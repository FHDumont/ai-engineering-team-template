#!/usr/bin/env bash
# Rule 1 of AGENTS.md is a full sentence and says the setup is pre-approved (issue #148).
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

rule="$(grep -E '^1\. ' "$REPO/AGENTS.md")"
assert_contains "$rule" "pré-aprovado" "rule 1 says the setup is pre-approved"
assert_contains "$rule" "scripts/setup-repo.sh --check" "rule 1 still requires a clean setup check"
assert_contains "$rule" "O dono nunca roda script" "rule 1 still says the owner never runs a method script"
words="$(wc -w <"$REPO/AGENTS.md" | tr -d ' ')"
[ "$words" -ge 300 ] && [ "$words" -le 500 ] && ok || bad "AGENTS.md has $words words (allowed 300-500)"

finish
