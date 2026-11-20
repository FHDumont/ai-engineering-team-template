#!/usr/bin/env bash
# Tests of redo-phase.sh in a sandbox: a local origin, a second clone that moves
# main, and a fake gh that keeps the state of the old and the new PR.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

repo="$(make_repo)"
copy_scripts "$repo"
printf '.worktrees/\n.process/\n' >"$repo/.gitignore"
printf '# Changelog\n\n- seed\n' >"$repo/CHANGELOG.md"
printf '# Roadmap\n' >"$repo/ROADMAP.md"
git -C "$repo" add scripts .gitignore CHANGELOG.md ROADMAP.md
git -C "$repo" commit --quiet -m "chore: scripts"
remote="$TMP/remote.git"
git clone --quiet --bare "$repo" "$remote"
git -C "$repo" remote add origin "$remote"
git -C "$repo" fetch --quiet origin
other="$TMP/other"
git clone --quiet "$remote" "$other"
git -C "$other" config user.email test@example.org
git -C "$other" config user.name test
git -C "$other" config commit.gpgsign false
mkdir -p "$repo/.worktrees"
REGISTRY="$repo/.worktrees/parallel-active.tsv"
REDO="$repo/scripts/redo-phase.sh"

commit() { # commit <checkout> <file> <content> <message>
  mkdir -p "$(dirname "$1/$2")"
  printf '%s\n' "$3" >"$1/$2"
  git -C "$1" add "$2"
  git -C "$1" commit --quiet -m "$4"
}
main_moves() { # main_moves <file> <content> <message>: another phase merged
  git -C "$other" pull --quiet origin main
  commit "$other" "$1" "$2" "$3"
  git -C "$other" push --quiet origin HEAD:main
}
remote_heads() { git -C "$repo" ls-remote --heads origin | sed 's#.*refs/heads/##' | paste -sd' ' -; }

# Fake GitHub: PR <old> is open on the phase branch until "pr close"; "pr create"
# opens PR <new> on the redone branch. FAKE_CLOSE_FAILS: the close does not take.
handler() { # handler <old PR> <new PR> <issue>
  rm -f "$TMP/created" "$TMP/closed"
  cat >"$TMP/handler.sh" <<H
case "\$*" in
  "pr list"*"-r2 --state open"*|"pr list"*"-r3 --state open"*) [ -f "$TMP/created" ] && echo $2 ;;
  "pr list"*"--state open"*) [ -f "$TMP/closed" ] || echo $1 ;;
  "pr view $1"*"title,body,labels"*) jq -cn '{title: "feat: phase $3", body: "Resumo\n\nCloses #$3", labels: [{name: "type:feature"}, {name: "needs-owner-ok"}]}' ;;
  "pr view $1"*"--json state"*) if [ -f "$TMP/closed" ]; then echo CLOSED; else echo OPEN; fi ;;
  "pr create"*) touch "$TMP/created" ;;
  "pr close $1"*) [ -n "\${FAKE_CLOSE_FAILS:-}" ] || touch "$TMP/closed" ;;
esac
H
  use_fake_gh "$TMP/handler.sh"
}
created_body() { cat "$(gh_calls | sed -n 's/.*pr create .*--body-file \([^ ]*\).*/\1/p' | head -1)"; }

# 1. Conflict only in a generated file, plus a commit that main already has.
git -C "$repo" switch --quiet -c feat/issue-12-x origin/main
commit "$repo" docs/specs/g.md "spec of the group" "docs(specs): add the spec of issue #12"
commit "$repo" phase12.txt phase "feat: phase 12"
printf '# Changelog\n\n- phase 12\n- seed\n' >"$repo/CHANGELOG.md"
git -C "$repo" add CHANGELOG.md
git -C "$repo" commit --quiet -m "docs: regenerate changelog"
git -C "$repo" push --quiet origin feat/issue-12-x
main_moves docs/specs/g.md "spec of the group" "docs(specs): add the spec of issue #11"
main_moves ahead.txt ahead "feat: phase 11"
main_moves CHANGELOG.md "# Changelog

