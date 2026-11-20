#!/usr/bin/env bash
# Tests of close-phase.sh: sensitive refusal, review/independent and merge only with --rebase.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

# Clones the scripts into a temporary repo with a local "origin" remote.
repo="$(make_repo)"
mkdir -p "$repo/.github"
# copy_scripts stubs validate.sh and check-docs.sh before the first close-phase.sh
# call: --prepare never reaches the real suite from here, whatever the gate answers.
copy_scripts "$repo"
assert_contains "$(cat "$repo/scripts/validate.sh")" "ok: stub" "validate.sh is a stub from the copy on"
assert_contains "$(cat "$repo/scripts/check-docs.sh")" "ok: stub" "check-docs.sh is a stub from the copy on"
cp "$REPO/.github/sensitive-paths" "$REPO/.github/labels.tsv" "$repo/.github/"
git -C "$repo" add scripts .github
git -C "$repo" commit --quiet -m "chore: scripts"
remote="$TMP/remote.git"
git clone --quiet --bare "$repo" "$remote"
git -C "$repo" remote add origin "$remote"
# Counts the pushes of the round with a pre-push hook in the test repo.
PUSH_LOG="$TMP/pushes.log"; : >"$PUSH_LOG"
mkdir -p "$TMP/hooks"
printf '#!/bin/sh\necho push >>"%s"\n' "$PUSH_LOG" >"$TMP/hooks/pre-push"
chmod +x "$TMP/hooks/pre-push"
git -C "$repo" config core.hooksPath "$TMP/hooks"
# Gate of --merge: the trace the gate reads is .process/events.jsonl of the checkout
# (PROCESS_EVENTS_FILE never redirects it). The phase needs phase_opened, and the
# session that merges must be another one, with its own phase_session (check-env.sh)
# and an event recorded by the harness hooks (trace-event.sh).
TRACE="$repo/.process/events.jsonl"
mkdir -p "$repo/.process"
printf '.process/\n' >>"$repo/.git/info/exclude"
ev() { jq -cn --arg e "$1" --arg s "$2" --arg i "${3:-}" '{event: $e, session_id: $s, issue: $i}' >>"$TRACE"; }
push_ev() { jq -cn --arg b feat/issue-5-x --arg s "$1" '{event: "phase_push", branch: $b, sha: $s}' >>"$TRACE"; }
round_ev() { jq -cn --arg s "${1:-child}" --arg t "${2:-close-reviewer}" '{event: "SubagentStart", session_id: $s, agent_type: $t}' >>"$TRACE"; }
# The child session with the review evidence --merge asks for: the push of HEAD and,
# after it, a close-reviewer round of the session. NO_REVIEW=1 leaves the evidence out.
child_session() { # child_session <issue> [session_id of the working session]
  ev phase_opened plan "$1"
  ev SessionStart "${2:-child}"
  ev phase_session "${2:-child}" "$1"
  [ -n "${NO_REVIEW:-}" ] || { push_ev "$SHA"; round_ev "${2:-child}"; }
}
reset_phase_evidence() { rm -f "$PROCESS_EVENTS_FILE" "$TRACE" "$TMP/subagent-phases"; }
# Every close-phase.sh call below runs as the child session, unless it says otherwise.
export CLAUDE_CODE_SESSION_ID=child
pushes() { wc -l <"$PUSH_LOG" | tr -d ' '; }
git -C "$repo" fetch --quiet origin
git -C "$repo" switch --quiet -c feat/issue-5-x
echo x >"$repo/feature.txt"
git -C "$repo" add feature.txt
git -C "$repo" commit --quiet -m "feat: x"
git -C "$repo" push --quiet origin feat/issue-5-x
SHA="$(git -C "$repo" rev-parse HEAD)"
CLOSE="$repo/scripts/close-phase.sh"

