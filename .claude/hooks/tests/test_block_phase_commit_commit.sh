#!/usr/bin/env bash
# Tests for the block-phase-commit.sh hook: commits, other ways of writing history, wrappers.
# shellcheck source=.claude/hooks/tests/phase_commit_common.sh
source "$(dirname "$0")/phase_commit_common.sh"

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

finish
