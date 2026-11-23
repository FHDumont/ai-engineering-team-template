#!/usr/bin/env bash
# A pull request that is not a phase branch (not fix/issue-*) receives
# review/independent and merges only with --pr, --owner-ok equal to that PR
# head, green CI and the saved independent review of that SHA. A phase branch
# is refused on this path and keeps --merge.
# shellcheck source=scripts/tests/close_phase_common.sh
source "$(dirname "$0")/close_phase_common.sh"

git -C "$repo" switch --quiet -c renovate/lodash
echo dep >"$repo/dep.txt"
git -C "$repo" add dep.txt
git -C "$repo" commit --quiet -m "chore: bump lodash"
OUTSHA="$(git -C "$repo" rev-parse HEAD)"
# The command names the PR; it does not use the checkout that happens to be current.
git -C "$repo" switch --quiet feat/issue-5-x

outside_handler() {
  cat >"$TMP/handler-out.sh" <<H
case "\$*" in
  "pr view 40"*"headRefName"*)
    jq -cn --arg b "\${FAKE_HEAD_BRANCH:-renovate/lodash}" --arg s "\${FAKE_HEAD_SHA:-$OUTSHA}" --arg base "\${FAKE_BASE:-main}" '{headRefName: \$b, headRefOid: \$s, baseRefName: \$base}' ;;
  "pr view 40"*"--json body"*) printf '%s\n' "\${FAKE_PR_BODY:-Resumo}" ;;
  "pr view 40"*"--json commits"*) echo '{"commits":[]}' ;;
  "api repos/owner/repo/commits/"*"/status"*) echo "\${FAKE_REVIEW:-success}" ;;
  "api repos/owner/repo/commits/"*"/check-runs"*) echo "\${FAKE_CI:-success}" ;;
  "api repos/owner/repo/branches/"*"/protection"*)
    [ "\${FAKE_PROTECTION:-}" != none ] || { echo '{"message":"Branch not protected"}'; exit 1; }
    printf '%s\n' \${FAKE_PROTECTION:-CI review/independent} ;;
  "variable list"*) [ -z "\${FAKE_MODE:-}" ] || echo PROCESS_BRANCH_MODE ;;
  "pr view 40"*"--json state"*) echo "\${FAKE_PR_STATE:-OPEN}" ;;
esac
H
  use_fake_gh "$TMP/handler-out.sh"
}

save_review() { # save_review <sha> <verdict>
  mkdir -p "$repo/.process"
  printf 'Revisão independente do SHA %s.\n' "$1" >"$repo/.process/reviewer-$1.md"
  printf '%s\n' "$2" >"$repo/.process/reviewer-$1.verdict"
}

outside_handler
save_review "$OUTSHA" success
: >"$FAKE_GH_LOG"
assert_status 0 "publishes review/independent on a non-phase pull request" \
  sh -c "cd '$repo' && '$CLOSE' --pr 40 --publish-review '$repo/.process/reviewer-$OUTSHA.md' --verdict success"
assert_contains "$(gh_calls)" "api -X POST repos/owner/repo/statuses/$OUTSHA -f state=success -f context=review/independent" \
  "sets review/independent on the pull request head"
assert_contains "$(gh_calls)" "pr comment 40" "posts the saved review"
assert_not_contains "$(git -C "$repo" rev-parse HEAD)" "$OUTSHA" "the checkout head is not the pull request head"

for phase_branch in feat/issue-9-x fix/issue-9-x docs/issue-9-x chore/issue-9-x; do
  : >"$FAKE_GH_LOG"
  assert_status 2 "refuses to publish a phase branch $phase_branch through --pr" \
    env FAKE_HEAD_BRANCH="$phase_branch" \
    sh -c "cd '$repo' && '$CLOSE' --pr 40 --publish-review '$repo/.process/reviewer-$OUTSHA.md' --verdict success"
  assert_contains "$(last_output)" "phase branch" "says a phase branch keeps --merge ($phase_branch)"
  assert_not_contains "$(gh_calls)" "statuses" "no status on a phase branch ($phase_branch)"
done

: >"$FAKE_GH_LOG"
assert_status 5 "refuses a non-phase merge without --owner-ok" \
  sh -c "cd '$repo' && '$CLOSE' --pr 40 --merge"
assert_contains "$(last_output)" "--owner-ok" "says the owner's ok is required"
assert_not_contains "$(gh_calls)" "pr merge" "no merge without --owner-ok"