handler() { # handler <comma-separated labels> <review state>
  cat >"$TMP/handler.sh" <<H
case "\$*" in
  "pr list"*"--state open"*) echo 12 ;;
  "pr view 12 --json body"*) printf '%s\n' "\${FAKE_PR_BODY:-Resumo}" ;;
  "pr view 12"*"labels,headRefOid,baseRefName"*) jq -cn --arg l "$1" --arg s "$SHA" --arg b "\${FAKE_BASE:-main}" '{labels: (\$l | split(",") | map(select(length>0)) | map({name: .})), headRefOid: \$s, baseRefName: \$b}' ;;
  "pr view 12"*"headRefOid --jq"*) echo "$SHA" ;;
  "issue view 5"*"labels"*) printf '%s\n' "\${FAKE_ISSUE_LABELS:-type:feature}" | tr ',' '\n' ;;
  "api repos/owner/repo/commits/$SHA/status"*) echo "$2" ;;
  # Protection of main: FAKE_PROTECTION=none answers like an unprotected branch;
  # any other value is the list of required contexts.
  "api repos/owner/repo/branches/main/protection"*)
    [ "\${FAKE_PROTECTION:-}" != none ] || { echo '{"message":"Branch not protected","status":"404"}'; exit 1; }
    printf '%s\n' \${FAKE_PROTECTION:-CI review/independent} ;;
  # needs-owner-ok put on the PR by close-phase.sh (through label-issue.sh).
  "issue edit 12"*"--add-label needs-owner-ok"*) touch "$TMP/owner-label" ;;
  "issue view 12"*"--json labels"*) [ ! -f "$TMP/owner-label" ] || echo needs-owner-ok ;;
  "pr view 12 --repo owner/repo --json state"*) echo "\${FAKE_PR_STATE:-OPEN}" ;;
  "pr view 12 --repo owner/repo --json mergeable,mergeStateStatus,headRefOid"*)
    # FAKE_UNKNOWN_READS: how many reads return UNKNOWN before the final value.
    reads=\$(( \$(cat "$TMP/reads" 2>/dev/null || echo 0) + 1 )); echo "\$reads" >"$TMP/reads"
    m="\${FAKE_MERGEABLE:-MERGEABLE}"; s="\${FAKE_MERGE_STATE:-CLEAN}"
    [ "\$reads" -gt "\${FAKE_UNKNOWN_READS:-0}" ] || { m=UNKNOWN; s=UNKNOWN; }
    jq -cn --arg m "\$m" --arg s "\$s" --arg h "$SHA" '{mergeable: \$m, mergeStateStatus: \$s, headRefOid: \$h}' ;;
  "api repos/owner/repo/commits/$SHA/check-runs"*) echo "\${FAKE_HEAD_CHECKS:-1}" ;;
  "api repos/owner/repo/commits/"*"/check-runs"*) echo 3 ;;
esac
H
  use_fake_gh "$TMP/handler.sh"
  rm -f "$TMP/reads" "$TMP/owner-label"
}

# Barrier: the phase needs a child session; a test issue follows the same path.
reset_phase_evidence
handler "type:feature" success
assert_status 1 "refuses merge without child session" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(last_output)" "no phase_opened" "says the phase was never opened"
assert_not_contains "$(gh_calls)" "pr merge" "never merges a phase without a child session"
child_session 5 plan
assert_status 1 "the planning session itself does not count as a child session" sh -c "cd '$repo' && '$CLOSE' --merge"
child_session 9
assert_status 1 "a child session of another issue does not count" sh -c "cd '$repo' && '$CLOSE' --merge"
reset_phase_evidence
# A line in .process/subagent-phases opens nothing: the announced subagent is gone.
printf '5\tstep too small for a session\n' >"$TMP/subagent-phases"
assert_status 1 "a subagent-phases line does not replace the child session" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_not_contains "$(gh_calls)" "pr merge" "never merges on a subagent-phases line"

# Fails closed: every way around the child session is refused.
merge_refused() { # merge_refused <description> [env assignments and close-phase.sh arguments...]
  local what="$1"
  shift
  handler "type:feature" success
  assert_status 1 "$what" env "$@" sh -c "cd '$repo' && '$CLOSE' --merge \$CLOSE_ARGS"
  assert_not_contains "$(gh_calls)" "pr merge" "no merge: $what"
}
reset_phase_evidence
ev SessionStart child
ev phase_session child 5
merge_refused "phase_session without phase_opened does not open" CLOSE_ARGS=
reset_phase_evidence
child_session 9
handler "type:feature" success
assert_status 2 "--issue of another phase does not open" sh -c "cd '$repo' && '$CLOSE' --merge --issue 9"
assert_not_contains "$(gh_calls)" "pr merge" "no merge with --issue of another phase"
assert_contains "$(last_output)" "--issue 9" "says --issue differs from the branch"
reset_phase_evidence
ev phase_opened plan 5
ev phase_session forged 5
merge_refused "a forged CLAUDE_CODE_SESSION_ID does not open" CLAUDE_CODE_SESSION_ID=forged CLOSE_ARGS=
reset_phase_evidence
child_session 5 other
merge_refused "the phase_session of another session does not cover this one" CLOSE_ARGS=
reset_phase_evidence
child_session 5
merge_refused "no session id does not open" CLAUDE_CODE_SESSION_ID= CLOSE_ARGS=
echo '{"event": "phase_ses' >>"$TRACE"
merge_refused "a corrupted trace line does not open" CLOSE_ARGS=
reset_phase_evidence
jq -cn '{event: "phase_opened", session_id: "plan", issue: "5"}, {event: "SessionStart", session_id: "child"}, {event: "phase_session", session_id: "child", issue: "5"}' >"$TMP/forged.jsonl"
merge_refused "a forged PROCESS_EVENTS_FILE does not open" PROCESS_EVENTS_FILE="$TMP/forged.jsonl" CLOSE_ARGS=
# The session that opened the phase does not close it: every step refuses, with exit 9.
reset_phase_evidence
child_session 5
handler "type:feature" success
echo "Closes #5" >"$TMP/opener-body.md"
for step in "--check" "--merge" "--prepare --title x --body-file $TMP/opener-body.md" "--publish-review $TMP/opener-body.md --verdict success"; do
  assert_status 9 "the opening session cannot run $step" env CLAUDE_CODE_SESSION_ID=plan sh -c "cd '$repo' && '$CLOSE' $step"
