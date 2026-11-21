#!/usr/bin/env bash
#: start-headless.sh: opens the child session of a phase as a headless "claude -p".
#:
#: Usage: start-headless.sh <issue> [--dry-run]
#:
#: For the manager when the app refuses start_session (Remote Control): the phase
#: must already be open (phase-start.sh). It reads the pair "modelo/esforço" of the
#: spec, then starts in the background, inside .worktrees/issue-<n>:
#:   claude -p <execute prompt> --session-id <uuid> --model <m> --effort <e>
#: with the log in .worktrees/issue-<n>/.process/headless.log (outside git) and
#: records phase_headless in the trace (pid, child_session, log, model, effort).
#: The child runs check-env.sh like an app session and records phase_session itself.
#: It has no choice board: a question for the owner goes as a comment on the issue
#: and the manager answers with: claude -p --resume <child_session> "<answer>"
#: (run inside the worktree; the id is in the phase_headless event).
#: Permission mode: HEADLESS_PERMISSION_MODE (default acceptEdits, plus Bash allowed).
#: Exit 3: "claude" is not installed (fall back to the card of start_session);
#: 4: the process died right after the start (see the log); 2: bad usage or no
#: worktree/pair. --dry-run prints the command and starts nothing.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"

issue="" dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --dry-run) dry=1; shift ;;
    *[!0-9]*) die "unknown argument: $1 (see --help)" 2 ;;
    *) issue="$1"; shift ;;
  esac
done
[ -n "$issue" ] || { print_help "$0"; exit 2; }
require_cmd git jq python3
command -v claude >/dev/null 2>&1 || die "claude is not installed: use the card of start_session" 3

main_root="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
wt="$main_root/.worktrees/issue-$issue"
[ -d "$wt" ] || die "no worktree for #$issue: open the phase with scripts/phase-start.sh first" 2
specs="$(specs_citing "$issue" "$main_root")"
# shellcheck disable=SC2086
pair="$(spec_pairs "$issue" $specs | head -1)" && [ -n "$pair" ] || die "no 'modelo: ... · esforço: ...' pair in the spec of #$issue" 2
model="${pair% *}" effort="${pair#* }"

sid="$(python3 -c 'import uuid; print(uuid.uuid4())')"
log="$wt/.process/headless.log"
mode="${HEADLESS_PERMISSION_MODE:-acceptEdits}"
prompt="Execute the phase of issue #$issue with the execute skill; work in the worktree $wt by absolute path. You run headless: there is no choice board and no one answers in this session. A question for the owner goes as a comment on issue #$issue (gh issue comment), then stop with scripts/status.sh --state esperando --need '<the question>'; the manager resumes this session with the answer."
cmd=(claude -p "$prompt" --session-id "$sid" --model "$model" --effort "$effort"
  --permission-mode "$mode" --allowedTools Bash)
if [ "$dry" = 1 ]; then
  echo "cwd: $wt"
  printf '%q ' "${cmd[@]}"; echo
  echo "log: $log"
  exit 0
fi

mkdir -p "$wt/.process"
(cd "$wt" && nohup "${cmd[@]}" </dev/null >"$log" 2>&1 &
  echo $! >"$wt/.process/headless.pid")
pid="$(cat "$wt/.process/headless.pid")"
sleep 1
if ! kill -0 "$pid" 2>/dev/null; then
  # A fast fake or a real failure: the exit status is not readable once it is gone,
  # so a log that says it failed decides; an empty log of a dead process is a failure too.
  if [ ! -s "$log" ] || grep -qiE 'error|fail|not found' "$log"; then
    die "headless child of #$issue died right after the start; log: $log" 4
  fi
fi
(cd "$wt" && trace_event phase_headless "issue=$issue" "pid=$pid" "child_session=$sid" \
  "model=$model" "effort=$effort" "log=$log")
echo "headless child of #$issue started: pid $pid, session $sid"
echo "log: $log"