- phase 11
- seed" "docs: regenerate changelog"
printf '11\tfeat/issue-11-w\t/w11\n12\tfeat/issue-12-x\t%s\n' "$repo" >"$REGISTRY"
handler 77 78 12
assert_status 0 "a conflict only in a generated file is redone alone" sh -c "cd '$repo' && '$REDO'"
out="$(last_output)"
new=feat/issue-12-x-r2
assert_eq "$new" "$(git -C "$repo" branch --show-current)" "the worktree is on the new branch"
files="$(git -C "$repo" ls-tree -r --name-only "$new")"
assert_contains "$files" "phase12.txt" "the phase commit was cherry-picked"
assert_contains "$files" "ahead.txt" "the new branch starts from the updated main"
assert_eq "$(git -C "$repo" show origin/main:CHANGELOG.md)" "$(git -C "$repo" show "$new:CHANGELOG.md")" "the generated file is the one of main"
assert_eq "feat: phase 12" "$(git -C "$repo" log --format=%s "origin/main..$new")" "only the phase commit is left (spec already on main and generated file dropped)"
assert_eq 0 "$(git -C "$repo" rev-list --merges --count "origin/main..$new")" "no merge commit"
assert_eq "$(git -C "$repo" rev-parse "$new")" "$(git -C "$remote" rev-parse "$new")" "the new branch is on origin"
calls="$(gh_calls)"
assert_contains "$calls" "pr create --repo owner/repo --base main --head $new --title feat: phase 12" "opens the new PR from the new branch"
assert_contains "$calls" "--label type:feature --label needs-owner-ok" "the new PR keeps the labels of the old one"
assert_contains "$(created_body)" "Closes #12" "the new PR closes the issue"
assert_contains "$(created_body)" "PR #77" "the new PR names the old one"
assert_contains "$calls" "pr close 77" "closes the old PR"
assert_contains "$calls" "pr view 77 --repo owner/repo --json state" "reads the old PR back"
assert_not_contains " $(remote_heads) " " feat/issue-12-x " "the old remote branch is deleted"
assert_eq "" "$(git -C "$repo" branch --list feat/issue-12-x)" "the old local branch is deleted"
assert_eq "12	$new	$repo" "$(grep '^12	' "$REGISTRY")" "the registry line points to the new branch"
assert_eq "11	feat/issue-11-w	/w11" "$(grep '^11	' "$REGISTRY")" "the other registry lines stay"
assert_contains "$out" "redone: PR #78" "says which PR replaces the old one"
assert_eq "$new $(git -C "$repo" rev-parse "$new")" "$(jq -r 'select(.event == "phase_push") | [.branch, .sha] | join(" ")' "$PROCESS_EVENTS_FILE" | tail -1)" "records the push of the new branch in the trace"
assert_not_contains "$out" "ask" "asks nobody"

# 2. Real conflict: exit 4, nothing on GitHub; resolved by the session, the rerun finishes.
git -C "$repo" switch --quiet -c feat/issue-13-y origin/main
commit "$repo" ahead.txt mine "feat: phase 13"
commit "$repo" phase13.txt more "feat: phase 13, second step"
git -C "$repo" push --quiet origin feat/issue-13-y
main_moves ahead.txt theirs "feat: phase 14"
printf '13\tfeat/issue-13-y\t%s\n' "$repo" >"$REGISTRY"
handler 80 81 13
assert_status 4 "a real conflict in the cherry-pick stops" sh -c "cd '$repo' && '$REDO'"
assert_contains "$(last_output)" "conflict: ahead.txt" "names the conflicting file"
assert_not_contains "$(gh_calls)" "pr create" "no new PR on a real conflict"
assert_not_contains "$(gh_calls)" "pr close" "the old PR stays open on a real conflict"
assert_contains " $(remote_heads) " " feat/issue-13-y " "the old remote branch stays on a real conflict"
assert_eq "13	feat/issue-13-y	$repo" "$(cat "$REGISTRY")" "the registry is untouched on a real conflict"
assert_status 4 "a rerun with the cherry-pick still stopped refuses" sh -c "cd '$repo' && '$REDO'"
printf 'both\n' >"$repo/ahead.txt"
git -C "$repo" add ahead.txt
git -C "$repo" -c core.editor=true cherry-pick --continue >/dev/null
assert_status 0 "the rerun resumes after the conflict is resolved" sh -c "cd '$repo' && '$REDO'"
assert_eq "feat: phase 13, second step
feat: phase 13" "$(git -C "$repo" log --format=%s origin/main..feat/issue-13-y-r2)" "the rerun picks the commits that were left"
assert_contains "$(gh_calls)" "pr create --repo owner/repo --base main --head feat/issue-13-y-r2" "opens the new PR after the resume"
assert_eq "13	feat/issue-13-y-r2	$repo" "$(cat "$REGISTRY")" "the registry is rewritten after the resume"

