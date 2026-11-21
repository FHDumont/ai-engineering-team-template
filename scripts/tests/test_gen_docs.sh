#!/usr/bin/env bash
# Tests of gen-docs.sh in a sandbox: the single generation of CHANGELOG.md and
# ROADMAP.md enters main through a PR that holds only those two files and the
# removal of the specs whose issues are all closed.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

repo="$(make_repo)"
copy_scripts "$repo"
printf '.worktrees/\n' >"$repo/.gitignore"
# What a parallel group with one shared spec leaves on main: the first phase kept
# the spec (the other issue was open) and the second one, redone by redo-phase.sh,
# did not remove it either. #7 and #8 are closed; #9 is open.
mkdir -p "$repo/docs/specs"
printf '# Spec\n\nFases #7 e #8.\n' >"$repo/docs/specs/group.md"
printf '# Spec\n\nFases #7 e #9.\n' >"$repo/docs/specs/open.md"
git -C "$repo" add scripts .gitignore docs/specs/group.md docs/specs/open.md
git -C "$repo" commit --quiet -m "chore: scripts"
remote="$TMP/remote.git"
git clone --quiet --bare "$repo" "$remote"
git -C "$repo" remote add origin "$remote"
git -C "$repo" fetch --quiet origin
GEN="$repo/scripts/gen-docs.sh"
pr_branch() { echo "gen-docs/$(git -C "$remote" rev-parse main | cut -c1-12)"; }
BRANCH="$(pr_branch)"

# Fake GitHub: one merged phase PR and one open issue feed the generators; the PR
# of gen-docs.sh is #30. FAKE_FILES: the files GitHub shows in it (default: the
# real ones of the pushed branch). FAKE_CHANGES: "status<TAB>path" lines of its
# diff (default: the real ones). FAKE_MERGES=0: the merge never happens; otherwise
# the merge moves main of the remote and deletes the branch, as GitHub does.
# FAKE_STATUS: the review/independent state read back.
cat >"$TMP/handler.sh" <<H
branch="gen-docs/\$(git -C "$remote" rev-parse main | cut -c1-12)"
case "\$*" in
  "issue list"*"--jq"*) echo 9 ;;
  "run list"*) echo '[]' ;;
  "pr list --state merged"*) echo '[{"number":7,"title":"feat: seven","labels":[{"name":"type:feature"}],"mergedAt":"2026-01-10T10:00:00Z","url":"https://x/pull/7","headRefName":"feat/issue-7-x"}]' ;;
  "issue list"*) echo '[{"number":9,"title":"Nine","labels":[{"name":"area:scripts"}],"url":"https://x/issues/9"}]' ;;
  "pr list"*"number,headRefName"*) [ -f "$TMP/old-closed" ] || printf '%b' "\${FAKE_OLD_PR:-}" ;;
  "pr close 29"*) [ -n "\${FAKE_CLOSE_FAILS:-}" ] || touch "$TMP/old-closed" ;;
  "pr view 29"*"--json state"*) if [ -f "$TMP/old-closed" ]; then echo CLOSED; else echo OPEN; fi ;;
  "pr list"*"--state open"*) [ -f "$TMP/created" ] && echo 30 ;;
  "pr create"*) touch "$TMP/created" ;;
  "pr view 30"*"--json files,headRefOid"*) printf '%s\n' \${FAKE_FILES:-\$(git -C "$remote" diff --name-only "main...\$branch")} | jq -Rcn --arg s "\$(git -C "$remote" rev-parse "\$branch")" '{files: [inputs | {path: .}], headRefOid: \$s}' ;;
  "api repos/owner/repo/compare/main..."*) if [ -n "\${FAKE_CHANGES:-}" ]; then printf '%b\n' "\$FAKE_CHANGES"; else git -C "$remote" diff --name-status "main...\$branch" | sed -e 's/^A/added/' -e 's/^M/modified/' -e 's/^D/removed/'; fi ;;
  "api repos/owner/repo/commits/"*"/status"*) echo "\${FAKE_STATUS:-success}" ;;
  "pr merge 30"*) touch "$TMP/merge-asked"
    if [ "\${FAKE_MERGES:-1}" = 1 ]; then
      git -C "$remote" update-ref refs/heads/main "\$(git -C "$remote" rev-parse "\$branch")"
      git -C "$remote" update-ref -d "refs/heads/\$branch"
    fi ;;
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
assert_eq "A	CHANGELOG.md
A	ROADMAP.md
D	docs/specs/group.md" "$(git -C "$remote" diff --name-status main "$BRANCH")" "the pushed branch holds the two generated files and the removal of the spec of closed issues"
assert_contains "$(git -C "$remote" show "$BRANCH:CHANGELOG.md")" "feat: seven" "the changelog comes from the merged PRs"
assert_contains "$(git -C "$remote" show "$BRANCH:ROADMAP.md")" "Nine" "the roadmap comes from the open issues"

