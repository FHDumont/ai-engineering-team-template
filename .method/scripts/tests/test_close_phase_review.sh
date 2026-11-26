#!/usr/bin/env bash
# Tests of close-phase.sh --publish-review.
# shellcheck source=.method/scripts/tests/close_phase_common.sh
source "$(dirname "$0")/close_phase_common.sh"

handler "type:feature" success
# Publish the review: comment + status on the HEAD SHA + review_round in the trace,
# only with a reviewer round of this session after the last push of the branch.
printf '## Revisão independente\n\nVeredito: aprovado\nRodada: 1\n' >"$TMP/review.md"
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
mkdir -p "$repo/.process"
cp "$TMP/review.md" "$repo/.process/reviewer-$SHA.md"
printf '## Revisão independente\n\nVeredito: aprovado\nResumo próprio sem o checklist.\n' >"$TMP/rewritten.md"
: >"$FAKE_GH_LOG"
assert_status 1 "refuses a rewritten review" sh -c "cd '$repo' && '$CLOSE' --publish-review '$TMP/rewritten.md' --verdict success --round 1"
assert_contains "$(last_output)" "differs from the saved" "says the file is not the saved reviewer output"
assert_not_contains "$(gh_calls)" "pr comment" "no comment for a rewritten review"
assert_not_contains "$(gh_calls)" "statuses" "no status for a rewritten review"
: >"$FAKE_GH_LOG"
assert_status 1 "refuses a swapped verdict" sh -c "cd '$repo' && '$CLOSE' --publish-review '$TMP/review.md' --verdict failure --round 1"
assert_contains "$(last_output)" "does not match the Veredito" "says the verdict does not match the opinion"
assert_not_contains "$(gh_calls)" "statuses" "no status for a swapped verdict"
: >"$FAKE_GH_LOG"
assert_status 0 "publishes review" sh -c "cd '$repo' && '$CLOSE' --publish-review '$TMP/review.md' --verdict success --round 1"
assert_eq "review_round 1 success 12" "$(jq -r '[.event, .round, .verdict, .pr] | join(" ")' "$PROCESS_EVENTS_FILE")" "records review_round in the trace"
assert_eq "success" "$(cat "$repo/.process/reviewer-$SHA.verdict")" "the script writes .verdict from the Veredito line (#192)"
calls="$(gh_calls)"
assert_contains "$calls" "pr comment 12 --repo owner/repo --body-file $TMP/review.md" "posts the review comment"
assert_contains "$calls" "api -X POST repos/owner/repo/statuses/$SHA -f state=success -f context=review/independent" "sets the status on HEAD"
# The phase session may save the output in the .process/ of its own worktree, not the main checkout's.
git -C "$repo" switch --quiet --detach
git -C "$repo" worktree add --quiet "$TMP/wt" feat/issue-5-x
rm -f "$repo/.process/reviewer-$SHA.md" "$repo/.process/reviewer-$SHA.verdict"
mkdir -p "$TMP/wt/.process"
cp "$TMP/review.md" "$TMP/wt/.process/reviewer-$SHA.md"
: >"$FAKE_GH_LOG"
assert_status 0 "publishes a review saved in the .process/ of the phase worktree" \
  sh -c "cd '$TMP/wt' && '$TMP/wt/.method/scripts/close-phase.sh' --publish-review '$TMP/review.md' --verdict success --round 1"
