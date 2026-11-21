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
#: each phase (or, when the app refuses start_session, start-headless.sh --brief-file with
#: the same background), followed by the manager steps (the pair of each child read back
#: and quoted to the owner): create the manager heartbeat (a
#: recurring agent task, every 4 minutes), open every session in this turn and
#: delete the heartbeat in the single end step. The loose copy stays while the spec
#: cites another open issue whose phase is not open yet. The --need sentence takes
#: the title of the session read back from the app, never a guessed one; with no
#: way to read it, "a sessão que abriu a fase". --no-check skips check-env.sh;
#: --dry-run only checks and lists.
#: Before anything else it runs setup-repo.sh --check: on a repository that is not
#: configured for the method it refuses with what is missing and the sentence to
#: say ("configurar o repo"), creating nothing. No option skips this, not even --no-check.
#: It never runs the test suite: it reads from GitHub the check "CI" of the base commit
#: (origin/main) before creating any branch or worktree, and refuses, creating
#: nothing, when it is red, still running or absent, naming the run. Absent is accepted when
#: the merged PR that holds the commit (gh api commits/<sha>/pulls) had CI green on its head
#: with the same tree (ci.yml runs only on pull_request; a rebase merge creates commits with no check). The merge gate
#: already requires a green CI on main; the suite runs at the end (close-phase.sh
#: --prepare) and in CI. The environment is checked by check-env.sh (tools and
#: declared dependencies, no tests). A failure in the middle of the opening undoes
#: what the scripts created (new-phase.sh, open-parallel.sh).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"

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

# Mandatory setup: nothing of the method opens on a repository that is not configured.
"$HERE/setup-repo.sh" --check >/dev/null

main_root="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
cd "$main_root"

# Prints the number of the merged PR whose head had CI green and the same tree as commit $1
# (returns 0), or the reason (returns 1).
base_pr_vouches() {
  local sha="$1" slug prs n head tree htree ci
  slug="$(repo_slug)"
  prs="$(gh api "repos/$slug/commits/$sha/pulls" 2>/dev/null |
    jq -r '.[]? | select(.merged_at != null) | "\(.number) \(.head.sha)"' 2>/dev/null || true)"
  [ -n "$prs" ] || { echo "no merged PR holds it"; return 1; }
  tree="$(git rev-parse "$sha^{tree}")"
  while read -r n head; do
    [ -n "$n" ] || continue
    ci="$(gh api "repos/$slug/commits/$head/check-runs?per_page=100" 2>/dev/null |
      jq -r '[.check_runs[]? | select(.name == "CI")] | sort_by(.started_at // "") | last
        | if . == null then "absent" else "\(.status)/\(.conclusion // "none")" end' 2>/dev/null || true)"
    [ "$ci" = "completed/success" ] || { echo "the CI of its PR #$n is ${ci:-absent}"; return 1; }
    htree="$(gh api "repos/$slug/git/commits/$head" 2>/dev/null | jq -r '.tree.sha // empty' 2>/dev/null || true)"
    [ "$htree" = "$tree" ] || { echo "the tree of its PR #$n differs from the commit of main"; return 1; }
    echo "$n"; return 0
  done <<EOF2
$prs
EOF2
  echo "no merged PR holds it"; return 1
}

# The base of every branch is origin/main: its CI check must be green before anything is created.
git fetch --quiet origin main || die "cannot fetch origin/main: nothing was created"
base="$(git rev-parse origin/main)"
ci="$(gh api "repos/$(repo_slug)/commits/$base/check-runs?per_page=100" 2>/dev/null |
  jq -r '[.check_runs[]? | select(.name == "CI")] | sort_by(.started_at // "") | last
    | if . == null then "absent" else "\(.status)/\(.conclusion // "none") \(.html_url // "")" end' 2>/dev/null || true)"
case "$ci" in
  completed/success*) echo "ok: CI of the base commit ${base:0:9} is green" ;;
  ""|absent)
    # ci.yml runs only on pull_request and a rebase merge creates commits with no check:
    # the base is accepted when the merged PR that holds it had CI green on its head, same tree.
    if pr="$(base_pr_vouches "$base")"; then
      echo "ok: no check 'CI' on the base commit ${base:0:9}, but its merged PR #$pr had CI green on the same tree"
    else
      die "no check 'CI' on the base commit ${base:0:9} of main and ${pr}: no phase opens; wait for the run of main or start it (gh workflow run), then open again; nothing was created"
    fi ;;
  *) die "check 'CI' of the base commit ${base:0:9} of main is ${ci%% *} (${ci#* }): no phase opens on a red or unfinished base; fix main or wait for the run, then open again; nothing was created" ;;
