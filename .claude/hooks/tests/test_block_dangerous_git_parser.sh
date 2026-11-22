#!/usr/bin/env bash
# Tests for the block-dangerous-git.sh hook: cd and -C to main, envelopes, alternative ways of calling, comments, config.
# shellcheck source=.claude/hooks/tests/dangerous_git_common.sh
source "$(dirname "$0")/dangerous_git_common.sh"

blocked "$repo" "cd $main_repo && git commit -m x"
allowed "$main_repo" "cd $repo && git commit -m x"
blocked "$repo" "cd \"$main_repo\" && git commit -m x"
blocked "$repo" "cd '$main_repo' && git commit -m x"
blocked "$main_repo" 'git checkout -- README.md && git commit -m x'
allowed "$repo" 'git checkout -- README.md && git commit -m x'
blocked "$repo" "bash -c \"git commit --no-verify -m 'x'\""
# Nested envelopes: the text inside inner quotes is a command too.
blocked "$repo" "bash -c \"bash -c 'git push --force'\""
blocked "$repo" "sh -c 'eval \"git reset --hard\"'"
blocked "$repo" "bash -c \"eval 'gh pr merge 6 --admin'\""
blocked "$repo" "bash -c \"cd '$main_repo' && git commit -m x\""
blocked "$repo" "bash -c \"git -C '$main_repo' commit -m x\""
# A quoted message inside -c is still text, not a flag.
allowed "$repo" "bash -c \"git commit -m 'fix: drop -n flag'\""
# Strings that contain "cd"/"-C" do not hide the command in the middle.
blocked "$repo" "echo 'a -C ' ; git push --force ; echo ' b'"
blocked "$repo" "echo 'a cd ' && git reset --hard && echo ' b'"
blocked "$repo" "echo 'a cd ' && gh pr merge 6 --admin && echo ' b'"
blocked "$repo" "echo 'a cd ' && git add -A && echo ' b'"
blocked "$repo" "echo 'a cd ' && git commit --no-verify -m x && echo ' b'"
blocked "$repo" "git commit -m 'msg -C ' && git push --force && echo ' end'"
blocked "$repo" "git log --grep 'x -C ' ; git push -f ; echo ' y'"
blocked "$main_repo" "echo 'a cd ' && git commit -m x && echo ' b'"
# Alternative ways of calling git/gh and of hiding the command.
blocked "$repo" 'env git push --force'
blocked "$repo" 'command git reset --hard'
blocked "$repo" '"git" push -f'
blocked "$repo" '/usr/bin/git add -A'
blocked "$repo" 'bash -e -c "git push --force"'
blocked "$repo" '/bin/bash -c "git reset --hard"'
blocked "$repo" 'echo "git push --force" | bash'
blocked "$repo" 'git reset "--hard"'
blocked "$repo" 'git push origin "+main"'
blocked "$repo" 'git add "."'
blocked "$repo" 'git add :/'
blocked "$repo" 'git add -Av'
blocked "$repo" 'git stage -A'
blocked "$repo" 'git push --mirror'
blocked "$repo" 'git -c "core.hooksPath=/dev/null" commit -m x'
blocked "$repo" 'git config core.hookspath /tmp/x'
blocked "$repo" 'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null git commit -m x'
blocked "$repo" '"gh" pr merge 6 --rebase'
blocked "$repo" 'env gh pr merge 6 --rebase'
blocked "$repo" 'gh api -X PUT repos/o/r/pulls/6/merge'
blocked "$repo" "pushd $main_repo >/dev/null && git commit -m x"
blocked "$repo" "cd -- $main_repo && git commit -m x"
heredoc_msg="git commit -m \"\$(cat <<'MSG'
feat: it's a heredoc message mentioning git push --force
MSG
)\""
allowed "$repo" "$heredoc_msg"
allowed "$repo" 'git log --oneline -n 5'
allowed "$repo" 'gh pr view 6 --json labels'
allowed "$repo" 'git checkout -b feat/issue-9-x'
allowed "$repo" 'gh api repos/o/r/pulls/6'
allowed "$repo" 'git push -u origin feat/issue-1-x 2>&1 | tail -3'
# Comments, ANSI-C quotes and a heredoc with an odd quote hide nothing.
blocked "$repo" "git push --force # don't"
blocked "$repo" "git reset --hard # it's ok"
blocked "$repo" "gh pr merge 6 --admin # it's ok"
blocked "$repo" "git add -A # it's"
blocked "$repo" "git commit --no-verify -m x # it's"
blocked "$main_repo" "git commit -m x # wip: main's fix"
blocked "$repo" "echo \$'it\\'s' && git push --force"
odd_heredoc="git commit --no-verify -m \"\$(cat <<'MSG'
feat: a \" odd quote
MSG
)\""
blocked "$repo" "$odd_heredoc"
allowed "$repo" "git status # it's fine"
allowed "$repo" "git log --oneline # don't worry"
# Other git config syntaxes.
blocked "$repo" 'git config set core.hooksPath /dev/null'
blocked "$repo" 'git config unset core.hooksPath'
blocked "$repo" 'git config --file .git/config core.hooksPath /dev/null'
blocked "$repo" 'git config -f .git/config core.hooksPath /dev/null'
blocked "$repo" 'git --config-env=core.hooksPath=X commit -m x'
allowed "$repo" 'git config --get core.hooksPath'
allowed "$repo" 'git config get core.hooksPath'
finish