done
assert_contains "$(last_output)" "child session" "points to the child session"
assert_eq "" "$(gh_calls)" "the opening session reaches nothing on GitHub"
reset_phase_evidence
child_session 5
handler "type:feature,test" success
assert_status 0 "a test issue closes through the same gate" env FAKE_ISSUE_LABELS="type:feature,test" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(gh_calls)" "pr merge 12" "merges a test issue like any other"
child_session 5
assert_status 0 "merges with the child session present" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(gh_calls)" "pr merge 12" "requests the merge"

child_session 5
handler "type:feature,needs-owner-ok" success
assert_status 5 "refuses merge with needs-owner-ok" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(last_output)" "needs-owner-ok" "says why"
assert_not_contains "$(gh_calls)" "pr merge" "never calls merge when refused"

handler "type:feature,area:auth" success
assert_status 5 "refuses merge with sensitive area label" sh -c "cd '$repo' && '$CLOSE' --merge"

handler "type:feature" missing
assert_status 1 "refuses merge without review/independent" sh -c "cd '$repo' && '$CLOSE' --merge"

handler "type:feature" success
assert_status 0 "merges when clean and reviewed" sh -c "cd '$repo' && '$CLOSE' --merge"
calls="$(gh_calls)"
assert_contains "$calls" "pr merge 12 --repo owner/repo --auto --rebase --delete-branch" "merges with --auto --rebase --delete-branch"
assert_not_contains "$calls" "--admin" "never as admin"
assert_not_contains "$calls" "--squash" "never squash"
assert_contains "$calls" "pr view 12 --json body" "checks the final PR body before merging"

handler "type:feature" success
assert_status 1 "refuses merge when the final PR body is signed" \
  env FAKE_PR_BODY="Co-Authored-By: Claude <noreply@anthropic.com>" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(last_output)" "AI attribution" "says why"
assert_not_contains "$(gh_calls)" "pr merge" "never merges a signed PR"

handler "type:feature,needs-owner-ok" success
assert_status 0 "merges with --owner-ok after the owner's choice" sh -c "cd '$repo' && '$CLOSE' --merge --owner-ok"
assert_contains "$(gh_calls)" "<!-- owner-ok sha:$SHA -->" "records the owner's ok on the PR"

# --owner-ok only counts with needs-owner-ok already on the PR: a refusal
# puts the label there, read back, so the owner sees the PR waiting before any ok.
handler "type:feature,area:auth" success
assert_status 5 "--owner-ok without the label on the PR is refused" sh -c "cd '$repo' && '$CLOSE' --merge --owner-ok"
assert_contains "$(last_output)" "--owner-ok does not count" "says the flag did not count"
assert_not_contains "$(gh_calls)" "pr merge" "never merges on --owner-ok without the label"
assert_not_contains "$(gh_calls)" "<!-- owner-ok" "records no owner's ok without the label"
assert_contains "$(gh_calls)" "issue edit 12 --repo owner/repo --add-label needs-owner-ok" "puts needs-owner-ok on the PR"
assert_contains "$(last_output)" "needs-owner-ok is now on PR #12 (read back)" "the label is read back"
handler "type:feature,area:auth" success
assert_status 5 "a refusal without --owner-ok also puts the label" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(gh_calls)" "--add-label needs-owner-ok" "refusal labels the PR"
handler "type:feature,area:auth" success
assert_status 1 "a label that does not stick fails the refusal" env FAKE_GH_FAIL='^issue edit 12' sh -c "cd '$repo' && '$CLOSE' --merge"
assert_not_contains "$(gh_calls)" "pr merge" "never merges when the label cannot be put"

# review/independent only counts with the reviewer's event in the trace:
# a status posted by hand, without a close-reviewer round after the push of HEAD, opens nothing.
no_review() { # no_review <description> <text expected>
  handler "type:feature" success
  assert_status 1 "$1" sh -c "cd '$repo' && '$CLOSE' --merge"
  assert_contains "$(last_output)" "$2" "says why: $1"
  assert_not_contains "$(gh_calls)" "pr merge" "no merge: $1"
}
reset_phase_evidence; NO_REVIEW=1 child_session 5
no_review "refuses a green status without a recorded push" "no phase_push"
push_ev "$SHA"
no_review "refuses a green status without a reviewer round" "no close-reviewer round after the last push"
round_ev other; round_ev child general-purpose
no_review "the round of another session or agent does not count" "no close-reviewer round after the last push"
round_ev; push_ev "$SHA"
no_review "a push after the round asks for a new round" "no close-reviewer round after the last push"
round_ev
handler "type:feature" success
assert_status 0 "merges with the reviewer round after the push" sh -c "cd '$repo' && '$CLOSE' --merge"

