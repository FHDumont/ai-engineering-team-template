#!/usr/bin/env bash
# setup and plan stay inside the 4-question card limit (issue #116).
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

plan="$(cat "$REPO/.claude/skills/plan/SKILL.md")"
setup="$(cat "$REPO/.claude/skills/setup/SKILL.md")"
assert_contains "$plan" "num quadro só" "plan still grills in one card when it fits"
assert_not_contains "$plan" "quadro por decisão" "plan does not make one card per decision"
assert_contains "$plan" "quadros seguidos no mesmo turno" "plan splits a card that would pass 4 questions"
assert_contains "$setup" "quadros seguidos no mesmo turno" "setup splits a card that would pass 4 questions"
assert_contains "$plan" "4 perguntas" "plan names the limit of 4 questions"
assert_contains "$setup" "4 perguntas" "setup names the limit of 4 questions"
words="$(wc -w <"$REPO/.claude/skills/plan/SKILL.md" | tr -d ' ')"
[ "$words" -le 400 ] && ok || bad "plan skill has $words words (allowed up to 400)"

finish
