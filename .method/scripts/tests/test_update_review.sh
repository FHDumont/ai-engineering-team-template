#!/usr/bin/env bash
# The update review names what it did not read (#129).
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"
rev="$(cat "$REPO/.claude/agents/close-reviewer.md")"
skill="$(cat "$REPO/.claude/skills/close-phase/SKILL.md")"
assert_contains "$rev" "method-diff.sh" "the reviewer compares an update with the template"
assert_contains "$rev" "Não lido" "the opinion names what was not read"
assert_contains "$rev" "emenda" "the reviewer separates an owner amendment from the child"
assert_contains "$skill" "Não lido" "the merge card shows what was not read"
finish
