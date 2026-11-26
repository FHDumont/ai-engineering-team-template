#!/usr/bin/env bash
# Tests of the real pair of the phase session: check-env.sh reads it, compares it with
# the pair of the spec, records it in the trace and exits non-zero on a divergence.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

repo="$(make_repo)"
copy_scripts "$repo"
# phase-start.sh checks the setup against the labels file of the repository.
mkdir -p "$repo/.github" && cp "$REPO/.github/labels.tsv" "$repo/.github/labels.tsv"
printf '.worktrees/\n.process/\n' >"$repo/.gitignore"
mkdir -p "$repo/docs/specs"
cat >"$repo/docs/specs/pair.md" <<'S'
# Spec

## Fase #7 — x

1. Etapa. modelo: big · esforço: high · motivo: forte
2. Etapa. modelo: small · esforço: low · motivo: leve
3. Etapa. modelo: big · esforço: high · motivo: forte
S
git -C "$repo" add scripts .gitignore docs .github
git -C "$repo" commit --quiet -m "chore: scripts and spec"
export PROCESS_EVENTS_FILE="$repo/.process/events.jsonl"
mkdir -p "$repo/.process"
git -C "$repo" worktree add --quiet -b feat/issue-7-x "$repo/.worktrees/issue-7"
wt="$repo/.worktrees/issue-7"
echo ': ' >"$TMP/handler.sh"
use_fake_gh "$TMP/handler.sh"
fake_setup ok

# The harness keeps the transcript of a session at <config>/projects/<slug>/<session id>.jsonl.
export CLAUDE_CONFIG_DIR="$TMP/claude"
transcript() { # transcript <session id> <model>
  mkdir -p "$CLAUDE_CONFIG_DIR/projects/p"
  {
    jq -cn --arg m "$2" '{type: "assistant", isSidechain: false, message: {model: $m}}'
    jq -cn '{type: "assistant", isSidechain: true, message: {model: "claude-helper-1"}}'
    echo 'not json'
  } >"$CLAUDE_CONFIG_DIR/projects/p/$1.jsonl"
}
opened() { # opened <opener model> <opener effort>: the trace as phase-start.sh leaves it
  jq -cn --arg m "$1" --arg e "$2" '{ts: "2026-01-01T00:00:00Z", event: "phase_opened", session_id: "manager", issue: "7", model: $m, effort: $e}' >"$PROCESS_EVENTS_FILE"
}
check() { # check <session id> <effort>
  env CLAUDE_CODE_SESSION_ID="$1" CLAUDE_EFFORT="$2" sh -c "cd '$wt' && scripts/check-env.sh"
}
session_event() { # session_event <session id> <event> <jq expression>
  jq -r --arg s "$1" --arg e "$2" "select(.event == \$e and .session_id == \$s) | $3" "$PROCESS_EVENTS_FILE"
}

# Same pair as the spec: the session works, and the trace holds the real and the asked pair.
opened claude-big-9 high
transcript child claude-big-9-1
assert_status 0 "check-env accepts the session in the pair of the spec" check child high
out="$(last_output)"
assert_contains "$out" "ok: session pair claude-big-9-1 high (the spec asks big high)" "prints the real and the asked pair"
assert_eq "claude-big-9-1 high big high" "$(session_event child phase_session '[.model, .effort, .requested_model, .requested_effort] | join(" ")')" "phase_session carries the real and the asked pair"
# The rule of the steps: by comparing the pair of the step with the pair of the session.
assert_contains "$out" "step pair big high: the session pair: run it in this session" "a step of the session pair runs in the session"
assert_contains "$out" "step pair small low: another pair: run it in a subagent (Agent with model small, effort low)" "a step of another pair goes to a subagent"
assert_eq 2 "$(echo "$out" | grep -c '^step pair')" "each pair of the spec is listed once"

# Another pair than the asked one: exits non-zero before any step,
# and no phase_session is recorded, so the merge gate stays closed.
transcript wrong claude-small-1
assert_status 1 "check-env refuses a session in another pair" check wrong low
assert_contains "$(last_output)" "runs at claude-small-1 low and the spec of #7 asks big high" "names the two pairs"
assert_eq "" "$(session_event wrong phase_session .issue)" "no phase_session on a divergence"
assert_eq "claude-small-1 low big high" "$(session_event wrong phase_pair_mismatch '[.model, .effort, .requested_model, .requested_effort] | join(" ")')" "records the divergence in the trace"
transcript halfway claude-big-9-1
assert_status 1 "check-env refuses the right model with another effort" check halfway medium

# The spec asks more than the session that opened the phase has: the child opens in the
# pair of the opening session, check-env accepts it and the trace keeps both pairs.
opened claude-mid-2 medium
transcript capped claude-mid-2
assert_status 0 "check-env accepts the pair of the session that opened the phase" check capped medium
assert_contains "$(last_output)" "the pair of the session that opened the phase (the spec asks big high; the PR table records it)" "says the PR records it"
assert_eq "claude-mid-2 medium big high" "$(session_event capped phase_session '[.model, .effort, .requested_model, .requested_effort] | join(" ")')" "phase_session keeps the divergence for the PR table"
assert_status 1 "a third pair is still refused" check wrong low

# A pair that cannot be read never passes, even when the opening session is unknown too.
opened unknown unknown
assert_status 1 "check-env refuses a session without a transcript" check ghost high
assert_contains "$(last_output)" "cannot read the real pair" "says the pair was not read"
assert_status 1 "check-env refuses a session without an effort" env -u CLAUDE_EFFORT CLAUDE_CODE_SESSION_ID=child sh -c "cd '$wt' && scripts/check-env.sh"

# new-phase.sh records the pair of the opening session in phase_opened.
cat >"$TMP/handler.sh" <<'H'
case "$*" in
  "issue view "*"--json state,title,labels"*) echo '{"state":"OPEN","title":"Outra","labels":[{"name":"type:feature"}]}' ;;
esac
H
printf '\n## Fase #8 — y\n\n1. Etapa. modelo: big · esforço: high · motivo: forte\n' >>"$repo/docs/specs/pair.md"
git clone --quiet --bare "$repo" "$TMP/remote.git"
git -C "$repo" remote add origin "$TMP/remote.git"
git -C "$repo" fetch --quiet origin
transcript manager claude-mid-2
assert_status 0 "phase-start opens the phase" env CLAUDE_CODE_SESSION_ID=manager CLAUDE_EFFORT=medium sh -c "cd '$repo' && scripts/phase-start.sh 8 --no-check"
assert_eq "claude-mid-2 medium" "$(jq -r 'select(.event == "phase_opened" and .issue == "8") | "\(.model) \(.effort)"' "$PROCESS_EVENTS_FILE")" "phase_opened carries the pair of the opening session"
assert_contains "$(last_output)" "model: big" "start_session gets the pair of the spec"

finish
