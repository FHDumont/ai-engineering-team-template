#!/usr/bin/env bash
# Tests for the block-dangerous-git.sh hook.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/../../../scripts/tests/lib.sh"
HOOK="$REPO/.claude/hooks/block-dangerous-git.sh"

repo="$(make_repo)"
git -C "$repo" switch --quiet -c feat/issue-1-x

run() { # run <cwd> <command>
  jq -cn --arg c "$2" --arg d "$1" '{tool_input: {command: $c}, cwd: $d}' | "$HOOK"
}
blocked() { assert_status 2 "blocks: $2" run "$1" "$2"; }
allowed() { assert_status 0 "allows: $2" run "$1" "$2"; }

blocked "$repo" 'git commit -am "x"'
blocked "$repo" 'git commit -a -m "x"'
blocked "$repo" 'git commit --all -m x'
blocked "$repo" 'git add -A'
blocked "$repo" 'git add .'
blocked "$repo" 'git add --all'
blocked "$repo" 'git status && git add -A'
blocked "$repo" 'git push --force origin x'
blocked "$repo" 'git push -f'
blocked "$repo" 'git push --force-with-lease'
blocked "$repo" 'git push origin +x'
blocked "$repo" 'git reset --hard HEAD~1'
blocked "$repo" 'gh pr merge 3 --admin --rebase'
blocked "$repo" 'gh pr merge 3 --squash'
blocked "$repo" 'gh pr merge 3 --merge'
blocked "$repo" 'gh pr merge 3'
allowed "$repo" 'git commit -m "fix: handle -a and --all in text"'
allowed "$repo" 'git commit --amend -m "x"'
allowed "$repo" 'git commit -uno -m x'
allowed "$repo" 'git commit -mrename'
# -S accepts a glued keyid (-Sabc, -S<keyid>): the rest is the value, not flags.
allowed "$repo" 'git commit -Sabc -m x'
allowed "$repo" 'git commit -S1A2B3C4D -m x'
allowed "$repo" 'git commit -S -m x'
blocked "$repo" 'git commit -S -a -m x'
blocked "$repo" 'git commit -aSabc -m x'
blocked "$repo" 'git commit -mx -n'
allowed "$repo" 'git add scripts/a.sh docs/b.md'
allowed "$repo" 'git push -u origin feat/issue-1-x'
blocked "$repo" 'gh pr merge 3 --auto --rebase --delete-branch'
blocked "$repo" 'gh -R owner/repo pr merge 3 --rebase'
blocked "$repo" 'git commit --no-verify -m x'
blocked "$repo" 'git commit -nm x'
blocked "$repo" 'git -c core.hooksPath=/dev/null commit -m x'
blocked "$repo" 'git config core.hooksPath /tmp/none'
allowed "$repo" 'git config core.hooksPath .githooks'
blocked "$repo" 'git push -fu origin x'
blocked "$repo" 'bash -c "git push --force"'
blocked "$repo" "sh -c 'git reset --hard'"
blocked "$repo" 'git switch main && git commit -m x'
blocked "$repo" 'git checkout main; git commit -m x'
allowed "$repo" 'git switch -c feat/issue-2-y && git commit -m x'
allowed "$repo" 'git push --follow-tags origin x'
allowed "$repo" 'scripts/close-phase.sh --merge'
# Deploy dispatch outside scripts/deploy.sh: gh workflow run, gh run rerun and the
# API endpoints behind them, in every command form the parser reads.
blocked "$repo" 'gh workflow run deploy-example.yml --ref main'
blocked "$repo" 'gh workflow run deploy-example.yml --repo owner/repo --ref main'
blocked "$repo" 'gh -R owner/repo workflow run deploy-example.yml'
blocked "$repo" 'gh run rerun 123'
blocked "$repo" 'gh run rerun --failed 123'
blocked "$repo" 'gh --repo owner/repo run rerun 123'
blocked "$repo" 'gh api -X POST repos/owner/repo/actions/workflows/deploy-example.yml/dispatches -f ref=main'
blocked "$repo" 'gh api repos/owner/repo/dispatches -f event_type=deploy'
blocked "$repo" 'gh api --method POST /repos/owner/repo/actions/runs/123/rerun'
blocked "$repo" 'gh api -X POST repos/owner/repo/actions/runs/123/rerun-failed-jobs'
blocked "$repo" 'gh workflow \
  run deploy-example.yml'
