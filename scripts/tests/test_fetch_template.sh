#!/usr/bin/env bash
# fetch-template.sh brings the template destination into .process/template without a worktree or a clone (#215).
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"
FETCH="$SCRIPTS/fetch-template.sh"

template="$(make_repo)"
mkdir -p "$template/scripts" "$template/.github"
printf 'scripts/a.sh\nscripts/b.sh\n' >"$template/.github/method-files.txt"
echo one >"$template/scripts/a.sh"
echo bee >"$template/scripts/b.sh"
echo old >"$template/scripts/c.sh"
echo x >"$template/scripts/d.sh"
git -C "$template" add .github scripts
git -C "$template" commit --quiet -m "chore: origin"
origin="$(git -C "$template" rev-parse HEAD)"
echo two >"$template/scripts/a.sh"
echo new >"$template/scripts/c.sh"
echo y >"$template/scripts/d.sh"
git -C "$template" add scripts
git -C "$template" commit --quiet -m "chore: next"
dest="$(git -C "$template" rev-parse HEAD)"

repo="$(make_repo)"
mkdir -p "$repo/.github" "$repo/scripts"
printf '%s\n' "$origin" >"$repo/.github/method-origin"
echo one >"$repo/scripts/a.sh"
echo mine >"$repo/scripts/own.sh"
echo old >"$repo/scripts/c.sh"
echo mine-adapted >"$repo/scripts/d.sh"

assert_contains "$(bash "$FETCH" --help)" "fetch-template.sh" "--help works"
assert_status 2 "no sha is a usage error" bash -c "cd '$repo' && '$FETCH' --url '$template'"

(cd "$repo" && bash "$FETCH" "$dest" --url "$template") >"$TMP/last.out" 2>&1 || bad "fetch failed: $(last_output)"
assert_eq "two" "$(cat "$repo/.process/template/scripts/a.sh")" "destination extracted into .process/template"
assert_eq "$dest" "$(git -C "$repo/.process/template" rev-parse "$dest")" "destination commit readable for method-diff"
assert_eq "$origin" "$(git -C "$repo/.process/template" rev-parse "$origin")" "origin commit fetched too"
assert_eq "1" "$(git -C "$repo" worktree list | wc -l | tr -d ' ')" "no worktree registered"
assert_eq "one" "$(cat "$repo/scripts/a.sh")" "plain fetch does not touch the repository"

diff_out="$(cd "$repo" && bash "$SCRIPTS/method-diff.sh" --template .process/template --to "$dest")"
assert_contains "$diff_out" "outdated scripts/a.sh" "method-diff reads the extracted template"

(cd "$repo" && bash "$FETCH" "$dest" --url "$template" --apply) >"$TMP/last.out" 2>&1 || bad "apply failed: $(last_output)"
assert_eq "two" "$(cat "$repo/scripts/a.sh")" "--apply copies the changed method file"
assert_eq "bee" "$(cat "$repo/scripts/b.sh")" "--apply copies the missing method file"
assert_eq "mine" "$(cat "$repo/scripts/own.sh")" "--apply leaves repository-only files"

assert_eq "new" "$(cat "$repo/scripts/c.sh")" "--apply copies an outdated file outside the manifest"
assert_eq "mine-adapted" "$(cat "$repo/scripts/d.sh")" "--apply leaves an adapted file"

assert_status 1 "unknown sha fails" bash -c "cd '$repo' && '$FETCH' deadbeefdeadbeefdeadbeefdeadbeefdeadbeef --url '$template'"
finish