# No merge without the protection of the base branch: the gate is the protection.
handler "type:feature" success
assert_status 1 "refuses merge on an unprotected branch" env FAKE_PROTECTION=none sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(last_output)" "main is not protected" "says the branch is not protected"
assert_contains "$(last_output)" "scripts/setup-repo.sh --only protection" "says the fix command"
assert_not_contains "$(gh_calls)" "pr merge" "never merges without protection"
handler "type:feature" success
assert_status 1 "refuses merge when a required check is missing" env FAKE_PROTECTION="CI" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(last_output)" "does not require review/independent" "names the missing check"
assert_not_contains "$(gh_calls)" "pr merge" "never merges with a partial protection"

# Conflicting PR: --check calls redo-phase.sh, asks nobody and exits 0 with the new PR.
# redo-phase.sh is a stub here (its own behaviour is in test_redo_phase.sh).
export CLOSE_PHASE_MERGEABLE_PAUSE=0 CLOSE_PHASE_CI_TIMEOUT=0 CLOSE_PHASE_CI_POLL=0
cp "$repo/scripts/redo-phase.sh" "$TMP/redo-phase.real"
printf '#!/usr/bin/env bash\necho "redo called" >>"%s"\necho "redone: PR #13 replaces PR #12"\nexit "${FAKE_REDO_RC:-0}"\n' "$TMP/redo.log" >"$repo/scripts/redo-phase.sh"
redo_calls() { if [ -f "$TMP/redo.log" ]; then wc -l <"$TMP/redo.log" | tr -d ' '; else echo 0; fi; }
handler "type:feature" success
assert_status 0 "--check redoes a conflicting PR and exits 0" env FAKE_MERGEABLE=CONFLICTING FAKE_MERGE_STATE=DIRTY sh -c "cd '$repo' && '$CLOSE' --check"
out="$(last_output)"
assert_eq 1 "$(redo_calls)" "--check calls redo-phase.sh once"
assert_contains "$out" "PR #13" "--check shows the new PR"
assert_not_contains "$out" "ask the repo owner" "a conflicting PR asks nobody"
assert_not_contains "$out" "rebase" "a conflicting PR is never offered a rebase"
assert_not_contains "$out" "--force" "never suggests a force push"
assert_not_contains "$(gh_calls)" "check-runs" "does not wait for CI on a conflicting PR"
handler "type:feature" success
assert_status 4 "only a real conflict in the cherry-pick fails --check" env FAKE_MERGEABLE=CONFLICTING FAKE_MERGE_STATE=DIRTY FAKE_REDO_RC=4 sh -c "cd '$repo' && '$CLOSE' --check"
# --merge on a conflicting PR: redone, but never merged (the new PR has no CI and no review).
rm -f "$TMP/redo.log"
handler "type:feature" success
assert_status 6 "--merge redoes a conflicting PR and does not merge" env FAKE_MERGEABLE=CONFLICTING FAKE_MERGE_STATE=DIRTY sh -c "cd '$repo' && '$CLOSE' --merge"
assert_eq 1 "$(redo_calls)" "--merge calls redo-phase.sh once"
assert_not_contains "$(gh_calls)" "pr merge" "never merges a conflicting PR"
# A PR that is only behind main (no conflict) is not redone.
rm -f "$TMP/redo.log"
handler "type:feature" success
assert_status 0 "--check passes on a PR that is only behind" env FAKE_MERGEABLE=MERGEABLE FAKE_MERGE_STATE=BEHIND sh -c "cd '$repo' && '$CLOSE' --check"
assert_eq 0 "$(redo_calls)" "a PR that is only behind is not redone"
cp "$TMP/redo-phase.real" "$repo/scripts/redo-phase.sh"
# No script output offers a rebase or tells anyone to ask about a conflict.
for f in close-phase.sh redo-phase.sh integrate-parallel.sh; do
  assert_not_contains "$(grep -v '^#' "$SCRIPTS/$f")" "rebase onto" "$f offers no rebase"
done
assert_not_contains "$(cat "$SCRIPTS/close-phase.sh")" "both ways out" "close-phase.sh has no choice of ways out"
# UNKNOWN: repeats the read until GitHub computes it.
handler "type:feature" success
assert_status 0 "retries while mergeable is UNKNOWN" env FAKE_UNKNOWN_READS=3 sh -c "cd '$repo' && '$CLOSE' --check"
assert_eq 4 "$(gh_calls | grep -c 'mergeable,mergeStateStatus,headRefOid')" "reads mergeable until it is known"
handler "type:feature" success
assert_status 8 "gives up after 5 UNKNOWN reads" env FAKE_UNKNOWN_READS=9 sh -c "cd '$repo' && '$CLOSE' --check"
assert_eq 5 "$(gh_calls | grep -c 'mergeable,mergeStateStatus,headRefOid')" "at most 5 reads"
# CI missing on HEAD: a green check of an earlier SHA does not count; it does not wait forever.
handler "type:feature" success
assert_status 7 "reports CI missing on HEAD" env FAKE_HEAD_CHECKS=0 sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(last_output)" "CI missing" "says CI is missing"
assert_contains "$(last_output)" "${SHA:0:12}" "names the HEAD SHA"
assert_not_contains "$(gh_calls)" "pr merge" "never merges without CI on HEAD"
handler "type:feature" success
assert_status 0 "--check passes when HEAD has checks" sh -c "cd '$repo' && '$CLOSE' --check"
assert_contains "$(gh_calls)" "commits/$SHA/check-runs" "reads the checks of the HEAD SHA"

