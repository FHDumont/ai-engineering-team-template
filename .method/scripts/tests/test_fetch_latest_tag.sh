#!/usr/bin/env bash
# fetch-template.sh without a destination brings the last method tag, not the tip of main (#311).
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"
FETCH="$SCRIPTS/fetch-template.sh"

template="$(make_repo)"
mkdir -p "$template/.method/scripts/lib" "$template/.github"
cp "$SCRIPTS/method-diff.sh" "$template/.method/scripts/method-diff.sh"
cp "$SCRIPTS/lib/common.sh" "$template/.method/scripts/lib/common.sh"
printf '.method/scripts/a.sh\n' >"$template/.github/method-files.txt"
commit() { echo "$1" >"$template/.method/scripts/a.sh"; git -C "$template" add .; git -C "$template" commit --quiet -m "chore: $1"; }
commit one
c1="$(git -C "$template" rev-parse HEAD)"
git -C "$template" tag v2026.11.20-1
commit two
git -C "$template" tag v2026.11.27-9
commit three
c3="$(git -C "$template" rev-parse HEAD)"
git -C "$template" tag v2026.11.27-10 "$c3"
commit four
git -C "$template" tag latest-experiment
git -C "$template" tag v1
commit tip
tip="$(git -C "$template" rev-parse HEAD)"

repo="$(make_repo)"
(cd "$repo" && bash "$FETCH" --url "$template") >"$TMP/last.out" 2>&1 || bad "fetch without destination failed: $(last_output)"
assert_eq "$c3" "$(git -C "$repo/.process/template" rev-parse HEAD)" "no destination brings the last tag (-10 beats -9, other tags ignored)"
assert_eq "three" "$(cat "$repo/.process/template/.method/scripts/a.sh")" "the files are the ones of the tag, not the tip"
assert_contains "$(last_output)" "v2026.11.27-10" "the output names the tag"

(cd "$repo" && bash "$FETCH" "$tip" --url "$template") >"$TMP/last.out" 2>&1 || bad "explicit sha failed"
assert_eq "$tip" "$(git -C "$repo/.process/template" rev-parse HEAD)" "an explicit sha still goes to that sha"
(cd "$repo" && bash "$FETCH" v2026.11.20-1 --url "$template") >"$TMP/last.out" 2>&1 || bad "explicit tag failed: $(last_output)"
assert_eq "$c1" "$(git -C "$repo/.process/template" rev-parse HEAD)" "an explicit tag goes to that tag"

(cd "$repo" && bash "$FETCH" --url "$template" --apply) >"$TMP/last.out" 2>&1 || bad "apply without destination failed: $(last_output)"
assert_contains "$(last_output)" "v2026.11.27-10" "the update notice cites the tag"

untagged="$(make_repo)"
assert_status 1 "a template without tags fails with the reason" bash -c "cd '$repo' && '$FETCH' --url '$untagged'"
assert_contains "$(last_output)" "no method tag" "the failure says there is no tag"
finish
