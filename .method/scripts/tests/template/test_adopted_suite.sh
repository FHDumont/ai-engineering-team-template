#!/usr/bin/env bash
# Builds an adopted repository (no example app, no template-only tests, project
# files that would fail a whole-repo scan) and runs the method suite there.
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "$0")/../lib.sh"

adopt="$TMP/adopted"
mkdir -p "$adopt"
tar -C "$REPO" -cf - \
  --exclude .git \
  --exclude .worktrees \
  --exclude .process \
  --exclude app \
  --exclude CHANGELOG.md \
  --exclude ROADMAP.md \
  --exclude .method/scripts/tests/template \
  --exclude .github/workflows/deploy-example.yml \
  . | tar -C "$adopt" -xf -

# What an adopted project has, and what the old scans used to reject.
mkdir -p "$adopt/app" "$adopt/.github/workflows" "$adopt/.claude/agents" "$adopt/.claude/skills/product" "$adopt/docs"
printf '# Projeto\n\nRode gh auth refresh antes do deploy. Intervalo: 8 min.\n' >"$adopt/README.md"
printf '.min-w-8 { width: 8px; }\n' >"$adopt/app/style.css"
printf 'GH_TOKEN=local\n' >"$adopt/app/run.sh"
printf 'name: build\non: push\njobs:\n  b:\n    runs-on: adopted-runner-zz\n' >"$adopt/.github/workflows/build.yml"
printf 'model: opus\n' >"$adopt/.claude/agents/product.md"
printf 'effort: high\nopus\n' >"$adopt/.claude/skills/product/SKILL.md"
printf '# Notas\n\n## Nomes só deste repositório\n\n- `adopted-runner-zz`\n' >"$adopt/docs/repo-notes.md"
# The example area and group labels are replaced, as the adoption step says.
sed -e 's/^area:app	/area:web	/' -e 's/^group:app	/group:web	/' \
  "$adopt/.github/labels.tsv" >"$adopt/.github/labels.tsv.new"
mv "$adopt/.github/labels.tsv.new" "$adopt/.github/labels.tsv"

git -C "$adopt" init --quiet -b main
git -C "$adopt" config user.email test@example.org
git -C "$adopt" config user.name test
git -C "$adopt" config commit.gpgsign false
git -C "$adopt" add -A
git -C "$adopt" commit --quiet -m "chore: adopt the method"

if env REPO_ROOT="$adopt" "$adopt/.method/scripts/check-docs.sh" >"$TMP/docs.out" 2>&1; then
  ok
else
  cat "$TMP/docs.out"
  bad "the adopted repository passes check-docs"
fi
if bash "$adopt/.method/scripts/tests/test_bots.sh" >"$TMP/bots.out" 2>&1; then
  ok
  suite_out="$TMP/suite.out"
  if env -u PROCESS_VALIDATE_RUNNING AI_METHOD_TEST_JOBS="${AI_METHOD_TEST_JOBS:-4}" \
    "$adopt/.method/scripts/validate.sh" --tests >"$suite_out" 2>&1; then
    ok
  else
    grep -E 'FAIL |not ok:' "$suite_out" | head -60
    bad "the adopted repository passes the suite"
  fi
else
  tail -40 "$TMP/bots.out"
  bad "the adopted repository passes the bots scan"
fi
finish