# The phase never deploys: merged or not, solo or parallel, close-phase.sh
# dispatches nothing and says who does (scripts/deploy.sh, by the main session).
mkdir -p "$repo/.github/workflows"
printf '# deploy-paths: app/\non:\n  workflow_dispatch:\n' >"$repo/.github/workflows/deploy-example.yml"
printf '#!/usr/bin/env bash\necho called >>"%s"\n' "$TMP/deploy.log" >"$repo/scripts/deploy.sh"
handler "type:feature" success
assert_status 0 "merge request without the merge yet" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_not_contains "$(gh_calls)" "workflow run" "never dispatches the deploy before the merge"
handler "type:feature" success
assert_status 0 "solo phase merged" env FAKE_PR_STATE=MERGED sh -c "cd '$repo' && '$CLOSE' --merge"
assert_eq 0 "$(gh_calls | grep -c 'workflow run')" "a merged solo phase dispatches no deploy"
assert_contains "$(last_output)" "no deploy from the phase: the main session runs scripts/deploy.sh" "says who deploys"
mkdir -p "$repo/.worktrees"
printf '5\tfeat/issue-5-x\t%s\n' "$repo" >"$repo/.worktrees/parallel-active.tsv"
handler "type:feature" success
assert_status 0 "parallel phase merged" env FAKE_PR_STATE=MERGED sh -c "cd '$repo' && '$CLOSE' --merge"
assert_eq 0 "$(gh_calls | grep -c 'workflow run')" "a merged parallel phase dispatches no deploy"
assert_eq "" "$(cat "$TMP/deploy.log" 2>/dev/null || true)" "close-phase.sh never calls deploy.sh"
for word in solo_deploy dispatch_deploy "workflow run"; do
  assert_not_contains "$(cat "$SCRIPTS/close-phase.sh" "$SCRIPTS/lib/common.sh")" "$word" "close-phase.sh and common.sh have no $word"
done
cp "$SCRIPTS/deploy.sh" "$repo/scripts/deploy.sh"
rm -rf "$repo/.worktrees" "$repo/.github/workflows"

# Sensitive path in the diff, even without the label.
mkdir -p "$repo/src/auth"; echo y >"$repo/src/auth/login.py"
git -C "$repo" add src/auth/login.py; git -C "$repo" commit --quiet -m "feat: login"
git -C "$repo" push --quiet origin feat/issue-5-x
SHA="$(git -C "$repo" rev-parse HEAD)"
handler "type:feature" success
assert_status 5 "refuses merge touching sensitive paths" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(last_output)" "src/auth/login.py" "names the sensitive path"

# The list is the union of the base's and the PR's: a PR that drops an entry
# from .github/sensitive-paths (and the entry of the list itself) still needs the ok
# for the path it took out; an entry the PR adds already counts for the new path.
commit_push() { # commit_push <subject> <file...>
  local subject="$1"
  shift
  git -C "$repo" add "$@"; git -C "$repo" commit --quiet -m "$subject"
  git -C "$repo" push --quiet origin feat/issue-5-x
  SHA="$(git -C "$repo" rev-parse HEAD)"
}
grep -vxF -e '**/auth/**' -e '.github/sensitive-paths' "$REPO/.github/sensitive-paths" >"$repo/.github/sensitive-paths"
commit_push "chore: drop entries from the list" .github/sensitive-paths
handler "type:feature" success
assert_status 5 "refuses merge of a PR that drops the entry of a path it touches" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(last_output)" "src/auth/login.py" "the base list still covers the dropped path"
assert_contains "$(last_output)" ".github/sensitive-paths" "the base list still covers the list itself"
printf 'newzone/**\n' >>"$repo/.github/sensitive-paths"
mkdir -p "$repo/newzone"; echo z >"$repo/newzone/a.txt"
commit_push "chore: add an entry to the list" .github/sensitive-paths newzone/a.txt
handler "type:feature" success
assert_status 5 "refuses merge touching a path the PR itself made sensitive" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(last_output)" "newzone/a.txt" "the PR list counts for the new path"
# Fails closed: a base without a readable list blocks the merge, whatever the PR lists.
git -C "$repo" switch --quiet -c nolist main
git -C "$repo" rm --quiet .github/sensitive-paths; git -C "$repo" commit --quiet -m "chore: no list"
git -C "$repo" push --quiet origin nolist
git -C "$repo" switch --quiet feat/issue-5-x
handler "type:feature" success
assert_status 1 "refuses merge when the base has no readable list" env FAKE_BASE=nolist sh -c "cd '$repo' && '$CLOSE' --merge --owner-ok"
assert_contains "$(last_output)" "cannot read .github/sensitive-paths of origin/nolist" "says the base list is unreadable"
assert_not_contains "$(gh_calls)" "pr merge" "never merges without the base list"
cp "$REPO/.github/sensitive-paths" "$repo/.github/sensitive-paths"
git -C "$repo" rm --quiet newzone/a.txt
commit_push "chore: restore the list" .github/sensitive-paths
handler "type:feature" success
# The repo's own list covers the docs checker the CI reads from the base.
assert_eq "scripts/check-docs.sh" "$(echo scripts/check-docs.sh | python3 "$SCRIPTS/lib/sensitive_paths.py" "$REPO/.github/sensitive-paths")" "check-docs.sh is a sensitive path"

