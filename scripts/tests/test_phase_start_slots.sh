#!/usr/bin/env bash
# Tests of phase-start.sh when no phase slot is free: it waits in the same turn, it never leaves a card.
# shellcheck source=scripts/tests/phase_start_common.sh
source "$(dirname "$0")/phase_start_common.sh"

spec seven.md 7
slot="$AI_METHOD_CACHE/slots/fase/1"
hold() { mkdir -p "$slot"; printf 'repo\t99\t%s\t%s\t%s\t0\n' "$$" "$(date +%s)" "$repo" >"$slot/info"; }
export AI_METHOD_SLOTS_FASE=1 PHASE_START_SLOT_POLL=1

# A group bigger than the machine limit never fits: it exits at once (not 75), without waiting or creating anything.
spec eight.md 8
spec eleven.md 11
spec twelve.md 12
AI_METHOD_SLOTS_FASE=3
start="$(date +%s)"
rc=0
env PHASE_START_SLOT_WAIT=60 CLAUDE_CODE_SESSION_ID=manager sh -c "cd '$repo' && scripts/phase-start.sh 7 8 11 12 --no-check" >"$TMP/big.out" 2>&1 || rc=$?
elapsed=$(( $(date +%s) - start ))
assert_eq 1 "$([ "$rc" != 0 ] && [ "$rc" != 75 ] && echo 1 || echo 0)" "a group over the limit exits with its own code, not 75"
assert_eq 1 "$([ "$elapsed" -lt 20 ] && echo 1 || echo 0)" "a group over the limit does not wait"
assert_contains "$(cat "$TMP/big.out")" "split the group" "tells to split the group"
assert_eq "" "$(ls "$repo/.worktrees" 2>/dev/null || true)" "no worktree for a group over the limit"
assert_eq "" "$(git -C "$repo" branch --list 'fix/*' 'feat/*' | tr -d ' ')" "no branch for a group over the limit"
AI_METHOD_SLOTS_FASE=1

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
