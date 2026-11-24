#!/usr/bin/env bash
#: phase-start.sh: the single entry point of a phase: it opens only with a spec in git.
#:
#: Usage: phase-start.sh <issue> [<issue>...] [--no-check] [--dry-run]
#:
#: One issue opens a solo phase (new-phase.sh); two or more, the parallel group
#: (open-parallel.sh). Exits non-zero, creating nothing, when an issue is not
#: open, when no docs/specs/*.md cites #<n>, or when the spec lacks the pair
#: "modelo: ... · esforço: ...". With a spec: records phase_opened, creates the
#: branch and the worktree, commits the spec on the branch (the session that
#: opens the phase never commits in the worktree), removes the loose copy of the
#: spec from the main checkout and prints the exact start_session arguments of
#: each phase (or, when the app refuses start_session, a card with own_initiative; start-headless.sh --brief-file only if headless is on, with
#: the same background), followed by the manager steps (the pair of each child read back
#: and quoted to the owner): create the manager heartbeat (a
#: recurring agent task, every 4 minutes), open every session in this turn and
#: delete the heartbeat in the single end step. The loose copy stays while the spec
#: has a "## Fase #n" section of another open issue whose phase was never opened (no phase_opened, no worktree; an issue only
#: cited in the text does not hold it). The --need sentence takes
#: the title of the session read back from the app, never a guessed one; with no
#: way to read it, "a sessão que abriu a fase". --no-check skips check-env.sh;
#: --dry-run only checks and lists.
#: Before anything else it runs setup-repo.sh --check: on a repository that is not
#: configured for the method it refuses with what is missing and the sentence to
#: say ("configurar o repo"), creating nothing. No option skips this, not even --no-check.
#: It never runs the test suite: it reads from GitHub the check "CI" of the base commit
#: (origin/main) before creating any branch or worktree, and refuses, creating
#: nothing, when it is red, absent or still running past the deadline, naming the run (a failure of the
#: GitHub API reading the check is reported as such, with its error, not as absent). Absent is accepted when
#: the merged PR that holds the commit (gh api commits/<sha>/pulls) had CI green on its head
#: with the same tree. Record `pr` in .github/ci-mode (one line; else the repository
#: variable PROCESS_CI_MODE) to keep CI on pull requests only: a base with no check
#: is then accepted when the merged PR that contains it had CI green, with a warning
#: when the tree differs, and a red base stays refused. A private repository with
#: no record (file, variable PROCESS_CI_MODE, or setup-repo.sh --ci-mode) is refused. ci.yml also runs on push to main, so a run of main that is still going is waited
#: for (PHASE_START_CI_WAIT seconds, default 900; progress step "waiting for the CI of main"), even before the
#: job CI exists (the workflow run of the commit counts); with no run there is nothing to wait for. A red
#: check is not cleared by rerunning that run: it keeps the gate of the commit it checked out. Push a new
#: commit on main (an empty commit is enough when there is nothing to generate) so the next run reads the
#: gate of that commit. The merge gate
#: already requires a green CI on main; the suite runs at the end (close-phase.sh
#: --prepare) and in CI. The environment is checked by check-env.sh (tools and
#: declared dependencies, no tests). A failure in the middle of the opening undoes
#: what the scripts created (new-phase.sh, open-parallel.sh).
#: Each step goes to ~/.cache/ai-method/progress/ (scripts/progress.sh), never to the
#: output; --dry-run records nothing.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=scripts/lib/progress.sh
source "$HERE/lib/progress.sh"

issues=() pass=() dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --no-check) pass+=("$1"); shift ;;
    --dry-run) pass+=("$1"); dry=1; shift ;;
    *[!0-9]*) die "unknown argument: $1 (see --help)" 2 ;;
    *) issues+=("$1"); shift ;;
  esac
