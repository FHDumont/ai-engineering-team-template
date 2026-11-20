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
#: each phase, followed by the manager steps: open every session in this turn,
#: create the manager heartbeat (a recurring agent task, every 8 minutes) and
#: delete it in the single end step. --no-check skips check-env.sh; --dry-run
#: only checks and lists.
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

main_root="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
cd "$main_root"

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
for n in "${issues[@]}"; do
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    status="$(git status --porcelain -- "$rel")"
    [ -n "$status" ] || continue
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
else
  label="phases $(printf '#%s ' "${issues[@]}" | sed 's/ $//')"
fi
cat <<STEPS

Manager steps. Do all three, in this order:
1. Open every session above in this same turn. start_session refused (the turn was not started by an owner message): call it again with initiation: own_initiative and the same fields, then stop with scripts/status.sh --state esperando.
2. Right after the first session opens, create the manager heartbeat: one recurring agent task, every 8 minutes, with the text below (in Claude Code: the CronCreate tool, cron "*/8 * * * *", recurring). Create it once, not once per phase. The tool does not exist: write in "Você precisa" (scripts/status.sh --need) that the owner must write here when a phase ends.
   Heartbeat text, copy it as is:
   Manager heartbeat of $label: read the state of the linked sessions and of the pull request of each open phase (scripts/status.sh --state trabalhando), then do the next step: answer a child session that asked something, or, when every pull request is MERGED, run the integrate skill. Nothing changed: end the turn.
3. Delete the heartbeat in the single end step (integrate skill), before scripts/end-check.sh (in Claude Code: the CronDelete tool).
STEPS
