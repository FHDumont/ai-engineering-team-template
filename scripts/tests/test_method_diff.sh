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
assert_contains "$out" "outdated scripts/changed.sh" "a repository file equal to the origin, behind the destination, is outdated"
assert_not_contains "$out" "adapted scripts/changed.sh" "an outdated file is not adapted"
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

# Files of the repository that have a template default (FHDumont/ai-engineering-team-template#207): missing when absent, never overwritten.
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

# README.md belongs to each repository: never listed (FHDumont/ai-engineering-team-template#207).
assert_not_contains "$out" "README.md" "the update never lists README.md"

# A method label the repository lacks is listed; the repository's own labels are not touched (FHDumont/ai-engineering-team-template#207).
printf 'type:bug\td73a4a\tBug\t\nneeds-gate-review\te11d21\tGate\t\narea:app\t1\tex\t\nfinding\tc5def5\tF\t\nbot:<slug>\t1\tb\t\n' >"$ts/.github/labels.tsv"
git -C "$ts" add .github
git -C "$ts" commit --quiet -m "chore: labels"
printf 'type:bug\td73a4a\tBug\t\nfinding\tc5def5\tF\t\nteam:mine\t1\tx\t\n' >"$rs/.github/labels.tsv"
out="$(cd "$rs" && "$DIFF" --template "$ts")"
assert_contains "$out" "missing-label needs-gate-review" "a method label the repository lacks is listed"
assert_not_contains "$out" "missing-label type:bug" "a label the repository has is not listed"
assert_not_contains "$out" "missing-label area:app" "an example area label is not listed"
assert_not_contains "$out" "missing-label bot:" "a bot slug row is not listed"

# Template-only tests copied to a repository are flagged and removed (FHDumont/ai-engineering-team-template#207).
mkdir -p "$rs/scripts/tests/template"
echo x >"$rs/scripts/tests/template/test_x.sh"
git -C "$rs" add scripts
out="$(cd "$rs" && "$DIFF" --template "$ts")"
assert_contains "$out" "template-only scripts/tests/template/test_x.sh" "a template-only test in the repository is flagged"
(cd "$rs" && "$DIFF" --template "$ts" --remove >/dev/null)
assert_eq "no" "$([ -e "$rs/scripts/tests/template/test_x.sh" ] && echo yes || echo no)" "--remove deletes a template-only test"

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

# #213: outdated (repo = origin, destination differs) is apart from adapted (repo differs from both).
echo local >"$repo/scripts/changed.sh"
out="$(cd "$repo" && "$DIFF" --template "$template" --to "$dest")"
assert_contains "$out" "adapted scripts/changed.sh" "a file that differs from origin and destination is adapted"
assert_not_contains "$out" "outdated scripts/changed.sh" "an adapted file is not outdated"

# #213: a new file of the destination inside the method folders is missing, even outside the manifest.
tn="$(make_repo)"
mkdir -p "$tn/scripts/tests" "$tn/.github"
printf 'scripts/a.sh\n' >"$tn/.github/method-files.txt"
echo a >"$tn/scripts/a.sh"
echo old >"$tn/scripts/tests/test_old.sh"
git -C "$tn" add .github scripts
git -C "$tn" commit --quiet -m "chore: origin"
norigin="$(git -C "$tn" rev-parse HEAD)"
echo new >"$tn/scripts/tests/test_new.sh"
mkdir -p "$tn/scripts/tests/template" "$tn/docs/specs"
echo t >"$tn/scripts/tests/template/test_t.sh"
echo s >"$tn/docs/specs/x.md"
git -C "$tn" add scripts docs
git -C "$tn" commit --quiet -m "chore: new test"
rn="$(make_repo)"
mkdir -p "$rn/scripts/tests" "$rn/.github"
echo a >"$rn/scripts/a.sh"
echo old >"$rn/scripts/tests/test_old.sh"
cp "$tn/.github/method-files.txt" "$rn/.github/"
printf '%s\n' "$norigin" >"$rn/.github/method-origin"
git -C "$rn" add .github scripts
git -C "$rn" commit --quiet -m "chore: adopted"
out="$(cd "$rn" && "$DIFF" --template "$tn")"
assert_contains "$out" "missing scripts/tests/test_new.sh" "a new destination test outside the manifest is missing"
assert_not_contains "$out" "scripts/tests/template/test_t.sh" "a template-only test is never brought"
assert_not_contains "$out" "docs/specs/x.md" "a spec is never brought"

# #213: --notice lists only what matters in the interval.
tz="$(make_repo)"
mkdir -p "$tz/scripts/lib" "$tz/.claude" "$tz/.github"
printf 'scripts/a.sh\n.claude/settings.json\n' >"$tz/.github/method-files.txt"
echo a >"$tz/scripts/a.sh"
echo '{}' >"$tz/.claude/settings.json"
echo 'limit docs/STATE.md 1 500' >"$tz/scripts/check-docs.sh"
echo 'x = 1' >"$tz/scripts/lib/sensitive_paths.py"
git -C "$tz" add .github scripts .claude
git -C "$tz" commit --quiet -m "chore: origin"
zorigin="$(git -C "$tz" rev-parse HEAD)"
echo 'limit docs/STATE.md 1 800' >"$tz/scripts/check-docs.sh"
echo 'SENSITIVE_CLASS' >>"$tz/scripts/lib/sensitive_paths.py"
echo new >"$tz/scripts/new.sh"
printf 'scripts/a.sh\n.claude/settings.json\nscripts/new.sh\n' >"$tz/.github/method-files.txt"
git -C "$tz" add .github scripts
git -C "$tz" commit --quiet -m "chore: dest"
rz="$(make_repo)"
mkdir -p "$rz/scripts/lib" "$rz/.claude" "$rz/.github" "$rz/docs"
echo a >"$rz/scripts/a.sh"
echo '{}' >"$rz/.claude/settings.json"
cp "$tz/.github/method-files.txt" "$rz/.github/"
printf '%s\n' "$zorigin" >"$rz/.github/method-origin"
echo 'o job `tests` roda em todo PR' >"$rz/docs/STATE.md"
git -C "$rz" add .
git -C "$rz" commit --quiet -m "chore: adopted"
out="$(cd "$rz" && env -u PROCESS_CI_MODE PATH="$TMP/nogh:$PATH" "$DIFF" --notice --template "$tz")"
assert_contains "$out" "scripts/new.sh" "the notice lists the missing file"
assert_contains "$out" "ci-mode" "the notice asks for ci-mode when absent"
assert_contains "$out" "o job \`tests\` roda em todo PR" "the notice names the old STATE sentence when present"
assert_contains "$out" "needs-owner-ok" "an origin verifier with no classes puts needs-owner-ok"
assert_contains "$out" "close-phase.sh" "the notice says the gate label enters at the merge by close-phase.sh"
assert_contains "$out" "show $zorigin:scripts/check-docs.sh" "the notice gives the exact command for the origin check-docs"
assert_not_contains "$out" "settings.json" "settings.json equal to the destination asks no owner ok"
assert_not_contains "$out" "missing-label" "no missing label, none in the notice"
# An origin that already has the classes gives needs-gate-review, and says nothing of the old label.
out="$(cd "$rz" && env -u PROCESS_CI_MODE "$DIFF" --notice --template "$tz" --from "$(git -C "$tz" rev-parse HEAD)" --to "$(git -C "$tz" rev-parse HEAD)")"
assert_contains "$out" "needs-gate-review" "an origin verifier with the classes puts needs-gate-review"
assert_not_contains "$out" "check-docs.sh" "no interval, no check-docs command"
finish
