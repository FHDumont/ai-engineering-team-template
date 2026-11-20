#!/usr/bin/env bash
# Tests for the block-card-title.sh hook.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/../../../scripts/tests/lib.sh"
HOOK="$REPO/.claude/hooks/block-card-title.sh"

run() { # run <session_id> <cwd> <question>...
  local s="$1" d="$2"
  shift 2
  jq -cn --arg s "$s" --arg d "$d" '{session_id: $s, cwd: $d, tool_name: "AskUserQuestion",
    tool_input: {questions: ($ARGS.positional | map({question: ., header: "h", options: []}))}}' --args "$@" | "$HOOK"
}

main="$(make_repo)"
mkdir -p "$main/.process"
trace="$main/.process/events.jsonl"
ev() { jq -cn --arg e "$1" --arg s "$2" --arg i "$3" '{event: $e, session_id: $s, issue: $i}' >>"$trace"; }

# No phase open: setup, triage and the first planning ask freely.
assert_status 0 "allows any card with no phase open" run mgr "$main" "Aceita o quadro do GitHub Projects?"

git -C "$main" worktree add --quiet -b feat/issue-7-x "$main/.worktrees/issue-7"
git -C "$main" worktree add --quiet -b feat/issue-8-y "$main/.worktrees/issue-8"
ev phase_opened mgr 7
ev phase_opened mgr 8
ev phase_session child 7
wt="$main/.worktrees/issue-7"

# The session of the phase: the card starts with the number of its own phase.
assert_status 0 "allows the card of the phase session" run child "$wt" "Fase #7 — fim coerente: autoriza o merge do PR #12?"
assert_status 2 "blocks a card of the phase session without the title" run child "$wt" "Autoriza o merge do PR #12?"
assert_contains "$(last_output)" "Fase #7 — <title>:" "says how the card starts"
assert_status 2 "blocks a card of the phase session with another phase" run child "$wt" "Fase #8 — outra: autoriza o merge?"
assert_status 2 "blocks when one of the questions has no title" run child "$wt" "Fase #7 — fim coerente: autoriza?" "E o deploy?"
assert_status 2 "blocks the number without the title" run child "$wt" "Fase #7 — "
assert_status 2 "blocks a hyphen in place of the dash" run child "$wt" "Fase #7 - fim coerente: autoriza?"

# The main session, with a phase open: the card names a phase.
assert_status 0 "allows the card of the main session that names a phase" run mgr "$main" "Fase #8 — modelo: arquivar a sessão agora?"
assert_status 2 "blocks a card of the main session without a phase" run mgr "$main" "Arquivar a sessão agora?"
assert_contains "$(last_output)" "a phase is open (#7, #8)" "names the open phases"
# phase_session recorded by the session that opened the phase does not make it a phase session.
ev phase_session mgr 7
assert_status 0 "the opener is not tied to the phase it opened" run mgr "$main" "Fase #8 — modelo: arquivar a sessão agora?"

assert_status 0 "allows a call with no question" sh -c "echo '{\"session_id\":\"child\",\"cwd\":\"$wt\",\"tool_input\":{}}' | '$HOOK'"
assert_contains "$(jq -r '.hooks.PreToolUse[] | select(.matcher == "AskUserQuestion") | .hooks[].command' "$REPO/.claude/settings.json" 2>/dev/null || true)" \
  "block-card-title.sh" "settings.json runs the hook on every AskUserQuestion"
assert_status 2 "blocks invalid input" sh -c "echo 'not json' | '$HOOK'"
finish
