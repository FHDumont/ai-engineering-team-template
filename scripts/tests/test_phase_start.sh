#!/usr/bin/env bash
# Tests of the single phase entry: phase-start.sh, and the spec guard of
# new-phase.sh, open-parallel.sh and check-env.sh.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

repo="$(make_repo)"
copy_scripts "$repo"
# phase-start.sh checks the setup against the labels file of the repository.
mkdir -p "$repo/.github" && cp "$REPO/.github/labels.tsv" "$repo/.github/labels.tsv"
# The git hooks are active and the trace is the one the phase locks read: the
# session that opens the phase (phase_opened) cannot commit in the worktree.
cp -R "$REPO/.githooks" "$repo/.githooks"
printf '.worktrees/\n.process/\n' >"$repo/.gitignore"
git -C "$repo" add scripts .githooks .gitignore .github
git -C "$repo" commit --quiet -m "chore: scripts"
git -C "$repo" config core.hooksPath .githooks
export PROCESS_EVENTS_FILE="$repo/.process/events.jsonl"
git clone --quiet --bare "$repo" "$TMP/remote.git"
git -C "$repo" remote add origin "$TMP/remote.git"

# Issues 7, 8, 11 and 12 are open; 9 is closed; 10 is a test issue.
cat >"$TMP/handler.sh" <<'H'
case "$*" in
  "issue view 9 "*) echo '{"state":"CLOSED","title":"Fechada","labels":[{"name":"type:bug"}]}' ;;
  "issue view 10 "*) echo '{"state":"OPEN","title":"Teste de fluxo","labels":[{"name":"test"}]}' ;;
  "issue view "*"--json state,title,labels"*) echo '{"state":"OPEN","title":"Listar issues","labels":[{"name":"type:feature"}]}' ;;
  "issue list"*"--state open"*) printf '%s\n' ${FAKE_OPEN:-} ;;
esac
H
use_fake_gh "$TMP/handler.sh"
fake_setup ok
events() { cat "$PROCESS_EVENTS_FILE" 2>/dev/null || true; }
spec() { # spec <file> <issue> [pair line]
  mkdir -p "$repo/docs/specs"
  printf '# Spec\n\n## Fase #%s — x\n\n1. Etapa. %s\n' "$2" "${3-modelo: sonnet · esforço: low · motivo: leve}" >"$repo/docs/specs/$1"
}

# No spec citing #n: nothing opens, by any of the three scripts.
spec other.md 70
assert_status 1 "phase-start refuses an issue without a spec" sh -c "cd '$repo' && scripts/phase-start.sh 7 --no-check"
assert_contains "$(last_output)" "no spec" "says the spec is missing"
assert_status 1 "new-phase refuses an issue without a spec" sh -c "cd '$repo' && scripts/new-phase.sh 7 --no-check"
assert_status 1 "new-phase --dry-run refuses too" sh -c "cd '$repo' && scripts/new-phase.sh 7 --dry-run"
spec eight.md 8
assert_status 1 "open-parallel refuses when one issue has no spec" sh -c "cd '$repo' && scripts/open-parallel.sh 8 7 --no-check"
assert_eq "" "$(ls "$repo/.worktrees" 2>/dev/null || true)" "no worktree is created without a spec"
assert_eq "" "$(git -C "$repo" branch --list '*issue-*')" "no branch is created without a spec"
assert_not_contains "$(events)" "phase_opened" "no phase_opened without a spec"
rm "$repo/docs/specs/eight.md" "$repo/docs/specs/other.md"

# The check CI of the base commit of main decides before anything is created: red, still
# running or absent refuse, name the run, and leave no branch, worktree, registry or phase_opened.
spec seven.md 7
for ci in red running absent; do
  assert_status 1 "phase-start refuses a base with CI $ci" env FAKE_BASE_CI=$ci sh -c "cd '$repo' && scripts/phase-start.sh 7 --no-check"
  assert_contains "$(last_output)" "no phase opens" "says why ($ci)"
  assert_contains "$(last_output)" "nothing was created" "says nothing was created ($ci)"
  assert_eq "" "$(ls "$repo/.worktrees" 2>/dev/null || true)" "no worktree with CI $ci"
  assert_eq "" "$(git -C "$repo" branch --list '*issue-*')" "no branch with CI $ci"
  assert_not_contains "$(events)" "phase_opened" "no phase_opened with CI $ci"
