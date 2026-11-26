#!/usr/bin/env bash
# Tests of close-phase.sh --prepare: refuses when origin/main changed a gate path after the base.
# shellcheck source=scripts/tests/close_phase_common.sh
source "$(dirname "$0")/close_phase_common.sh"

git -C "$repo" switch --quiet -c chore/stale origin/main
echo w >"$repo/work.txt"
git -C "$repo" add work.txt; git -C "$repo" commit --quiet -m "chore: work"
printf 'Resumo\n\nCloses #1\n' >"$TMP/body.md"
cat >"$TMP/handler.sh" <<'H'
case "$*" in
  "pr list"*"--state open"*) echo 12 ;;
  "issue view 1"*) printf 'type:chore\n' ;;
  "pr view 12"*) echo '{"number":12,"title":"chore: x","labels":[{"name":"type:chore"}],"url":"u"}' ;;
  "pr list"*"merged"*) echo '[]' ;;
  "issue list"*) echo '[]' ;;
esac
H
use_fake_gh "$TMP/handler.sh"

# origin/main moves with a path that is not of the gate: no refusal.
other="$TMP/other"
git clone --quiet "$remote" "$other"
git -C "$other" config user.email t@t; git -C "$other" config user.name t
echo n >"$other/notes.txt"; git -C "$other" add notes.txt; git -C "$other" commit --quiet -m "chore: notes"
git -C "$other" push --quiet origin HEAD:main
assert_status 0 "a moved main without a gate path does not stop the prepare" sh -c "cd '$repo' && scripts/close-phase.sh --prepare --body-file '$TMP/body.md'"

# origin/main changes a gate path after the base: refused, rebase first, nothing pushed.
echo '{}' >"$other/package-lock.json"; git -C "$other" add package-lock.json; git -C "$other" commit --quiet -m "chore: lock"
git -C "$other" push --quiet origin HEAD:main
: >"$PUSH_LOG"
assert_status 1 "a gate path changed on origin/main after the base stops the prepare" sh -c "cd '$repo' && scripts/close-phase.sh --prepare --body-file '$TMP/body.md'"
assert_contains "$(last_output)" "package-lock.json" "names the gate path"
assert_contains "$(last_output)" "rebase" "says to rebase before the review"
assert_eq "0" "$(pushes)" "nothing is pushed"

# After the rebase it passes.
git -C "$repo" rebase --quiet origin/main
sh -c "cd '$repo' && scripts/close-phase.sh --prepare --body-file '$TMP/body.md'" >"$TMP/after.out" 2>&1 || true
assert_not_contains "$(cat "$TMP/after.out")" "changed gate path" "after the rebase the stale-base refusal is gone"

finish
