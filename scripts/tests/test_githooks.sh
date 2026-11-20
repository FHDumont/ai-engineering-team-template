#!/usr/bin/env bash
# Tests for the git hooks (.githooks/pre-commit and commit-msg).
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

repo="$(make_repo)"
mkdir -p "$repo/scripts/lib"
cp "$SCRIPTS/check-attribution.sh" "$repo/scripts/"
cp "$SCRIPTS/lib/common.sh" "$repo/scripts/lib/"
cp -R "$REPO/.githooks" "$repo/.githooks"
git -C "$repo" config core.hooksPath .githooks

echo a >"$repo/a.txt"
git -C "$repo" add a.txt
assert_status 1 "pre-commit blocks commit on main" git -C "$repo" commit -m "feat: a"
assert_contains "$(last_output)" "never commit on main" "pre-commit explains"

git -C "$repo" switch --quiet -c feat/issue-1-a
assert_status 0 "allows commit on a phase branch" git -C "$repo" commit -m "feat: a"
echo b >"$repo/b.txt"
git -C "$repo" add b.txt
assert_status 1 "commit-msg blocks AI trailer" git -C "$repo" commit -m "feat: b

Co-Authored-By: Claude <noreply@anthropic.com>"

# Phase lock: the session that recorded phase_opened never writes to the phase,
# by any git command. The hooks are tracked, so every worktree has them.
git -C "$repo" add .githooks scripts
git -C "$repo" commit --quiet -m "chore: hooks"
echo base >"$repo/base.txt"
git -C "$repo" add base.txt
git -C "$repo" commit --quiet -m "feat: base"
printf '.worktrees/\n.process/\n' >"$repo/.git/info/exclude"
git -C "$repo" switch --quiet -c side
echo side >"$repo/side.txt"
git -C "$repo" add side.txt
git -C "$repo" commit --quiet -m "feat: side"
side="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" switch --quiet feat/issue-1-a
wt="$repo/.worktrees/issue-7"
git -C "$repo" worktree add --quiet -b feat/issue-7-x "$wt" feat/issue-1-a
mkdir -p "$repo/.process"
jq -cn '{event: "phase_opened", session_id: "mgr", issue: "7"}' >"$repo/.process/events.jsonl"
as() { # as <session id> <command...>
  local sid="$1"
  shift
  env CLAUDE_CODE_SESSION_ID="$sid" "$@"
}
head_of() { git -C "$wt" rev-parse HEAD; }
# Leaves the worktree as it was: stops any half-done operation and drops loose changes.
tidy() { # tidy <worktree>
  local op
  for op in cherry-pick revert merge rebase am; do git -C "$1" "$op" --abort >/dev/null 2>&1 || true; done
  git -C "$1" read-tree -u --reset HEAD
  git -C "$1" clean -fdq
}
# refused <description> <command...>: run by the session that opened the phase, it fails with the lock's reason.
refused() {
  local what="$1" rc=0
  shift
  as mgr "$@" >"$TMP/last.out" 2>&1 || rc=$?
  if [ "$rc" != 0 ] && grep -q "opened phase #7" "$TMP/last.out"; then ok; else bad "$what (exit $rc): $(head -c 300 "$TMP/last.out")"; fi
  tidy "$wt"
}
before="$(head_of)"
stage_c() { echo c >"$wt/c.txt" && git -C "$wt" add c.txt; }
stage_c
refused "pre-commit blocks the session that opened the phase" git -C "$wt" commit -m "feat: c"
assert_contains "$(last_output)" "pre-commit:" "pre-commit is the hook that refuses a plain commit"
mkdir -p "$wt/sub"
stage_c
refused "blocks commit from a subfolder" sh -c "cd '$wt/sub' && git commit -m 'feat: c'"
stage_c
refused "blocks commit --no-verify (reference-transaction)" git -C "$wt" commit --no-verify -m "feat: c"
refused "blocks cherry-pick" git -C "$wt" cherry-pick "$side"
refused "blocks revert" git -C "$wt" revert --no-edit HEAD
refused "blocks merge (fast-forward)" git -C "$wt" merge side
refused "blocks merge --no-ff" git -C "$wt" merge --no-ff -m "merge" side
refused "blocks rebase" git -C "$wt" rebase side
git -C "$repo" format-patch --quiet -1 "$side" -o "$TMP/patches"
refused "blocks am" git -C "$wt" am "$TMP"/patches/*.patch
refused "blocks update-ref from the main checkout" git -C "$repo" update-ref refs/heads/feat/issue-7-x "$side"
refused "blocks reset to another commit" git -C "$wt" reset --quiet --soft "$side"
tree="$(git -C "$wt" rev-parse "$side^{tree}")"
made="$(as mgr git -C "$wt" commit-tree "$tree" -p "$before" -m "feat: plumbing")"
refused "blocks commit-tree + update-ref" git -C "$wt" update-ref HEAD "$made"
git -C "$repo" worktree add --quiet -b feat/issue-7-x-r2 "$repo/.worktrees/issue-7-r2" feat/issue-1-a
refused "blocks the redo worktree issue-7-r2" git -C "$repo/.worktrees/issue-7-r2" cherry-pick "$side"
tidy "$repo/.worktrees/issue-7-r2"
assert_eq "$before" "$(head_of)" "the phase branch did not move"
assert_eq "$before" "$(git -C "$repo" rev-parse feat/issue-7-x-r2)" "the redo branch did not move"
# The child session and a plain terminal write normally; the opener still creates and deletes branches.
assert_status 0 "the child session cherry-picks" as child git -C "$wt" cherry-pick "$side"
echo d >"$wt/d.txt"
git -C "$wt" add d.txt
assert_status 0 "the child session commits" as child git -C "$wt" commit -m "feat: d"
echo e >"$wt/e.txt"
git -C "$wt" add e.txt
assert_status 0 "a commit without a session id passes" env -u CLAUDE_CODE_SESSION_ID git -C "$wt" commit -m "feat: e"
assert_status 0 "the opener creates a phase worktree" as mgr git -C "$repo" worktree add --quiet -b feat/issue-9-z "$repo/.worktrees/issue-9" feat/issue-1-a
jq -cn '{event: "phase_opened", session_id: "mgr", issue: "9"}' >>"$repo/.process/events.jsonl"
assert_status 0 "the opener removes the worktree" as mgr git -C "$repo" worktree remove --force "$repo/.worktrees/issue-9"
assert_status 0 "the opener deletes the phase branch" as mgr git -C "$repo" branch -D feat/issue-9-z
finish
