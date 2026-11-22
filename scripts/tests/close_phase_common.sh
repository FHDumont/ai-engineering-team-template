#!/usr/bin/env bash
# Shared setup of the close-phase.sh tests (test_close_phase*.sh): a temporary repo with a
# local "origin", the trace helpers and the fake gh handler. Sourced, never run alone.
# shellcheck disable=SC2034  # the variables are read by the test files that source this one
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
git -C "$repo" config core.quotepath true
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
  "issue view 5"*"--json comments"*) cat "$TMP/comments.json" 2>/dev/null || true ;;
  "issue view 5"*"labels"*) printf '%s\n' "\${FAKE_ISSUE_LABELS:-type:feature}" | tr ',' '\n' ;;
  "api repos/owner/repo/commits/$SHA/status"*) echo "$2" ;;
  # Unprotected mode: FAKE_MODE=1 records it; FAKE_CI is the state of the CI check run on HEAD.
  "variable list"*) [ -z "\${FAKE_MODE:-}" ] || echo PROCESS_BRANCH_MODE ;;
  "api repos/owner/repo/commits/$SHA/check-runs"*"select(.name"*) echo "\${FAKE_CI:-success}" ;;
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
