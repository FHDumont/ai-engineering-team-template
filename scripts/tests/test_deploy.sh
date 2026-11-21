#!/usr/bin/env bash
# Tests of deploy.sh in a sandbox: one test per refusal and per path.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"
repo="$(make_repo)"
copy_scripts "$repo"
mkdir -p "$repo/.github/workflows" "$repo/app"
printf '# deploy-paths: app/ .github/workflows/deploy-app.yml\non:\n  workflow_dispatch:\n' >"$repo/.github/workflows/deploy-app.yml"
echo v1 >"$repo/app/index.html"
printf '.worktrees/\n.process/\n' >"$repo/.gitignore"
git -C "$repo" add scripts .github app .gitignore
git -C "$repo" commit --quiet -m "chore: scripts and app"
remote="$TMP/remote.git"
git clone --quiet --bare "$repo" "$remote"
git -C "$repo" remote add origin "$remote"
git -C "$repo" fetch --quiet origin
DEPLOY="$repo/scripts/deploy.sh"
SHA="$(git -C "$repo" rev-parse HEAD)"
TRACE="$repo/.process/events.jsonl"
mkdir -p "$repo/.process"

# Fake GitHub. FAKE_PRS: JSON of the open PRs. FAKE_RUNS: JSON of the runs before
# the dispatch. The dispatched run is id 77 on FAKE_RUN_SHA; it ends as
# FAKE_CONCLUSION after FAKE_POLLS reads that still show it in progress.
cat >"$TMP/handler.sh" <<H
run77() { # run77 <status> <conclusion>
  jq -cn --arg s "\${FAKE_RUN_SHA:-$SHA}" --arg st "\$1" --arg c "\$2" \
    '{databaseId: 77, headSha: \$s, status: \$st, conclusion: \$c, url: "https://x/actions/runs/77"}'
}
case "\$*" in
  "pr list"*) echo "\${FAKE_PRS:-[]}" ;;
  "workflow run"*) touch "$TMP/dispatched" ;;
  "run list"*)
    if [ -f "$TMP/dispatched" ]; then
      jq -cn --argjson old "\${FAKE_RUNS:-[]}" --argjson new "\$(run77 queued "")" '[\$new] + \$old'
    else
      echo "\${FAKE_RUNS:-[]}"
    fi ;;
  "run view 77"*)
    echo x >>"$TMP/polls"
    if [ "\$(wc -l <"$TMP/polls")" -le "\${FAKE_POLLS:-1}" ]; then run77 in_progress ""; else run77 completed "\${FAKE_CONCLUSION:-success}"; fi ;;
esac
H
use_fake_gh "$TMP/handler.sh"
run() { # run <exit code> <description> [VAR=value...]
  local want="$1" what="$2"
  shift 2
  : >"$FAKE_GH_LOG"; rm -f "$TMP/dispatched" "$TMP/polls"
  assert_status "$want" "$what" env CLAUDE_CODE_SESSION_ID=main ${1+"$@"} sh -c "cd '$repo' && '$DEPLOY' --interval 0 --timeout 10"
}
dispatches() { gh_calls | grep -c '^workflow run' || true; }
success_run() { # success_run <sha> [status] [conclusion]
  jq -cn --arg s "$1" --arg st "${2:-completed}" --arg c "${3-success}" \
    '[{databaseId: 70, headSha: $s, status: $st, conclusion: $c, url: "https://x/actions/runs/70"}]'
}

assert_status 0 "--help works" "$DEPLOY" --help
assert_contains "$(last_output)" "Usage: deploy.sh" "--help shows the usage"

# --timeout and --interval take a whole number of seconds: without a value, with
# a value that is not a number or with a negative one, exit 2 with the usage,
# before anything is dispatched or read from GitHub.
usage_error() { # usage_error <description> <deploy.sh arguments...>
  local what="$1"
  shift
  : >"$FAKE_GH_LOG"; rm -f "$TMP/dispatched" "$TMP/polls"
  assert_status 2 "$what: exits 2" env CLAUDE_CODE_SESSION_ID=main sh -c 'cd "$1" && shift && "$@"' sh "$repo" "$DEPLOY" "$@"
  assert_contains "$(last_output)" "Usage: deploy.sh [--timeout seconds] [--interval seconds]" "$what: shows the usage"
  assert_eq "" "$(gh_calls)" "$what: dispatches nothing and reads nothing from GitHub"
}
usage_error "--timeout without a value" --interval 0 --timeout
usage_error "--interval without a value" --timeout 10 --interval
usage_error "--timeout with a value that is not a number" --interval 0 --timeout soon
usage_error "--interval with a value that is not a number" --timeout 10 --interval fast
usage_error "--timeout with a negative value" --interval 0 --timeout -5
usage_error "--interval with a negative value" --timeout 10 --interval -1