done
assert_status 1 "a red base refuses the group too" env FAKE_BASE_CI=red sh -c "cd '$repo' && scripts/phase-start.sh 7 8 --no-check"
assert_eq "" "$(ls "$repo/.worktrees" 2>/dev/null || true)" "the group creates nothing on a red base"
assert_contains "$(last_output)" "actions/runs/3" "names the run of the red CI"
assert_status 1 "a red base refuses --dry-run" env FAKE_BASE_CI=red sh -c "cd '$repo' && scripts/phase-start.sh 7 --dry-run"
# The ci.yml runs only on pull_request and the rebase merge creates commits without a check: a base
# with no check CI is accepted when the merged PR that holds it had CI green on its head with the same tree.
assert_status 0 "phase-start accepts a base without CI whose merged PR has green CI and the same tree" env FAKE_BASE_CI=absent FAKE_BASE_PR=green CLAUDE_CODE_SESSION_ID=manager sh -c "cd '$repo' && scripts/phase-start.sh 7 --dry-run"
assert_contains "$(last_output)" "PR #30" "says the PR that vouches for the base"
git -C "$repo" worktree list | grep -q issue-7 && git -C "$repo" worktree remove --force "$repo/.worktrees/issue-7" || true
for pr in none red tree open; do
  assert_status 1 "phase-start refuses a base without CI when the PR is $pr" env FAKE_BASE_CI=absent FAKE_BASE_PR=$pr sh -c "cd '$repo' && scripts/phase-start.sh 7 --no-check"
  assert_contains "$(last_output)" "nothing was created" "says nothing was created (PR $pr)"
  assert_eq "" "$(ls "$repo/.worktrees" 2>/dev/null || true)" "no worktree (PR $pr)"
done
rm "$repo/docs/specs/seven.md"

# Opening never runs the suite: with check-env.sh active the output has the environment
# lines and no test result, and the opening does not wait for any test run.
spec seven.md 7
assert_status 0 "phase-start opens with a green base, check-env included" env CLAUDE_CODE_SESSION_ID=manager sh -c "cd '$repo' && scripts/phase-start.sh 7"
assert_contains "$(last_output)" "CI of the base commit" "says the CI of the base was read"
assert_contains "$(last_output)" "ok: tools of the method" "the check-env of the opening checks the environment"
assert_not_contains "$(last_output)" "tests pass" "the opening does not run the suite"
assert_not_contains "$(last_output)" "passed" "the opening prints no test result"
git -C "$repo" worktree remove --force "$repo/.worktrees/issue-7"
git -C "$repo" branch -D feat/issue-7-listar-issues >/dev/null
rm -rf "$AI_METHOD_CACHE"; : >"$PROCESS_EVENTS_FILE"
git -C "$repo" status --porcelain | grep -q . && git -C "$repo" checkout --quiet -- . || true

# Closed issue: refused even with a spec.
spec nine.md 9
assert_status 1 "phase-start refuses a closed issue" sh -c "cd '$repo' && scripts/phase-start.sh 9 --no-check"
assert_contains "$(last_output)" "not open" "says the issue is not open"
assert_status 1 "new-phase refuses a closed issue" sh -c "cd '$repo' && scripts/new-phase.sh 9 --no-check"
rm "$repo/docs/specs/nine.md"

# A spec without a model/effort pair cannot give the start_session arguments.
spec seven.md 7 "sem par"
assert_status 1 "phase-start refuses a spec without model and effort" sh -c "cd '$repo' && scripts/phase-start.sh 7 --no-check"
assert_contains "$(last_output)" "modelo:" "says what the spec lacks"
assert_eq "" "$(ls "$repo/.worktrees" 2>/dev/null || true)" "nothing opens without the pair"

