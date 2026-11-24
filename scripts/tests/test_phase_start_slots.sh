#!/usr/bin/env bash
# Tests of phase-start.sh when no phase slot is free: it waits in the same turn, it never leaves a card.
# shellcheck source=scripts/tests/phase_start_common.sh
source "$(dirname "$0")/phase_start_common.sh"

spec seven.md 7
slot="$AI_METHOD_CACHE/slots/fase/1"
hold() { mkdir -p "$slot"; printf 'repo\t99\t%s\t%s\t%s\t0\n' "$$" "$(date +%s)" "$repo" >"$slot/info"; }
export AI_METHOD_SLOTS_FASE=1 PHASE_START_SLOT_POLL=1

# No slot until the deadline: exit 75, nothing created.
hold
assert_status 75 "no free slot until the deadline exits 75" env PHASE_START_SLOT_WAIT=2 CLAUDE_CODE_SESSION_ID=manager sh -c "cd '$repo' && scripts/phase-start.sh 7 --no-check"
assert_contains "$(last_output)" "no free phase slot after" "says the slot did not come"
assert_contains "$(last_output)" "nothing was created" "says nothing was created"
assert_eq "" "$(ls "$repo/.worktrees" 2>/dev/null || true)" "no worktree was left"

# The slot is released while it waits: the phase opens in the same call.
hold
(sleep 2; rm -rf "$slot") &
assert_status 0 "a slot freed while it waits opens the phase in the same call" env PHASE_START_SLOT_WAIT=30 CLAUDE_CODE_SESSION_ID=manager sh -c "cd '$repo' && scripts/phase-start.sh 7 --no-check"
wait
assert_contains "$(last_output)" "title: Fase #7" "prints the start_session arguments after the wait"

finish