blocked "$repo" 'env GH_REPO=owner/repo gh workflow run deploy-example.yml'
blocked "$repo" 'GH_REPO=owner/repo gh run rerun 123'
blocked "$repo" '(gh workflow run deploy-example.yml)'
blocked "$repo" 'echo "$(gh run rerun 123)"'
blocked "$repo" 'bash -c "gh workflow run deploy-example.yml"'
blocked "$repo" "sh -c 'gh api repos/o/r/actions/workflows/1/dispatches -f ref=main'"
blocked "$repo" 'gh "workflow" "run" deploy-example.yml'
blocked "$repo" "gh 'run' 'rerun' 123"
blocked "$repo" '/opt/homebrew/bin/gh workflow run deploy-example.yml'
blocked "$repo" 'git status && gh workflow run deploy-example.yml'
blocked "$repo" 'echo "gh workflow run deploy-example.yml" | bash'
blocked "$repo" 'eval "gh run rerun 123"'
allowed "$repo" 'scripts/deploy.sh'
allowed "$repo" 'gh run list --workflow deploy-example.yml'
allowed "$repo" 'gh run view 123 --json status,conclusion,url'
allowed "$repo" 'gh run watch 123'
allowed "$repo" 'gh workflow list'
allowed "$repo" 'gh workflow view deploy-example.yml'
allowed "$repo" 'gh api repos/owner/repo/actions/runs/123'
allowed "$repo" 'echo "gh workflow run is only for scripts/deploy.sh"'
allowed "$repo" 'gh issue create --title "gh workflow run without the gate" --body "gh run rerun"'
# Merge through GraphQL and any write on branch protection: the gate has no shortcut.
blocked "$repo" "gh api graphql -f query='mutation { mergePullRequest(input: {pullRequestId: \"PR_x\"}) { clientMutationId } }'"
blocked "$repo" "gh api graphql -F id=PR_x -f query='mutation(\$id: ID!) { enablePullRequestAutoMerge(input: {pullRequestId: \$id}) { clientMutationId } }'"
blocked "$repo" "gh api graphql --raw-field query='mutation { enqueuePullRequest(input: {pullRequestId: \"PR_x\"}) { clientMutationId } }'"
blocked "$repo" "gh api graphql -f query='mutation { mergeBranch(input: {repositoryId: \"R\", base: \"main\", head: \"x\"}) { clientMutationId } }'"
printf 'mutation { mergePullRequest(input: {pullRequestId: "PR_x"}) { clientMutationId } }\n' >"$repo/q.graphql"
blocked "$repo" 'gh api graphql -F query=@q.graphql'
blocked "$repo" 'gh api graphql -F query=@missing.graphql'
blocked "$repo" 'gh api graphql --input q.json'
blocked "$repo" 'echo "{}" | gh api graphql --input -'
blocked "$repo" "gh api graphql -f query='mutation { updateBranchProtectionRule(input: {branchProtectionRuleId: \"B\"}) { clientMutationId } }'"
blocked "$repo" "gh api graphql -f query='mutation { deleteBranchProtectionRule(input: {branchProtectionRuleId: \"B\"}) { clientMutationId } }'"
blocked "$repo" 'gh api -X PUT repos/o/r/branches/main/protection --input p.json'
blocked "$repo" 'gh api --method PATCH repos/o/r/branches/main/protection/required_status_checks -f strict=false'
blocked "$repo" 'gh api -XDELETE repos/o/r/branches/main/protection'
blocked "$repo" 'gh api --method=DELETE repos/o/r/branches/main/protection/enforce_admins'
blocked "$repo" 'gh api -X POST repos/o/r/branches/main/protection/enforce_admins'
blocked "$repo" 'gh api repos/o/r/branches/main/protection/required_status_checks/contexts -f "contexts[]=x"'
blocked "$repo" 'gh api repos/o/r/branches/main/protection --input p.json'
blocked "$repo" 'bash -c "gh api -X DELETE repos/o/r/branches/main/protection"'
allowed "$repo" 'gh api repos/o/r/branches/main/protection'
allowed "$repo" 'gh api -X GET repos/o/r/branches/main/protection --jq .required_status_checks'
allowed "$repo" "gh api graphql -f query='query { repository(owner: \"o\", name: \"r\") { pullRequest(number: 3) { mergeable } } }'"
allowed "$repo" 'gh issue create --title "mergePullRequest by graphql" --body "gh api -X PUT branches/main/protection is blocked"'
settings="$(jq -r '.permissions.deny[]' "$REPO/.claude/settings.json")"
for rule in 'Bash(gh api *mergePullRequest*)' 'Bash(gh api *enablePullRequestAutoMerge*)' 'Bash(gh api *enqueuePullRequest*)' \
  'Bash(gh api *pulls/*/merge*)' 'Bash(gh api *BranchProtectionRule*)' \
  'Bash(gh api *-X PUT*branches/*/protection*)' 'Bash(gh api *--method PUT*branches/*/protection*)' \
  'Bash(gh api *branches/*/protection*-X PUT*)' 'Bash(gh api *branches/*/protection*--method PUT*)' \
  'Bash(gh api *-X PATCH*branches/*/protection*)' 'Bash(gh api *-X POST*branches/*/protection*)' \
  'Bash(gh api *branches/*/protection* -f *)' 'Bash(gh api *branches/*/protection* --input *)'; do
  assert_contains "$settings" "$rule" "settings.json denies $rule"