# Happy path: branch, worktree, the spec committed by the script, phase_opened, arguments.
spec seven.md 7
assert_status 0 "phase-start opens a phase that has a spec" env CLAUDE_CODE_SESSION_ID=manager sh -c "cd '$repo' && scripts/phase-start.sh 7 --no-check"
out="$(last_output)"
wt="$repo/.worktrees/issue-7"
assert_eq "feat/issue-7-listar-issues" "$(git -C "$wt" branch --show-current)" "worktree is on the phase branch"
# Progress of the opening: recorded for the owner, never printed.
pf="$AI_METHOD_CACHE/progress/$(basename "$repo")-7.jsonl"
assert_eq "phase-start.sh new-phase.sh" "$(jq -r 'select(.state == "end") | .script' "$pf" 2>/dev/null | sort -r | paste -sd' ' -)" "phase-start.sh and new-phase.sh record their end"
assert_contains "$(jq -r 'select(.script == "new-phase.sh") | .step' "$pf")" "creating the branch and the worktree" "new-phase.sh records its steps"
assert_not_contains "$out" "jsonl" "the opening prints no progress path"
assert_eq "docs/specs/seven.md" "$(git -C "$wt" show --name-only --format= HEAD)" "the script commits the spec on the phase branch"
assert_eq "" "$(git -C "$wt" status --porcelain)" "the worktree is clean after the spec commit"
assert_eq "" "$(git -C "$repo" status --porcelain)" "the main checkout keeps no loose copy of the spec"
assert_eq "manager" "$(events | jq -r 'select(.event == "phase_opened" and .issue == "7") | .session_id')" "records phase_opened for the opening session"
assert_contains "$out" "cwd: $repo" "prints the cwd of start_session"
assert_contains "$out" "use_worktree: false" "prints use_worktree"
assert_contains "$out" "initiation: user_asked" "prints the initiation of start_session"
assert_contains "$out" "context: fresh" "prints the context of start_session"
assert_contains "$out" "title: Fase #7" "prints the title of start_session"
assert_contains "$out" "background:" "prints the background of start_session"
assert_contains "$out" "initiation: own_initiative" "says what to do when start_session is refused"
assert_contains "$out" "scripts/start-headless.sh <issue>" "says to open the headless child when start_session is refused"
assert_contains "$out" "start-headless.sh <issue> --brief-file <file with the same background you gave start_session>" "the headless child gets the same background as start_session"
assert_contains "$out" "get_session for the model and effort of each one" "says to read the pair of each child back"
assert_contains "$out" 'quote per phase the pair read back ("Fase #n: modelo/esforço")' "says to quote the pair per phase to the owner"
assert_contains "$out" "exits 3 (no claude) or 4" "keeps the card only for a missing claude or a dead child"
assert_contains "$out" "model: sonnet" "prints the model of the spec"
assert_contains "$out" "effort: low" "prints the effort of the spec"
assert_contains "$out" "issue #7" "the prompt names the issue"
assert_contains "$out" "$wt" "the prompt names the worktree"
# The manager steps come with the arguments: every session in this turn, the
# heartbeat that wakes the manager when the end notice of a child never arrives,
# and its removal in the single end step.
assert_eq 1 "$(grep -c "Open every session above in this same turn" <<<"$out")" "says once to open every session in this turn"
assert_contains "$out" "create the manager heartbeat" "says to create the manager heartbeat"
assert_contains "$out" "At least one child is running (app or headless): create the manager heartbeat" "creates the heartbeat only with a child running"
assert_contains "$out" "create no heartbeat; the manager resumes when the owner writes here" "no heartbeat while every child is a card"
# Order: the sessions open first, the heartbeat only after list_sessions shows a
# child running, the stop (card) after it, the removal last.
# A missing step counts as line 0, so the comparison fails instead of breaking.
step_line() { local l; l="$(grep -n -F -- "$1" <<<"$out" | head -1 | cut -d: -f1)"; echo "${l:-0}"; }
hb_line="$(step_line "create the manager heartbeat")"
open_line="$(step_line "Open every session above in this same turn")"
stop_line="$(step_line "scripts/status.sh --state esperando --need")"
del_line="$(step_line "Delete the heartbeat, if it was created, in the single end step")"
assert_eq 1 "$((open_line < hb_line))" "the heartbeat step comes after the sessions step"
assert_eq 1 "$((hb_line < stop_line))" "the stop comes after the heartbeat step"
assert_eq 1 "$((stop_line < del_line))" "the removal of the heartbeat comes last"
assert_eq 1 "$(grep -c -F -- "--state esperando" <<<"$out")" "one stop command, after the sessions"
# The stop sentence is ready for --need: which card, in which session, and where the
# owner finds that session in the sidebar.
need="$(grep -F -- "scripts/status.sh --state esperando --need" <<<"$out" || true)"
assert_contains "$need" 'clique no cartão "Fase #7" na sessão "TITULO"' "the stop sentence names the card and the session"
assert_contains "$need" "na barra lateral, dentro do agrupamento da sessão principal; se não aparecer, abra o agrupamento" "the stop sentence says where the session is"
# The title is read back, never guessed: a session opened by another one does
# not know its own title; without a way to read it, the sentence names no title.
assert_contains "$out" "Replace TITULO with the title of this session read back from the app" "says to read the title of the session back"
assert_contains "$out" "never a guessed one" "says the title is never guessed"
assert_contains "$out" 'No way to read it: replace na sessão "TITULO" with na sessão que abriu a fase' "says what to write when the title cannot be read"
assert_contains "$out" "A child session not started yet (its card was not clicked): nothing to do for it" "the heartbeat covers the card not clicked yet"
assert_contains "$out" "Write to the owner only when something changed since the last heartbeat" "the heartbeat writes only on change"
assert_contains "$out" 'The same state as the last heartbeat (same phases, same states, same "Você precisa"): end the turn with no message to the owner and without the scripts/status.sh block' "the heartbeat is silent when the state is the same"
assert_contains "$out" "every 4 minutes" "gives the interval of the heartbeat"
assert_contains "$out" 'cron "*/4 * * * *"' "gives the cron of the heartbeat"
# An end-step action denied by the app: the heartbeat text sends it to a choice
# card and the session runs the action itself; the owner never runs a script.
hb_text="$(grep -F -- "Manager heartbeat of phase #7:" <<<"$out" || true)"
assert_contains "$hb_text" "denied by the app (scripts/deploy.sh, archiving a session)" "the heartbeat covers an end-step action denied by the app"
assert_contains "$hb_text" 'choice card (AskUserQuestion) that starts with "Fase #n — título"' "the heartbeat sends a denied action to a choice card"
assert_contains "$hb_text" '"Autorizar o deploy"' "the heartbeat names the option that authorizes"
assert_contains "$hb_text" "run the action again yourself" "the heartbeat makes the session run the action after the ok"
assert_contains "$hb_text" "never ask the owner to run a script or to archive in the sidebar" "the heartbeat never sends the owner to run a script"
assert_contains "$out" "CronCreate" "names the Claude Code tool of the heartbeat"
assert_contains "$out" "Você precisa" "says what to do when the tool does not exist"
assert_contains "$out" "Manager heartbeat of phase #7:" "prints the heartbeat text with the phase"
assert_contains "$out" "linked sessions" "the heartbeat reads the linked sessions"
assert_contains "$out" "pull request of each open phase" "the heartbeat reads the PRs of the open phases"
assert_contains "$out" "do the next step" "the heartbeat does the next step"
assert_contains "$out" "Delete the heartbeat, if it was created, in the single end step" "says to delete the heartbeat at the end"
assert_status 0 "check-env accepts the phase branch with its spec" sh -c "cd '$wt' && scripts/check-env.sh"
# phase_session is the mark of the session that works on the phase, never of the one that opened it.
assert_status 0 "check-env runs for the opening session" env CLAUDE_CODE_SESSION_ID=manager sh -c "cd '$wt' && scripts/check-env.sh"
assert_eq "" "$(events | jq -r 'select(.event == "phase_session" and .session_id == "manager") | .issue')" "no phase_session for the session that opened the phase"
# The child session runs in the pair of the spec (its transcript and CLAUDE_EFFORT say so).
mkdir -p "$TMP/claude/projects/p"
echo '{"type":"assistant","message":{"model":"claude-sonnet-1"}}' >"$TMP/claude/projects/p/child.jsonl"
assert_status 0 "check-env runs for the child session" env CLAUDE_CODE_SESSION_ID=child CLAUDE_EFFORT=low CLAUDE_CONFIG_DIR="$TMP/claude" sh -c "cd '$wt' && scripts/check-env.sh"
assert_eq "7" "$(events | jq -r 'select(.event == "phase_session" and .session_id == "child") | .issue')" "records phase_session for the child session"