assert_contains "$(gh_calls)" "context=review/independent" "the worktree review sets the status"
assert_eq "success" "$(cat "$TMP/wt/.process/reviewer-$SHA.verdict")" "the .verdict goes beside the saved review"
git -C "$repo" worktree remove --force "$TMP/wt"
git -C "$repo" switch --quiet feat/issue-5-x
# #192: the agent saves only the .md; the verdict comes from its Veredito line.
reset_phase_evidence
push_ev "$SHA"
round_ev
rm -f "$repo/.process/reviewer-$SHA.md" "$repo/.process/reviewer-$SHA.verdict"
: >"$FAKE_GH_LOG"
assert_status 1 "a missing saved review says who writes it" sh -c "cd '$repo' && '$CLOSE' --publish-review '$TMP/review.md' --round 1"
assert_contains "$(last_output)" "the phase session writes the whole close-reviewer output" "says the phase session saves the output"
assert_contains "$(last_output)" "step 5" "points at step 5 of the skill"
printf '## Revisão independente\n\nSem linha de veredito.\n' >"$TMP/noverdict.md"
cp "$TMP/noverdict.md" "$repo/.process/reviewer-$SHA.md"
assert_status 1 "an opinion without a Veredito line is refused" sh -c "cd '$repo' && '$CLOSE' --publish-review '$TMP/noverdict.md' --round 1"
assert_contains "$(last_output)" "no Veredito line" "says the line is missing"
printf '## Revisão independente\n\nVeredito: mudanças pedidas\n' >"$TMP/changes.md"
cp "$TMP/changes.md" "$repo/.process/reviewer-$SHA.md"
assert_status 1 "--verdict success on an opinion that asks for changes is refused" sh -c "cd '$repo' && '$CLOSE' --publish-review '$TMP/changes.md' --verdict success --round 1"
assert_not_contains "$(gh_calls)" "statuses" "no status for a verdict that differs from the opinion"
assert_status 0 "publishes an opinion that asks for changes with the verdict it states" sh -c "cd '$repo' && '$CLOSE' --publish-review '$TMP/changes.md' --round 1"
assert_eq "failure" "$(cat "$repo/.process/reviewer-$SHA.verdict")" "mudanças pedidas is failure"
assert_contains "$(gh_calls)" "-f state=failure -f context=review/independent" "status failure"
printf 'Co-Authored-By: Claude <noreply@anthropic.com>\n' >"$TMP/signed.md"
assert_status 1 "refuses a signed review" sh -c "cd '$repo' && '$CLOSE' --publish-review '$TMP/signed.md' --verdict success"

# No session id: the push of this branch at HEAD plus a clean pre_review of that SHA
# is enough to publish and to merge. A set session id still needs the harness round.
reset_phase_evidence
push_ev "$SHA"
jq -cn --arg sha "$SHA" --arg b feat/issue-5-x '{event: "pre_review", verdict: "clean", sha: $sha, branch: $b}' >>"$TRACE"
handler "type:feature" success
mkdir -p "$repo/.process"
cp "$TMP/review.md" "$repo/.process/reviewer-$SHA.md"
: >"$FAKE_GH_LOG"
assert_status 0 "publishes without a session id when HEAD was pushed and pre-reviewed clean" \
  env -u CLAUDE_CODE_SESSION_ID sh -c "cd '$repo' && '$CLOSE' --publish-review '$TMP/review.md' --verdict success --round 1"
assert_contains "$(gh_calls)" "api -X POST repos/owner/repo/statuses/$SHA -f state=success -f context=review/independent" "sets review/independent without a session id"
assert_status 0 "merges without a session id when HEAD was pushed and pre-reviewed clean" \
  env -u CLAUDE_CODE_SESSION_ID sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(gh_calls)" "pr merge 12" "merges without a session id"

# #219: a suffix on the Veredito line is refused with what to do; an opinion edited after it was saved is refused.
reset_phase_evidence
push_ev "$SHA"
round_ev
printf '## Revisão independente\n\nVeredito: aprovado, com uma ressalva\n' >"$TMP/suffix.md"
cp "$TMP/suffix.md" "$repo/.process/reviewer-$SHA.md"
assert_status 1 "a Veredito line with a suffix is refused" sh -c "cd '$repo' && '$CLOSE' --publish-review '$TMP/suffix.md' --round 1"
assert_contains "$(last_output)" "run the close-reviewer again; never edit the opinion" "says to run the reviewer again"
reset_phase_evidence
push_ev "$SHA"
printf '## Revisão independente\n\nVeredito: aprovado\nRessalva: x\n' >"$TMP/orig.md"
round_ev
out_ev "$TMP/orig.md"
printf '## Revisão independente\n\nVeredito: aprovado\nRessalva: editada\n' >"$TMP/edited.md"
cp "$TMP/edited.md" "$repo/.process/reviewer-$SHA.md"
: >"$FAKE_GH_LOG"
assert_status 1 "an opinion edited after it was saved is refused" sh -c "cd '$repo' && '$CLOSE' --publish-review '$TMP/edited.md' --round 1"
assert_contains "$(last_output)" "does not match the close-reviewer output recorded in the trace" "says the hash differs"
assert_not_contains "$(gh_calls)" "statuses" "no status for an edited opinion"
cp "$TMP/orig.md" "$repo/.process/reviewer-$SHA.md"
assert_status 0 "the opinion as recorded is published" sh -c "cd '$repo' && '$CLOSE' --publish-review '$TMP/orig.md' --round 1"
handler "type:feature" success