: >"$FAKE_GH_LOG"
assert_status 5 "refuses --owner-ok for another SHA" \
  sh -c "cd '$repo' && '$CLOSE' --pr 40 --merge --owner-ok deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
assert_contains "$(last_output)" "does not match HEAD" "says the SHA is not the pull request head"
assert_not_contains "$(gh_calls)" "pr merge" "no merge on the wrong SHA"

: >"$FAKE_GH_LOG"
assert_status 11 "refuses a non-phase merge when CI is missing" \
  env FAKE_CI=missing \
  sh -c "cd '$repo' && '$CLOSE' --pr 40 --merge --owner-ok '$OUTSHA'"
assert_contains "$(last_output)" "CI is missing" "says CI is missing"
assert_not_contains "$(gh_calls)" "pr merge" "no merge without CI"

for phase_branch in feat/issue-9-x fix/issue-9-x docs/issue-9-x chore/issue-9-x; do
  : >"$FAKE_GH_LOG"
  assert_status 2 "refuses to merge a phase branch $phase_branch through --pr" \
    env FAKE_HEAD_BRANCH="$phase_branch" \
    sh -c "cd '$repo' && '$CLOSE' --pr 40 --merge --owner-ok '$OUTSHA'"
  assert_contains "$(last_output)" "phase branch" "a phase branch is not this command ($phase_branch)"
  assert_not_contains "$(gh_calls)" "pr merge" "the phase gate is not bypassed ($phase_branch)"
done

rm -f "$repo/.process/reviewer-$OUTSHA.md" "$repo/.process/reviewer-$OUTSHA.verdict"
: >"$FAKE_GH_LOG"
assert_status 1 "refuses a non-phase merge without the saved review of that SHA" \
  sh -c "cd '$repo' && '$CLOSE' --pr 40 --merge --owner-ok '$OUTSHA'"
assert_contains "$(last_output)" "no saved reviewer output" "says the saved review is missing"
assert_not_contains "$(gh_calls)" "pr merge" "no merge without the saved review"
save_review "$OUTSHA" success

: >"$FAKE_GH_LOG"
assert_status 0 "merges a non-phase pull request with --owner-ok, green CI and the saved review" \
  sh -c "cd '$repo' && '$CLOSE' --pr 40 --merge --owner-ok '$OUTSHA'"
calls="$(gh_calls)"
assert_contains "$calls" "pr merge 40 --repo owner/repo --auto --rebase --delete-branch" "merges with rebase"
assert_not_contains "$calls" "--admin" "never as admin"
assert_not_contains "$calls" "--squash" "never squash"

outside_fn="$(sed -n '/^outside_merge() {/,/^}$/p' "$SCRIPTS/close-phase.sh")"
assert_contains "$outside_fn" "owner_ok" "the non-phase merge checks --owner-ok"
assert_not_contains "$outside_fn" "phase_gate" "the non-phase merge does not call the phase gate"
phase_fn="$(sed -n '/^merge() {/,/^}$/p' "$SCRIPTS/close-phase.sh")"
assert_contains "$phase_fn" "phase_gate" "a phase branch still goes through phase_gate"

readme="$(cat "$REPO/README.md")"
warn_at="$(printf '%s\n' "$readme" | awk '/Antes de ligar a proteção/{print NR; exit}')"
setup_at="$(printf '%s\n' "$readme" | awk '/O agente roda `scripts\/setup-repo.sh`/{print NR; exit}')"
assert_contains "$readme" 'fix/issue-*' "the README names the phase branch the warning is about"
assert_contains "$readme" '--owner-ok' "the README names --owner-ok"
if [ -n "$warn_at" ] && [ -n "$setup_at" ] && [ "$warn_at" -lt "$setup_at" ]; then
  ok
else
  bad "the README warns before setup turns protection on (warning line ${warn_at:-none}, setup line ${setup_at:-none})"
fi

design="$(awk '/^## 10\. /{p=1} p && /^## 11\./{exit} p' "$REPO/docs/process-design.md")"
assert_contains "$design" '--pr' "process-design §10 names --pr"
assert_contains "$design" 'fix/issue-*' "process-design §10 keeps the phase branch on --merge"
assert_contains "$design" '--owner-ok' "process-design §10 requires --owner-ok of the HEAD"

assert_status 0 "setup-repo.sh warns before it turns protection on" \
  awk '
    /warning:.*fix\/issue-\*/ { seen = 1 }
    seen && /gh api -X PUT "repos\/\$repo\/branches\/\$branch\/protection"/ { found = 1 }
    END { exit !found }
  ' "$SCRIPTS/setup-repo.sh"

finish
