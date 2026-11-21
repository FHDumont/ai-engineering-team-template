#!/usr/bin/env bash
#: validate.sh: lint and tests of the project and of the method's scripts.
#:
#: Usage: validate.sh [--lint] [--tests] [--full]   (no option: both, everything)
#:
#: --lint: shellcheck on Bash scripts and a Python syntax check. Alone, during a
#:         phase, it looks only at the files changed against the merge-base with the
#:         main branch (AI_METHOD_LINT_BASE) and the untracked ones; the full
#:         validation stays in close-phase.sh --prepare and in the CI.
#: --tests: runs scripts/tests/test_*.sh, scripts/tests/test_*.py and
#:          .claude/hooks/tests/test_*.sh. App tests join here once there is an app.
#: --full: forces everything: the whole lint, never the incremental one. The CI
#:         (CI=true in the environment) and a run without options are always full.
#:
#: One run per worktree: a second validate.sh in the same worktree does not start
#: another; it waits for the one running and prints its result (same options).
#: Machine-wide: at most AI_METHOD_SLOTS_VALIDATE (default 2) run at once; the
#: others wait with "waiting for a validate slot" and who holds one, up to
#: AI_METHOD_WAIT_TIMEOUT_SECONDS (exit 4). Wait and duration go to
#: ~/.cache/ai-method/history.tsv (see machine-slots.sh --report). The limits are in
#: ~/.config/ai-method/machine-limits.env.
#:
#: Never runs from inside its own tests: it sets PROCESS_VALIDATE_RUNNING=1 in the
#: environment and, called again with the mark, exits 3 at once.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=scripts/lib/slots.sh
source "$HERE/lib/slots.sh"
ROOT="$(cd "$HERE/.." && pwd)"
cd "$ROOT"

lint=0 tests=0 full=0
args="$*"
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --lint) lint=1; shift ;;
    --tests) tests=1; shift ;;
    --full) full=1; shift ;;
    *) die "unknown option: $1 (see --help)" 2 ;;
  esac
done
alone=0
[ "$lint" = 1 ] && [ "$tests" = 0 ] && [ "$full" = 0 ] && alone=1
[ "$lint" = 1 ] || [ "$tests" = 1 ] || { lint=1; tests=1; }
# Incremental lint: --lint alone, outside the CI.
incremental=0
[ "$alone" = 1 ] && [ -z "${CI:-}" ] && incremental=1

# Re-entry lock: a test that reaches validate.sh again (through close-phase.sh
# --prepare, check-env.sh or directly) would run the suite inside the suite, without
# end. The mark travels in the environment of every test.
if [ -n "${PROCESS_VALIDATE_RUNNING:-}" ]; then
  die "validate.sh is already running: a test called it again (PROCESS_VALIDATE_RUNNING is set); stub scripts/validate.sh in the temporary repo of the test" 3
fi
export PROCESS_VALIDATE_RUNNING=1

# Files with a bash shebang among the candidates on stdin, including hooks without an extension.
bash_files() {
  while read -r f; do
    [ -f "$f" ] && head -1 "$f" | grep -qE '^#!.*\bbash' && echo "$f"; true
  done
}

# Candidate files of the lint: all of them, or only the ones this phase changed.
lint_candidates() {
  if [ "$incremental" = 1 ]; then
    local base
    base="$(git merge-base HEAD "$AI_METHOD_LINT_BASE" 2>/dev/null || true)"
    if [ -n "$base" ]; then
      { git diff --name-only --diff-filter=ACMR "$base"; git ls-files -o --exclude-standard; } | sort -u
      return
    fi
    echo "warn: no merge-base with $AI_METHOD_LINT_BASE: linting everything" >&2
  fi
  git ls-files -co --exclude-standard
}