# #277: two close-reviewer stops of different sessions in the shared trace: the opinion of this
# session is checked against its own stop, not against the last one of the trace.
reset_phase_evidence
push_ev "$SHA"
round_ev
printf '## Revisão independente\n\nVeredito: aprovado\nRessalva: minha\n' >"$TMP/mine.md"
printf '## Revisão independente\n\nVeredito: aprovado\nRessalva: de outra fase\n' >"$TMP/other.md"
out_ev "$TMP/mine.md" child
out_ev "$TMP/other.md" other-session
cp "$TMP/mine.md" "$repo/.process/reviewer-$SHA.md"
: >"$FAKE_GH_LOG"
assert_status 0 "the opinion of this session passes although another session's reviewer stopped later" \
  sh -c "cd '$repo' && '$CLOSE' --publish-review '$TMP/mine.md' --round 1"
assert_contains "$(gh_calls)" "statuses" "the opinion of this session is published"
cp "$TMP/edited.md" "$repo/.process/reviewer-$SHA.md"
assert_status 1 "an edited opinion is still refused with two reviewers in the trace" \
  sh -c "cd '$repo' && '$CLOSE' --publish-review '$TMP/edited.md' --round 1"
# With the agent id saved next to the opinion (--save-review), the stop is the one of that agent.
jq -cn --arg h "$(opinion_sha "$TMP/mine.md")" '{event: "SubagentStop", session_id: "x", agent_id: "mine1", agent_type: "close-reviewer", output_sha: $h}' >>"$TRACE"
out_ev "$TMP/other.md" other-session
cp "$TMP/mine.md" "$repo/.process/reviewer-$SHA.md"
echo mine1 >"$repo/.process/reviewer-$SHA.agent"
assert_status 0 "the opinion passes by its agent id with another reviewer stopping later" \
  sh -c "cd '$repo' && '$CLOSE' --publish-review '$TMP/mine.md' --round 1"
cp "$TMP/edited.md" "$repo/.process/reviewer-$SHA.md"
assert_status 1 "an edited opinion is refused with the agent id saved" \
  sh -c "cd '$repo' && '$CLOSE' --publish-review '$TMP/edited.md' --round 1"
echo ghost >"$repo/.process/reviewer-$SHA.agent"
assert_status 1 "an agent id with no stop in the trace is refused" \
  sh -c "cd '$repo' && '$CLOSE' --publish-review '$TMP/edited.md' --round 1"
assert_contains "$(last_output)" "no close-reviewer stop for agent ghost" "says the agent has no stop"
rm -f "$repo/.process/reviewer-$SHA.agent"

# #131: a second --prepare that sends nothing must not record phase_push, or the
# review of that same SHA is refused. A later prepare that does push still asks
# for a new round.
git -C "$repo" switch --quiet feat/issue-5-x
echo more >>"$repo/feature.txt"
git -C "$repo" add feature.txt
git -C "$repo" commit --quiet -m "fix: another"
export PROCESS_EVENTS_FILE="$TRACE"
: >"$TRACE"
printf 'Resumo\n\nCloses #5\n' >"$TMP/body131.md"
cat >"$TMP/handler.sh" <<H
case "\$*" in
  "pr list"*"--state open"*) echo 12 ;;
  "issue view 5"*"labels"*) printf 'type:feature\n' ;;
  "pr view 12"*"headRefOid --jq"*) git -C "$repo" rev-parse HEAD ;;
  "pr view 12 --repo owner/repo --json title,body") echo '{"title":"feat: x","body":""}' ;;
  "issue list"*) printf '' ;;
esac
H
use_fake_gh "$TMP/handler.sh"
: >"$PUSH_LOG"
assert_status 0 "prepare pushes the commit the review will judge" \
  sh -c "cd '$repo' && '$CLOSE' --prepare --title 'feat: x' --body-file '$TMP/body131.md'"
head131="$(git -C "$repo" rev-parse HEAD)"
round_ev
printf '## Revisão independente\n\nVeredito: aprovado\nRodada: 1\n' >"$TMP/review131.md"
cp "$TMP/review131.md" "$repo/.process/reviewer-$head131.md"
assert_status 0 "prepare again when the SHA is already on origin" \
  sh -c "cd '$repo' && '$CLOSE' --prepare --body-file '$TMP/body131.md'"