esac

# Everything is checked before anything opens: issue open and spec (new-phase.sh --dry-run), then the pair.
pairs=()
for n in "${issues[@]}"; do
  "$HERE/new-phase.sh" "$n" --dry-run >/dev/null
  specs="$(specs_citing "$n" "$main_root")"
  # shellcheck disable=SC2086
  pair="$(spec_pairs "$n" $specs | head -1)" && [ -n "$pair" ] ||
    die "the spec of #$n ($(echo "$specs" | paste -sd' ' -)) has no 'modelo: ... · esforço: ...' pair: start_session needs both"
  pairs+=("$pair")
done

if [ ${#issues[@]} -eq 1 ]; then
  "$HERE/new-phase.sh" "${issues[0]}" ${pass[@]+"${pass[@]}"}
else
  "$HERE/open-parallel.sh" "${issues[@]}" ${pass[@]+"${pass[@]}"}
fi
[ "$dry" = 0 ] || exit 0

# The spec now lives on the phase branches; a loose copy in the main checkout would
# block the update of main after the merge. It only goes away when a branch holds it.
# A group spec whose other phases open later stays: the loose copy is the only spec
# the main checkout has for them until the first phase of the group is merged.
open_issues="$(gh issue list --state open --limit 1000 --json number --jq '.[].number' 2>/dev/null || true)"
for n in "${issues[@]}"; do
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    status="$(git status --porcelain -- "$rel")"
    [ -n "$status" ] || continue
    later=""
    for o in $(spec_open_issues "$rel" "$open_issues"); do
      [ -d "$main_root/.worktrees/issue-$o" ] || later="$later #$o"
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
1. Open every session above in this same turn. start_session refused (the turn was not started by an owner message, Remote Control): for each refused phase run scripts/start-headless.sh <issue> --brief-file <file with the same background you gave start_session> (the child does not see the background otherwise), which starts the child as a headless claude -p in the worktree (log in .worktrees/issue-<n>/.process/headless.log, pid and session id in the trace as phase_headless); a question of that child comes as a comment on the issue, and you answer from the worktree with CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 claude -p "<answer>" --resume <child_session> (the prompt right after -p, never after --allowedTools). Only when start-headless.sh exits 3 (no claude) or 4 (the child died): call start_session again with initiation: own_initiative and the same fields. It becomes a card that the owner clicks.
2. Only after step 1, read the sessions back (in Claude Code: list_sessions; get_session for the model and effort of each one) and, in the message to the owner, quote per phase the pair read back ("Fase #n: modelo/esforço"), never the one that was asked. At least one child is running (app or headless): create the manager heartbeat, one recurring agent task, every 4 minutes, with the text below (in Claude Code: the CronCreate tool, cron "*/4 * * * *", recurring). Create it once, not once per phase. Every child became a card, none running: create no heartbeat; the manager resumes when the owner writes here. The tool does not exist: write in "Você precisa" (scripts/status.sh --need) that the owner must write here when a phase ends.
   Heartbeat text, copy it as is:
   Manager heartbeat of $label: read the state of the linked sessions and of the pull request of each open phase (scripts/status.sh --state trabalhando). A child session not started yet (its card was not clicked): nothing to do for it. Otherwise do the next step: answer a child session that asked something, or, when every pull request is MERGED, run the integrate skill. An action of the end step denied by the app (scripts/deploy.sh, archiving a session): open a choice card (AskUserQuestion) that starts with "Fase #n — título" and offers to authorize it (for example "Autorizar o deploy"), and with the ok of the owner run the action again yourself; never ask the owner to run a script or to archive in the sidebar. Write to the owner only when something changed since the last heartbeat (a session started, a child asked something, a pull request changed state, a new pending action): then write and paste the scripts/status.sh block. The same state as the last heartbeat (same phases, same states, same "Você precisa"): end the turn with no message to the owner and without the scripts/status.sh block.
3. Only now, and only when a session became a card (a card that waits has no heartbeat to repeat it), stop with the command below. Replace TITULO with the title of this session read back from the app (the tool that describes the session itself; in Claude Code: get_session, or list_sessions), never a guessed one: a session opened by another session does not know its own title. No way to read it: replace na sessão "TITULO" with na sessão que abriu a fase. Change nothing else:
   scripts/status.sh --state esperando --need '$need'
4. Delete the heartbeat, if it was created, in the single end step (integrate skill), before scripts/end-check.sh (in Claude Code: the CronDelete tool).
STEPS
