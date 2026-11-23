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
#:          .claude/hooks/tests/test_*.sh. When .github/validate-repo.sh exists,
#:          it runs after those tests and its exit code counts: that is where
#:          the repository puts its own checks, without editing this file.
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
#: Tests run in parallel, each in its own temporary folder: AI_METHOD_TEST_JOBS at once
#: (default: CPUs divided by AI_METHOD_SLOTS_VALIDATE, at least 1; 1 = in series). The
#: report keeps the fixed order of the tests.
#:
#: Progress (for the owner and the dashboard, never printed): each step goes to
#: ~/.cache/ai-method/progress/<repo>-<issue>.jsonl (scripts/progress.sh reads it).
#:
#: Orphans: every test runs with TMPDIR inside a folder of this run. At the end, and on
#: INT/TERM, a process still alive there (cwd or command line in that folder) is stopped
#: and listed ("orphan process <pid>") and the run exits 1: a process left by the suite
#: is a defect (issue #66).
#:
#: Never runs from inside its own tests: it sets PROCESS_VALIDATE_RUNNING=1 in the
#: environment and, called again with the mark, exits 3 at once.
#: A full green run (lint and tests) on a clean tree records phase_validate on HEAD
#: so close-phase.sh --prepare can reuse it.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=scripts/lib/slots.sh
source "$HERE/lib/slots.sh"
# shellcheck source=scripts/lib/progress.sh
source "$HERE/lib/progress.sh"
# shellcheck source=scripts/lib/procs.sh
source "$HERE/lib/procs.sh"
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
    [ -f "$f" ] && head -1 "$f" | stdin_grep -qE '^#!.*\bbash' && echo "$f"; true
  done
}

# Candidate files of the lint: all of them, or only the ones this phase changed.
lint_candidates() {
  if [ "$incremental" = 1 ]; then
    local base
    base="$(git merge-base HEAD "$AI_METHOD_LINT_BASE" 2>/dev/null || true)"
    if [ -n "$base" ]; then
      { git diff --name-only --no-renames -z --diff-filter=ACMR "$base" | tr '\0' '\n'; git ls-files -z -o --exclude-standard | tr '\0' '\n'; } | sort -u
      return
    fi
    echo "warn: no merge-base with $AI_METHOD_LINT_BASE: linting everything" >&2
  fi
  git ls-files -co --exclude-standard
}

# Outside the CI, a missing module in the output of a failed test becomes one line:
# folder, module and install command. Output on stdin; the CI prints nothing extra.
missing_dep_hint() {
  [ -z "${CI:-}" ] || return 0
  local out mod base f dir
  out="$(cat)"
  printf '%s\n' "$out" | sed -nE "s/.*No module named '([^'.]+)[^']*'.*/\1/p" | sort -u | while read -r mod; do
    f="$(git ls-files -co --exclude-standard 'requirements*.txt' '*/requirements*.txt' | while read -r r; do
      grep -qiE "^${mod//_/[-_]}([^A-Za-z0-9_.-]|\$)" "$r" 2>/dev/null && echo "$r" && break
    done | head -1)"
    if [ -n "$f" ]; then
      echo "missing dependency: module $mod (folder $(dirname "$f")): pip install -r $f"
    else
      echo "missing dependency: module $mod (no requirements*.txt lists it): pip install $mod"
    fi
  done
  printf '%s\n' "$out" | sed -nE "s/.*Cannot find module '([^']+)'.*/\1/p" | sort -u | while read -r mod; do
    f="$(git ls-files -co --exclude-standard package.json '*/package.json' | head -1)"
    dir="$(dirname "${f:-package.json}")"
    if [ "$dir" = . ]; then
      echo "missing dependency: module $mod (folder .): npm install"
    else
      echo "missing dependency: module $mod (folder $dir): cd $dir && npm install"
    fi
  done
}