run_validate() {
  local fail=0 files pyfiles passed failed t out cands scope=""
  if [ "$lint" = 1 ]; then
    require_cmd shellcheck python3
    cands="$(lint_candidates)"
    [ "$incremental" = 0 ] || scope=", incremental"
    files="$(printf '%s\n' "$cands" | bash_files)"
    if [ -z "$files" ]; then
      echo "ok: shellcheck (0 files$scope)"
    else
      # shellcheck disable=SC2086
      if shellcheck -x -S warning $files; then
        echo "ok: shellcheck ($(echo "$files" | wc -l | tr -d ' ') files$scope)"
      else
        fail=1
      fi
    fi
    pyfiles="$(printf '%s\n' "$cands" | grep -E '\.py$' | while read -r f; do [ -f "$f" ] && echo "$f"; done || true)"
    # shellcheck disable=SC2086
    if [ -z "$pyfiles" ] || python3 -c 'import ast, sys
for f in sys.argv[1:]:
    ast.parse(open(f, encoding="utf-8").read(), f)' $pyfiles; then
      echo "ok: python syntax$scope"
    else
      fail=1
    fi
  fi

  if [ "$tests" = 1 ]; then
    passed=0 failed=0
    for t in scripts/tests/test_*.sh .claude/hooks/tests/test_*.sh; do
      [ -e "$t" ] || continue
      if out="$(bash "$t" 2>&1)"; then
        passed=$((passed + 1))
      else
        failed=$((failed + 1)); fail=1
        echo "FAIL $t"; echo "$out" | tail -20 | sed 's/^/  /'
      fi
    done
    for t in scripts/tests/test_*.py; do
      [ -e "$t" ] || continue
      if out="$(python3 "$t" 2>&1)"; then
        passed=$((passed + 1))
      else
        failed=$((failed + 1)); fail=1
        echo "FAIL $t"; echo "$out" | tail -20 | sed 's/^/  /'
      fi
    done
    echo "tests: $passed passed, $failed failed"
  fi
  exit "$fail"
}

slots_load_limits
home="$(slots_home)"
lockbase="$home/locks"
key="$(printf '%s' "$ROOT" | cksum | cut -d' ' -f1)"
lockdir="$lockbase/$key.lock"
resultf="$lockbase/$key.result"
mkdir -p "$lockbase"

# One run per worktree. The holder writes its result before it frees the lock; a
# second call waits for the holder and prints that result, if it ran the same options.
wait_start="$(now_epoch)"
announced=0
while ! mkdir "$lockdir" 2>/dev/null; do
  holder="$(cat "$lockdir/pid" 2>/dev/null || true)"
  if [ -n "$holder" ] && ! pid_alive "$holder"; then
    rm -rf "$lockdir"   # the run died without freeing its lock
    continue
  fi
  if [ "$announced" = 0 ]; then
    echo "validate.sh is already running in this worktree (pid ${holder:-?}): waiting for its result"
    announced=1
  fi
  if [ $(( $(now_epoch) - wait_start )) -ge "$AI_METHOD_WAIT_TIMEOUT_SECONDS" ]; then
    die "timeout waiting for the validate.sh running in this worktree (pid ${holder:-?})" 4
  fi
  sleep "$AI_METHOD_POLL_SECONDS"
  if [ ! -d "$lockdir" ] && [ -f "$resultf" ]; then
    IFS="$(printf '\t')" read -r r_ts r_rc r_args <"$resultf" || true
    if [ "${r_ts:-0}" -ge "$wait_start" ] && [ "${r_args:-}" = "$args" ]; then
      sed 1d "$resultf"
      exit "${r_rc:-1}"
    fi
  fi
done
echo $$ >"$lockdir/pid"
log="$(mktemp "${TMPDIR:-/tmp}/validate.XXXXXX")"
started=0
finish_run() {
  local rc=$?
  if [ "$started" = 1 ]; then
    { printf '%s\t%s\t%s\n' "$(now_epoch)" "$rc" "$args"; cat "$log"; } >"$resultf.tmp" 2>/dev/null && mv "$resultf.tmp" "$resultf"
  fi
  rm -f "$log"
  slots_release
  rm -rf "$lockdir"
}
trap finish_run EXIT

slots_wait validate "$(issue_from_branch "$(current_branch)")" "$ROOT" || exit $?
slots_load_report | grep '^warn:' || true
t0="$(now_epoch)"
started=1
set +e
run_validate 2>&1 | tee "$log"
rc=${PIPESTATUS[0]}
set -e
history_add validate "$(slots_repo_name)" "$(issue_from_branch "$(current_branch)")" "$SLOT_WAIT" "$(( $(now_epoch) - t0 ))"
exit "$rc"
