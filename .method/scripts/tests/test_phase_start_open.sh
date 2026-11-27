#!/usr/bin/env bash
# Tests of the single phase entry, opening: closed issue, missing pair, happy path and the arguments of start_session.
# shellcheck source=.method/scripts/tests/phase_start_common.sh
source "$(dirname "$0")/phase_start_common.sh"


# Opening never runs the suite: with check-env.sh active the output has the environment
# lines and no test result, and the opening does not wait for any test run.
spec seven.md 7
assert_status 0 "phase-start opens with a green base, check-env included" env CLAUDE_CODE_SESSION_ID=manager sh -c "cd '$repo' && .method/scripts/phase-start.sh 7"
assert_contains "$(last_output)" "CI of the base commit" "says the CI of the base was read"
assert_contains "$(last_output)" "ok: tools of the method" "the check-env of the opening checks the environment"
assert_not_contains "$(last_output)" "tests pass" "the opening does not run the suite"
assert_not_contains "$(last_output)" "passed" "the opening prints no test result"
git -C "$repo" worktree remove --force "$repo/.worktrees/issue-7"
git -C "$repo" branch -D feat/issue-7-listar-issues >/dev/null
rm -rf "$AI_METHOD_CACHE"; : >"$PROCESS_EVENTS_FILE"
[ -z "$(git -C "$repo" status --porcelain)" ] || git -C "$repo" checkout --quiet -- .

# Closed issue: refused even with a spec.
spec nine.md 9
assert_status 1 "phase-start refuses a closed issue" sh -c "cd '$repo' && .method/scripts/phase-start.sh 9 --no-check"
assert_contains "$(last_output)" "not open" "says the issue is not open"
assert_status 1 "new-phase refuses a closed issue" sh -c "cd '$repo' && .method/scripts/new-phase.sh 9 --no-check"
rm "$repo/docs/specs/nine.md"

# A spec without a model/effort pair cannot give the start_session arguments.
spec seven.md 7 "sem par"
assert_status 1 "phase-start refuses a spec without model and effort" sh -c "cd '$repo' && .method/scripts/phase-start.sh 7 --no-check"
assert_contains "$(last_output)" "modelo:" "says what the spec lacks"
assert_eq "" "$(ls "$repo/.worktrees" 2>/dev/null || true)" "nothing opens without the pair"