run_validate() {
  local fail=0 files pyfiles passed failed t out cands scope=""
  if [ "$lint" = 1 ]; then
    require_cmd shellcheck python3
    progress_step "shellcheck and python syntax"
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
    local list=() n_total rdir pid n_seen=0 line runner alive
    for t in scripts/tests/test_*.sh .claude/hooks/tests/test_*.sh scripts/tests/test_*.py; do
      [ -e "$t" ] && list+=("$t")
    done
    n_total=${#list[@]}
    passed=0 failed=0
    # bash 3.2 with set -u rejects "${list[@]}" when the list is empty (#110).
    # Skip the runner entirely; there is no test file to hand to xargs.
    if [ "$n_total" -gt 0 ]; then
    # Each test runs in the background, up to AI_METHOD_TEST_JOBS at once, with its own
    # temporary folder (tests/lib.sh makes one per run); output and exit code go to
    # files and are reported afterwards, in the fixed order of the list. Each finished
    # test appends its name to done.log, which feeds the progress.
    rdir="$RDIR"
    : >"$rdir/done.log"
    # shellcheck disable=SC2016  # the runner is a script for the child shell
    runner='n="$(printf %s "$2" | tr / _)"
      case "$2" in *.py) python3 "$2" >"$1/$n.out" 2>&1 ;; *) bash "$2" >"$1/$n.out" 2>&1 ;; esac
      echo $? >"$1/$n.rc"; basename "$2" >>"$1/done.log"'
    # Each test gets its own TMPDIR inside the folder of the run: orphan_sweep finds what it leaves.
    runner="mkdir -p \"\$1/tmp\"; export TMPDIR=\"\$1/tmp\"; $runner"
    printf '%s\0' "${list[@]}" | xargs -0 -n1 -P "$AI_METHOD_TEST_JOBS" bash -c "$runner" _ "$rdir" &
    pid=$!
    while :; do
      alive=1; kill -0 "$pid" 2>/dev/null || alive=0
      while IFS= read -r line; do
        n_seen=$((n_seen + 1)); progress_step "tests $line" "$n_seen" "$n_total"
      done < <(sed -n "$((n_seen + 1)),\$p" "$rdir/done.log")
      [ "$alive" = 1 ] || break
      sleep 1
    done
    wait "$pid" || true
    for t in "${list[@]}"; do
      if [ "$(cat "$rdir/$(printf %s "$t" | tr / _).rc" 2>/dev/null || echo 1)" = 0 ]; then
        passed=$((passed + 1))
      else
        failed=$((failed + 1)); fail=1
        out="$(cat "$rdir/$(printf %s "$t" | tr / _).out" 2>/dev/null || true)"
        echo "FAIL $t"; echo "$out" | tail -20 | sed 's/^/  /'
        echo "$out" | missing_dep_hint
      fi
    done
    fi
    echo "tests: $passed passed, $failed failed"
    if [ -f .github/validate-repo.sh ]; then
      echo "repo: .github/validate-repo.sh"
      bash .github/validate-repo.sh || fail=1
    fi
  fi
  exit "$fail"
}

# Stops what is alive in the folder of this run (its tests' processes and whatever they
# left detached), listing it; returns 0 when there was something.
orphan_sweep() {
  local pids p all="" stop="" found=1
  [ -n "${RDIR:-}" ] && [ -d "$RDIR" ] || return 1
  pids="$(procs_orphans "$RDIR"; procs_in_dir "$RDIR"; pgrep -f "$RDIR/" 2>/dev/null || true)"
  for p in $pids; do
    [ "$p" != "$$" ] || continue
    case " $(proc_chain "$$" | tr '\n' ' ') " in *" $p "*) continue ;; esac
    proc_alive "$p" || continue
    all="$all $p $(proc_descendants "$p" | tr '\n' ' ')"
  done
  for p in $(printf '%s\n' "$all" | tr ' ' '\n' | grep . | sort -un); do
    proc_alive "$p" || continue
    case " $(proc_chain "$$" | tr '\n' ' ') " in *" $p "*) continue ;; esac
    stop="$stop $p"
    echo "orphan process $p: $(proc_cmd "$p" | cut -c1-100)"
    found=0
  done
  # shellcheck disable=SC2086
  [ -z "$stop" ] || proc_stop $stop
  return "$found"
}

# Identity of the worktree this run would validate: HEAD plus the dirty and
# untracked files. A waiter inherits a result only when this is unchanged.
tree_key() {
  {
    git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo none
    git -C "$ROOT" status --porcelain=v1 --untracked-files=all
  } | cksum | awk '{print $1}'
}

