#!/usr/bin/env bash
# Tests of start-headless.sh with a fake "claude".
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

repo="$(make_repo)"
copy_scripts "$repo"
printf '.worktrees/\n.process/\n' >"$repo/.gitignore"
mkdir -p "$repo/docs/specs"
printf '# Spec\n\n## Fase #7 — x\n\n1. Etapa. modelo: sonnet · esforço: medium · motivo: x\n' >"$repo/docs/specs/seven.md"
git -C "$repo" add .gitignore scripts docs
git -C "$repo" commit --quiet -m "chore: scripts and spec"
export PROCESS_EVENTS_FILE="$repo/.process/events.jsonl"
events() { cat "$PROCESS_EVENTS_FILE" 2>/dev/null || true; }

# A fake claude that records its arguments and cwd, then stays alive a little.
bin="$TMP/bin"; mkdir -p "$bin"
cat >"$bin/claude" <<'F'
#!/usr/bin/env bash
printf '%s\n' "$PWD" "$@" >"$FAKE_CLAUDE_ARGS"
printf '%s\n' "${CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS:-unset}" >"$FAKE_CLAUDE_ARGS.env"
echo "child running"
sleep 5
F
chmod +x "$bin/claude"
export FAKE_CLAUDE_ARGS="$TMP/claude.args"

assert_status 0 "--help works" "$repo/scripts/start-headless.sh" --help
assert_contains "$(last_output)" 'claude -p "<answer>" --resume' "the resume text puts the prompt right after -p"
assert_status 2 "needs an issue number" sh -c "cd '$repo' && scripts/start-headless.sh"
assert_status 2 "refuses a phase without worktree" sh -c "cd '$repo' && PATH='$bin:$PATH' scripts/start-headless.sh 7"
assert_contains "$(last_output)" "phase-start.sh" "says to open the phase first"

git -C "$repo" worktree add --quiet -b feat/issue-7-x "$repo/.worktrees/issue-7"
wt="$repo/.worktrees/issue-7"

# claude missing: exit 3, nothing recorded (PATH without claude).
nobin="$TMP/nobin"; mkdir -p "$nobin"
for t in git jq python3 sed cat dirname; do ln -sf "$(command -v "$t")" "$nobin/$t"; done
assert_status 3 "exit 3 without claude" sh -c "cd '$repo' && PATH='$nobin:/bin' scripts/start-headless.sh 7"
assert_not_contains "$(events)" "phase_headless" "no event without claude"

assert_status 0 "--dry-run starts nothing" sh -c "cd '$repo' && PATH='$bin:$PATH' scripts/start-headless.sh 7 --dry-run"
assert_contains "$(last_output)" "--model sonnet" "dry-run shows the model of the spec"
assert_not_contains "$(events)" "phase_headless" "dry-run records nothing"

assert_status 0 "starts the headless child" sh -c "cd '$repo' && PATH='$bin:$PATH' scripts/start-headless.sh 7"
args="$(cat "$FAKE_CLAUDE_ARGS")"
assert_contains "$args" "$wt" "runs inside the worktree"
assert_contains "$args" "-p" "runs headless"
assert_contains "$args" "execute skill" "prompt names the execute skill"
assert_contains "$args" "issue #7" "prompt names the issue"
assert_contains "$(tr '\n' ' ' <"$FAKE_CLAUDE_ARGS")" "--model sonnet --effort medium" "passes the pair of the spec"
assert_contains "$(tr '\n' ' ' <"$FAKE_CLAUDE_ARGS")" "--session-id" "passes the session id"
assert_contains "$(cat "$wt/.process/headless.log")" "child running" "log is in the worktree"
assert_eq "0" "$(cat "$FAKE_CLAUDE_ARGS.env")" "claude -p waits for background tasks (ceiling 0)"
assert_eq "-p" "$(sed -n 2p "$FAKE_CLAUDE_ARGS")" "-p is the first argument"
assert_contains "$(sed -n 3p "$FAKE_CLAUDE_ARGS")" "execute skill" "the prompt comes right after -p"
ev="$(events | jq -c 'select(.event == "phase_headless")')"
pid="$(jq -r .pid <<<"$ev")"
assert_eq "7" "$(jq -r .issue <<<"$ev")" "event carries the issue"
assert_eq "sonnet" "$(jq -r .model <<<"$ev")" "event carries the model"
assert_eq "medium" "$(jq -r .effort <<<"$ev")" "event carries the effort"
assert_contains "$(jq -r .log <<<"$ev")" ".process/headless.log" "event carries the log path"
assert_eq "$(jq -r .child_session <<<"$ev")" "$(tr '\n' ' ' <"$FAKE_CLAUDE_ARGS" | sed -n 's/.*--session-id \([^ ]*\).*/\1/p')" "event id is the one passed to claude"
assert_eq 0 "$(kill -0 "$pid" 2>/dev/null && echo 0 || echo 1)" "the recorded pid is alive"
kill "$pid" 2>/dev/null || true
assert_eq "no" "$(jq -r .brief <<<"$ev")" "event says there was no brief"
assert_not_contains "$args" "Brief of the manager" "no brief section without a brief"