# Publish the review: comment + status on the HEAD SHA + review_round in the trace,
# only with a reviewer round of this session after the last push of the branch.
printf 'Revisão: aprovado.\n' >"$TMP/review.md"
export PROCESS_EVENTS_FILE="$TMP/events.jsonl"
review_refused() { # review_refused <description> <text expected in the output>
  : >"$FAKE_GH_LOG"
  assert_status 1 "$1" sh -c "cd '$repo' && '$CLOSE' --publish-review '$TMP/review.md' --verdict success --round 1"
  assert_contains "$(last_output)" "$2" "says why: $1"
  assert_not_contains "$(gh_calls)" "pr comment" "no comment: $1"
  assert_not_contains "$(gh_calls)" "statuses" "no status: $1"
}
reset_phase_evidence
review_refused "refuses a review with no trace" "no trace"
round_ev
review_refused "refuses a review without a recorded push" "no phase_push"
push_ev "$SHA"
review_refused "refuses a review whose reviewer round came before the last push" "no close-reviewer round after the last push"
round_ev other
round_ev child general-purpose
review_refused "the round of another session or of another agent does not count" "no close-reviewer round after the last push"
round_ev
push_ev 0000000000000000000000000000000000000000
review_refused "refuses when the last recorded push is not the PR head" "is not the PR head"
push_ev "$SHA"
review_refused "a new push asks for a new reviewer round" "no close-reviewer round after the last push"
round_ev
: >"$FAKE_GH_LOG"
assert_status 0 "publishes review" sh -c "cd '$repo' && '$CLOSE' --publish-review '$TMP/review.md' --verdict success --round 1"
assert_eq "review_round 1 success 12" "$(jq -r '[.event, .round, .verdict, .pr] | join(" ")' "$PROCESS_EVENTS_FILE")" "records review_round in the trace"
calls="$(gh_calls)"
assert_contains "$calls" "pr comment 12 --repo owner/repo --body-file $TMP/review.md" "posts the review comment"
assert_contains "$calls" "api -X POST repos/owner/repo/statuses/$SHA -f state=success -f context=review/independent" "sets the status on HEAD"
printf 'Co-Authored-By: Claude <noreply@anthropic.com>\n' >"$TMP/signed.md"
assert_status 1 "refuses a signed review" sh -c "cd '$repo' && '$CLOSE' --publish-review '$TMP/signed.md' --verdict success"

# --prepare with no number in the branch: the issue comes from the "Closes #n" of the body.
# The phase branch does not touch docs/STATE.md and gets no generated file.
git -C "$repo" switch --quiet -c chore/no-number origin/main
echo w >"$repo/work.txt"
git -C "$repo" add work.txt; git -C "$repo" commit --quiet -m "chore: work"
printf 'Resumo\n\nCloses #1\n' >"$TMP/body.md"
cat >"$TMP/handler.sh" <<'H'
case "$*" in
  "pr list"*"--state open"*) echo 12 ;;
  "issue view 1"*) printf 'type:chore\nend:lab-test\napproved\n' ;;
  "pr view 12"*) echo '{"number":12,"title":"chore: x","labels":[{"name":"type:chore"}],"url":"u"}' ;;
  "pr list"*"merged"*) echo '[]' ;;
  "issue list"*) echo '[]' ;;
