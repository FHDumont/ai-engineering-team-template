#!/usr/bin/env bash
#: start-headless.sh: opens the child session of a phase as a headless "claude -p".
#:
#: Usage: start-headless.sh <issue> [--brief <text> | --brief-file <file>] [--dry-run]
#:
#: Off by default. PROCESS_HEADLESS=on or a one-line "on" in .github/headless
#: (a repo file; the template update does not overwrite it) turns it on. A
#: refusal for lack of owner speech is a card or a wait, not this script.
#: No --allowedTools Bash beyond the app child.
#: For the manager when the owner turned headless on for that opening or the app
#: does not exist: the phase must already be open (phase-start.sh). It reads the pair "modelo/esforço" of the
#: spec in the worktree of the phase (the spec may exist only on its branch), then starts in the background, inside .worktrees/issue-<n>:
#:   claude -p <execute prompt> --session-id <uuid> --model <m> --effort <e>
#: with stdin from /dev/null, stdout and stderr only in the log
#: .worktrees/issue-<n>/.process/headless.log (outside git), in a session of its own
#: (it holds no pipe of the caller and does not die with the caller's process group), and
#: records phase_headless in the trace (pid, child_session, log, model, effort).
#: The child runs check-env.sh like an app session and records phase_session itself.
#: It has no choice board: a question for the owner goes as a comment on the issue
#: and the manager answers with: CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 claude -p "<answer>" --resume <child_session>
#: (run inside the worktree; the id is in the phase_headless event). The prompt goes
#: right after -p: after --allowedTools it becomes a tool name and the resume fails with
#: "No deferred tool marker found". The variable (also set for the child here) makes
#: claude -p wait for background tasks instead of stopping them 10m after the last turn;
#: even so the child runs the close-reviewer in the foreground.
#: --brief / --brief-file: the same background the manager gives start_session (extra
#: scope, findings to solve, file limits). It is appended to the prompt, after the
#: execute prompt, under "Brief of the manager:"; phase_headless records brief=yes
#: (or brief=no). The app child gets the brief through the background of
#: start_session; without it here the headless child would only see the skill.
#: Permission mode: HEADLESS_PERMISSION_MODE (default acceptEdits; same tools as the app child).
#: Exit 5: headless is off (card or wait instead); 3: "claude" is not installed
#: (fall back to the card of start_session); 4: the process died right after the
#: start (see the log); 2: bad usage or no worktree/pair. --dry-run prints the
#: command and starts nothing.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=scripts/lib/slots.sh
source "$HERE/lib/slots.sh"

issue="" dry=0 brief=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --dry-run) dry=1; shift ;;
    --brief) [ $# -ge 2 ] || die "--brief needs a text" 2; brief="$2"; shift 2 ;;
    --brief-file)
      [ $# -ge 2 ] || die "--brief-file needs a file" 2
      [ -f "$2" ] || die "no such brief file: $2" 2
      brief="$(cat "$2")"; shift 2 ;;
    *[!0-9]*) die "unknown argument: $1 (see --help)" 2 ;;
    *) issue="$1"; shift ;;
  esac
done
[ -n "$issue" ] || { print_help "$0"; exit 2; }
require_cmd git
headless_on() {
  case "${PROCESS_HEADLESS:-}" in on|ON|1|true) return 0 ;; esac
  local root
  root="$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
  [ -n "$root" ] || root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -f "$root/.github/headless" ] && grep -qxF on "$root/.github/headless"
}
headless_on || die "headless is off: propose the session (initiation own_initiative) or wait for the owner to speak here; do not start a headless child" 5
require_cmd jq python3
command -v claude >/dev/null 2>&1 || die "claude is not installed: use the card of start_session" 3