# 3. Read back: a close that did not take stops before the remote branch is deleted.
git -C "$repo" switch --quiet -c feat/issue-15-z origin/main
commit "$repo" phase15.txt phase "feat: phase 15"
git -C "$repo" push --quiet origin feat/issue-15-z
main_moves ahead2.txt ahead "feat: phase 16"
rm -f "$REGISTRY"
handler 90 91 15
assert_status 1 "an old PR that did not close is an error" env FAKE_CLOSE_FAILS=1 sh -c "cd '$repo' && '$REDO'"
assert_contains "$(last_output)" "not read back as CLOSED" "says what was not read back"
assert_contains " $(remote_heads) " " feat/issue-15-z " "the old remote branch stays while the old PR is open"
assert_status 0 "the rerun finishes the steps that were left" sh -c "cd '$repo' && '$REDO'"
assert_eq 1 "$(gh_calls | grep -c 'pr create')" "the rerun does not open a second PR"
assert_not_contains " $(remote_heads) " " feat/issue-15-z " "the rerun deletes the old remote branch"

# 3b. A stopped cherry-pick that the session skips instead of resolving loses a commit:
# the rerun refuses before any push and the old PR and branch stay.
git -C "$repo" switch --quiet -c feat/issue-19-s origin/main
commit "$repo" ahead2.txt mine "feat: phase 19"
git -C "$repo" push --quiet origin feat/issue-19-s
main_moves ahead2.txt theirs "feat: phase 20"
handler 97 98 19
assert_status 4 "a real conflict stops (phase 19)" sh -c "cd '$repo' && '$REDO'"
git -C "$repo" cherry-pick --skip >/dev/null 2>&1
assert_status 1 "a skipped cherry-pick is not pushed as a redone phase" sh -c "cd '$repo' && '$REDO'"
assert_contains "$(last_output)" "aborted or skipped" "says a commit is missing"
assert_not_contains "$(gh_calls)" "pr create" "no new PR with a commit missing"
assert_not_contains "$(gh_calls)" "pr close" "the old PR stays open with a commit missing"
assert_contains " $(remote_heads) " " feat/issue-19-s " "the old remote branch stays with a commit missing"
git -C "$repo" switch --quiet feat/issue-19-s
git -C "$repo" branch -D feat/issue-19-s-r2 >/dev/null
rm -f "$repo/.git/redo-phase" "$repo/.git/redo-phase.todo" "$repo/.git/redo-phase.kept"

# 3a. End to end: close-phase.sh --check on the conflicting PR redoes it and exits 0.
git -C "$repo" switch --quiet -c feat/issue-18-e origin/main
commit "$repo" phase18.txt phase "feat: phase 18"
printf '# Changelog\n\n- phase 18\n' >"$repo/CHANGELOG.md"
git -C "$repo" add CHANGELOG.md
git -C "$repo" commit --quiet -m "docs: regenerate changelog"
git -C "$repo" push --quiet origin feat/issue-18-e
main_moves CHANGELOG.md "# Changelog

- phase 16" "docs: regenerate changelog"
handler 95 96 18
cat >>"$TMP/handler.sh" <<'H'
case "$*" in
  "pr view 95"*"mergeable,mergeStateStatus,headRefOid"*) echo '{"mergeable":"CONFLICTING","mergeStateStatus":"DIRTY","headRefOid":"abc"}' ;;
esac
H
assert_status 0 "close-phase.sh --check redoes the conflicting PR and exits 0" sh -c "cd '$repo' && scripts/close-phase.sh --check"
out="$(last_output)"
assert_contains "$out" "redone: PR #96 (branch feat/issue-18-e-r2) replaces PR #95" "--check ends with the new PR"
assert_not_contains "$out" "ask the repo owner" "--check asks nobody"
assert_not_contains "$out" "rebase" "--check offers no rebase"
assert_contains "$(gh_calls)" "pr create --repo owner/repo --base main --head feat/issue-18-e-r2" "--check opened the new PR"

# 4. Refusals: no open PR, main, and the session that opened the phase.
git -C "$repo" switch --quiet -c feat/issue-17-q origin/main
commit "$repo" phase17.txt phase "feat: phase 17"
cat >"$TMP/none.sh" <<'H'
H
use_fake_gh "$TMP/none.sh"
assert_status 1 "refuses a branch without an open PR" sh -c "cd '$repo' && '$REDO'"
assert_eq "feat/issue-17-q" "$(git -C "$repo" branch --show-current)" "stays on the phase branch when refused"
mkdir -p "$repo/.process"
jq -cn '{event: "phase_opened", session_id: "plan", issue: "17"}' >"$repo/.process/events.jsonl"
assert_status 9 "the session that opened the phase does not redo it" env CLAUDE_CODE_SESSION_ID=plan sh -c "cd '$repo' && '$REDO'"
git -C "$repo" switch --quiet main
assert_status 1 "refuses to run on main" sh -c "cd '$repo' && '$REDO'"
assert_status 0 "--help works" sh -c "'$REDO' --help"
assert_contains "$(last_output)" "Usage: redo-phase.sh" "--help prints the usage"
finish
