#!/usr/bin/env bash
# Tests of the session-setup-check.sh hook and of the texts of the mandatory setup.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/../../../scripts/tests/lib.sh"
HOOK="$REPO/.claude/hooks/session-setup-check.sh"
: >"$TMP/none.sh"
use_fake_gh "$TMP/none.sh"

repo="$(make_repo)"
git -C "$repo" remote add origin "https://example.invalid/owner/repo.git"
run() { # run <session> [<repo>]
  jq -cn --arg s "$1" --arg d "${2:-$repo}" '{hook_event_name: "SessionStart", source: "startup", session_id: $s, cwd: $d}' | "$HOOK"
}

# Setup pending: warns once per session and points to the setup skill.
for state in nolabels noprotection offer; do
  fake_setup "$state"
  assert_status 0 "never blocks ($state)" run "s-$state"
  out="$(last_output)"
  assert_contains "$out" "Setup pending" "warns ($state)"
  assert_contains "$out" "load the setup skill" "the first step is the setup skill ($state)"
  assert_contains "$out" "missing:" "says what is missing ($state)"
  assert_status 0 "never blocks, second start ($state)" run "s-$state"
  assert_eq "" "$(last_output)" "warns once per session ($state)"
done
assert_status 0 "never blocks (another session)" run s-other
assert_contains "$(last_output)" "Setup pending" "another session is warned too"
assert_eq ".process/" "$(git -C "$repo" status --porcelain | sed 's/^?? //')" "the marker stays in .process"

# Configured repository: silent, and the next sessions do not read GitHub again.
fake_setup ok
assert_status 0 "never blocks (configured)" run s-ok
assert_eq "" "$(last_output)" "says nothing on a configured repository"
: >"$FAKE_GH_LOG"
assert_status 0 "never blocks (configured, next session)" run s-ok2
assert_eq "" "$(last_output)$(gh_calls)" "a configured repository is not read again"
rm "$repo/.process/setup-ok"

# A plan without branch protection: the message of setup-repo.sh, not the skill.
fake_setup freeplan
assert_status 0 "never blocks (plan)" run s-plan
assert_contains "$(last_output)" "branch protection is not available" "plan: carries the message of setup-repo.sh"
assert_not_contains "$(last_output)" "load the setup skill" "plan: does not point to the setup skill"

# No remote, gh failing (no network or no login), no gh, slow gh: silent, and quick.
fake_setup nolabels
bare="$(make_repo)"
assert_status 0 "never blocks (no remote)" run s-bare "$bare"
assert_eq "" "$(last_output)" "says nothing without a remote"
run_failing() { FAKE_GH_FAIL='.' run s-net; }
assert_status 0 "never blocks (gh failing)" run_failing
assert_eq "" "$(last_output)" "says nothing when gh fails"
mkdir -p "$TMP/nogh"
for c in jq git head sed tr mktemp sleep cat rm mkdir dirname bash env; do ln -s "$(command -v "$c")" "$TMP/nogh/$c"; done
assert_status 0 "never blocks (no gh)" env PATH="$TMP/nogh" bash -c "echo '{\"session_id\":\"s-nogh\",\"cwd\":\"$repo\"}' | '$HOOK'"
assert_eq "" "$(last_output)" "says nothing without gh"
echo 'sleep 6' >"$TMP/slow.sh"
SECONDS=0
assert_status 0 "never blocks (slow gh)" env FAKE_GH_HANDLER="$TMP/slow.sh" FAKE_SETUP="" SETUP_CHECK_TIMEOUT=1 "$SHELL" -c "echo '{\"session_id\":\"s-slow\",\"cwd\":\"$repo\"}' | '$HOOK'"
assert_eq "" "$(last_output)" "says nothing when the check times out"
[ "$SECONDS" -lt 5 ] && ok || bad "the time limit holds (took ${SECONDS}s)"
assert_status 0 "empty input passes" sh -c "echo '{}' | '$HOOK'"

# The hook is wired to SessionStart, with a short time limit.
wired="$(jq -c '.hooks.SessionStart[].hooks[] | select(.command | contains("session-setup-check.sh"))' "$REPO/.claude/settings.json")"
assert_contains "$wired" "session-setup-check.sh" "settings.json runs the hook on SessionStart"
assert_eq "true" "$(printf '%s' "$wired" | jq '.timeout <= 10')" "settings.json gives the hook a short timeout"

# Texts: the rule is told in the design; the skill and AGENTS.md point to the check.
design="$(cat "$REPO/docs/process-design.md")"
assert_contains "$design" 'setup-repo.sh --check' "the design names the check"
assert_contains "$design" '`.claude/hooks/session-setup-check.sh`' "the design lists the hook"
assert_contains "$(cat "$REPO/.claude/skills/setup/SKILL.md")" 'setup-repo.sh --check' "the setup skill ends on the check"
assert_contains "$(cat "$REPO/AGENTS.md")" 'setup-repo.sh --check' "AGENTS.md names the check"
for f in "$REPO/AGENTS.md" "$REPO/.claude/skills/setup/SKILL.md"; do
  assert_eq "" "$(grep -n 'session-setup-check' "$f" || true)" "$(basename "$(dirname "$f")")/$(basename "$f") does not repeat the hook of the design"
done
finish