main_root="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
wt="$main_root/.worktrees/issue-$issue"
[ -d "$wt" ] || die "no worktree for #$issue: open the phase with scripts/phase-start.sh first" 2
# The spec lives on the branch of the phase (phase-start.sh commits it there and removes the
# loose copy of the main checkout): read it from the worktree.
specs="$(specs_citing "$issue" "$wt" | sed "s#^#$wt/#")"
# shellcheck disable=SC2086
pair="$(spec_pairs "$issue" $specs | head -1)" && [ -n "$pair" ] || die "no 'modelo: ... · esforço: ...' pair in the spec of #$issue" 2
model="${pair% *}" effort="${pair#* }"

sid="$(python3 -c 'import uuid; print(uuid.uuid4())')"
log="$wt/.process/headless.log"
mode="${HEADLESS_PERMISSION_MODE:-acceptEdits}"
prompt="Execute the phase of issue #$issue with the execute skill; work in the worktree $wt by absolute path. You run headless: there is no choice board and no one answers in this session. A question for the owner goes as a comment on issue #$issue (gh issue comment), then stop with scripts/status.sh --state esperando --need '<the question>'; the manager resumes this session with the answer. Commit with plain git add <file> from inside the worktree (no -C, no &&). A template update brings the template with scripts/fetch-template.sh <sha> into .process/template; no worktree or clone of it."
[ -z "$brief" ] || prompt="$prompt

Brief of the manager:
$brief"
cmd=(claude -p "$prompt" --session-id "$sid" --model "$model" --effort "$effort"
  --permission-mode "$mode")
if [ "$dry" = 1 ]; then
  echo "cwd: $wt"
  echo "env: CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0"
  printf '%q ' "${cmd[@]}"; echo
  echo "log: $log"
  exit 0
fi

mkdir -p "$wt/.process"
# The child gets its own session (setsid via python3: macOS has no setsid(1)), stdin from
# /dev/null and stdout/stderr only in the log: it holds no pipe of the caller (a "| tail -2"
# returns at once) and does not die with the process group of the caller.
rm -f "$wt/.process/headless.pid"
# The redirections sit on the whole group, not on the command: the subshell that waits for the
# child would otherwise keep the pipe of the caller open; "exec" leaves no waiter behind.
(cd "$wt" && CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 exec nohup python3 -c '
import os, sys
os.setsid()
with open(sys.argv[1], "w") as pidfile:
    pidfile.write("%d\n" % os.getpid())
os.execvp(sys.argv[2], sys.argv[2:])
' "$wt/.process/headless.pid" "${cmd[@]}") </dev/null >"$log" 2>&1 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&- &
bg=$!
# The pid file is written by the wrapper before exec. Two seconds is the
# expected wait; past that, warn and keep waiting. The hang limit grows with
# the load (30s on a free machine, the same scale as slots_test_timeout).
slots_load_limits
hang=$(( $(slots_test_timeout) / 20 ))
[ "$hang" -ge 2 ] || hang=2
ticks=0
hang_ticks=$((hang * 5))
while [ ! -s "$wt/.process/headless.pid" ] && [ "$ticks" -lt "$hang_ticks" ]; do
  sleep 0.2
  ticks=$((ticks + 1))
done
if [ ! -s "$wt/.process/headless.pid" ]; then
  # The child is running and the file never appeared: record it, do not cat a
  # missing file and leave it without a trace.
  pid="$bg"
  warn_over_expected headless-pid "$hang" 2 || true
  (cd "$wt" && trace_event phase_headless "issue=$issue" "pid=$pid" "child_session=$sid" \
    "model=$model" "effort=$effort" "log=$log" "brief=$([ -n "$brief" ] && echo yes || echo no)")
  echo "headless child of #$issue recorded without a pid file: pid $pid, session $sid"
  echo "log: $log"
  exit 0
fi
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
  "model=$model" "effort=$effort" "log=$log" "brief=$([ -n "$brief" ] && echo yes || echo no)")
echo "headless child of #$issue started: pid $pid, session $sid"
echo "log: $log"