slots_load_limits
home="$(slots_home)"
lockbase="$home/locks"
key="$(printf '%s' "$ROOT" | cksum | cut -d' ' -f1)"
lockdir="$lockbase/$key.lock"
resultf="$lockbase/$key.result"
mkdir -p "$lockbase"

# One run per worktree. The holder writes its result before it frees the lock; a
# second call waits for the holder and prints that result, if it ran the same options
# on the same tree.
wait_start="$(now_epoch)"
wait_tree="$(tree_key)"
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
    IFS="$(printf '\t')" read -r r_ts r_rc r_args r_tree <"$resultf" || true
    now_tree="$(tree_key)"
    if [ "${r_ts:-0}" -ge "$wait_start" ] && [ "${r_args:-}" = "$args" ] &&
       [ "${r_tree:-}" = "$wait_tree" ] && [ "$now_tree" = "$wait_tree" ] &&
       [ "${r_tree:-}" != stale ]; then
      sed 1d "$resultf"
      exit "${r_rc:-1}"
    fi
  fi
done
echo $$ >"$lockdir/pid"
run_tree="$(tree_key)"
printf '%s\n' "$run_tree" >"$lockdir/tree"
RDIR="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/validate-tests.XXXXXX")" && pwd -P)"
log="$(mktemp "${TMPDIR:-/tmp}/validate.XXXXXX")"
started=0
finish_run() {
  local rc=$? cache_tree="${run_tree:-stale}" now_tree
  now_tree="$(tree_key)"
  [ "$now_tree" = "$cache_tree" ] || cache_tree=stale
  if [ "$started" = 1 ]; then
    { printf '%s\t%s\t%s\t%s\n' "$(now_epoch)" "$rc" "$args" "$cache_tree"; cat "$log"; } >"$resultf.tmp" 2>/dev/null && mv "$resultf.tmp" "$resultf"
  fi
  # Interrupted or failed run: the tests still running and what they left go too.
  # shellcheck disable=SC2046
  proc_stop $(proc_descendants "$$" | tr '\n' ' ') 2>/dev/null || true
  orphan_sweep >/dev/null 2>&1 || true
  progress_end "$rc"
  rm -f "$log"
  [ -z "${RDIR:-}" ] || rm -rf "$RDIR"
  slots_release
  rm -rf "$lockdir"
}
trap finish_run EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

export AI_METHOD_OVER_EXPECTED="${AI_METHOD_OVER_EXPECTED:-$RDIR/over-expected}"
slots_wait validate "$(issue_from_branch "$(current_branch)")" "$ROOT" || exit $?
slots_load_report | grep '^warn:' || true
t0="$(now_epoch)"
progress_start validate.sh "$(issue_from_branch "$(current_branch)")"
started=1
set +e
run_validate 2>&1 | tee "$log"
rc=${PIPESTATUS[0]}
if [ "$tests" = 1 ]; then
  sleep 1   # a test that exited just now may still be detaching its children
  if orphan="$(orphan_sweep)"; then
    { printf '%s\n' "$orphan"; echo "FAIL: the suite left orphan processes (listed and stopped above); the test that starts a process stops it"; } 2>&1 | tee -a "$log"
    rc=1
  fi
fi
set -e
history_add validate "$(slots_repo_name)" "$(issue_from_branch "$(current_branch)")" "$SLOT_WAIT" "$(( $(now_epoch) - t0 ))"
warn_over_expected "validate.sh" "$(( $(now_epoch) - t0 ))" 240 || true
if [ -s "${AI_METHOD_OVER_EXPECTED:-}" ]; then
  echo "over-expected:"
  cat "$AI_METHOD_OVER_EXPECTED"
fi
# The local cache: a full green run on a clean tree is the result --prepare reuses.
if [ "$rc" = 0 ] && [ "$lint" = 1 ] && [ "$tests" = 1 ] && [ "$incremental" = 0 ]; then
  if git diff --quiet && git diff --cached --quiet; then
    trace_event phase_validate sha="$(git rev-parse HEAD)" secs="$(( $(now_epoch) - t0 ))"
  fi
fi
exit "$rc"
