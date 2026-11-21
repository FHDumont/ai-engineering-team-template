#!/usr/bin/env bash
# Tests for the block-phase-commit.sh hook.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/../../../scripts/tests/lib.sh"
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

# Forms of a commit by the session that opened the phase.
blocked mgr "$wt" 'git commit -m "feat: x"'
blocked mgr "$wt/src" 'git commit -m "feat: x"'
blocked mgr "$main" "cd $wt && git commit -m x"
blocked mgr "$main" "git -C \"$wt\" commit -m x"
blocked mgr "$wt" '/usr/bin/git commit -m x'
blocked mgr "$wt" 'git -c user.name=a commit -m x'
blocked mgr "$TMP/main dir" "git -C \"$spwt\" commit -m x"
blocked mgr "$main" 'cd .worktrees && cd issue-7 && git commit -m x'
blocked mgr "$main" "d=$wt; git -C \$d commit -m x"
blocked mgr "$wt" "sh -c 'git commit -m x'"
blocked mgr "$TMP" "cd $(basename "$main")/.worktrees && git -C issue-7 commit -m x"
blocked mgr "$wt" $'git add a\ngit commit -m x'
blocked mgr "$main" "cd $wt"$'\ngit commit -m x'
blocked mgr "$main" "cd $wt && git commit -F - <<'M'"$'\nfix: don\'t break\nM'
blocked mgr "$wt" $'git add a\ngit commit -F - <<\'M\'\nfix: don\'t\nM'
blocked mgr "$main" "echo x"$'\ncd '"$wt"$'\ngit commit -F - <<\'M\'\ndon\'t\nM'
blocked mgr "$wt" $'echo "a\\"b"\ngit commit -m x'
blocked mgr "$main" "(cd $wt && git commit -m x)"
blocked mgr "$main" "pushd $wt && git commit -m x"

# Every other way of writing history in the worktree.
for sub in 'cherry-pick abc' 'revert abc' 'merge other' 'rebase main' 'am x.patch' \
  'commit-tree abc -m x' 'update-ref refs/heads/feat/issue-7-x abc' 'pull' 'reset HEAD~1' 'push origin HEAD'; do
  blocked mgr "$wt" "git $sub"
done

# Wrappers, blocks and nested shells (the parser of block-dangerous-git.sh).
blocked mgr "$wt" 'env git commit -m x'
blocked mgr "$wt" 'command git commit -m x'
blocked mgr "$wt" 'time git commit -m x'
blocked mgr "$wt" 'if true; then git commit -m x; fi'
blocked mgr "$wt" '{ git commit -m x; }'
blocked mgr "$wt" "bash -lc 'git commit -m x'"
blocked mgr "$wt" 'eval "git commit -m x"'
blocked mgr "$wt" 'echo "git commit -m x" | sh'
blocked mgr "$main" "cd -- $wt && git commit -m x"
blocked mgr "$wt" $'git \\\ncommit -m x'
blocked mgr "$main" "git --git-dir=$wt/.git --work-tree=$wt commit -m x"
blocked mgr "$main" "git --git-dir $main/.git/worktrees/issue-7 commit -m x"
blocked mgr "$main" "GIT_DIR=$wt/.git GIT_WORK_TREE=$wt git commit -m x"
blocked mgr "$main" "export GIT_WORK_TREE=$wt; git commit -m x"
blocked mgr "$main/.worktrees/issue-7-r2" 'git commit -m x'
blocked mgr "$main" "git -C .worktrees/issue-7-r2 cherry-pick abc"

