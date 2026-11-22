#!/usr/bin/env bash
# Tests of close-phase.sh --merge: conflicts, CI on HEAD, no deploy from the phase, sensitive paths.
# shellcheck source=scripts/tests/close_phase_common.sh
source "$(dirname "$0")/close_phase_common.sh"

reset_phase_evidence
child_session 5
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

finish