done
[ ${#issues[@]} -ge 1 ] || { print_help "$0"; exit 2; }
require_cmd git gh jq python3
if [ "$dry" = 0 ]; then
  progress_start phase-start.sh "$([ ${#issues[@]} -ne 1 ] || echo "${issues[0]}")"
  trap 'progress_end $?' EXIT
fi
progress_step "checking the setup of the repo"

# Mandatory setup: nothing of the method opens on a repository that is not configured.
"$HERE/setup-repo.sh" --check >/dev/null

main_root="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
cd "$main_root"

# push: CI on main (the public template). pr: recorded in .github/ci-mode, else PROCESS_CI_MODE.
# A private repository with neither record is refused: push on main spends minutes,
# and the choice has to be on main before a phase opens.
ci_mode="" ci_recorded=0
if [ -f .github/ci-mode ]; then
  ci_mode="$(tr -d '[:space:]' < .github/ci-mode)"
  ci_recorded=1
elif [ -n "${PROCESS_CI_MODE:-}" ]; then
  ci_mode="$PROCESS_CI_MODE"
  ci_recorded=1
else
  ci_mode="$(gh variable get PROCESS_CI_MODE --repo "$(repo_slug)" 2>/dev/null || true)"
  ci_mode="$(printf '%s' "$ci_mode" | tr -d '[:space:]')"
  [ -n "$ci_mode" ] && ci_recorded=1
fi
[ -n "$ci_mode" ] || ci_mode=push
case "$ci_mode" in
  push|pr) ;;
  *) die ".github/ci-mode is '$ci_mode' and must be push or pr: no phase opens; nothing was created" ;;
esac
if [ "$ci_recorded" = 0 ]; then
  priv="$(gh api "repos/$(repo_slug)" --jq .private 2>/dev/null || true)"
  if [ "$priv" = true ]; then
    die "$(ci_mode_unrecorded_text). No phase opens until then; nothing was created"
  fi
fi

