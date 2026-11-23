#!/usr/bin/env bash
# The update review reads adapted files and says what it did not read (#129).
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"
reviewer="$(cat "$REPO/.claude/agents/close-reviewer.md")"
skill="$(cat "$REPO/.claude/skills/close-phase/SKILL.md")"
assert_contains "$reviewer" "method-diff.sh" "the reviewer compares an update with method-diff.sh"
assert_contains "$reviewer" "Não lido" "the opinion names what was not read"
assert_contains "$skill" "Não lido" "the merge question shows what the reviewer did not read"
finish
