#!/usr/bin/env bash
# Lab-test criteria stay distinct, and a post-merge issue stays open (issue #114).
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

plan="$(cat "$REPO/.claude/skills/plan/SKILL.md")"
readme="$(cat "$REPO/README.md")"
integrate="$(cat "$REPO/.claude/skills/integrate/SKILL.md")"
assert_contains "$plan" "prova da parada" "plan names the proof at the stop"
assert_contains "$plan" "do fecho" "plan names the proof at close"
assert_contains "$plan" "pós-merge" "plan names the proof after the merge"
assert_contains "$plan" "issue fica aberta até a prova" "plan lets a spec keep the issue open until the proof"
assert_contains "$plan" "não pede na parada" "the brief does not ask, at the stop, for a later proof"
assert_contains "$readme" "filtro \`app\`" "the update guide names the app filter"
assert_contains "$readme" "inclua \`ci.yml\` no filtro" "the update guide says to include ci.yml so the build runs"
assert_contains "$integrate" "issue fica aberta até a prova" "integrate closes a post-merge issue with its proofs"
words="$(wc -w <"$REPO/.claude/skills/plan/SKILL.md" | tr -d ' ')"
[ "$words" -le 400 ] && ok || bad "plan skill has $words words (allowed up to 400)"

if [ ! -f "$SCRIPTS/lib/refs.sh" ]; then
  bad "refs.sh keeps a post-merge issue open"
else
  # shellcheck source=scripts/lib/refs.sh
  source "$SCRIPTS/lib/refs.sh"
  root="$TMP/specroot"
  mkdir -p "$root/docs/specs"
  printf '## Fase #9 — piloto\n\nPronto quando: issue fica aberta até a prova.\n' >"$root/docs/specs/p.md"
  issue_kept_open 9 "$root" && ok || bad "a spec that keeps the issue open is recognized"
  printf '## Fase #8 — normal\n\nmodelo: sonnet\n' >"$root/docs/specs/q.md"
  issue_kept_open 8 "$root" && bad "a normal spec does not keep the issue open" || ok
  printf 'Refs #9\n' >"$TMP/body.md"
  body_keep_open "$TMP/body.md" 9 "$root"
  assert_not_contains "$(cat "$TMP/body.md")" "Closes #9" "redo does not add Closes when the issue stays open"
  assert_contains "$(cat "$TMP/body.md")" "Refs #9" "the body keeps Refs"
  printf 'Closes #9\n' >"$TMP/body.md"
  body_keep_open "$TMP/body.md" 9 "$root"
  assert_not_contains "$(cat "$TMP/body.md")" "Closes #9" "an existing Closes becomes Refs"
  assert_contains "$(cat "$TMP/body.md")" "Refs #9" "Refs replaces Closes"
fi

# shellcheck source=scripts/lib/common.sh
source "$SCRIPTS/lib/common.sh"
# shellcheck source=scripts/lib/project.sh
source "$SCRIPTS/lib/project.sh"
if ! declare -F project_set_done_if_closed >/dev/null; then
  bad "the board goes to Done while the issue is still open"
else
  cat >"$TMP/handler.sh" <<'H'
case "$*" in
  "variable list"*) echo "${FAKE_BOARD:-}" ;;
  "issue view 9"*"--json state"*) echo "$FAKE_STATE" ;;
  "auth status"*) printf "  - Token scopes: 'project', 'repo'\n" ;;
  "project item-add"*) echo ITEM ;;
  "project view"*) echo PID ;;
  "project field-list"*) echo '{"fields":[{"name":"Status","id":"FID","options":[{"name":"Done","id":"OD"}]}]}' ;;
  "project item-edit"*) echo Done >"$TMP/status" ;;
  "api graphql"*) cat "$TMP/status" 2>/dev/null || true ;;
esac
H
  use_fake_gh "$TMP/handler.sh"
  : >"$FAKE_GH_LOG"
  out="$(FAKE_BOARD=7 FAKE_STATE=OPEN project_set_done_if_closed 9)"
  assert_contains "$out" "not set to Done" "an open issue is not moved to Done"
  assert_not_contains "$(gh_calls)" "item-edit" "an open issue is not edited on the board"
fi

finish