# check-env: a phase branch without a spec for its issue is refused.
git -C "$repo" worktree add --quiet -b feat/issue-55-nospec "$repo/.worktrees/issue-55" origin/main
assert_status 1 "check-env refuses a phase branch without a spec" sh -c "cd '$repo/.worktrees/issue-55' && scripts/check-env.sh"
assert_contains "$(last_output)" "no spec" "check-env says the spec is missing"

# phase_opened is recorded before the worktree exists: it is there even when the worktree fails.
spec eleven.md 11
git -C "$repo" branch feat/issue-11-listar-issues
rc=0; (cd "$repo" && scripts/new-phase.sh 11 --no-check) >/dev/null 2>&1 || rc=$?
assert_eq 1 "$((rc != 0))" "worktree creation fails on an existing branch"
assert_eq "11" "$(events | jq -r 'select(.event == "phase_opened" and .issue == "11") | .issue')" "phase_opened comes before the worktree"
rm "$repo/docs/specs/eleven.md"

# A test issue follows the same path, and a spec of the group serves two phases.
spec group.md 10 "modelo: fable · esforço: medium · motivo: padrão"
printf '\n## Fase #12 — y\n\n1. Etapa.\n' >>"$repo/docs/specs/group.md"
assert_status 0 "phase-start opens a group in parallel, test issue included" sh -c "cd '$repo' && scripts/phase-start.sh 10 12 --no-check"
out="$(last_output)"
assert_contains "$out" "phase #10" "arguments for the test issue"
assert_contains "$out" "phase #12" "arguments for the second issue"
assert_contains "$out" "model: fable" "pair of the section"
assert_contains "$out" "Manager heartbeat of phases #10 #12:" "one heartbeat names every phase of the group"
assert_eq 1 "$(grep -c "create the manager heartbeat" <<<"$out")" "one heartbeat for the whole group"
assert_contains "$out" 'clique nos cartões "Fase #10" e "Fase #12" na sessão "TITULO"' "the stop sentence names every card of the group"
assert_eq 2 "$(cut -f1 "$repo/.worktrees/parallel-active.tsv" | grep -c .)" "registers the parallel phases"
for n in 10 12; do
  assert_eq "docs/specs/group.md" "$(git -C "$repo/.worktrees/issue-$n" show --name-only --format= HEAD)" "spec committed on the branch of #$n"