assert_eq "1" "$(jq -s --arg s "$head131" '[.[] | select(.event == "phase_push" and .sha == $s)] | length' "$TRACE")" "a prepare that does not push records no new phase_push"
assert_eq "1" "$(pushes)" "a prepare that does not push does not call git push"
assert_status 0 "publish survives a prepare that did not push" \
  sh -c "cd '$repo' && '$CLOSE' --publish-review '$TMP/review131.md' --verdict success --round 1"
echo later >>"$repo/feature.txt"
git -C "$repo" add feature.txt
git -C "$repo" commit --quiet -m "fix: after the review"
assert_status 0 "prepare pushes the commit made after the review" \
  sh -c "cd '$repo' && '$CLOSE' --prepare --body-file '$TMP/body131.md'"
assert_status 1 "a real push after the review still asks for a new round" \
  sh -c "cd '$repo' && '$CLOSE' --publish-review '$TMP/review131.md' --verdict success --round 1"
assert_contains "$(last_output)" "no close-reviewer round after the last push" "says the round has to follow the push"

# #258: --save-review writes the literal opinion from the transcript of a background subagent.
head258="$(git -C "$repo" rev-parse HEAD)"
reset_phase_evidence
push_ev "$head258"
round_ev
rm -f "$repo/.process/reviewer-$head258.md" "$repo/.process/reviewer-$head258.verdict" "$repo/.process/reviewer-gate-$head258.md"
export CLOSE_PHASE_SUBAGENTS_ROOT="$TMP/transcripts"
mkdir -p "$CLOSE_PHASE_SUBAGENTS_ROOT/sess/subagents"
opinion258=$'## Revisão independente\n\nVeredito: aprovado\nRodada: 1'
{
  jq -cn --arg t "$opinion258" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}'
  jq -cn '{type:"assistant",message:{content:[{type:"text",text:"Parecer salvo."}]}}'
} >"$CLOSE_PHASE_SUBAGENTS_ROOT/sess/subagents/agent-bg1.jsonl"
sha258="$(printf '%s' "$opinion258" | shasum -a 256 | cut -d' ' -f1)"
assert_status 1 "--save-review refuses an agent the trace never saw stop"   sh -c "cd '$repo' && '$CLOSE' --save-review bg1"
assert_eq "no" "$([ -f "$repo/.process/reviewer-$head258.md" ] && echo yes || echo no)" "nothing saved without the trace hash"
jq -cn --arg h "0000" '{event: "SubagentStop", session_id: "child", agent_id: "bg1", agent_type: "close-reviewer", output_sha: $h}' >>"$TRACE"
assert_status 1 "--save-review refuses a hash that differs from the trace"   sh -c "cd '$repo' && '$CLOSE' --save-review bg1"
assert_contains "$(last_output)" "does not match" "says the hash differs"
assert_eq "no" "$([ -f "$repo/.process/reviewer-$head258.md" ] && echo yes || echo no)" "nothing saved on a hash mismatch"
jq -cn --arg h "$sha258" '{event: "SubagentStop", session_id: "child", agent_id: "bg1", agent_type: "close-reviewer", output_sha: $h}' >>"$TRACE"
assert_status 0 "--save-review saves the opinion of the background subagent"   sh -c "cd '$repo' && '$CLOSE' --save-review bg1"
assert_eq "bg1" "$(cat "$repo/.process/reviewer-$head258.agent")" "--save-review records the agent id next to the opinion"
assert_eq "$sha258" "$(printf '%s' "$(cat "$repo/.process/reviewer-$head258.md")" | shasum -a 256 | cut -d' ' -f1)" "the saved file holds the opinion literally"
: >"$FAKE_GH_LOG"
assert_status 0 "--publish-review accepts the saved file"   sh -c "cd '$repo' && '$CLOSE' --publish-review '$repo/.process/reviewer-$head258.md' --verdict success --round 1"
assert_contains "$(gh_calls)" "context=review/independent" "the saved opinion is published"
assert_status 0 "--save-review --gate saves the second review"   sh -c "cd '$repo' && '$CLOSE' --save-review bg1 --gate"
assert_eq "yes" "$([ -f "$repo/.process/reviewer-gate-$head258.md" ] && echo yes || echo no)" "the gate opinion goes to reviewer-gate-<sha>.md"
unset CLOSE_PHASE_SUBAGENTS_ROOT

finish
