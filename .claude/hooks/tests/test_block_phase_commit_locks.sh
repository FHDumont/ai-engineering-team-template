#!/usr/bin/env bash
# Tests for the block-phase-commit.sh hook: session locks, what stays allowed, fail closed.
# shellcheck source=.claude/hooks/tests/phase_commit_common.sh
source "$(dirname "$0")/phase_commit_common.sh"

# The locks read CLAUDE_CODE_SESSION_ID and the trace: no session sets them or writes the trace.
blocked child "$wt" 'CLAUDE_CODE_SESSION_ID=x git commit -m x'
blocked child "$wt" 'env -u CLAUDE_CODE_SESSION_ID git commit -m x'
blocked child "$main" 'unset CLAUDE_CODE_SESSION_ID'
blocked child "$main" "export PROCESS_EVENTS_FILE=$TMP/other.jsonl"
blocked child "$main" "PROCESS_EVENTS_FILE=$TMP/other.jsonl .method/scripts/close-phase.sh --merge"
blocked child "$main" "echo '{\"event\":\"phase_session\"}' >> .process/events.jsonl"
blocked child "$main" "echo x | tee -a $main/.process/events.jsonl"
allowed child "$main" 'echo "$CLAUDE_CODE_SESSION_ID"'
allowed child "$main" 'jq -c . .process/events.jsonl'
allowed child "$main" 'jq -c . .process/events.jsonl > .process/events.jsonl.bak'

# What stays allowed.
allowed child "$main" "cd $wt && git commit -m x"
allowed child "$wt" 'git commit -m "feat: x"'
allowed child "$wt" 'git cherry-pick abc'
allowed mgr "$main/other" 'git commit -m "feat: x"'
allowed mgr "$TMP" "cd $(basename "$main")/other && git -C . commit -m x"
allowed mgr "$main/.worktrees/issue-8" 'git commit -m "feat: x"'
allowed mgr "$wt" 'git status'
allowed mgr "$wt" 'git hash-object README.md'
allowed mgr "$wt" 'git diff-index HEAD'
allowed mgr "$wt" 'git check-attr -a README.md'
allowed mgr "$wt" 'git worktree list'
allowed mgr "$wt" 'git config --get core.hooksPath'
blocked mgr "$wt" 'git hash-object -w README.md'
assert_contains "$(last_output)" "hash-object" "the refusal names the git subcommand"
blocked mgr "$wt" 'git worktree add ../elsewhere'
blocked mgr "$wt" 'git config user.name someone'
allowed mgr "$main" "git -C $wt log --oneline -3"
allowed mgr "$main" "git -C $wt diff origin/main...HEAD"
allowed mgr "$wt" 'git branch --show-current'
allowed mgr "$wt" $'cat <<M\nit\'s\nM'

# A redirected trace opens nothing.
jq -cn '{event: "phase_opened", session_id: "someone", issue: "7"}' >"$TMP/forged.jsonl"
export PROCESS_EVENTS_FILE="$TMP/forged.jsonl"
blocked mgr "$wt" 'git commit -m "feat: x"'
export PROCESS_EVENTS_FILE="$trace"

# Fails closed when it cannot tell who opened the phase.
assert_status 2 "blocks without a session id" run "" "$wt" 'git commit -m x'
assert_status 2 "blocks a phase branch push without a session id" run "" "$main" 'git push origin feat/issue-7-x'
echo '{"event": "phase_opened", "session_id": "mg' >>"$trace"
assert_status 2 "blocks with a corrupted trace line" run child "$wt" 'git commit -m x'
assert_status 2 "blocks a phase branch push with a corrupted trace line" run child "$main" 'git push origin feat/issue-7-x'
assert_status 2 "blocks push --all with a corrupted trace line" run child "$main" 'git push origin --all'
jq -cn '{event: "phase_opened", session_id: "mgr8", issue: "8"}' >"$trace"
assert_status 2 "blocks without a phase_opened event of the issue" run child "$wt" 'git commit -m x'
rm -f "$trace"
assert_status 2 "blocks without a trace" run child "$wt" 'git commit -m x'
assert_status 2 "blocks a phase branch push without a trace" run child "$main" 'git push origin HEAD:feat/issue-7-x'
assert_status 2 "blocks push --all without a trace" run child "$main" 'git push origin --all'
assert_status 0 "a push of a branch that is not of a phase passes without a trace" run child "$main" 'git push origin gen-docs/2026-01-20'
mkdir -p "$TMP/plain/.worktrees/issue-7"
assert_status 2 "blocks outside a git repository" run child "$TMP/plain/.worktrees/issue-7" 'git commit -m x'
assert_status 0 "a read-only command passes without a trace" run child "$wt" 'git status'
finish