done
assert_eq "" "$(git -C "$repo" status --porcelain)" "main checkout clean after the group"

# A group spec opened one phase at a time: the loose copy stays in the main
# checkout while another open issue of the spec has no phase, so the second phase,
# opened before the merge of the first, still finds its spec.
spec later.md 13
printf '\n## Fase #14 — y\n\n1. Etapa.\n' >>"$repo/docs/specs/later.md"
export FAKE_OPEN="13 14"
assert_status 0 "phase-start opens the first phase of a group spec alone" sh -c "cd '$repo' && scripts/phase-start.sh 13 --no-check"
assert_contains "$(last_output)" "kept the loose copy of docs/specs/later.md" "says the loose copy stays for the phase not open yet"
assert_status 0 "the second phase of the spec opens before the merge of the first" sh -c "cd '$repo' && scripts/phase-start.sh 14 --no-check"
assert_eq "docs/specs/later.md" "$(git -C "$repo/.worktrees/issue-14" show --name-only --format= HEAD)" "the second phase gets the spec on its branch"
assert_eq "" "$(git -C "$repo" status --porcelain)" "the loose copy leaves with the last phase of the spec"
unset FAKE_OPEN

# A mention in passing is not a spec: an issue cited only inside the section of
# another phase does not pass the guard and inherits no pair.
spec passing.md 15
printf 'Depende da #16, que fica para depois.\n' >>"$repo/docs/specs/passing.md"
assert_status 1 "phase-start refuses an issue cited only in the section of another phase" sh -c "cd '$repo' && scripts/phase-start.sh 16 --no-check"
assert_contains "$(last_output)" "no spec" "a mention in passing is not a spec"
assert_status 0 "the issue of the section still has its spec" sh -c "cd '$repo' && scripts/new-phase.sh 15 --dry-run"
rm "$repo/docs/specs/passing.md"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPTS/lib/common.sh"
printf '# Spec (issues #1 e #2)\n\nIntro #9.\n\n## Fase #1 — a\n\nVer #3.\n\n## Notas\n\n#4\n' >"$TMP/cites.md"
assert_eq "1 2 4 9" "$(spec_open_issues "$TMP/cites.md" "1 2 3 4 9 33" | paste -sd' ' -)" "title, intro, heading and a section without issue cite; the section of another phase does not"
assert_status 2 "phase-start needs an issue number" sh -c "cd '$repo' && scripts/phase-start.sh"
finish
