#!/usr/bin/env bash
# Tests of the prompt-phase-entry.sh hook and of the texts that keep "executar #n" on one path.
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "$0")/../../../.method/scripts/tests/lib.sh"
HOOK="$REPO/.claude/hooks/prompt-phase-entry.sh"

run() { jq -cn --arg p "$1" '{hook_event_name: "UserPromptSubmit", session_id: "s", prompt: $p}' | "$HOOK"; }

for p in "executar #95" "Executar #95 agora" "  executar a issue 95" "executar issue #95" "executar 95"; do
  assert_status 0 "never blocks: $p" run "$p"
  out="$(last_output)"
  assert_contains "$out" ".method/scripts/phase-start.sh 95" "points to phase-start.sh: $p"
  assert_contains "$out" "plan skill" "points to the plan skill: $p"
done
for p in "fechar fase" "pode executar #95 depois?" "executar a fase" "o que falta na #95?"; do
  assert_status 0 "never blocks: $p" run "$p"
  assert_eq "" "$(last_output)" "says nothing for: $p"
done
assert_status 0 "empty input passes" sh -c "echo '{}' | '$HOOK'"

# The hook is wired to UserPromptSubmit.
assert_contains "$(jq -r '.hooks.UserPromptSubmit[].hooks[].command' "$REPO/.claude/settings.json" 2>/dev/null || true)" "prompt-phase-entry.sh" "settings.json runs the hook on every prompt"

# Skills: "executar #n" loads plan, never execute.
front() { sed -n '2,/^---$/p' "$REPO/.claude/skills/$1/SKILL.md"; }
assert_contains "$(front plan)" '"executar #n"' 'plan has the phrase "executar #n"'
assert_contains "$(front plan)" '"executar a issue"' 'plan has the phrase "executar a issue"'
assert_eq "" "$(front execute | grep -i 'executar' || true)" 'execute has no "executar" in its front matter'
assert_eq "" "$(grep -n '^1a\.' "$REPO/.claude/skills/execute/SKILL.md" || true)" "execute has no step 1a (plan and execute in one session)"
assert_contains "$(cat "$REPO/.claude/skills/plan/SKILL.md")" "phase-start.sh" "plan opens the phase with phase-start.sh"
assert_eq "" "$(grep -ln 'new-phase.sh\|open-parallel.sh' "$REPO/AGENTS.md" "$REPO"/.claude/skills/*/SKILL.md || true)" "AGENTS.md and the skills name one entry only"
assert_contains "$(cat "$REPO/AGENTS.md")" "phase-start.sh" "AGENTS.md names phase-start.sh"
finish
