#!/usr/bin/env bash
# The update knows the template commit it came from (#115, #129).
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"
DIFF="$SCRIPTS/method-diff.sh"

template="$(make_repo)"
mkdir -p "$template/scripts" "$template/.github"
printf 'scripts/keep.sh\nscripts/changed.sh\nscripts/gone.sh\nscripts/new.sh\n' >"$template/.github/method-files.txt"
echo keep >"$template/scripts/keep.sh"
echo old >"$template/scripts/changed.sh"
echo gone >"$template/scripts/gone.sh"
git -C "$template" add .github scripts
git -C "$template" commit --quiet -m "chore: origin"
origin="$(git -C "$template" rev-parse HEAD)"
echo new >"$template/scripts/changed.sh"
git -C "$template" rm --quiet scripts/gone.sh
echo added >"$template/scripts/new.sh"
git -C "$template" add scripts
git -C "$template" commit --quiet -m "chore: next"

repo="$(make_repo)"
mkdir -p "$repo/scripts" "$repo/.github"
echo keep >"$repo/scripts/keep.sh"
echo old >"$repo/scripts/changed.sh"
echo gone >"$repo/scripts/gone.sh"
echo mine >"$repo/scripts/app-only.sh"
printf '%s\n' "$origin" >"$repo/.github/method-origin"
cp "$template/.github/method-files.txt" "$repo/.github/method-files.txt"
git -C "$repo" add .github scripts
git -C "$repo" commit --quiet -m "chore: adopted"

out="$(cd "$repo" && "$DIFF" --template "$template" --to "$dest")"
assert_contains "$out" "identical scripts/keep.sh" "an unchanged method file is identical"
assert_contains "$out" "adapted scripts/changed.sh" "a local edit is adapted"
assert_contains "$out" "missing scripts/new.sh" "a file added in the template is missing"
assert_contains "$out" "removed scripts/gone.sh" "a file the template dropped is removed"
assert_contains "$out" "repo-only scripts/app-only.sh" "a repository file is kept apart"
assert_not_contains "$out" "removed scripts/app-only.sh" "a repository file is not removed"

cd "$repo" && "$DIFF" --template "$template" --to "$dest" --remove >/dev/null
assert_eq "no" "$([ -e "$repo/scripts/gone.sh" ] && echo yes || echo no)" "an unchanged dropped file is removed"
assert_eq "yes" "$([ -f "$repo/scripts/app-only.sh" ] && echo yes)" "a repository file stays"

# A repo that diverged from a file the template then dropped is not deleted.
echo local >"$repo/scripts/gone.sh"
git -C "$template" checkout --quiet "$origin" -- scripts/gone.sh
# gone.sh is back only in the origin commit; the destination commit does not have it.
# Re-create the working copy that still matches a local edit of the origin blob.
printf '%s\n' "$origin" >"$repo/.github/method-origin"
# The file was removed above. Put a diverged copy back and ask again.
echo local-edit >"$repo/scripts/gone.sh"
out="$(cd "$repo" && "$DIFF" --template "$template" --to "$dest" --remove)"
assert_contains "$out" "kept scripts/gone.sh" "a diverged removal is not deleted"
assert_eq "yes" "$([ -f "$repo/scripts/gone.sh" ] && echo yes)" "the diverged file is still there"

found="$(cd "$repo" && "$DIFF" --find-base --template "$template")"
assert_contains "$found" "$origin" "find-base names the template commit the repo came from"
finish
