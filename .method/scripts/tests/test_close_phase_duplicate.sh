#!/usr/bin/env bash
# Tests of close-phase.sh --check: a commit of the branch that origin/main already has under another SHA.
# shellcheck source=.method/scripts/tests/close_phase_common.sh
source "$(dirname "$0")/close_phase_common.sh"

reset_phase_evidence
child_session 5
export CLOSE_PHASE_MERGEABLE_PAUSE=0 CLOSE_PHASE_CI_TIMEOUT=0 CLOSE_PHASE_CI_POLL=0
# redo-phase.sh is a stub here (its own behaviour is in test_redo_phase.sh).
printf '#!/usr/bin/env bash\necho "redo called" >>"%s"\necho "redone: PR #13 replaces PR #12"\n' "$TMP/redo.log" >"$repo/.method/scripts/redo-phase.sh"
redo_calls() { if [ -f "$TMP/redo.log" ]; then wc -l <"$TMP/redo.log" | tr -d ' '; else echo 0; fi; }
handler "type:feature" success

# Main moves with an unrelated commit: the PR is only behind, not redone.
other="$TMP/other"
git clone --quiet "$remote" "$other"
git -C "$other" config user.email t@t; git -C "$other" config user.name t
echo n >"$other/notes.txt"; git -C "$other" add notes.txt; git -C "$other" commit --quiet -m "chore: notes"
git -C "$other" push --quiet origin HEAD:main
assert_status 0 "--check passes on a PR with no commit the base already has" env FAKE_MERGEABLE=MERGEABLE FAKE_MERGE_STATE=BEHIND sh -c "cd '$repo' && '$CLOSE' --check"
assert_eq 0 "$(redo_calls)" "a PR that is only behind is not redone"

# Another phase brought the same commit to main under another SHA (a rebase merge).
git -C "$other" fetch --quiet origin feat/issue-5-x
git -C "$other" cherry-pick --quiet "$SHA"
git -C "$other" push --quiet origin HEAD:main
handler "type:feature" success
assert_status 0 "--check redoes a PR whose commit the base already has" env FAKE_MERGEABLE=MERGEABLE FAKE_MERGE_STATE=BEHIND sh -c "cd '$repo' && '$CLOSE' --check"
assert_eq 1 "$(redo_calls)" "--check calls redo-phase.sh once"
assert_contains "$(last_output)" "already has" "says the base already has a commit"
assert_contains "$(last_output)" "PR #13" "shows the new PR"
assert_not_contains "$(gh_calls)" "check-runs" "does not wait for CI"
rm -f "$TMP/redo.log"
assert_status 6 "--merge redoes it and does not merge" env FAKE_MERGEABLE=MERGEABLE FAKE_MERGE_STATE=BEHIND sh -c "cd '$repo' && '$CLOSE' --merge"
assert_eq 1 "$(redo_calls)" "--merge calls redo-phase.sh once"
assert_not_contains "$(gh_calls)" "pr merge" "never merges it"

finish
