#!/usr/bin/env bash
# Tests of end-check.sh in a sandbox: one test per leftover that fails the end.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

repo="$(make_repo)"
copy_scripts "$repo"
printf '.worktrees/\n.process/\n' >"$repo/.gitignore"
ISSUES='[{"number":30,"title":"Aberta","labels":[{"name":"area:scripts"}],"url":"https://x/30"}]'
echo "$ISSUES" >"$TMP/issues.json"
(cd "$repo" && python3 scripts/gen-roadmap.py --input "$TMP/issues.json" --output ROADMAP.md >/dev/null)
git -C "$repo" add scripts .gitignore ROADMAP.md
git -C "$repo" commit --quiet -m "chore: scripts"
git clone --quiet --bare "$repo" "$TMP/remote.git"
git -C "$repo" remote add origin "$TMP/remote.git"
git -C "$repo" fetch --quiet origin
CHECK="$repo/scripts/end-check.sh"

# Fake GitHub. FAKE_PRS: JSON of the open PRs. FAKE_ISSUES: JSON of the open issues.
# FAKE_RUNS: JSON of the deploy runs.
cat >"$TMP/handler.sh" <<H
jq_arg() { printf '%s' "\$*" | sed -n 's/.*--jq //p'; }
case "\$*" in
  "pr list"*) echo "\${FAKE_PRS:-[]}" | jq -r "\$(jq_arg "\$@")" ;;
  "issue list"*"number,title,labels,url"*) echo "\${FAKE_ISSUES:-\$(cat "$TMP/issues.json")}" ;;
  "issue list"*) echo "\${FAKE_ISSUES:-\$(cat "$TMP/issues.json")}" | jq -r "\$(jq_arg "\$@")" ;;
  "run list"*) echo "\${FAKE_RUNS:-[]}" ;;
  "variable list"*) [ -z "\${FAKE_MODE:-}" ] || echo PROCESS_BRANCH_MODE ;;
esac
H
use_fake_gh "$TMP/handler.sh"
check() { # check <exit code> <description> [VAR=value...] [-- end-check flags]
  local want="$1" what="$2"
  shift 2
  assert_status "$want" "$what" env "$@" sh -c "cd '$repo' && '$CHECK' \$CHECK_FLAGS"
}
fails_with() { # fails_with <description> <text> [VAR=value...]
  local what="$1" text="$2"
  shift 2
  check 1 "fails with $what" "$@"
  assert_contains "$(last_output)" "fail: $text" "names $what"
}

assert_status 0 "--help works" "$CHECK" --help
assert_contains "$(last_output)" "Usage: end-check.sh" "--help shows the usage"
check 0 "a clean end passes"
assert_contains "$(last_output)" "ok: end-check" "says the end is clean"
assert_not_contains "$(gh_calls)" "workflow run" "end-check dispatches nothing"
assert_not_contains "$(last_output)" "mode: unprotected" "protected mode: no mode note"
check 0 "the unprotected mode is not an error" FAKE_MODE=1
assert_contains "$(last_output)" "mode: unprotected" "unprotected mode: named in the ok line"

# CI of origin/main: green passes, red names the run, in progress says to wait, absent follows phase-start.
check 0 "a green CI of main passes" FAKE_BASE_CI=green
fails_with "a red CI of main" "CI of origin/main" FAKE_BASE_CI=red
assert_contains "$(last_output)" "actions/runs/3" "red CI names the run"
check 1 "CI of main still running" FAKE_BASE_CI=running
assert_contains "$(last_output)" "still running" "in-progress CI is named"
assert_contains "$(last_output)" "wait for it" "in-progress CI says to wait"
fails_with "an absent CI of main with no voucher" "no check 'CI'" FAKE_BASE_CI=absent FAKE_BASE_PR=none