# Refusals: each one dispatches nothing.
run 1 "refuses without a session id" CLAUDE_CODE_SESSION_ID=
assert_contains "$(last_output)" "no session id" "says the session id is missing"
assert_eq 0 "$(dispatches)" "no dispatch without a session id"

jq -cn '{event: "phase_session", session_id: "child", issue: "7"}' >"$TRACE"
run 1 "refuses in a session that has phase_session in the trace" CLAUDE_CODE_SESSION_ID=child
assert_contains "$(last_output)" "phase session" "says the phase session never deploys"
assert_contains "$(last_output)" "#7" "names the phase"
assert_eq 0 "$(dispatches)" "no dispatch from a phase session"
echo "not json" >>"$TRACE"
run 1 "refuses when a trace line is not JSON"
assert_eq 0 "$(dispatches)" "no dispatch with an unreadable trace"
jq -cn '{event: "phase_session", session_id: "child", issue: "7"}' >"$TRACE"

mkdir -p "$repo/.worktrees"
printf '5\tfeat/issue-5-x\t%s\n' "$repo/.worktrees/issue-5" >"$repo/.worktrees/parallel-active.tsv"
run 1 "refuses with a non-empty parallel registry"
assert_contains "$(last_output)" "parallel phases are still registered" "says the registry is not empty"
assert_eq 0 "$(dispatches)" "no dispatch with parallel phases registered"
: >"$repo/.worktrees/parallel-active.tsv"

git -C "$repo" worktree add --quiet -b feat/issue-5-x "$repo/.worktrees/issue-5" main
run 1 "refuses with a phase open"
assert_contains "$(last_output)" "phase still open (worktree of #5)" "names the open phase"
assert_eq 0 "$(dispatches)" "no dispatch with a phase open"
assert_status 1 "refuses outside the main checkout" env CLAUDE_CODE_SESSION_ID=main sh -c "cd '$repo/.worktrees/issue-5' && scripts/deploy.sh --interval 0"
assert_contains "$(last_output)" "runs from the main checkout" "says where it runs"
git -C "$repo" worktree remove --force "$repo/.worktrees/issue-5"
git -C "$repo" branch -D feat/issue-5-x >/dev/null

run 1 "refuses with a phase PR open" FAKE_PRS='[{"number":12,"headRefName":"fix/issue-9-y"}]'
assert_contains "$(last_output)" "phase PR still open (#12 (fix/issue-9-y))" "names the open PR"
assert_eq 0 "$(dispatches)" "no dispatch with a phase PR open"

# The main session that opened phases with the old new-phase.sh has phase_session
# events of its own (check-env.sh ran in it): a phase_session of an issue the same
# session opened does not make it a phase session.
cp "$TRACE" "$TMP/trace.bak"
{ jq -cn '{event: "phase_opened", session_id: "main", issue: "96"}'
  jq -cn '{event: "phase_session", session_id: "main", issue: "96"}'
  jq -cn '{event: "phase_opened", session_id: "main", issue: "97"}'
  jq -cn '{event: "phase_session", session_id: "main", issue: 97}'; } >"$TRACE"
run 0 "deploys from the session whose phase_session is of a phase it opened itself"
assert_eq 1 "$(dispatches)" "the main session that opened the phases dispatches"
# A phase_session of an issue the session did not open: still a phase session.
jq -cn '{event: "phase_opened", session_id: "other", issue: "98"}' >>"$TRACE"
jq -cn '{event: "phase_session", session_id: "main", issue: "98"}' >>"$TRACE"
run 1 "refuses the session with a phase_session of an issue it did not open"
assert_contains "$(last_output)" "phase_session of #98 in the trace" "names only the phase it did not open"
assert_not_contains "$(last_output)" "#96" "does not name the phase it opened itself"
assert_eq 0 "$(dispatches)" "no dispatch from the session of a phase it did not open"
cp "$TMP/trace.bak" "$TRACE"