esac
H
use_fake_gh "$TMP/handler.sh"
: >"$PUSH_LOG"
assert_status 0 "prepare runs on a branch without issue number" sh -c "cd '$repo' && scripts/close-phase.sh --prepare --body-file '$TMP/body.md'"
calls="$(gh_calls)"
assert_contains "$calls" "issue view 1" "reads the issue from Closes #1"
assert_contains "$calls" "--add-label type:chore --add-label end:lab-test" "copies the issue labels to the PR"
assert_not_contains "$calls" "--add-label approved" "does not copy approved"
assert_not_contains "$(last_output)" "STATE.md" "prepare does not require a change in docs/STATE.md"
assert_eq "chore: work" "$(git -C "$repo" log -1 --format=%s)" "prepare adds no commit to the branch"
assert_eq "" "$(git -C "$repo" ls-tree -r --name-only HEAD | grep -E '^(CHANGELOG|ROADMAP)\.md$' || true)" "prepare generates no CHANGELOG.md or ROADMAP.md"
assert_not_contains "$calls" "--state merged" "prepare does not read the merged PRs for a changelog"
assert_eq "1" "$(pushes)" "one push per round"
assert_eq "$(git -C "$repo" rev-parse HEAD)" "$(git -C "$remote" rev-parse chore/no-number)" "the push carries the branch HEAD"
assert_eq "chore/no-number $(git -C "$repo" rev-parse HEAD)" "$(jq -r 'select(.event == "phase_push") | [.branch, .sha] | join(" ")' "$PROCESS_EVENTS_FILE" | tail -1)" "prepare records the push in the trace"
# The "Modelo e esforço" section of the body is written by the script, from the trace.
sent="$(echo "$calls" | sed -n 's/^pr edit 12 --repo owner\/repo --title chore: x --body-file //p' | tail -1)"
assert_eq 1 "$([ -n "$sent" ] && [ -f "$sent" ] && echo 1)" "edits the PR when the body changed"
assert_contains "$(cat "$sent")" "Closes #1" "the body keeps what the body file says"
assert_contains "$(cat "$sent")" "## Modelo e esforço" "a body without the section gets it"
assert_contains "$(cat "$sent")" "| etapa | modelo/esforço pedido | modelo/esforço usado |" "the table comes from the script"
# A section filled by hand is replaced by the table of the trace; the other sections stay.
printf 'Resumo\n\nCloses #1\n\n## Modelo e esforço\n\nwritten by hand: big high\n\n## Achados\n\nnenhum\n' >"$TMP/hand.md"
jq -cn '{ts: "2026-01-01T00:00:00Z", event: "phase_session", session_id: "kid", issue: "1", model: "claude-real-1", effort: "low", requested_model: "asked", requested_effort: "high"}' >>"$PROCESS_EVENTS_FILE"
assert_status 0 "prepare with a hand-written pair section" sh -c "cd '$repo' && scripts/close-phase.sh --prepare --body-file '$TMP/hand.md'"
sent_hand="$(gh_calls | sed -n 's/^pr edit 12 .* --body-file //p' | tail -1)"
assert_not_contains "$(cat "$sent_hand")" "written by hand" "the hand-written pair section is replaced"
assert_contains "$(cat "$sent_hand")" "| sessão da fase | asked · high | claude-real-1 · low (diverge) |" "the table shows requested x used from the trace"
assert_contains "$(cat "$sent_hand")" "## Achados" "the sections after it stay"
assert_eq 1 "$(grep -c '^## Modelo e esforço' "$sent_hand")" "one pair section"

# New round without changing title or body: one push and no gh pr edit of the body.
echo y >"$repo/fix.txt"; git -C "$repo" add fix.txt; git -C "$repo" commit --quiet -m "fix: y"
jq -n --rawfile b "$sent_hand" '{number: 12, title: "chore: x", body: $b, labels: [{name: "type:chore"}], url: "u"}' >"$TMP/pr12.json"
cat >"$TMP/handler.sh" <<'H'
case "$*" in
  "pr list"*"--state open"*) echo 12 ;;
  "issue view 1"*) printf 'type:chore\n' ;;
  "pr view 12"*) cat "$FAKE_PR_JSON" ;;
  "pr list"*"merged"*) echo '[]' ;;
  "issue list"*) echo '[]' ;;
esac
H
use_fake_gh "$TMP/handler.sh"
: >"$PUSH_LOG"
assert_status 0 "prepare again with the same title and body" env FAKE_PR_JSON="$TMP/pr12.json" sh -c "cd '$repo' && scripts/close-phase.sh --prepare --body-file '$TMP/hand.md'"
assert_contains "$(last_output)" "title and body unchanged" "says nothing changed"
assert_not_contains "$(gh_calls)" "--body-file" "no gh pr edit when title and body are the same"
assert_eq "1" "$(pushes)" "one push in the second round"

# New PR: one push, then the PR; no number is predicted and nothing is generated.
git -C "$repo" switch --quiet -c chore/new-pr origin/main
echo n >"$repo/new.txt"
git -C "$repo" add new.txt
git -C "$repo" commit --quiet -m "chore: new"
rm -f "$TMP/created"
cat >"$TMP/handler.sh" <<H
case "\$*" in
  "pr list"*"--state open"*) [ -f "$TMP/created" ] && echo 13 ;;
  "pr create"*) touch "$TMP/created" ;;
  "issue view 1"*) printf 'type:chore\n' ;;