# A push of the phase branch by the session that opened the phase, from any directory.
blocked mgr "$main" 'git push origin feat/issue-7-x'
blocked mgr "$main" 'git push -u origin feat/issue-7-x'
blocked mgr "$main" 'git push --set-upstream origin feat/issue-7-x'
blocked mgr "$main" 'git push origin HEAD:feat/issue-7-x'
blocked mgr "$main" 'git push origin main:feat/issue-7-x'
blocked mgr "$main" 'git push origin HEAD:refs/heads/feat/issue-7-x'
blocked mgr "$main" 'git push origin refs/heads/feat/issue-7-x'
blocked mgr "$main" 'git push origin :feat/issue-7-x'
blocked mgr "$main" 'git push origin --delete feat/issue-7-x'
blocked mgr "$main" 'git push origin main feat/issue-7-x'
blocked mgr "$main" 'git push -o ci.skip origin feat/issue-7-x'
blocked mgr "$main" 'git push origin feat/issue-7-x-r2'
blocked mgr "$main/other" 'git push origin feat/issue-7-x'
blocked mgr "$TMP" "git -C $main push origin feat/issue-7-x"
blocked mgr "$TMP" "git -C $main/other push -u origin HEAD:feat/issue-7-x"
blocked mgr "$TMP/main dir" 'git push origin feat/issue-7-x'
blocked mgr "$TMP" "git -C \"$TMP/main dir\" push origin feat/issue-7-x"
blocked mgr "$main" 'git push origin --all'
blocked mgr "$main" 'git push --all origin'
blocked mgr "$main" 'git push origin --branches'
blocked mgr "$main" 'git push origin --mirror'
blocked mgr "$TMP" "git -C $main push --all"
blocked mgr "$main" "git push origin 'refs/heads/*:refs/heads/*'"
blocked mgr "$main" 'git checkout -b feat/issue-7-z && git push'
blocked mgr "$main" 'git switch -c feat/issue-7-z && git push -u origin HEAD'
# The command forms the parser of block-dangerous-git.sh reads.
blocked mgr "$main" $'git push \\\n  origin feat/issue-7-x'
blocked mgr "$main" 'env git push origin feat/issue-7-x'
blocked mgr "$main" 'env GIT_TRACE=1 git push origin feat/issue-7-x'
blocked mgr "$main" '(git push origin feat/issue-7-x)'
blocked mgr "$TMP" "(cd $main && git push origin feat/issue-7-x)"
blocked mgr "$main" 'git push origin "feat/issue-7-x"'
blocked mgr "$main" "git push 'origin' 'HEAD:feat/issue-7-x'"
blocked mgr "$main" 'git fetch origin && git push origin feat/issue-7-x'
blocked mgr "$main" "bash -c 'git push origin feat/issue-7-x'"
blocked mgr "$main" 'eval "git push origin feat/issue-7-x"'
blocked mgr "$main" '/usr/bin/git push origin feat/issue-7-x'
blocked mgr "$main" 'b=feat/issue-7-x; git push origin $b'
blocked mgr "$main" 'git push origin "$BRANCH"'
# Not blocked: a branch that is not of a phase this session opened, and the child session.
allowed mgr "$main" 'git push origin gen-docs/2026-01-20'
allowed mgr "$main" 'git push -u origin HEAD:gen-docs/2026-01-20'
allowed mgr "$main" 'git push'
allowed mgr "$main" 'git push origin HEAD'
allowed mgr "$main" 'git push origin feat/issue-8-y'
allowed mgr "$main" 'git push origin v1.0 refs/tags/issue-7'
allowed child "$main" 'git push origin feat/issue-7-x'
allowed child "$main" 'git push -u origin HEAD:feat/issue-7-x'
allowed child "$wt" 'git push -u origin feat/issue-7-x'
allowed child "$wt" 'git push'
allowed child "$main" 'git push origin --all'

# The locks read CLAUDE_CODE_SESSION_ID and the trace: no session sets them or writes the trace.
blocked child "$wt" 'CLAUDE_CODE_SESSION_ID=x git commit -m x'
blocked child "$wt" 'env -u CLAUDE_CODE_SESSION_ID git commit -m x'
blocked child "$main" 'unset CLAUDE_CODE_SESSION_ID'
blocked child "$main" "export PROCESS_EVENTS_FILE=$TMP/other.jsonl"
blocked child "$main" "PROCESS_EVENTS_FILE=$TMP/other.jsonl scripts/close-phase.sh --merge"
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