# Extra local branch of a phase still fails. A branch the phase did not create is a warning.
git -C "$repo" branch feat/issue-5-x
fails_with "an extra local branch" "extra local branch (feat/issue-5-x)"
git -C "$repo" branch -D feat/issue-5-x >/dev/null
git -C "$repo" branch notes
check 0 "a local branch the phase did not create does not fail" 
assert_contains "$(last_output)" "warn: local branch the phase did not create (notes)" "names the branch and does not require deleting it"
assert_contains "$(last_output)" "do not delete" "forbids deleting a branch the phase did not create"
git -C "$repo" branch -D notes >/dev/null

# Extra worktree of a phase still fails. A worktree the phase did not create is a warning.
git -C "$repo" worktree add --quiet --detach "$repo/.worktrees/issue-5" main
fails_with "an extra worktree" "extra worktree ($repo/.worktrees/issue-5)"
git -C "$repo" worktree remove --force "$repo/.worktrees/issue-5"
mkdir -p "$repo/.claude/worktrees"
git -C "$repo" worktree add --quiet --detach "$repo/.claude/worktrees/other" main
check 0 "a worktree the phase did not create does not fail"
assert_contains "$(last_output)" "warn: worktree the phase did not create ($repo/.claude/worktrees/other)" "names the worktree and does not require deleting it"
git -C "$repo" worktree remove --force "$repo/.claude/worktrees/other"

# Registry that is not empty.
printf '5\tfeat/issue-5-x\t%s\n' "$repo/.worktrees/issue-5" >"$repo/.worktrees/parallel-active.tsv"
fails_with "a registry that is not empty" "$repo/.worktrees/parallel-active.tsv is not empty (#5)"
: >"$repo/.worktrees/parallel-active.tsv"
check 0 "an empty registry file passes"

# Remote branch with no open PR; with its PR open it is not a leftover.
git -C "$repo" push --quiet origin main:refs/heads/feat/issue-6-y
fails_with "a remote branch with no open PR" "remote branch with no open PR (feat/issue-6-y)"
check 0 "a remote branch with an open PR passes" FAKE_PRS='[{"number":14,"headRefName":"feat/issue-6-y"}]'
git -C "$repo" push --quiet origin --delete feat/issue-6-y

# Spec of a closed issue; a spec that cites an open issue stays.
mkdir -p "$repo/docs/specs"
printf '# Spec\n\nFase #29.\n' >"$repo/docs/specs/old.md"
git -C "$repo" add docs
git -C "$repo" commit --quiet -m "docs: spec"
git -C "$repo" push --quiet origin main
fails_with "a spec of a closed issue" "spec of closed issues (docs/specs/old.md cites no open issue)"
printf '# Spec\n\nFases #29 e #30.\n' >"$repo/docs/specs/old.md"
git -C "$repo" commit --quiet -m "docs: spec of an open issue" docs/specs/old.md
git -C "$repo" push --quiet origin main
check 0 "a spec that cites an open issue passes"

# An untracked file the phase did not create is a warning, not a failure.
echo x >"$repo/loose.txt"
check 0 "an untracked file the phase did not create does not fail"
assert_contains "$(last_output)" "warn: untracked file in the main checkout (loose.txt)" "names the untracked file"
assert_contains "$(last_output)" "do not delete a file this phase did not create" "forbids deleting it to go green"
rm "$repo/loose.txt"
echo edit >>"$repo/README.md"
fails_with "an uncommitted change" "uncommitted change in the main checkout (README.md)"
git -C "$repo" checkout --quiet -- README.md

# Local main behind origin/main.
git -C "$repo" push --quiet origin "$(git -C "$repo" commit-tree -p main -m 'chore: ahead' 'main^{tree}')":refs/heads/main
fails_with "a local main that is not at origin/main" "local main is not at origin/main"
git -C "$repo" fetch --quiet origin main
git -C "$repo" merge --quiet --ff-only origin/main

# ROADMAP.md different from the generated one.
fails_with "a stale ROADMAP.md" "ROADMAP.md differs from the generated one" \
  FAKE_ISSUES='[{"number":30,"title":"Aberta","labels":[],"url":"https://x/30"},{"number":31,"title":"Nova","labels":[],"url":"https://x/31"}]'
