#!/usr/bin/env bash
# Tests of close-phase.sh --abort: it lists what would be lost and stops; with
# everything pushed, or with --discard, it closes the PR and deletes the remote branch.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

repo="$(make_repo)"
copy_scripts "$repo"
printf '.worktrees/\n.process/\n' >"$repo/.gitignore"
git -C "$repo" add scripts .gitignore
git -C "$repo" commit --quiet -m "chore: scripts"
git clone --quiet --bare "$repo" "$TMP/remote.git"
git -C "$repo" remote add origin "$TMP/remote.git"
git -C "$repo" fetch --quiet origin

# Fake GitHub. FAKE_OPEN_PR: number of the open PR of the branch (empty: none).
# FAKE_ANY_PR: number of a PR of the branch in any state (empty: none); its head
# is FAKE_PR_HEAD (default: the head of the remote branch).
cat >"$TMP/handler.sh" <<'H'
case "$*" in
  "pr list"*"--state open"*) echo "${FAKE_OPEN_PR:-}" ;;
  "pr list"*"--state all"*)
    [ -z "${FAKE_ANY_PR:-}" ] ||
      jq -cn --arg n "$FAKE_ANY_PR" --arg h "${FAKE_PR_HEAD:-$(git rev-parse "refs/remotes/origin/$(git branch --show-current)")}" \
        '[{number: ($n | tonumber), headRefOid: $h}]' | jq -r "$(printf '%s' "$*" | sed -n 's/.*--jq //p')" ;;
esac
H
use_fake_gh "$TMP/handler.sh"

wt="$repo/.worktrees/issue-7"
BR=feat/issue-7-x
open_phase() { # open_phase: a fresh phase worktree with one commit pushed
  git -C "$repo" worktree remove --force "$wt" 2>/dev/null || true
  git -C "$repo" branch -D "$BR" >/dev/null 2>&1 || true
  git -C "$repo" push --quiet origin --delete "$BR" 2>/dev/null || true
  git -C "$repo" worktree add --quiet -b "$BR" "$wt" main
  echo work >"$wt/work.txt"
  git -C "$wt" add work.txt
  git -C "$wt" commit --quiet -m "feat: work"
  git -C "$wt" push --quiet origin "$BR"
  : >"$FAKE_GH_LOG"
}
remote_branch() { git -C "$repo" ls-remote --heads origin "$BR" | wc -l | tr -d ' '; }
abort() { # abort <exit code> <description> [VAR=value...] [-- flags]
  local want="$1" what="$2"
  shift 2
  assert_status "$want" "$what" env FAKE_OPEN_PR=12 FAKE_ANY_PR=12 "$@" sh -c "cd '$wt' && scripts/close-phase.sh --abort \$ABORT_FLAGS"
}
kept() { # kept <description>: nothing was touched
  assert_eq 1 "$([ -d "$wt" ] && echo 1 || echo 0)" "$1: the worktree stays"
  assert_eq 1 "$(remote_branch)" "$1: the remote branch stays"
  assert_not_contains "$(gh_calls)" "pr close" "$1: the PR stays open"
}

# Loss 1: uncommitted change in a tracked file.
open_phase
echo more >>"$wt/work.txt"
abort 10 "refuses with an uncommitted change"
assert_contains "$(last_output)" "uncommitted changes:" "names the uncommitted kind"
assert_contains "$(last_output)" "work.txt" "lists the changed file"
kept "uncommitted"

# Loss 2: untracked file.
open_phase
echo note >"$wt/notes.txt"
abort 10 "refuses with an untracked file"
assert_contains "$(last_output)" "untracked files:" "names the untracked kind"
assert_contains "$(last_output)" "notes.txt" "lists the untracked file"
kept "untracked"

# Loss 3: commit that was never pushed.
open_phase
echo two >"$wt/two.txt"
git -C "$wt" add two.txt
git -C "$wt" commit --quiet -m "feat: second step"
abort 10 "refuses with a commit that was not pushed"
assert_contains "$(last_output)" "commits not pushed:" "names the unpushed kind"
assert_contains "$(last_output)" "feat: second step" "lists the unpushed commit"
assert_not_contains "$(last_output)" "feat: work" "a pushed commit is not listed as unpushed"
kept "unpushed"

# Loss 4: pushed commits that no PR keeps (deleting the remote branch drops them).
open_phase
abort 10 "refuses with pushed commits and no PR" FAKE_OPEN_PR= FAKE_ANY_PR=
assert_contains "$(last_output)" "pushed commits with no PR" "names the no-PR kind"
assert_contains "$(last_output)" "feat: work" "lists the commit only the remote branch keeps"
kept "no PR"

# A commit pushed after the PR was closed is not in the PR: it is listed too.
abort 10 "refuses with a pushed commit that the PR does not hold" FAKE_PR_HEAD=0000000000000000000000000000000000000000
assert_contains "$(last_output)" "pushed commits with no PR" "a PR with another head keeps nothing"
kept "PR with another head"

# Everything pushed and kept by the PR: closes the PR, deletes the remote branch, cleans up.
open_phase
abort 0 "aborts with everything pushed"
assert_contains "$(gh_calls)" "pr close 12" "closes the PR"
assert_eq 0 "$(remote_branch)" "deletes the remote branch"
assert_eq 0 "$([ -d "$wt" ] && echo 1 || echo 0)" "removes the worktree"
assert_eq "" "$(git -C "$repo" branch --list "$BR")" "deletes the local branch"

# Explicit confirmation: --discard drops every kind of loss.
open_phase
echo more >>"$wt/work.txt"; echo note >"$wt/notes.txt"
git -C "$wt" commit --quiet --allow-empty -m "feat: local only"
abort 0 "aborts with --discard" ABORT_FLAGS=--discard
assert_contains "$(last_output)" "discarded" "says what was discarded"
assert_contains "$(last_output)" "notes.txt" "still lists what is dropped"
assert_contains "$(gh_calls)" "pr close 12" "--discard closes the PR"
assert_eq 0 "$(remote_branch)" "--discard deletes the remote branch"
assert_eq 0 "$([ -d "$wt" ] && echo 1 || echo 0)" "--discard removes the worktree"

# A phase that was never pushed and has no PR: nothing to close, nothing to delete.
git -C "$repo" branch -D "$BR" >/dev/null 2>&1 || true
git -C "$repo" worktree add --quiet -b "$BR" "$wt" main
: >"$FAKE_GH_LOG"
abort 0 "aborts a phase with no commit of its own" FAKE_OPEN_PR= FAKE_ANY_PR=
assert_not_contains "$(gh_calls)" "pr close" "no PR to close"
finish
