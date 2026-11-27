#!/usr/bin/env bash
# Tests of the two classes of .github/sensitive-paths in close-phase.sh --merge (#186):
# owner-ok needs the owner; gate needs a second close-reviewer opinion and no owner.
# shellcheck source=.method/scripts/tests/close_phase_common.sh
source "$(dirname "$0")/close_phase_common.sh"

# The gate_review event goes where the gate reads the trace.
export PROCESS_EVENTS_FILE="$TRACE"
reset_phase_evidence
child_session 5
mkdir -p "$repo/.process"
GATE_OPINION="$TMP/gate.md"
printf '## Revisão independente\n\nVeredito: aprovado\nFoco: o PR enfraquece o portão?\n' >"$GATE_OPINION"
set_list() { printf '%s\n' "$@" >"$repo/.github/sensitive-paths"; }

# A PR whose diff touches a gate path (feature.txt, declared in the class gate).
set_list "# class: gate" "feature.txt"
handler "type:feature" success
assert_status 5 "a gate path without the second review is refused" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(last_output)" "needs-gate-review" "says it needs the gate review"
assert_not_contains "$(last_output)" "ask the repo owner" "does not send the owner a gate PR"
assert_contains "$(gh_calls)" "--add-label needs-gate-review" "puts needs-gate-review on the PR"
assert_not_contains "$(gh_calls)" "needs-owner-ok" "a gate PR does not get needs-owner-ok"
assert_not_contains "$(gh_calls)" "pr merge" "no merge without the second review"

# #220: the gate label is missing in the repository (an update from before the class):
# --merge creates it from labels.tsv of the PR HEAD, then puts it on the PR.
handler "type:feature" success
: >"$FAKE_GH_LOG"
assert_status 5 "a missing needs-gate-review label does not stop the refusal" env FAKE_GATE_LABEL_MISSING=1 sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(gh_calls)" "label create needs-gate-review --repo owner/repo --color e11d21" "creates the missing label with the color of labels.tsv"
assert_contains "$(gh_calls)" "--add-label needs-gate-review" "then puts it on the PR"
assert_contains "$(last_output)" "needs-gate-review is now on PR #12 (read back)" "read back"

# The second review is published like the first one, with --gate, and saved apart.
handler "type:feature,needs-gate-review" success
cp "$GATE_OPINION" "$repo/.process/reviewer-gate-$SHA.md"
: >"$FAKE_GH_LOG"
assert_status 0 "publishes the second review" sh -c "cd '$repo' && '$CLOSE' --publish-review '$GATE_OPINION' --gate --round 1"
assert_eq "success" "$(cat "$repo/.process/reviewer-gate-$SHA.verdict")" "the script writes the gate .verdict"
assert_contains "$(gh_calls)" "pr comment 12" "posts the second review"
assert_not_contains "$(gh_calls)" "context=review/independent" "the gate review is not the review/independent status"
assert_eq "gate_review success" "$(jq -r 'select(.event == "gate_review") | [.event, .verdict] | join(" ")' "$TRACE" | tail -1)" "records gate_review in the trace"
assert_status 0 "merges a gate PR with the approved second review, with no owner ok" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(gh_calls)" "pr merge 12" "merges"
assert_not_contains "$(gh_calls)" "<!-- owner-ok" "records no owner ok"

# A second review that asks for changes does not open the merge.
printf '## Revisão independente\n\nVeredito: mudanças pedidas\n' >"$TMP/gate-no.md"
cp "$TMP/gate-no.md" "$repo/.process/reviewer-gate-$SHA.md"
rm -f "$repo/.process/reviewer-gate-$SHA.verdict"
sed '/"event": "gate_review"/d' "$TRACE" >"$TMP/trace.tmp" && cat "$TMP/trace.tmp" >"$TRACE"
assert_status 0 "publishes a failing second review" sh -c "cd '$repo' && '$CLOSE' --publish-review '$TMP/gate-no.md' --gate --round 2"
handler "type:feature,needs-gate-review" success
assert_status 5 "a second review that asks for changes is refused" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_not_contains "$(gh_calls)" "pr merge" "no merge on a failing second review"

