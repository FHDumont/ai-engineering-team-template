#!/usr/bin/env bash
# Tests of close-phase.sh --prepare: PR body, pair table, pushes, validate once per HEAD.
# shellcheck source=.method/scripts/tests/close_phase_common.sh
source "$(dirname "$0")/close_phase_common.sh"

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
rm -rf "$AI_METHOD_CACHE/progress"
assert_status 0 "prepare runs on a branch without issue number" sh -c "cd '$repo' && .method/scripts/close-phase.sh --prepare --body-file '$TMP/body.md'"
assert_contains "$(last_output)" "warning: no pre_review of HEAD" "prepare warns without a pre_review of HEAD"
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
# Progress (process-design §6.4): --prepare records start, its steps and end; the output has none.
pfile="$(ls "$AI_METHOD_CACHE"/progress/*.jsonl 2>/dev/null | head -1 || true)"
assert_eq "close-phase.sh" "$(jq -r .script "$pfile" | head -1)" "prepare records its progress as close-phase.sh"
assert_eq "start" "$(jq -r .state "$pfile" | head -1)" "progress starts with state start"
assert_eq "end" "$(jq -r .state "$pfile" | tail -1)" "progress ends with state end"
assert_contains "$(jq -r .step "$pfile")" "pushing the branch" "progress has the push step"
assert_not_contains "$(cat "$TMP/last.out" 2>/dev/null; last_output)" "jsonl" "the output has no progress"
# validate.sh runs once per HEAD: --prepare again on the same commit skips the suite
# (the trace holds the green run).
VAL_LOG="$TMP/validate-runs.log"; : >"$VAL_LOG"
assert_eq "1" "$(jq -s '[.[] | select(.event == "phase_validate" and .sha == "'"$(git -C "$repo" rev-parse HEAD)"'")] | length' "$PROCESS_EVENTS_FILE")" "a green validate.sh is recorded with the HEAD sha"
# The SHA is the one read before the suite, and only when HEAD is still that commit.
assert_contains "$(awk '/^run_validate\(\)/,/^}/' "$SCRIPTS/close-phase.sh")" 'sha="$(git rev-parse HEAD)"' "run_validate photographs HEAD before validate.sh"
assert_contains "$(awk '/^run_validate\(\)/,/^}/' "$SCRIPTS/close-phase.sh")" 'trace_event phase_validate sha="$sha"' "phase_validate records the photographed SHA"
printf '#!/usr/bin/env bash\necho run >>"%s"\n' "$VAL_LOG" >"$TMP/validate-counter.sh"
cp "$repo/.method/scripts/validate.sh" "$TMP/validate-stub.sh"
cp "$TMP/validate-counter.sh" "$repo/.method/scripts/validate.sh"; chmod +x "$repo/.method/scripts/validate.sh"
git -C "$repo" update-index --assume-unchanged .method/scripts/validate.sh
assert_status 0 "prepare again on the same HEAD" sh -c "cd '$repo' && .method/scripts/close-phase.sh --prepare --body-file '$TMP/body.md'"
assert_contains "$(last_output)" "skipped validate.sh" "the same HEAD does not run the suite again"
assert_eq "0" "$(wc -l <"$VAL_LOG" | tr -d ' ')" "validate.sh not called on the same HEAD"
# A change in the tree (not a validated commit) runs the suite again (then it refuses: uncommitted).
echo y >>"$repo/work.txt"
assert_status 1 "prepare with a dirty tree" sh -c "cd '$repo' && .method/scripts/close-phase.sh --prepare --body-file '$TMP/body.md'"
assert_eq "1" "$(wc -l <"$VAL_LOG" | tr -d ' ')" "a dirty tree runs validate.sh"
git -C "$repo" checkout --quiet work.txt
git -C "$repo" update-index --no-assume-unchanged .method/scripts/validate.sh
cp "$TMP/validate-stub.sh" "$repo/.method/scripts/validate.sh"
# The "Modelo e esforço" section of the body is written by the script, from the trace.
sent="$(echo "$calls" | sed -n 's/^pr edit 12 --repo owner\/repo --title chore: x --body-file //p' | tail -1)"
assert_eq 1 "$([ -n "$sent" ] && [ -f "$sent" ] && echo 1)" "edits the PR when the body changed"
assert_contains "$(cat "$sent")" "Closes #1" "the body keeps what the body file says"
assert_contains "$(cat "$sent")" "## Modelo e esforço" "a body without the section gets it"
assert_contains "$(cat "$sent")" "| etapa | modelo/esforço pedido | modelo/esforço usado |" "the table comes from the script"
# A section filled by hand is replaced by the table of the trace; the other sections stay.
printf 'Resumo\n\nCloses #1\n\n## Modelo e esforço\n\nwritten by hand: big high\n\n## Achados\n\nnenhum\n' >"$TMP/hand.md"
jq -cn '{ts: "2026-01-01T00:00:00Z", event: "phase_session", session_id: "kid", issue: "1", model: "claude-real-1", effort: "low", requested_model: "asked", requested_effort: "high"}' >>"$PROCESS_EVENTS_FILE"
assert_status 0 "prepare with a hand-written pair section" sh -c "cd '$repo' && .method/scripts/close-phase.sh --prepare --body-file '$TMP/hand.md'"
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
assert_status 0 "prepare again with the same title and body" env FAKE_PR_JSON="$TMP/pr12.json" sh -c "cd '$repo' && .method/scripts/close-phase.sh --prepare --body-file '$TMP/hand.md'"
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
assert_status 1 "a new PR needs --title" sh -c "cd '$repo' && .method/scripts/close-phase.sh --prepare --body-file '$TMP/body.md'"
assert_eq "0" "$(pushes)" "no push without the title of a new PR"
assert_status 0 "prepare opens a new PR" sh -c "cd '$repo' && .method/scripts/close-phase.sh --prepare --title 'chore: new' --body-file '$TMP/body.md'"
assert_eq "1" "$(pushes)" "one push for a new PR"
assert_contains "$(gh_calls)" "pr create --repo owner/repo --base main --head chore/new-pr" "opens the PR after the push"
assert_not_contains "$(gh_calls)" "issues?state=all" "predicts no PR number"
assert_eq "" "$(git -C "$repo" ls-tree -r --name-only HEAD | grep -E '^(CHANGELOG|ROADMAP)\.md$' || true)" "a new PR carries no generated file"

