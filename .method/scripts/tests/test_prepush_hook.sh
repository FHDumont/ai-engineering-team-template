#!/usr/bin/env bash
# Tests of .githooks/pre-push: a push to main is refused only in the unprotected mode.
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

repo="$(make_repo)"
copy_scripts "$repo"
cp -R "$REPO/.githooks" "$repo/.githooks"
git -C "$repo" config core.hooksPath .githooks
git clone --quiet --bare "$repo" "$TMP/remote.git"
git -C "$repo" remote add origin "$TMP/remote.git"
git -C "$repo" switch --quiet -c feat/issue-1-a
echo a >"$repo/a.txt"
git -C "$repo" add a.txt
git -C "$repo" -c core.hooksPath=/dev/null commit --quiet -m "feat: a"

# FAKE_MODE=1 answers like a repository with PROCESS_BRANCH_MODE recorded.
cat >"$TMP/handler.sh" <<'H'
case "$*" in
  "variable list"*) [ -z "${FAKE_MODE:-}" ] || echo PROCESS_BRANCH_MODE ;;
esac
H
use_fake_gh "$TMP/handler.sh"

assert_status 1 "unprotected mode: push to main is refused" env FAKE_MODE=1 git -C "$repo" push origin HEAD:refs/heads/main
assert_contains "$(last_output)" "unprotected branch mode" "refusal explains the mode"
assert_status 0 "unprotected mode: push of a phase branch passes" env FAKE_MODE=1 git -C "$repo" push origin HEAD:refs/heads/feat/issue-1-a
assert_status 0 "protected mode: the hook leaves main to the server" git -C "$repo" push origin HEAD:refs/heads/main
finish