# The brief of the manager reaches the prompt, by text or by file, and the trace says so.
assert_status 0 "starts with --brief" sh -c "cd '$repo' && PATH='$bin:$PATH' scripts/start-headless.sh 7 --brief 'also solve #16; only touch scripts/status.sh'"
args="$(cat "$FAKE_CLAUDE_ARGS")"
assert_contains "$args" "Brief of the manager:" "the prompt has the brief section"
assert_contains "$args" "also solve #16; only touch scripts/status.sh" "the brief text is in the prompt"
assert_contains "$args" "execute skill" "the execute prompt is still there"
ev="$(events | jq -c 'select(.event == "phase_headless")' | tail -1)"
assert_eq "yes" "$(jq -r .brief <<<"$ev")" "the trace records the brief"
kill "$(jq -r .pid <<<"$ev")" 2>/dev/null || true
printf 'line one\nline two\n' >"$TMP/brief.txt"
assert_status 0 "starts with --brief-file" sh -c "cd '$repo' && PATH='$bin:$PATH' scripts/start-headless.sh 7 --brief-file '$TMP/brief.txt'"
assert_contains "$(cat "$FAKE_CLAUDE_ARGS")" "line two" "the file brief is in the prompt"
kill "$(events | jq -r 'select(.event == "phase_headless") | .pid' | tail -1)" 2>/dev/null || true
assert_status 2 "a missing brief file is refused" sh -c "cd '$repo' && PATH='$bin:$PATH' scripts/start-headless.sh 7 --brief-file '$TMP/none.txt'"
assert_status 0 "--dry-run shows the brief" sh -c "cd '$repo' && PATH='$bin:$PATH' scripts/start-headless.sh 7 --dry-run --brief 'dry brief'"
assert_contains "$(last_output)" "dry brief" "dry-run prints the prompt with the brief"

# #36: the spec exists only on the branch of the phase, not in the main checkout.
git -C "$repo" worktree add --quiet -b feat/issue-8-y "$repo/.worktrees/issue-8"
printf '# Spec\n\n## Fase #8 — y\n\n1. Etapa. modelo: opus · esforço: high · motivo: x\n' >"$repo/.worktrees/issue-8/docs/specs/eight.md"
git -C "$repo/.worktrees/issue-8" add docs/specs/eight.md
git -C "$repo/.worktrees/issue-8" commit --quiet -m "docs(specs): add the spec of issue #8"
assert_eq "no" "$([ -e "$repo/docs/specs/eight.md" ] && echo yes || echo no)" "the main checkout has no spec of #8"
assert_status 0 "reads the pair from the spec that exists only on the branch" sh -c "cd '$repo' && PATH='$bin:$PATH' scripts/start-headless.sh 8 --dry-run"
assert_contains "$(last_output)" "--model opus --effort high" "the pair comes from the worktree spec"

# A child that dies at once with an error: exit 4, no event.
cat >"$bin/claude" <<'F'
#!/usr/bin/env bash
echo "Error: boom" >&2
exit 1
F
before="$(events | wc -l)"
assert_status 4 "exit 4 when the child dies at once" sh -c "cd '$repo' && PATH='$bin:$PATH' scripts/start-headless.sh 7"
assert_eq "$before" "$(events | wc -l)" "no event for a child that died"
finish
