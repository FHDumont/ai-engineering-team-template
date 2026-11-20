#!/usr/bin/env bash
# Tests for the block-phase-edit.sh hook.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/../../../scripts/tests/lib.sh"
HOOK="$REPO/.claude/hooks/block-phase-edit.sh"

run() { # run <session_id> <cwd> <tool> <path>
  jq -cn --arg s "$1" --arg d "$2" --arg t "$3" --arg p "$4" \
    '{session_id: $s, cwd: $d, tool_name: $t, tool_input: (if $t == "NotebookEdit" then {notebook_path: $p} else {file_path: $p} end)}' | "$HOOK"
}

main="$(make_repo)"
git -C "$main" worktree add --quiet -b feat/issue-7-x "$main/.worktrees/issue-7"
git -C "$main" worktree add --quiet -b feat/issue-7-x-r2 "$main/.worktrees/issue-7-r2"
mkdir -p "$main/.process"
wt="$main/.worktrees/issue-7"
trace="$main/.process/events.jsonl"
jq -cn '{event: "phase_opened", session_id: "mgr", issue: "7"}' >"$trace"

assert_status 2 "blocks Edit by the session that opened the phase" run mgr "$main" Edit "$wt/a.txt"
assert_contains "$(last_output)" "opened phase #7" "explains"
assert_status 2 "blocks Write" run mgr "$main" Write "$wt/src/new.txt"
assert_status 2 "blocks NotebookEdit" run mgr "$main" NotebookEdit "$wt/n.ipynb"
assert_status 2 "blocks a relative path from the worktree" run mgr "$wt" Edit "a.txt"
assert_status 2 "blocks a path with .. into the worktree" run mgr "$main" Edit "$main/other/../.worktrees/issue-7/a.txt"
assert_status 2 "blocks the redo worktree issue-7-r2" run mgr "$main" Write "$main/.worktrees/issue-7-r2/a.txt"
assert_status 0 "allows the child session" run child "$main" Edit "$wt/a.txt"
assert_status 0 "allows the opener outside the worktree" run mgr "$main" Edit "$main/README.md"
assert_status 2 "no session writes the trace by hand" run child "$main" Write "$trace"
assert_status 2 "blocks without a session id" run "" "$main" Edit "$wt/a.txt"
echo '{"event": "phase_op' >>"$trace"
assert_status 2 "blocks with a corrupted trace line" run child "$main" Edit "$wt/a.txt"
rm -f "$trace"
assert_status 2 "blocks without a trace" run child "$main" Edit "$wt/a.txt"
assert_status 0 "a path outside any phase passes without a trace" run child "$main" Edit "$main/README.md"
finish