done
for rule in 'Bash(gh workflow run*)' 'Bash(gh * workflow run*)' 'Bash(gh run rerun*)' 'Bash(gh * run rerun*)' \
  'Bash(gh api *dispatches*)' 'Bash(gh api *rerun*)'; do
  assert_contains "$settings" "$rule" "settings.json denies $rule"
done
allowed "$repo" 'ls -la'
assert_status 0 "ignores empty input" sh -c "echo '{}' | '$HOOK'"
python3 -c 'import json, sys; print(json.dumps({"tool_input": {"command": "git push --force; echo " + "a" * 1200000}, "cwd": sys.argv[1]}))' "$repo" >"$TMP/big.json"
start="$(date +%s)"
assert_status 2 "large input still checked" sh -c "'$HOOK' <'$TMP/big.json'"
python3 -c 'import json, sys; print(json.dumps({"tool_input": {"command": "echo " + "a " * 1500000 + "; git push --force"}, "cwd": sys.argv[1]}))' "$repo" >"$TMP/big2.json"
assert_status 2 "very large input fails closed" sh -c "'$HOOK' <'$TMP/big2.json'"
assert_eq yes "$([ $(( $(date +%s) - start )) -lt 10 ] && echo yes)" "large inputs are checked fast (no timeout = fail open)"
assert_status 2 "invalid JSON fails closed" sh -c "echo 'not json' | '$HOOK'"

# `cd` to a checkout on main before the commit.
main_repo="$(make_repo)"
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
# Alternative ways to call git/gh and to hide the command.
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
# Blocks, prefixes, abbreviations and command substitution.
blocked "$repo" '{ git push -f; }'
blocked "$repo" 'if true; then git push -f; fi'
blocked "$repo" '! git push -f'
blocked "$repo" 'nice -n 5 git push -f'
blocked "$repo" 'timeout 30 git reset --hard'
blocked "$repo" 'env -u HOME git push -f'
blocked "$repo" 'bash -o pipefail -c "git push -f"'
blocked "$repo" "bash <<<'git push -f'"
blocked "$repo" 'git commit --no-verif -m x'
blocked "$repo" 'git push --forc origin x'
blocked "$repo" 'echo "$(git push -f)"'
blocked "$repo" 'echo `git reset --hard`'
blocked "$repo" 'gh pr -R o/r merge 6'
# `<<` inside quotes or a comment, heredoc to a shell by pipe/source.
blocked "$repo" "echo \"<<EOF\"
git push --force
EOF"
blocked "$repo" "echo x # <<EOF
git reset --hard
EOF"
blocked "$repo" "git commit -m \"x <<EOF\"
git push --force
EOF"
blocked "$repo" "cat <<'EOF' | bash
git push --force
EOF"
blocked "$repo" "cat <<'EOF' | sh
git commit --no-verify -m x
EOF"
blocked "$repo" "source /dev/stdin <<'EOF'
git reset --hard
EOF"
allowed "$repo" "cat > notes.md <<'EOF'
Nunca rode git push --force nem git reset --hard; it's \" odd
EOF"
allowed "$repo" "python3 - <<'EOF'
import subprocess  # git push --force aparece só como texto
EOF"
# Line continuation and file checkout.
blocked "$repo" "git \\
push --force"
blocked "$repo" "git commit \\
  --no-verify -m x"
allowed "$repo" 'git checkout main README.md && git commit -m x'
# Half-quoted delimiter, `\ #`, pipe at the end of the line, prefixes, many commits.
blocked "$repo" "cat <<E\"OF\"
EOF
git push --force
E"
blocked "$repo" "cat <<'E'OF
EOF
git reset --hard
E"
blocked "$repo" "cat <<E\\OF
EOF
git add -A
E"
blocked "$repo" 'echo \ # ; git push --force'
blocked "$repo" 'echo a\ #; git reset --hard'
blocked "$repo" "cat <<'EOF' |
git push --force
EOF
bash"
blocked "$repo" 'caffeinate -i /usr/bin/git push --force'
blocked "$repo" 'arch -arm64 /usr/bin/git reset --hard'
blocked "$repo" 'watch /usr/bin/git add -A'
allowed "$repo" 'echo git push --force'
many="$(python3 -c 'print("git commit -m x; " * 3000 + "git push --force")')"
start="$(date +%s)"
blocked "$repo" "$many"
assert_eq yes "$([ $(( $(date +%s) - start )) -lt 10 ] && echo yes)" "many commits are checked fast"

# Quoted paths, with a space.
spaced="$TMP/dir com espaço"; mkdir -p "$spaced"; git clone --quiet "$main_repo" "$spaced/main"
blocked "$repo" "cd \"$spaced/main\" && git commit -m x"
blocked "$repo" "git -C \"$spaced/main\" commit -m x"
blocked "$repo" "git -C '$main_repo' commit -m x"

# A commit on main is blocked.
git -C "$repo" switch --quiet main
blocked "$repo" 'git commit -m "x"'
blocked "$repo" "git -C $repo commit -m x"
assert_contains "$(run "$repo" 'git commit -m x' 2>&1 || true)" "never commit on main" "explains the main block"
finish
