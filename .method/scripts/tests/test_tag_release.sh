#!/usr/bin/env bash
# tag-release.sh tags the tip of main as vYYYY.MM.DD-N only when its CI is green, and never twice (#311).
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

repo="$(make_repo)"
mkdir -p "$repo/.method/scripts/lib"
cp "$SCRIPTS/lib/common.sh" "$repo/.method/scripts/lib/common.sh"
cp "$SCRIPTS/tag-release.sh" "$SCRIPTS/ci-already-green.sh" "$repo/.method/scripts/"
git -C "$repo" add .method
git -C "$repo" commit --quiet -m "chore: scripts"
git clone --quiet --bare "$repo" "$TMP/remote.git"
git -C "$repo" remote add origin "$TMP/remote.git"
git -C "$repo" push --quiet origin main
git -C "$repo" fetch --quiet origin
S="$repo/.method/scripts/tag-release.sh"
use_fake_gh "$TMP/handler.sh"
: >"$TMP/handler.sh"
run() { env "$@" sh -c "cd '$repo' && '$S'"; }
today="$(date -u +%Y.%m.%d)"
tags_remote() { git -C "$TMP/remote.git" tag -l 'v*'; }

assert_contains "$(bash "$S" --help 2>&1 || true)" "tag-release.sh" "--help works"
assert_status 3 "a red CI creates no tag" run FAKE_BASE_CI=red
assert_contains "$(last_output)" "CI" "the refusal says why"
assert_status 3 "a running CI creates no tag" run FAKE_BASE_CI=running
assert_status 3 "a missing CI check creates no tag" run FAKE_BASE_CI=absent
assert_status 3 "a skipped CI without a proving PR creates no tag" run FAKE_BASE_CI=skipped FAKE_BASE_PR=none
assert_status 3 "a skipped CI with a red PR creates no tag" run FAKE_BASE_CI=skipped FAKE_BASE_PR=red
assert_status 3 "a skipped CI with a PR of another tree creates no tag" run FAKE_BASE_CI=skipped FAKE_BASE_PR=tree
assert_eq "" "$(tags_remote)" "no tag reached the remote"
assert_eq "" "$(git -C "$repo" tag -l 'v*')" "no tag exists locally"

assert_status 0 "a skipped CI proved by a merged green PR of the same tree tags the tip" run FAKE_BASE_CI=skipped FAKE_BASE_PR=green
assert_eq "v$today-1" "$(tags_remote)" "the first tag of the day is -1, pushed"
assert_eq "$(git -C "$repo" rev-parse origin/main)" "$(git -C "$TMP/remote.git" rev-parse "v$today-1^{commit}")" "the tag points at the tip of main"
assert_status 0 "a second run on the same commit is fine" run FAKE_BASE_CI=green
assert_contains "$(last_output)" "v$today-1" "it names the tag already there"
assert_eq "v$today-1" "$(tags_remote)" "no new tag on the same commit"

echo two >"$repo/two"
git -C "$repo" add two
git -C "$repo" commit --quiet -m "chore: two"
git -C "$repo" push --quiet origin main
assert_status 0 "a new commit gets a new tag" run FAKE_BASE_CI=green
assert_eq "v$today-1 v$today-2" "$(tags_remote | tr '\n' ' ' | sed 's/ $//')" "the second tag of the day is -2"
finish
