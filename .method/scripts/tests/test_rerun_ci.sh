#!/usr/bin/env bash
# .method/scripts/rerun-ci.sh reruns only the failed jobs of ci.yml on the PR head.
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

repo="$(make_repo)"
mkdir -p "$repo/.method/scripts/lib" "$repo/.github/workflows"
cp "$SCRIPTS/lib/common.sh" "$repo/.method/scripts/lib/common.sh"
cp "$SCRIPTS/rerun-ci.sh" "$repo/.method/scripts/rerun-ci.sh"
chmod +x "$repo/.method/scripts/rerun-ci.sh"
R="$repo/.method/scripts/rerun-ci.sh"
HEAD=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
cat >"$TMP/handler.sh" <<'H'
case "$*" in
  "api repos/owner/repo/actions/runs/"*"/jobs")
    printf '%s\n' "$FAKE_JOBS" ;;
  "api repos/owner/repo/actions/runs/"*)
    printf '%s\n' "${FAKE_RUN:-}" ;;
  "pr view 4 --repo owner/repo --json headRefOid --jq .headRefOid")
    printf '%s\n' "${FAKE_PR_HEAD:-}" ;;
  "run rerun "*" --failed --repo owner/repo") echo rerun ;;
esac
H
use_fake_gh "$TMP/handler.sh"
export FAKE_PR_HEAD="$HEAD"
export FAKE_JOBS='{"jobs":[{"name":"Tests","conclusion":"timed_out"}]}'
export FAKE_RUN="{\"path\":\".github/workflows/ci.yml\",\"head_sha\":\"$HEAD\",\"pull_requests\":[{\"number\":4}]}"

assert_status 0 "reruns the failed jobs of ci.yml on the PR head" "$R" 9
assert_contains "$(gh_calls)" "run rerun 9 --failed" "asks gh to rerun only the failed jobs"
assert_contains "$(last_output)" "attempt 1 of 2" "counts the attempt"

export FAKE_RUN='{"path":".github/workflows/deploy-example.yml","head_sha":"'"$HEAD"'","pull_requests":[{"number":4}]}'
: >"$FAKE_GH_LOG"
assert_status 1 "refuses a run of another workflow" "$R" 9
assert_contains "$(last_output)" "deploy-example.yml" "names the refused workflow"
assert_not_contains "$(gh_calls)" "run rerun" "does not rerun another workflow"

export FAKE_RUN="{\"path\":\".github/workflows/ci.yml\",\"head_sha\":\"$HEAD\",\"pull_requests\":[{\"number\":4}]}"
export FAKE_PR_HEAD=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
: >"$FAKE_GH_LOG"
assert_status 1 "refuses a ci.yml run that is not the PR head" "$R" 9
assert_contains "$(last_output)" "not the HEAD" "says the run is not the PR head"
assert_not_contains "$(gh_calls)" "run rerun" "does not rerun an old SHA"

export FAKE_PR_HEAD="$HEAD"
export FAKE_JOBS='{"jobs":[{"name":"Tests","conclusion":"success"}]}'
: >"$FAKE_GH_LOG"
assert_status 1 "refuses a run with no failed job" "$R" 8
assert_not_contains "$(gh_calls)" "run rerun" "does not rerun a green run"

export FAKE_JOBS='{"jobs":[{"name":"Tests","conclusion":"failure"}]}'
: >"$FAKE_GH_LOG"
assert_status 0 "the second rerun is still inside the limit" env RERUN_CI_LIMIT=2 "$R" 9
assert_contains "$(gh_calls)" "run rerun 9 --failed" "the second attempt still reruns"
: >"$FAKE_GH_LOG"
assert_status 1 "past the limit it offers an issue and does not rerun" env RERUN_CI_LIMIT=2 "$R" 9
assert_contains "$(last_output)" "offer:" "offers an issue for the intermittent failure"
assert_contains "$(last_output)" "open-issue.sh --type finding" "names how to open the issue"
assert_not_contains "$(gh_calls)" "run rerun" "does not rerun after the limit"

# A job cancelled by a network failure (issue #209) counts as failed for the rerun.
export FAKE_JOBS='{"jobs":[{"name":"CI","conclusion":"cancelled"}]}'
: >"$FAKE_GH_LOG"
assert_status 0 "reruns a run whose job CI was cancelled" "$R" 11
assert_contains "$(gh_calls)" "run rerun 11 --failed" "asks gh to rerun the cancelled job"

# A request GitHub refuses with a 5xx is not a rerun: it is not counted and the error shows (issue #302).
export FAKE_JOBS='{"jobs":[{"name":"CI","conclusion":"failure"}]}'
: >"$FAKE_GH_LOG"
assert_status 1 "a refused rerun request fails" env FAKE_GH_FAIL='run rerun 12' FAKE_GH_FAIL_MSG='HTTP 500: Server Error' RERUN_CI_LIMIT=1 "$R" 12
assert_contains "$(last_output)" "HTTP 500" "shows the error of the refused request"
assert_not_contains "$(last_output)" "reran the failed jobs" "does not report a rerun"
assert_status 0 "the refused request did not use the limit" env RERUN_CI_LIMIT=1 "$R" 12
assert_contains "$(last_output)" "attempt 1 of 1" "the first accepted rerun is attempt 1"

finish