# Happy path: branch, worktree, the spec committed by the script, phase_opened, arguments.
spec seven.md 7
assert_status 0 "phase-start opens a phase that has a spec" env CLAUDE_CODE_SESSION_ID=manager sh -c "cd '$repo' && .method/scripts/phase-start.sh 7 --no-check"
out="$(last_output)"
wt="$repo/.worktrees/issue-7"
assert_eq "feat/issue-7-listar-issues" "$(git -C "$wt" branch --show-current)" "worktree is on the phase branch"
# Progress of the opening: recorded for the owner, never printed.
pf="$AI_METHOD_CACHE/progress/$(basename "$repo")-7.jsonl"
assert_eq "phase-start.sh new-phase.sh" "$(jq -r 'select(.state == "end") | .script' "$pf" 2>/dev/null | sort -r | paste -sd' ' -)" "phase-start.sh and new-phase.sh record their end"
assert_contains "$(jq -r 'select(.script == "new-phase.sh") | .step' "$pf")" "creating the branch and the worktree" "new-phase.sh records its steps"
assert_not_contains "$out" "jsonl" "the opening prints no progress path"
assert_eq "docs/specs/seven.md" "$(git -C "$wt" show --name-only --format= HEAD)" "the script commits the spec on the phase branch"
assert_eq "" "$(git -C "$wt" status --porcelain)" "the worktree is clean after the spec commit"
assert_eq "" "$(git -C "$repo" status --porcelain)" "the main checkout keeps no loose copy of the spec"
assert_eq "manager" "$(events | jq -r 'select(.event == "phase_opened" and .issue == "7") | .session_id')" "records phase_opened for the opening session"
assert_contains "$out" "cwd: $repo" "prints the cwd of start_session"
assert_contains "$out" "use_worktree: false" "prints use_worktree"
assert_contains "$out" "initiation: user_asked" "prints the initiation of start_session"
assert_contains "$out" "context: fresh" "prints the context of start_session"
assert_contains "$out" "title: Fase #7" "prints the title of start_session"
assert_contains "$out" "background:" "prints the background of start_session"
assert_contains "$out" "initiation: own_initiative" "a refusal is the last resort: a card"
assert_contains "$out" "Do not run .method/scripts/start-headless.sh: headless is off by default" "a refusal is a card, not headless"
assert_not_contains "$out" "eartbeat" "no heartbeat anywhere in the steps"
assert_not_contains "$out" "CronCreate" "no recurring task is created"
assert_not_contains "$out" "cron " "no cron in the steps"
assert_contains "$out" "the end of the turn of a child wakes the manager" "the manager wakes by the end of the turn of a child"
assert_contains "$out" "model: sonnet" "prints the model of the spec"
assert_contains "$out" "effort: low" "prints the effort of the spec"
assert_contains "$out" "issue #7" "the prompt names the issue"
assert_contains "$out" "$wt" "the prompt names the worktree"
# The manager steps come with the arguments: every session in this turn, no heartbeat.
assert_eq 1 "$(grep -c "Open every session above in this same turn" <<<"$out")" "says once to open every session in this turn"
assert_eq 1 "$(grep -c -F -- "--state esperando" <<<"$out")" "one stop command, only for a card"
# The stop sentence works over Remote Control too: the owner writes "abrir a #n" in a new message.
need="$(grep -F -- ".method/scripts/status.sh --state esperando --need" <<<"$out" || true)"
assert_contains "$need" 'escreva "abrir a #7" numa mensagem nova' "the stop sentence asks for a new message, which works over Remote Control"
assert_not_contains "$need" "clique" "the stop sentence never sends the owner to click a card"
assert_status 0 "check-env accepts the phase branch with its spec" sh -c "cd '$wt' && .method/scripts/check-env.sh"
# phase_session is the mark of the session that works on the phase, never of the one that opened it.
assert_status 0 "check-env runs for the opening session" env CLAUDE_CODE_SESSION_ID=manager sh -c "cd '$wt' && .method/scripts/check-env.sh"
assert_eq "" "$(events | jq -r 'select(.event == "phase_session" and .session_id == "manager") | .issue')" "no phase_session for the session that opened the phase"
# The child session runs in the pair of the spec (its transcript and CLAUDE_EFFORT say so).
mkdir -p "$TMP/claude/projects/p"
echo '{"type":"assistant","message":{"model":"claude-sonnet-1"}}' >"$TMP/claude/projects/p/child.jsonl"
assert_status 0 "check-env runs for the child session" env CLAUDE_CODE_SESSION_ID=child CLAUDE_EFFORT=low CLAUDE_CONFIG_DIR="$TMP/claude" sh -c "cd '$wt' && .method/scripts/check-env.sh"
assert_eq "7" "$(events | jq -r 'select(.event == "phase_session" and .session_id == "child") | .issue')" "records phase_session for the child session"


# A phase of a later wave opens in the same turn and waits for the merge of the previous wave.
spec eight.md 8
assert_status 0 "phase-start opens a later-wave phase with --after" env CLAUDE_CODE_SESSION_ID=manager sh -c "cd '$repo' && .method/scripts/phase-start.sh 8 --no-check --after 7"
out="$(last_output)"
assert_contains "$out" "wave wait: #7" "names the phase of the previous wave"
assert_contains "$out" "origin/main" "reads the merge on origin/main"
assert_contains "$out" "git rebase origin/main" "tells the child to update the branch on main before the first step"
assert_contains "$out" "background task of your own, no scheduled job" "the wait is a background task of the child"
assert_not_contains "$out" "eartbeat" "no heartbeat in a later wave either"
finish