assert_contains "$(last_output)" "gen-docs.sh" "says who regenerates it"

# Deploy not checked: a deploy workflow with no successful run on main.
mkdir -p "$repo/.github/workflows" "$repo/app"
printf '# deploy-paths: app/\non:\n  workflow_dispatch:\n' >"$repo/.github/workflows/deploy-app.yml"
echo v1 >"$repo/app/index.html"
git -C "$repo" add .github app
git -C "$repo" commit --quiet -m "feat: app"
git -C "$repo" push --quiet origin main
SHA="$(git -C "$repo" rev-parse HEAD)"
fails_with "a deploy that was not checked" "deploy not checked"
assert_contains "$(last_output)" "scripts/deploy.sh" "says who deploys"
assert_eq 0 "$(gh_calls | grep -c '^workflow run' || true)" "the check dispatches nothing"
check 0 "a deploy read back on the SHA passes" \
  FAKE_RUNS="$(jq -cn --arg s "$SHA" '[{databaseId: 70, headSha: $s, status: "completed", conclusion: "success", url: "https://x/70"}]')"
fails_with "a deploy still running" "deploy not checked" \
  FAKE_RUNS="$(jq -cn --arg s "$SHA" '[{databaseId: 70, headSha: $s, status: "in_progress", conclusion: "", url: "https://x/70"}]')"

# --offline: only what does not need GitHub.
: >"$FAKE_GH_LOG"
check 0 "--offline skips the GitHub checks" CHECK_FLAGS=--offline
assert_eq "" "$(gh_calls)" "--offline calls no gh"
git -C "$repo" branch feat/issue-5-x
check 1 "--offline still fails with an extra branch" CHECK_FLAGS=--offline
git -C "$repo" branch -D feat/issue-5-x >/dev/null

# --issue N: the end of one phase. Leftovers of other phases do not count.
git -C "$repo" worktree add --quiet -b feat/issue-8-z "$repo/.worktrees/issue-8" main
check 0 "the phase scope ignores another phase" CHECK_FLAGS="--issue 7"
check 1 "the phase scope fails with the worktree of the phase" CHECK_FLAGS="--issue 8"
assert_contains "$(last_output)" "fail: worktree of phase #8 still exists" "names the worktree"
assert_contains "$(last_output)" "fail: local branch of phase #8 still exists (feat/issue-8-z)" "names the local branch"
git -C "$repo" worktree remove --force "$repo/.worktrees/issue-8"
git -C "$repo" branch -D feat/issue-8-z >/dev/null
git -C "$repo" push --quiet origin main:refs/heads/feat/issue-8-z
check 1 "the phase scope fails with the remote branch of the phase" CHECK_FLAGS="--issue 8"
assert_contains "$(last_output)" "fail: remote branch of phase #8 still exists (feat/issue-8-z)" "names the remote branch"
check 1 "the phase scope fails with the PR of the phase open" CHECK_FLAGS="--issue 8" FAKE_PRS='[{"number":15,"headRefName":"feat/issue-8-z"}]'
assert_contains "$(last_output)" "fail: PR of phase #8 is still open (#15)" "names the open PR"
check 0 "issue 80 is not issue 8" CHECK_FLAGS="--issue 80"
git -C "$repo" push --quiet origin --delete feat/issue-8-z
printf '8\tfeat/issue-8-z\t%s\n' "$repo/.worktrees/issue-8" >"$repo/.worktrees/parallel-active.tsv"
check 1 "the phase scope fails with the registry line of the phase" CHECK_FLAGS="--issue 8"
: >"$repo/.worktrees/parallel-active.tsv"
check 0 "a phase with nothing left passes" CHECK_FLAGS="--issue 8" \
  FAKE_RUNS="$(jq -cn --arg s "$SHA" '[{databaseId: 70, headSha: $s, status: "completed", conclusion: "success", url: "https://x/70"}]')"
finish