# #139: the spec-removal commit --prepare itself creates changes no file the suite
# reads, so the suite runs once. A later inert doc reuses that result; code does not.
# A full green validate.sh on a clean tree is what --prepare reuses.
git -C "$repo" switch --quiet -c fix/issue-1-spec origin/main
mkdir -p "$repo/docs/specs"
printf '# Spec\n\n## Fase #1 — remove\n\n' >"$repo/docs/specs/one.md"
git -C "$repo" add docs/specs/one.md
git -C "$repo" commit --quiet -m "docs(specs): add the spec of issue #1"
SPEC_LOG="$TMP/spec-validate.log"; : >"$SPEC_LOG"
printf '#!/usr/bin/env bash\necho run >>"%s"\n' "$SPEC_LOG" >"$repo/.method/scripts/validate.sh"
chmod +x "$repo/.method/scripts/validate.sh"
git -C "$repo" update-index --assume-unchanged .method/scripts/validate.sh
cat >"$TMP/handler.sh" <<'H'
case "$*" in
  "pr list"*"--state open"*) echo 12 ;;
  "issue view 1"*) printf 'type:chore\n' ;;
  "pr view 12"*) echo '{"number":12,"title":"chore: spec","labels":[{"name":"type:chore"}],"url":"u","body":""}' ;;
  "issue list"*) printf '' ;;
esac
H
use_fake_gh "$TMP/handler.sh"
: >"$PUSH_LOG"
assert_status 0 "prepare removes the spec and validates once" \
  sh -c "cd '$repo' && .method/scripts/close-phase.sh --prepare --title 'chore: spec' --body-file '$TMP/body.md'"
assert_eq "docs(specs): remove the spec whose last open issue is #1" "$(git -C "$repo" log -1 --format=%s)" "prepare commits the spec removal"
assert_eq "1" "$(wc -l <"$SPEC_LOG" | tr -d ' ')" "the first prepare runs the suite once"
assert_eq "$(git -C "$repo" rev-parse HEAD)" "$(jq -r 'select(.event == "phase_validate" and .branch == "fix/issue-1-spec") | .sha' "$PROCESS_EVENTS_FILE" | tail -1)" "the spec-removal commit inherits the validation"
assert_status 0 "second prepare on the spec-removal commit" \
  sh -c "cd '$repo' && .method/scripts/close-phase.sh --prepare --body-file '$TMP/body.md'"
assert_eq "1" "$(wc -l <"$SPEC_LOG" | tr -d ' ')" "the spec-removal commit does not run the suite again"
mkdir -p "$repo/docs"
printf 'note\n' >"$repo/docs/note.md"
git -C "$repo" add docs/note.md
git -C "$repo" commit --quiet -m "docs: inert note"
assert_status 0 "prepare after an inert doc" \
  sh -c "cd '$repo' && .method/scripts/close-phase.sh --prepare --body-file '$TMP/body.md'"
assert_eq "1" "$(wc -l <"$SPEC_LOG" | tr -d ' ')" "an inert doc reuses the validation"
printf 'x\n' >"$repo/.method/scripts/z.sh"
git -C "$repo" add .method/scripts/z.sh
git -C "$repo" commit --quiet -m "chore: code the suite reads"
assert_status 0 "prepare after code the suite reads" \
  sh -c "cd '$repo' && .method/scripts/close-phase.sh --prepare --body-file '$TMP/body.md'"
assert_eq "2" "$(wc -l <"$SPEC_LOG" | tr -d ' ')" "code the suite reads runs the suite again"
git -C "$repo" update-index --no-assume-unchanged .method/scripts/validate.sh
assert_contains "$(cat "$SCRIPTS/validate.sh")" 'trace_event phase_validate' "a full green validate.sh records the result --prepare reuses"

finish
