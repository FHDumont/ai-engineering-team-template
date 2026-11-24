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
dest="$(git -C "$template" rev-parse HEAD)"

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

# Cause one: no commit of the repo has .github/method-origin; find-base falls back to the first commit.
t2="$(make_repo)"
mkdir -p "$t2/scripts"
echo one >"$t2/scripts/a.sh"
git -C "$t2" add scripts
git -C "$t2" commit --quiet -m "chore: one"
base1="$(git -C "$t2" rev-list --max-parents=0 HEAD)" # the seed commit both repos share
echo two >"$t2/scripts/a.sh"
git -C "$t2" add scripts
git -C "$t2" commit --quiet -m "chore: two"
r2="$(make_repo)"
mkdir -p "$r2/scripts"
echo one >"$r2/scripts/a.sh"
git -C "$r2" add scripts
git -C "$r2" commit --quiet -m "chore: adopted"
rc=0
found="$(cd "$r2" && "$DIFF" --find-base --template "$t2" 2>&1)" || rc=$?
assert_eq "0" "$rc" "find-base without .github/method-origin exits 0"
assert_contains "$found" "$base1" "find-base without .github/method-origin names the matching commit"

# Cause two: the repo's first commit has a file the oldest template commits lack (absent on one side differs).
t3="$(make_repo)"
echo seed >"$t3/seed.txt"
git -C "$t3" add seed.txt
git -C "$t3" commit --quiet -m "chore: seed"
mkdir -p "$t3/scripts"
echo late >"$t3/scripts/late.sh"
git -C "$t3" add scripts
git -C "$t3" commit --quiet -m "chore: late"
late="$(git -C "$t3" rev-parse HEAD)"
r3="$(make_repo)"
mkdir -p "$r3/scripts" "$r3/.github"
echo late >"$r3/scripts/late.sh"
echo "$late" >"$r3/.github/method-origin"
git -C "$r3" add scripts .github
git -C "$r3" commit --quiet -m "chore: adopted"
rc=0
found="$(cd "$r3" && "$DIFF" --find-base --template "$t3" 2>&1)" || rc=$?
assert_eq "0" "$rc" "find-base with a file absent in old template commits exits 0"
assert_contains "$found" "$late" "find-base skips template commits lacking the file"

# A template with no commits is a real failure: a message, never a silent 128.
t4="$(mktemp -d)"
git -C "$t4" init --quiet
rc=0
found="$(cd "$r3" && "$DIFF" --find-base --template "$t4" 2>&1)" || rc=$?
assert_eq "1" "$rc" "find-base on an empty template fails with exit 1"
assert_contains "$found" "no template commit" "find-base on an empty template says why"

# Files of the repository that have a template default (#207): missing when absent, never overwritten.
ts="$(make_repo)"
mkdir -p "$ts/.github"
printf 'scripts/x.sh\n' >"$ts/.github/method-files.txt"
for f in required-checks headless update-notice.md label-areas.tsv ci-extra-jobs; do echo "default $f" >"$ts/.github/$f"; done
git -C "$ts" add .github
git -C "$ts" commit --quiet -m "chore: defaults"
rs="$(make_repo)"
mkdir -p "$rs/.github"
printf 'scripts/x.sh\n' >"$rs/.github/method-files.txt"
echo mine >"$rs/.github/headless"
printf '%s\n' "$(git -C "$ts" rev-parse HEAD)" >"$rs/.github/method-origin"
git -C "$rs" add .github
git -C "$rs" commit --quiet -m "chore: adopted"
out="$(cd "$rs" && "$DIFF" --template "$ts")"
for f in required-checks update-notice.md label-areas.tsv ci-extra-jobs; do
  assert_contains "$out" "missing .github/$f" "a missing repository file with a template default is listed: $f"
done
assert_not_contains "$out" "missing .github/headless" "an existing repository file is not listed as missing"
assert_eq "mine" "$(cat "$rs/.github/headless")" "an existing repository file is not overwritten"

# The guide says to bring the default and to drop the old STATE sentence.
assert_contains "$(cat "$SCRIPTS/../README.md")" "trazer o padrão do template quando faltar" "the guide brings the default of repository-owned files"
assert_contains "$(cat "$SCRIPTS/../README.md")" "o job \`tests\` roda em todo PR" "the guide names the old STATE sentence"

# find-base must not spawn git per file and commit: many commits, many files, a time limit.
t5="$(make_repo)"
mkdir -p "$t5/scripts"
for i in $(seq 1 40); do echo "v0 $i" >"$t5/scripts/f$i.sh"; done
git -C "$t5" add scripts
git -C "$t5" commit --quiet -m "chore: files"
for i in $(seq 1 60); do
  echo "v$i" >"$t5/scripts/f$((i % 40 + 1)).sh"
  git -C "$t5" commit --quiet -am "chore: edit $i"
done
r5="$(mktemp -d)"
git -C "$r5" init --quiet -b main
git -C "$r5" config user.email test@example.org
git -C "$r5" config user.name test
git -C "$r5" config commit.gpgsign false
mkdir -p "$r5/scripts"
for i in $(seq 1 40); do echo "v0 $i" >"$r5/scripts/f$i.sh"; done
git -C "$r5" add scripts
git -C "$r5" commit --quiet -m "chore: adopted"
start=$SECONDS
found="$(cd "$r5" && "$DIFF" --find-base --template "$t5" 2>&1)"
elapsed=$((SECONDS - start))
assert_eq "yes" "$([ "$elapsed" -le 3 ] && echo yes || echo "no ($elapsed s)")" "find-base on 60 commits and 40 files is fast"
assert_eq "$(git -C "$t5" rev-list --reverse HEAD | sed -n 2p)" "$found" "find-base names the commit whose blobs match"
finish