# The base of every branch is origin/main: its CI check must be green before anything is created.
progress_step "reading the CI of the base commit"
git fetch --quiet origin main || die "cannot fetch origin/main: nothing was created"
base="$(git rev-parse origin/main)"
# A failure of the API (no network, GitHub down) is not an absent check: it says it did not read it.
read_base_ci() { # sets ci_json and ci from the check "CI" of the base commit
  ci_json="$(gh api "repos/$(repo_slug)/commits/$base/check-runs?per_page=100" 2>&1)" ||
    die "could not read the check 'CI' of the base commit ${base:0:9} (gh api failed: ${ci_json:-no output}): no phase opens; fix the access to GitHub and open again; nothing was created"
  ci="$(printf '%s' "$ci_json" |
    jq -r '[.check_runs[]? | select(.name == "CI")] | sort_by(.started_at // "") | last
      | if . == null then "absent" else "\(.status)/\(.conclusion // "none") \(.html_url // "")" end' 2>/dev/null || true)"
  # The job CI is born only after the jobs it depends on: with no check CI yet, a workflow run of
  # the commit that is still going is the run to wait for (FHDumont/ai-engineering-team-template#62).
  if [ "$ci" = absent ]; then
    local runs_json
    runs_json="$(gh api "repos/$(repo_slug)/actions/runs?head_sha=$base&per_page=100" 2>&1)" ||
      die "could not read the workflow runs of the base commit ${base:0:9} (gh api failed: ${runs_json:-no output}): no phase opens; fix the access to GitHub and open again; nothing was created"
    ci="$(printf '%s' "$runs_json" |
      jq -r '[.workflow_runs[]? | select(.status != "completed")] | last
        | if . == null then "absent" else "in_progress/none \(.html_url // "")" end' 2>/dev/null || echo absent)"
  fi
}
read_base_ci
# ci.yml also runs on push to main: a run that is still going is the only thing worth waiting for
# (the sum of PRs merged in a row has no other proof). No run, nothing to wait for. Deadline and
# poll in seconds, PHASE_START_CI_WAIT (default 900) and PHASE_START_CI_POLL (default 15).
case "$ci" in
  queued/*|in_progress/*|waiting/*|pending/*|requested/*)
    wait_max="${PHASE_START_CI_WAIT:-900}" poll="${PHASE_START_CI_POLL:-15}" waited=0 warned=0
    hang="${PHASE_START_CI_HANG:-$((wait_max * 3))}"
    [ "$hang" -gt "$wait_max" ] || hang="$wait_max"
    run_url="${ci#* }"
    while :; do
      case "$ci" in queued/*|in_progress/*|waiting/*|pending/*|requested/*) ;; *) break ;; esac
      if [ "$waited" -ge "$hang" ]; then
        die "the run of 'CI' on the base commit ${base:0:9} of main did not finish in ${hang}s (${run_url}): no phase opens; wait for it and open again; nothing was created"
      fi
      if [ "$warned" = 0 ] && [ "$waited" -gt "$wait_max" ]; then
        warn_over_expected ci-wait "$waited" "$wait_max"
        warned=1
      fi
      progress_step "waiting for the CI of main" "$waited" "$wait_max"
      sleep "$poll"; waited=$((waited + poll))
      read_base_ci
    done ;;
esac
case "$ci" in
  completed/success*) echo "ok: CI of the base commit ${base:0:9} is green" ;;
  completed/skipped*)
    # Skipped is not an absent check. GitHub skips CI on main when the same tree
    # was already green on the merged PR. Accept that voucher only when the trees
    # match: a red PR, or a different tree, still refuses, even in pr mode.
    if pr="$(base_pr_vouches "$base")"; then
      echo "ok: check 'CI' of the base commit ${base:0:9} is skipped, but its merged PR #$pr had CI green on the same tree"
    else
      die "check 'CI' of the base commit ${base:0:9} of main is skipped and ${pr}: no phase opens; a skipped check is accepted only when the merged PR of that commit had CI green on the same tree; nothing was created"
    fi ;;
  ""|absent)
    # A rebase merge made before ci.yml ran on main leaves a commit with no check.
    # push mode accepts the merged PR only when its head has the same tree.
    # pr mode accepts that PR when it had CI green, and warns if the tree differs.
    if pr="$(base_pr_vouches "$base" "$ci_mode")"; then
      n="${pr%% *}"
      if [ "$pr" != "$n" ]; then
        echo "warn: no check 'CI' on the base commit ${base:0:9}; merged PR #$n had CI green, but its tree differs from main (that sum was not tested)"
      else
        echo "ok: no check 'CI' on the base commit ${base:0:9}, but its merged PR #$n had CI green on the same tree"
      fi
    else
      die "no check 'CI' on the base commit ${base:0:9} of main and ${pr}: no phase opens; CI on main starts on push to main (ci.yml has no workflow_dispatch). Push a commit to main, or record pr in .github/ci-mode so a merged PR with green CI can open the phase; nothing was created"
    fi ;;
  *) die "check 'CI' of the base commit ${base:0:9} of main is ${ci%% *} (${ci#* }): no phase opens on a red or unfinished base; rerunning that run keeps the gate of the commit it checked out. When that gate is the previous commit's, push a new commit on main (an empty commit is enough when there is nothing to generate) so the next run reads the gate of that commit. A failed test still needs a fix; nothing was created" ;;
esac

# Everything is checked before anything opens: issue open and spec (new-phase.sh --dry-run), then the pair.
progress_step "checking the issues and the specs" 0 "${#issues[@]}"
# The guards of every issue (gh and the board) run at the same time: the wait is the
# slowest one, not the sum. open-parallel.sh does not repeat them (PHASE_START_CHECKED).
guard_dir="$(mktemp -d)"
guard_pids=()
for n in "${issues[@]}"; do
  "$HERE/new-phase.sh" "$n" --dry-run >/dev/null 2>"$guard_dir/$n.err" &
  guard_pids+=($!)
done
guard_fail=0
for i in "${!issues[@]}"; do
  wait "${guard_pids[$i]}" || { guard_fail=1; cat "$guard_dir/${issues[$i]}.err" >&2; }
done
rm -rf "$guard_dir"
[ "$guard_fail" = 0 ] || exit 1
export PHASE_START_CHECKED=1
pairs=()
for n in "${issues[@]}"; do
  specs="$(specs_citing "$n" "$main_root")"
  # shellcheck disable=SC2086
  pair="$(spec_pairs "$n" $specs | head -1)" && [ -n "$pair" ] ||
    die "the spec of #$n ($(echo "$specs" | paste -sd' ' -)) has no 'modelo: ... · esforço: ...' pair: start_session needs both"
  pairs+=("$pair")
done

progress_step "opening the phase(s)" 0 "${#issues[@]}"
# No free phase slot (exit 75, nothing created): wait for one here, in the turn of the request, so the
# child sessions open in this same turn and none becomes a card the owner has to click (a card does
# not show in Remote Control). Deadline and poll in seconds, PHASE_START_SLOT_WAIT (default 540, under the 600 s of a foreground command)
# and PHASE_START_SLOT_POLL (default 15).
slot_max="${PHASE_START_SLOT_WAIT:-540}" slot_poll="${PHASE_START_SLOT_POLL:-15}" slot_waited=0
while :; do
  rc=0
  if [ ${#issues[@]} -eq 1 ]; then
    "$HERE/new-phase.sh" "${issues[0]}" ${pass[@]+"${pass[@]}"} || rc=$?
  else
    "$HERE/open-parallel.sh" "${issues[@]}" ${pass[@]+"${pass[@]}"} || rc=$?
  fi
  # 76: the group is bigger than the machine limit; waiting cannot help, so it ends here.
  [ "$rc" = 75 ] || break
  [ "$dry" = 0 ] || break
  if [ "$slot_waited" -ge "$slot_max" ]; then
    echo "error: no free phase slot after ${slot_waited}s: nothing was created; wait for a phase to end and open again" >&2
    exit 75
  fi
  progress_step "waiting for a phase slot" "$slot_waited" "$slot_max"
  sleep "$slot_poll"; slot_waited=$((slot_waited + slot_poll))
done
[ "$rc" = 0 ] || exit "$rc"
[ "$dry" = 0 ] || exit 0

# The spec now lives on the phase branches; a loose copy in the main checkout would
# block the update of main after the merge. It only goes away when a branch holds it.
# A group spec whose other phases open later stays: the loose copy is the only spec
# the main checkout has for them until the first phase of the group is merged.
progress_step "cleaning the loose copies of the spec"
open_issues="$(gh issue list --state open --limit 1000 --json number --jq '.[].number' 2>/dev/null || true)"
for n in "${issues[@]}"; do
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    status="$(git status --porcelain -- "$rel")"
    [ -n "$status" ] || continue
    later=""
    for o in $(spec_open_phases "$rel" "$open_issues"); do
      [ -d "$main_root/.worktrees/issue-$o" ] || phase_was_opened "$o" "$main_root" || later="$later #$o"
    done
    if [ -n "$later" ]; then
      echo "kept the loose copy of $rel in the main checkout: phase(s)$later of the same spec are not open yet"
      continue
    fi
    if [ "$(git -C "$main_root/.worktrees/issue-$n" rev-parse --quiet --verify "HEAD:$rel" 2>/dev/null || true)" != "$(git hash-object "$rel")" ]; then
      echo "warn: $rel differs from the phase branch: left in the main checkout"
      continue
    fi
    case "$status" in
      '?? '*) rm -f "$rel" ;;
      ' M '*) git restore --worktree -- "$rel" ;;
      *) echo "warn: $rel is staged in the main checkout: left as is" ;;
    esac
  done <<<"$(specs_citing "$n" "$main_root")"
done

i=0
for n in "${issues[@]}"; do
  path="$main_root/.worktrees/issue-$n"
  [ -d "$path" ] || die "worktree of #$n was not created: $path"
  echo
  echo "start_session arguments for phase #$n:"
  echo "  initiation: user_asked"
  echo "  context: fresh"
  echo "  cwd: $main_root"
  echo "  use_worktree: false"
  echo "  title: Fase #$n"
  echo "  model: ${pairs[$i]% *}"
  echo "  effort: ${pairs[$i]#* }"
  echo "  prompt: Execute the phase of issue #$n with the execute skill; work in the worktree $path by absolute path"
  echo "  background: at least 80 characters (goal, group and end mode of the phase)"
  i=$((i + 1))
done
# The manager only acts when something wakes it, and the end notice of a child
# session does not always arrive: the heartbeat is what wakes it. No lock checks
# that the heartbeat exists; these lines are the instruction.
if [ ${#issues[@]} -eq 1 ]; then
  label="phase #${issues[0]}"
  cards="no cartão \"Fase #${issues[0]}\""
else
  label="phases $(printf '#%s ' "${issues[@]}" | sed 's/ $//')"
  cards="nos cartões $(printf '"Fase #%s", ' "${issues[@]}" | sed -e 's/, $//' -e 's/\(.*\), /\1 e /')"
fi
# The sentence of --need is for the owner (Portuguese): which card, in which
# session, and where that session is in the sidebar.
need="clique $cards na sessão \"TITULO\", na barra lateral, dentro do agrupamento da sessão principal; se não aparecer, abra o agrupamento"
cat <<STEPS

Manager steps. Do all four, in this order:
1. Open every session above in this same turn. start_session refused (the turn was not started by an owner message): call start_session again with initiation: own_initiative and the same fields. It becomes a card that the owner clicks. Do not run scripts/start-headless.sh: headless is off by default. Only if the owner turned it on for this opening (.github/headless is on, or PROCESS_HEADLESS=on) or the app does not exist, run scripts/start-headless.sh <issue> --brief-file <file with the same background you gave start_session>. That child has no --allowedTools Bash beyond the app child.
2. Only after step 1, read the sessions back (in Claude Code: list_sessions; get_session for the model and effort of each one) and, in the message to the owner, quote per phase the pair read back ("Fase #n: modelo/esforço"), never the one that was asked. At least one child is running (app or headless): create the manager heartbeat, one recurring agent task, every 4 minutes, with the text below (in Claude Code: the CronCreate tool, cron "*/4 * * * *", recurring). Create it once, not once per phase. Every child became a card, none running: create no heartbeat; the manager resumes when the owner writes here. The tool does not exist: write in "Você precisa" (scripts/status.sh --need) that the owner must write here when a phase ends.
   Heartbeat text, copy it as is:
   Manager heartbeat of $label: read the state of the linked sessions and of the pull request of each open phase (scripts/status.sh --state trabalhando). A child session not started yet (its card was not clicked): nothing to do for it. Otherwise do the next step: answer a child session that asked something, or, when every pull request is MERGED, run the integrate skill. An action of the end step denied by the app (scripts/deploy.sh, archiving a session): open a choice card (AskUserQuestion) that starts with "Fase #n — título" and offers to authorize it (for example "Autorizar o deploy"), and with the ok of the owner run the action again yourself; never ask the owner to run a script or to archive in the sidebar. Write to the owner only when something changed since the last heartbeat (a session started, a child asked something, a pull request changed state, a new pending action): then write and paste the scripts/status.sh block. The same state as the last heartbeat (same phases, same states, same "Você precisa"): end the turn with no message to the owner and without the scripts/status.sh block. The only accepted reply when nothing changed is an empty turn: no characters at all, not even "Sem mudança.". When every open phase is only waiting for the owner, delete this heartbeat (CronDelete) in this same turn and do not leave it running; the owner's next message and the end of a child turn already wake the manager. When a phase is working again, create this same heartbeat if it is gone.
3. Only now, and only when a session became a card (a card that waits has no heartbeat to repeat it), stop with the command below. Replace TITULO with the title of this session read back from the app (the tool that describes the session itself; in Claude Code: get_session, or list_sessions), never a guessed one: a session opened by another session does not know its own title. No way to read it: replace na sessão "TITULO" with na sessão que abriu a fase. Change nothing else:
   scripts/status.sh --state esperando --need '$need'
4. Delete the heartbeat, if it was created, in the single end step (integrate skill), before scripts/end-check.sh (in Claude Code: the CronDelete tool).
STEPS
