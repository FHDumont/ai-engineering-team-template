#!/usr/bin/env bash
# Shared preparation of the test_block_phase_commit_*.sh files (not a test itself):
# the hook, the run/blocked/allowed helpers and a checkout with phase worktrees and its trace.
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../.method/scripts/tests/lib.sh"
HOOK="$REPO/.claude/hooks/block-phase-commit.sh"

run() { # run <session_id> <cwd> <command>
  jq -cn --arg s "$1" --arg d "$2" --arg c "$3" '{session_id: $s, tool_input: {command: $c}, cwd: $d}' | "$HOOK"
}
blocked() { assert_status 2 "blocks: $3" run "$1" "$2" "$3"; }
allowed() { assert_status 0 "allows: $3" run "$1" "$2" "$3"; }

# A real checkout with phase worktrees: the hook reads the trace of the main checkout.
main="$(make_repo)"
git -C "$main" worktree add --quiet -b feat/issue-7-x "$main/.worktrees/issue-7"
git -C "$main" worktree add --quiet -b feat/issue-7-x-r2 "$main/.worktrees/issue-7-r2"
git -C "$main" worktree add --quiet -b feat/issue-8-y "$main/.worktrees/issue-8"
mkdir -p "$main/.worktrees/issue-7/src" "$main/other" "$main/.process"
wt="$main/.worktrees/issue-7"
trace="$main/.process/events.jsonl"
good_trace() {
  jq -cn '{event: "phase_opened", session_id: "mgr", issue: "7"}' >"$trace"
  jq -cn '{event: "phase_opened", session_id: "mgr8", issue: "8"}' >>"$trace"
}
good_trace
# The old hook read the trace from this variable; the new one ignores it.
export PROCESS_EVENTS_FILE="$trace"

# A second checkout whose path has a space.
mkdir -p "$TMP/main dir"
git -C "$TMP/main dir" init --quiet -b main
git -C "$TMP/main dir" -c user.email=t@example.org -c user.name=t -c commit.gpgsign=false commit --quiet --allow-empty -m "chore: seed"
spwt="$TMP/main dir/.worktrees/issue-7"
git -C "$TMP/main dir" worktree add --quiet -b feat/issue-7-x "$spwt"
mkdir -p "$TMP/main dir/.process"
cp "$trace" "$TMP/main dir/.process/events.jsonl"
