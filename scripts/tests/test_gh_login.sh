#!/usr/bin/env bash
# Tests of the gh login rule: a scope fix is one single command with
# the complete scope list, and the repository neither asks for nor runs another `gh auth`.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

# The list of scopes lives in one place; the fix command carries all of it.
# shellcheck source=scripts/lib/project.sh
source "$SCRIPTS/lib/project.sh"
assert_eq "gist,project,read:org,repo,workflow" "${GH_SCOPES:-}" "the scope list is defined once, complete"
want="gh auth login -h github.com -p https -w -s ${GH_SCOPES:-}"
assert_eq "$want" "${GH_LOGIN_CMD:-}" "the login command carries every scope"
assert_contains "${PROJECT_FIX_SCOPE:-}" "$want" "the board fix line is the single login command"
out="$(gh() { echo "  - Token scopes: 'gist', 'repo'"; }; project_require_scopes 2>&1 || true)"
assert_contains "$out" "next: $want" "setup-repo --project asks for the single login command"
assert_contains "$out" "never types the device code" "the step forbids an agent typing the code"

# Every `gh auth login` with options written anywhere in the repo is that same command.
self="scripts/tests/test_gh_login.sh"
while IFS= read -r line; do
  [ -n "$line" ] || continue
  case "$line" in
    "$self":*|docs/specs/*) continue ;;
    *"$want"*) ok ;;
    scripts/lib/project.sh:*'-s $GH_SCOPES"') ok ;; # the definition itself
    *) bad "a gh auth login that is not the single command: $line" ;;
  esac
done <<<"$(git -C "$REPO" grep -nI --untracked -e 'gh auth login -' -- . || true)"

# Nothing in the repo asks for or runs another gh auth command, feeds a token to gh
# or sets the token variables. Allowed: the test itself, the specs (transient), the
# job token of ci.yml and the lines of the rule itself, which say "never"/"nunca".
banned='gh auth (refresh|logout|setup-git)|--with-token|(GH|GITHUB)_TOKEN='
offenders=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  case "$line" in
    "$self":*|docs/specs/*|.github/workflows/ci.yml:*) continue ;;
    AGENTS.md:*|docs/process-design.md:*|.claude/skills/setup/SKILL.md:*)
      if printf '%s' "$line" | grep -qiE 'nunca|never'; then continue; fi ;;
  esac
  offenders="$offenders$line"$'\n'
done <<<"$(git -C "$REPO" grep -nIE --untracked -e "$banned" -- . || true)"
assert_eq "" "$offenders" "no gh auth refresh/logout/setup-git, --with-token or token variable outside the rule"

# The same filter refuses a planted line (the check is not vacuous).
planted="$(printf 'scripts/x.sh:1:gh auth refresh --scopes project\ndocs/x.md:9:rode gh auth logout\n' | grep -cE "$banned")"
assert_eq 2 "$planted" "the pattern catches a planted command"

finish