# A review saved by hand and never published (no gate_review event) does not count.
reset_phase_evidence; export PROCESS_EVENTS_FILE="$TRACE"; child_session 5
cp "$GATE_OPINION" "$repo/.process/reviewer-gate-$SHA.md"
printf 'success\n' >"$repo/.process/reviewer-gate-$SHA.verdict"
handler "type:feature,needs-gate-review" success
assert_status 5 "a gate opinion that was never published does not count" sh -c "cd '$repo' && '$CLOSE' --merge"

# owner-ok paths still need the owner, with or without a gate review.
set_list "# class: owner-ok" "feature.txt"
reset_phase_evidence; export PROCESS_EVENTS_FILE="$TRACE"; child_session 5
cp "$GATE_OPINION" "$repo/.process/reviewer-gate-$SHA.md"
handler "type:feature" success
assert_status 5 "an owner-ok path is refused" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(gh_calls)" "--add-label needs-owner-ok" "puts needs-owner-ok"
handler "type:feature,needs-owner-ok" success
assert_status 0 "an owner-ok path merges with the owner's ok" sh -c "cd '$repo' && '$CLOSE' --merge --owner-ok '$SHA'"

# The ok of the approved spec (spec_ok in the trace, bound to this SHA) is the owner's ok
# for the paths and areas it declares, and only for those.
spec_ok_ev() { # spec_ok_ev <declared> [sha]
  jq -cn --arg d "$1" --arg s "${2:-$SHA}" '{event: "spec_ok", branch: "feat/issue-5-x", issue: "5", sha: $s, declared: $d}' >>"$TRACE"
}
set_list "# class: owner-ok" "feature.txt"
reset_phase_evidence; export PROCESS_EVENTS_FILE="$TRACE"; child_session 5
spec_ok_ev "feature.txt,owner-ok"
handler "type:feature,needs-owner-ok" success
assert_status 0 "the spec ok covers a declared owner-ok path" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(gh_calls)" "<!-- spec-ok sha:$SHA -->" "records the spec ok on the PR"
assert_not_contains "$(gh_calls)" "<!-- owner-ok" "no owner-ok marker"
assert_contains "$(gh_calls)" "pr merge 12" "merges"

reset_phase_evidence; export PROCESS_EVENTS_FILE="$TRACE"; child_session 5
spec_ok_ev "other.txt"
handler "type:feature,needs-owner-ok" success
assert_status 5 "a path the spec did not declare still asks the owner" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_not_contains "$(gh_calls)" "pr merge" "no merge for an undeclared path"
assert_contains "$(last_output)" "ask the repo owner" "the board stays"

reset_phase_evidence; export PROCESS_EVENTS_FILE="$TRACE"; child_session 5
spec_ok_ev "feature.txt" "0000000000000000000000000000000000000000"
handler "type:feature,needs-owner-ok" success
assert_status 5 "a spec ok of another SHA does not count" sh -c "cd '$repo' && '$CLOSE' --merge"

reset_phase_evidence; export PROCESS_EVENTS_FILE="$TRACE"; child_session 5
spec_ok_ev "feature.txt"
handler "type:feature,needs-owner-ok,area:auth" success
assert_status 5 "an area label the spec did not declare still asks the owner" sh -c "cd '$repo' && '$CLOSE' --merge"

# needs-owner-ok alone, with no declared path or area behind it, is not covered.
set_list "# class: owner-ok" "nothing-here.txt"
reset_phase_evidence; export PROCESS_EVENTS_FILE="$TRACE"; child_session 5
spec_ok_ev "feature.txt"
handler "type:feature,needs-owner-ok" success
assert_status 5 "needs-owner-ok alone is not covered by the spec ok" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_not_contains "$(gh_calls)" "pr merge" "no merge on the label alone"
set_list "# class: owner-ok" "feature.txt"

# An adopter's old file has one class: every path asks for the owner.
set_list "feature.txt"
reset_phase_evidence; export PROCESS_EVENTS_FILE="$TRACE"; child_session 5
handler "type:feature" success
assert_status 5 "a list without classes keeps asking the owner" sh -c "cd '$repo' && '$CLOSE' --merge"
assert_contains "$(gh_calls)" "--add-label needs-owner-ok" "old list: needs-owner-ok"
assert_not_contains "$(gh_calls)" "needs-gate-review" "old list: no gate class"

finish
