#!/usr/bin/env bash
# Tests of gen-docs.sh in a sandbox: the single generation of CHANGELOG.md and
# ROADMAP.md enters main through a PR that holds only those two files.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

repo="$(make_repo)"
copy_scripts "$repo"
printf '.worktrees/\n' >"$repo/.gitignore"
git -C "$repo" add scripts .gitignore
git -C "$repo" commit --quiet -m "chore: scripts"
remote="$TMP/remote.git"
git clone --quiet --bare "$repo" "$remote"
git -C "$repo" remote add origin "$remote"
git -C "$repo" fetch --quiet origin
GEN="$repo/scripts/gen-docs.sh"
BRANCH="gen-docs/$(git -C "$repo" rev-parse origin/main | cut -c1-12)"

# Fake GitHub: one merged phase PR and one open issue feed the generators; the PR
# of gen-docs.sh is #30. FAKE_FILES: the files GitHub shows in it. FAKE_MERGES=0:
# the merge never happens. FAKE_STATUS: the review/independent state read back.
cat >"$TMP/handler.sh" <<H
case "\$*" in
  "pr list --state merged"*) echo '[{"number":7,"title":"feat: seven","labels":[{"name":"type:feature"}],"mergedAt":"2026-01-10T10:00:00Z","url":"https://x/pull/7","headRefName":"feat/issue-7-x"}]' ;;
  "issue list"*) echo '[{"number":9,"title":"Nine","labels":[{"name":"area:scripts"}],"url":"https://x/issues/9"}]' ;;
  "pr list"*"--state open"*) [ -f "$TMP/created" ] && echo 30 ;;
  "pr create"*) touch "$TMP/created" ;;
  "pr view 30"*"--json files,headRefOid"*) printf '%s\n' \${FAKE_FILES:-CHANGELOG.md ROADMAP.md} | jq -Rcn --arg s "\$(git -C "$remote" rev-parse "$BRANCH")" '{files: [inputs | {path: .}], headRefOid: \$s}' ;;
  "api repos/owner/repo/commits/"*"/status"*) echo "\${FAKE_STATUS:-success}" ;;
  "pr merge 30"*) touch "$TMP/merge-asked" ;;
  "pr view 30"*"--json state"*) if [ -f "$TMP/merge-asked" ] && [ "\${FAKE_MERGES:-1}" = 1 ]; then echo MERGED; else echo OPEN; fi ;;
esac
H
use_fake_gh "$TMP/handler.sh"
run() { # run <exit code> <description> [VAR=value...]
  local want="$1" what="$2"
  shift 2
  : >"$FAKE_GH_LOG"; rm -f "$TMP/merge-asked"
  assert_status "$want" "$what" env ${1+"$@"} sh -c "cd '$repo' && '$GEN' --interval 0"
}

# A PR with any other file: no review status, no merge.
run 1 "refuses a PR that holds more than the generated files" FAKE_FILES="CHANGELOG.md scripts/close-phase.sh"
assert_contains "$(last_output)" "scripts/close-phase.sh" "names the file that is not generated"
assert_not_contains "$(gh_calls)" "statuses" "no review status on a PR with other files"
assert_not_contains "$(gh_calls)" "pr merge" "no merge of a PR with other files"
sha="$(git -C "$remote" rev-parse "$BRANCH")"
assert_eq "CHANGELOG.md
ROADMAP.md" "$(git -C "$remote" diff --name-only main "$BRANCH")" "the pushed branch holds only the two generated files"
assert_contains "$(git -C "$remote" show "$BRANCH:CHANGELOG.md")" "feat: seven" "the changelog comes from the merged PRs"
assert_contains "$(git -C "$remote" show "$BRANCH:ROADMAP.md")" "Nine" "the roadmap comes from the open issues"

# Rerun on the open PR: status read back, merge by rebase, merge read back.
run 1 "a review status that is not read back stops before the merge" FAKE_STATUS=missing
assert_not_contains "$(gh_calls)" "pr merge" "no merge without the status read back"
run 3 "a PR that does not merge in time exits 3" FAKE_MERGES=0
run 0 "merges the PR of generated files"
calls="$(gh_calls)"
assert_not_contains "$calls" "pr create" "the rerun opens no second PR"
assert_contains "$calls" "api -X POST repos/owner/repo/statuses/$sha -f state=success -f context=review/independent" "publishes review/independent on the PR head"
assert_contains "$calls" "pr merge 30 --repo owner/repo --auto --rebase --delete-branch" "merges by rebase"
assert_not_contains "$calls" "--admin" "never as admin"
assert_contains "$calls" "pr view 30 --repo owner/repo --json state" "reads the merge back"
assert_eq 1 "$(printf '%s\n' "$calls" | grep -c 'pr view 30 .*--json files,headRefOid')" "files and head SHA come from one read"
assert_not_contains "$calls" "--json headRefOid" "no separate read of the head SHA"
assert_contains "$(last_output)" "PR #30 merged" "says the PR is merged"
[ ! -e "$repo/.worktrees/gen-docs" ] && ok || bad "the worktree is removed"
assert_eq "" "$(git -C "$repo" branch --list 'gen-docs/*')" "the local branch is removed"

# Generated files already on main: nothing to do, no PR.
git -C "$repo" push --quiet origin "$sha:main"
rm -f "$TMP/created"
run 0 "up to date makes no PR"
assert_contains "$(last_output)" "up to date" "says the files are up to date"
assert_not_contains "$(gh_calls)" "pr create" "no PR when nothing changed"
[ ! -e "$repo/.worktrees/gen-docs" ] && ok || bad "no worktree left when up to date"

# A phase never runs it: only the main checkout does.
git -C "$repo" worktree add --quiet -b feat/issue-5-x "$repo/.worktrees/issue-5" origin/main
assert_status 1 "refuses to run from a phase worktree" sh -c "cd '$repo/.worktrees/issue-5' && scripts/gen-docs.sh --interval 0"
assert_contains "$(last_output)" "main checkout" "says who runs it"
assert_status 0 "--help works" sh -c "'$GEN' --help"
finish