esac
H
use_fake_gh "$TMP/handler.sh"
: >"$PUSH_LOG"
assert_status 1 "a new PR needs --title" sh -c "cd '$repo' && scripts/close-phase.sh --prepare --body-file '$TMP/body.md'"
assert_eq "0" "$(pushes)" "no push without the title of a new PR"
assert_status 0 "prepare opens a new PR" sh -c "cd '$repo' && scripts/close-phase.sh --prepare --title 'chore: new' --body-file '$TMP/body.md'"
assert_eq "1" "$(pushes)" "one push for a new PR"
assert_contains "$(gh_calls)" "pr create --repo owner/repo --base main --head chore/new-pr" "opens the PR after the push"
assert_not_contains "$(gh_calls)" "issues?state=all" "predicts no PR number"
assert_eq "" "$(git -C "$repo" ls-tree -r --name-only HEAD | grep -E '^(CHANGELOG|ROADMAP)\.md$' || true)" "a new PR carries no generated file"

# Specs leave by the issue they cite, never by the file name: a spec that cites the
# phase issue and no other open issue is deleted in a phase commit and goes to the PR body.
spec_round() { # spec_round <open issues, JSON> <spec file name> <spec text>
  git -C "$repo" switch --quiet -c "chore/issue-1-spec-$RANDOM" origin/main
  mkdir -p "$repo/docs/specs"
  printf '# Spec\n\n%s\n' "$3" >"$repo/docs/specs/$2"
  git -C "$repo" add docs
  git -C "$repo" commit --quiet -m "docs: spec and state"
  cat >"$TMP/handler.sh" <<H
case "\$*" in
  "pr list"*"--state open"*) echo 12 ;;
  "issue view 1"*) printf 'type:chore\ngroup:g\n' ;;
  "issue list"*"--state open"*) echo '$1' | jq -r "\$(printf '%s' "\$*" | sed -n 's/.*--jq //p')" ;;
  "pr view 12"*) echo '{"number":12,"title":"chore: x","body":"","labels":[],"url":"u"}' ;;
  "pr list"*"merged"*) echo '[]' ;;
  "issue list"*) echo '[]' ;;
esac
H
  use_fake_gh "$TMP/handler.sh"
  assert_status 0 "prepare with a spec ($2, open $1)" sh -c "cd '$repo' && scripts/close-phase.sh --prepare --title 'chore: x' --body-file '$TMP/body.md'"
}
# The file name has nothing of the group: it leaves because it cites #1 and no other open issue.
spec_round '[{"number":1},{"number":40}]' 2026-01-18-plano.md 'Texto da spec da fase #1.'
assert_contains "$(last_output)" "removed docs/specs/2026-01-18-plano.md" "says the spec was removed"
[ ! -e "$repo/docs/specs/2026-01-18-plano.md" ] && ok || bad "spec file is gone"
assert_eq "docs(specs): remove the spec whose last open issue is #1" "$(git -C "$repo" log -1 --format=%s)" "the spec removal is the last commit of the phase"
body_arg="$(gh_calls | sed -n 's/.*pr edit 12 --repo owner\/repo --title chore: x --body-file \([^ ]*\).*/\1/p' | head -1)"
assert_contains "$(cat "$body_arg")" "<summary>Spec (docs/specs/2026-01-18-plano.md)</summary>" "PR body carries the spec"
assert_contains "$(cat "$body_arg")" "Texto da spec da fase #1." "PR body has the spec text"
assert_contains "$(cat "$body_arg")" "Closes #1" "PR body keeps the original text"

# Another open issue cited: the spec stays, whatever the group label says.
spec_round '[{"number":1},{"number":2}]' 2026-01-18-g.md 'Fases #1 e #2.'
assert_contains "$(last_output)" "kept docs/specs/2026-01-18-g.md: it still cites open issue(s) #2" "keeps the spec while another cited issue is open"
[ -e "$repo/docs/specs/2026-01-18-g.md" ] && ok || bad "spec file stays"

# A spec named after the group that does not cite the phase issue is not the phase's to delete.
spec_round '[{"number":1}]' 2026-01-18-g.md 'Fase #15 apenas.'
[ -e "$repo/docs/specs/2026-01-18-g.md" ] && ok || bad "a spec that does not cite the issue stays"
assert_not_contains "$(last_output)" "removed" "nothing is removed by the file name"

# An issue the same PR closes does not count as another open issue.
printf 'Resumo\n\nCloses #1\nCloses #3\n' >"$TMP/body.md"
spec_round '[{"number":1},{"number":3}]' 2026-01-18-g.md 'Fases #1 e #3.'
assert_contains "$(last_output)" "removed docs/specs/2026-01-18-g.md" "issues closed by the PR do not keep the spec"
printf 'Resumo\n\nCloses #1\n' >"$TMP/body.md"

git -C "$repo" switch --quiet main
assert_status 1 "refuses to run on main" sh -c "cd '$repo' && '$CLOSE' --merge"
finish
