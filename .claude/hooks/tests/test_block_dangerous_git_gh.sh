#!/usr/bin/env bash
# Tests for the block-dangerous-git.sh hook: GraphQL merge, branch protection, settings deny rules, large input.
# shellcheck source=.claude/hooks/tests/dangerous_git_common.sh
source "$(dirname "$0")/dangerous_git_common.sh"

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
python3 -c 'import json, sys; print(json.dumps({"tool_input": {"command": "echo " + "a " * 1500000 + "; git push --force"}, "cwd": sys.argv[1]}))' "$repo" >"$TMP/big2.json"
start="$(date +%s)"
assert_status 2 "large input still checked" sh -c "'$HOOK' <'$TMP/big.json'"
assert_status 2 "very large input fails closed" sh -c "'$HOOK' <'$TMP/big2.json'"
elapsed=$(( $(date +%s) - start ))
limit="$(slots_test_timeout)"
if [ "$elapsed" -ge "$limit" ]; then
  bad "large inputs hung past the hang limit of ${limit}s (measured ${elapsed}s)"
else
  ok
fi
if [ "$elapsed" -ge 10 ]; then
  echo "warn: over-expected hook-large-inputs $elapsed 10"
fi
assert_status 2 "invalid JSON fails closed" sh -c "echo 'not json' | '$HOOK'"

finish