# A spec in the PR that is not the removal of a spec of closed issues: no review
# status, no merge.
refused() { # refused <description> <text> <VAR=value...>
  local what="$1" text="$2"
  shift 2
  run 1 "refuses a PR with $what" "$@"
  assert_contains "$(last_output)" "$text" "names $what"
  assert_not_contains "$(gh_calls)" "statuses" "no review status on a PR with $what"
  assert_not_contains "$(gh_calls)" "pr merge" "no merge of a PR with $what"
}
refused "a modified spec" "docs/specs/group.md is modified" \
  FAKE_CHANGES='added\tCHANGELOG.md\nadded\tROADMAP.md\nmodified\tdocs/specs/group.md'
refused "an added spec" "docs/specs/new.md is added" FAKE_FILES="CHANGELOG.md docs/specs/new.md" \
  FAKE_CHANGES='added\tCHANGELOG.md\nadded\tdocs/specs/new.md'
refused "a spec the diff does not show" "docs/specs/group.md is not in the diff" \
  FAKE_CHANGES='added\tCHANGELOG.md\nadded\tROADMAP.md'
refused "the removal of a spec that cites an open issue" "docs/specs/open.md still cites open issue(s) #9" \
  FAKE_FILES="CHANGELOG.md docs/specs/open.md" FAKE_CHANGES='added\tCHANGELOG.md\nremoved\tdocs/specs/open.md'
refused "a file under docs/specs that is not a spec" "docs/specs/sub/x.md" FAKE_FILES="CHANGELOG.md docs/specs/sub/x.md"

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

# The end of the group is clean: the shared spec left main with the end step, and
# the spec that cites an open issue stayed.
assert_eq "$sha" "$(git -C "$repo" rev-parse main)" "the local main is at the merged PR"
[ ! -e "$repo/docs/specs/group.md" ] && ok || bad "the spec of closed issues left main"
[ -f "$repo/docs/specs/open.md" ] && ok || bad "the spec that cites an open issue stays on main"
rm -f "$TMP/created"
assert_status 0 "end-check is clean after gen-docs.sh" sh -c "cd '$repo' && scripts/end-check.sh"

# Generated files already on main and no spec to remove: nothing to do, no PR.
run 0 "up to date makes no PR"
assert_contains "$(last_output)" "up to date" "says the files are up to date"
assert_not_contains "$(gh_calls)" "pr create" "no PR when nothing changed"
[ ! -e "$repo/.worktrees/gen-docs" ] && ok || bad "no worktree left when up to date"

# Generated files up to date and one spec of closed issues: a PR with the removal only.
printf '# Spec\n\nFase #8.\n' >"$repo/docs/specs/solo.md"
git -C "$repo" add docs/specs/solo.md
git -C "$repo" commit --quiet -m "docs: spec"
git -C "$repo" push --quiet origin main
before="$(git -C "$repo" rev-parse main)"
run 0 "merges a PR that only removes a spec"
assert_contains "$(gh_calls)" "pr create" "opens the PR of the removal"
assert_eq "D	docs/specs/solo.md" "$(git -C "$repo" diff --name-status "$before" main)" "the PR holds only the removal"
rm -f "$TMP/created"

# main moved between two runs: the PR of the earlier run, on gen-docs/<old
# SHA>, is closed (read back) and its branch deleted before the new PR opens.
printf '# Spec\n\nFase #8.\n' >"$repo/docs/specs/solo2.md"
git -C "$repo" add docs/specs/solo2.md
git -C "$repo" commit --quiet -m "docs: spec"
git -C "$repo" push --quiet origin main
git -C "$repo" push --quiet origin main:refs/heads/gen-docs/0000000000aa
run 1 "an earlier PR that does not close stops the run" FAKE_OLD_PR='29\tgen-docs/0000000000aa\n' FAKE_CLOSE_FAILS=1
assert_contains "$(last_output)" "earlier PR #29 (gen-docs/0000000000aa) not read back as CLOSED" "says the earlier PR was not closed"
assert_not_contains "$(gh_calls)" "pr create" "no new PR while the earlier one is open"
run 0 "closes the PR of an earlier run and merges the new one" FAKE_OLD_PR='29\tgen-docs/0000000000aa\n'
calls="$(gh_calls)"
assert_contains "$calls" "pr close 29 --repo owner/repo" "closes the earlier PR"
assert_contains "$calls" "pr view 29 --repo owner/repo --json state" "reads the earlier PR back"
assert_eq 1 "$((  $(printf '%s\n' "$calls" | grep -n 'pr close 29' | head -1 | cut -d: -f1) < $(printf '%s\n' "$calls" | grep -n 'pr create' | head -1 | cut -d: -f1) ))" "the earlier PR closes before the new one opens"
assert_eq "" "$(git -C "$remote" branch --list 'gen-docs/0000000000aa')" "the branch of the earlier PR is deleted"
assert_contains "$(last_output)" "closed PR #29 of an earlier run" "says the earlier PR was closed"
assert_contains "$(last_output)" "PR #30 merged" "the new PR is merged"
rm -f "$TMP/created" "$TMP/old-closed"

# A phase never runs it: only the main checkout does.
git -C "$repo" worktree add --quiet -b feat/issue-5-x "$repo/.worktrees/issue-5" origin/main
assert_status 1 "refuses to run from a phase worktree" sh -c "cd '$repo/.worktrees/issue-5' && scripts/gen-docs.sh --interval 0"
assert_contains "$(last_output)" "main checkout" "says who runs it"
assert_status 0 "--help works" sh -c "'$GEN' --help"
finish
