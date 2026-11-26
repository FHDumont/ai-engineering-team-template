#!/usr/bin/env bash
# Rule 1 of AGENTS.md is a full sentence and says the setup is pre-approved (issue #148).
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

rule="$(grep -E '^1\. ' "$REPO/AGENTS.md")"
assert_contains "$rule" "pré-aprovado" "rule 1 says the setup is pre-approved"
assert_contains "$rule" ".method/scripts/setup-repo.sh --check" "rule 1 still requires a clean setup check"
assert_contains "$rule" "O dono nunca roda script" "rule 1 still says the owner never runs a method script"
words="$(wc -w <"$REPO/AGENTS.md" | tr -d ' ')"
# The limits have one source: the "limit AGENTS.md" line of check-docs.sh.
read -r min max <<<"$(sed -n 's/^limit AGENTS.md \([0-9]*\) \([0-9]*\)$/\1 \2/p' "$SCRIPTS/check-docs.sh")"
[ -n "${max:-}" ] && [ "$words" -ge "$min" ] && [ "$words" -le "$max" ] && ok || bad "AGENTS.md has $words words (allowed ${min:-?}-${max:-?} in check-docs.sh)"

finish
