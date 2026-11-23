#!/usr/bin/env bash
# The deploy gate skips the suite only when this SHA, or the same tree, has green CI.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

repo="$(make_repo)"
mkdir -p "$repo/scripts/lib"
cp "$SCRIPTS/lib/common.sh" "$repo/scripts/lib/common.sh"
cp "$SCRIPTS/ci-already-green.sh" "$repo/scripts/ci-already-green.sh"
chmod +x "$repo/scripts/ci-already-green.sh"
echo x >"$repo/f"
git -C "$repo" add f
git -C "$repo" commit --quiet -m "chore: one"
git clone --quiet --bare "$repo" "$TMP/remote.git"
git -C "$repo" remote add origin "$TMP/remote.git"
git -C "$repo" push --quiet origin HEAD:main
SHA="$(git -C "$repo" rev-parse HEAD)"
S="$repo/scripts/ci-already-green.sh"
use_fake_gh "$TMP/handler.sh"
: >"$TMP/handler.sh"
run() { env "$@" sh -c "cd '$repo' && '$S' '$SHA'"; }

assert_status 0 "green CI skips the suite" run FAKE_BASE_CI=green
assert_eq "skip=true" "$(last_output)" "a green check skips"
assert_status 0 "an absent check runs the suite" run FAKE_BASE_CI=absent FAKE_BASE_PR=none
assert_eq "skip=false" "$(last_output)" "no CI means the suite runs"
assert_status 0 "a red check runs the suite" run FAKE_BASE_CI=red FAKE_BASE_PR=none
assert_eq "skip=false" "$(last_output)" "a red check does not skip"
assert_status 0 "an API failure runs the suite" run FAKE_GH_FAIL='check-runs' FAKE_BASE_CI=green
assert_eq "skip=false" "$(last_output)" "a failed API means the suite runs"
assert_status 0 "the same tree with green CI on the merged PR skips the suite" run FAKE_BASE_CI=absent FAKE_BASE_PR=green
assert_eq "skip=true" "$(last_output)" "a voucher on the same tree skips"
assert_status 0 "a different tree still runs the suite" run FAKE_BASE_CI=absent FAKE_BASE_PR=tree
assert_eq "skip=false" "$(last_output)" "a different tree does not skip"

finish
