#!/usr/bin/env bash
# Tests for the block-phase-commit.sh hook: pushes of the phase branch.
# shellcheck source=.claude/hooks/tests/phase_commit_common.sh
source "$(dirname "$0")/phase_commit_common.sh"

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

finish