# First deploy: dispatches once on main, prints the run URL, waits and reads the result.
: >"$PROCESS_EVENTS_FILE"
run 0 "deploys when nothing was deployed yet" FAKE_POLLS=2 FAKE_PRS='[{"number":13,"headRefName":"gen-docs/abc"}]'
out="$(last_output)"
assert_eq 1 "$(dispatches)" "dispatches once"
assert_contains "$(gh_calls)" "workflow run deploy-app.yml --repo owner/repo --ref main" "dispatches the workflow on main"
assert_contains "$out" "deploy run: https://x/actions/runs/77" "prints the run URL"
assert_contains "$out" "deployed: deploy-app.yml on main at ${SHA:0:12}" "reports the deploy read back"
assert_eq 3 "$(gh_calls | grep -c '^run view 77')" "waits until the run completes"
assert_contains "$(cat "$PROCESS_EVENTS_FILE")" '"conclusion":"success"' "records the deploy in the trace"

# A failed run exits non-zero and shows the URL.
run 4 "exits 4 when the run fails" FAKE_CONCLUSION=failure
assert_contains "$(last_output)" "deploy failed: deploy-app.yml run 77 ended as failure: https://x/actions/runs/77" "says the run failed, with the URL"
run 3 "exits 3 when the run does not finish in time" FAKE_POLLS=99

# Never twice on the same SHA.
run 0 "does not dispatch twice on the same SHA" FAKE_RUNS="$(success_run "$SHA")"
assert_eq 0 "$(dispatches)" "no second dispatch on a deployed SHA"
assert_contains "$(last_output)" "already deployed main at ${SHA:0:12}: https://x/actions/runs/70" "points to the run that deployed it"
run 0 "a run still going on the same SHA is waited for, not dispatched again" \
  FAKE_RUNS="$(jq -cn --arg s "$SHA" '[{databaseId: 77, headSha: $s, status: "in_progress", conclusion: "", url: "https://x/actions/runs/77"}]')"
assert_eq 0 "$(dispatches)" "no dispatch while a run is going on the SHA"
assert_contains "$(last_output)" "deployed: deploy-app.yml" "reads the result of the run in progress"
run 0 "a failed run on the same SHA is deployed again" FAKE_RUNS="$(success_run "$SHA" completed failure)"
assert_eq 1 "$(dispatches)" "dispatches after a failed run on the SHA"

# No change in the app since the last deploy: no dispatch.
echo docs >"$repo/NOTES.md"
git -C "$repo" add NOTES.md
git -C "$repo" commit --quiet -m "docs: notes"
git -C "$repo" push --quiet origin main
run 0 "does not deploy without a change in the app" FAKE_RUNS="$(success_run "$SHA")"
assert_eq 0 "$(dispatches)" "no dispatch without a change in the deploy paths"
assert_contains "$(last_output)" "no change in (app/ .github/workflows/deploy-app.yml) since the last deploy at ${SHA:0:12}" "says nothing changed"
echo v2 >"$repo/app/index.html"
git -C "$repo" add app/index.html
git -C "$repo" commit --quiet -m "feat: app v2"
git -C "$repo" push --quiet origin main
NEW="$(git -C "$repo" rev-parse HEAD)"
run 0 "deploys when the app changed since the last deploy" FAKE_RUNS="$(success_run "$SHA")" FAKE_RUN_SHA="$NEW"
assert_eq 1 "$(dispatches)" "dispatches after a change in the app"
run 0 "deploys when the last deployed SHA is unknown here" FAKE_RUNS="$(success_run 0123456789012345678901234567890123456789)" FAKE_RUN_SHA="$NEW"
assert_eq 1 "$(dispatches)" "dispatches when the last deploy cannot be compared"

# A deploy workflow that does not say what it deploys stops the script.
printf 'on:\n  workflow_dispatch:\n' >"$repo/.github/workflows/deploy-app.yml"
git -C "$repo" add .github/workflows/deploy-app.yml
git -C "$repo" commit --quiet -m "ci: drop deploy paths"
git -C "$repo" push --quiet origin main
run 1 "refuses a deploy workflow without deploy-paths"
assert_eq 0 "$(dispatches)" "no dispatch without deploy-paths"
git -C "$repo" rm --quiet .github/workflows/deploy-app.yml
git -C "$repo" commit --quiet -m "ci: no deploy"
git -C "$repo" push --quiet origin main
run 0 "nothing to deploy without a deploy workflow"
assert_contains "$(last_output)" "no deploy-*.yml workflow" "says there is no deploy workflow"
finish
