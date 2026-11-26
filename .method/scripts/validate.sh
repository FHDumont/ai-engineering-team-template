#!/usr/bin/env bash
#: validate.sh: lint and tests of the project and of the method's scripts.
#:
#: Usage: validate.sh [--lint] [--tests] [--full]   (no option: both; tests affected in a phase)
#:
#: --lint: shellcheck on Bash scripts and a Python syntax check. Alone, during a
#:         phase, it looks only at the files changed against the merge-base with the
#:         main branch (AI_METHOD_LINT_BASE) and the untracked ones; the full
#:         validation stays in close-phase.sh --prepare and in the CI.
#: --tests: runs .method/scripts/tests/test_*.sh, .method/scripts/tests/test_*.py and
#:          .claude/hooks/tests/test_*.sh. When .github/validate-repo.sh exists,
#:          it runs after those tests and its exit code counts: that is where
#:          the repository puts its own checks, without editing this file.
#: --full: forces everything: the whole lint, never the incremental one, and every
#:         test. The CI (CI=true in the environment) and a run outside a phase are
#:         always full.
#:
#: Affected tests: in a phase (branch with issue-<n>, outside the CI) the tests run are
#: the ones the diff against the merge-base with AI_METHOD_LINT_BASE reaches, plus the
#: gate tests (file names with "gate") and test_pipefail.sh, which scans every script. The map is read from the tests themselves: a
#: test is affected when its text mentions a changed file; for a file in .method/scripts/lib,
#: also when it mentions a script that mentions the library. Docs and root .md
#: files the suite does not read (the rule of ci.yml) need no test. A changed file
#: that no test reaches means there is no map: everything runs. The output says
#: "tests: affected only (n of m)". A green partial run is recorded as phase_validate
#: with scope=affected; the merge still needs the Tests check, which runs everything.
#:
#: One run per worktree: a second validate.sh in the same worktree does not start
#: another; it waits for the one running and prints its result (same options).
#: Machine-wide: at most AI_METHOD_SLOTS_VALIDATE (default 2) run at once; the
#: others wait with "waiting for a validate slot" and who holds one, up to
#: AI_METHOD_WAIT_TIMEOUT_SECONDS (exit 4). Wait and duration go to
#: ~/.cache/ai-method/history.tsv (see machine-slots.sh --report). The limits are in
#: ~/.config/ai-method/machine-limits.env.
#:
#: At the end: the time of the lint and of the repository block, and the 5 slowest
#: tests. The repository block time also goes to the history as the validate-repo
#: measure. The full lint runs shellcheck in parallel too (AI_METHOD_TEST_JOBS files
#: at once, 1 = in series; the output keeps the order of the files).
#:
#: Tests run in parallel, each in its own temporary folder: AI_METHOD_TEST_JOBS at once
#: (default: CPUs divided by AI_METHOD_SLOTS_VALIDATE, at least 1; 1 = in series). The
#: report keeps the fixed order of the tests.
#:
#: Progress (for the owner and the dashboard, never printed): each step goes to
#: ~/.cache/ai-method/progress/<repo>-<issue>.jsonl (.method/scripts/progress.sh reads it).
#:
#: Orphans: every test runs with TMPDIR inside a folder of this run. At the end, and on
#: INT/TERM, a process still alive there (cwd or command line in that folder) is stopped
#: and listed ("orphan process <pid>") and the run exits 1: a process left by the suite
#: is a defect (issue FHDumont/ai-engineering-team-template#66).
#:
#: Never runs from inside its own tests: it sets PROCESS_VALIDATE_RUNNING=1 in the
#: environment and, called again with the mark, exits 3 at once.
#: A full green run (lint and tests) on a clean tree records phase_validate on HEAD
#: so close-phase.sh --prepare can reuse it.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=.method/scripts/lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=.method/scripts/lib/slots.sh
source "$HERE/lib/slots.sh"
# shellcheck source=.method/scripts/lib/progress.sh
source "$HERE/lib/progress.sh"
# shellcheck source=.method/scripts/lib/procs.sh
source "$HERE/lib/procs.sh"
ROOT="$(cd "$HERE/../.." && pwd)"
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
  die "validate.sh is already running: a test called it again (PROCESS_VALIDATE_RUNNING is set); stub .method/scripts/validate.sh in the temporary repo of the test" 3
fi
export PROCESS_VALIDATE_RUNNING=1

# Files with a bash shebang among the candidates on stdin, including hooks without an extension.
bash_files() {
  while read -r f; do
    [ -f "$f" ] && head -1 "$f" | stdin_grep -qE '^#!.*\bbash' && echo "$f"; true
  done
}

# Partial test run: in a phase, outside the CI, without --full.
partial=0
[ "$tests" = 1 ] && [ "$full" = 0 ] && [ -z "${CI:-}" ] && [ -n "$(issue_from_branch "$(current_branch)")" ] && partial=1

# True for a path the suite does not read (the inert set of ci.yml).
inert_path() {
  case "$1" in
    docs/process-design.md|AGENTS.md|CLAUDE.md) return 1 ;;
    docs/*) return 0 ;;
    */*) return 1 ;;
    *.md) return 0 ;;
  esac
  return 1
}

# The tests the diff against the base reaches, one per line, from the tests on the
# command line. Exit 1: a changed file no test reaches (no map), run all.
select_tests() {
  local base files f names r hit sel names_file="$RDIR/names"
  base="$(git merge-base HEAD "$AI_METHOD_LINT_BASE" 2>/dev/null || true)"
  [ -n "$base" ] || return 1
  files="$({ git diff --name-only --no-renames -z "$base" | tr '\0' '\n'; git ls-files -z -o --exclude-standard | tr '\0' '\n'; } | sort -u)"
  # Gate tests and tests that scan every production script (test_pipefail.sh) always run: no changed file names them.
  sel="$(printf '%s\n' "$@" | grep -E 'gate|test_pipefail' || true)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    inert_path "$f" && continue
    case "$f" in
      .method/scripts/tests/test_*|.claude/hooks/tests/test_*)
        [ ! -e "$f" ] || sel="$sel"$'\n'"$f"
        continue ;;
    esac
    # The tests read the files they exercise; a shared library (.method/scripts/lib) is
    # exercised through the scripts that load it, so their tests count too.
    names="$(basename "$f")"
    case "$f" in
      .method/scripts/lib/*)
        for r in $(git grep -lF -e "$names" -- .method/scripts .claude .github ':(exclude).method/scripts/tests' ':(exclude).claude/hooks/tests' 2>/dev/null || true); do
          names="$names $(basename "$r")"
        done ;;
    esac
    # Substring matches (foo.sh in xfoo.sh) only select more tests: safe.
    printf '%s\n' $names >"$names_file"
    hit="$(grep -lFf "$names_file" "$@" 2>/dev/null || true)"
    [ -n "$hit" ] || return 1
    sel="$sel"$'\n'"$hit"
  done <<<"$files"
  printf '%s\n' "$sel" | grep . | sort -u || true
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

# Shellcheck on the files (one per line), up to AI_METHOD_TEST_JOBS at once (1 = in
# series). Each file's output goes to its own file and is printed in the list order;
# fails when any file does.
shellcheck_parallel() {
  local files="$1" f n rc=0 d="$RDIR/lint"
  mkdir -p "$d"
  # shellcheck disable=SC2016  # the runner is a script for the child shell
  printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 -n1 -P "$AI_METHOD_TEST_JOBS" bash -c \
    'n="$(printf %s "$2" | tr / _)"; shellcheck -x -S warning "$2" >"$1/$n.out" 2>&1; echo $? >"$1/$n.rc"' _ "$d" || true
  while IFS= read -r f; do
    n="$(printf %s "$f" | tr / _)"
    [ "$(cat "$d/$n.rc" 2>/dev/null || echo 1)" = 0 ] || rc=1
    cat "$d/$n.out" 2>/dev/null || true
  done <<<"$files"
  return "$rc"
}

run_validate() {
  local fail=0 files pyfiles passed failed t out cands scope=""
  if [ "$lint" = 1 ]; then
    local lint_t0
    lint_t0="$(now_epoch)"
    require_cmd shellcheck python3
    progress_step "shellcheck and python syntax"
    cands="$(lint_candidates)"
    [ "$incremental" = 0 ] || scope=", incremental"
    files="$(printf '%s\n' "$cands" | bash_files)"
    if [ -z "$files" ]; then
      echo "ok: shellcheck (0 files$scope)"
    else
      if shellcheck_parallel "$files"; then
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
    echo "time: lint $(( $(now_epoch) - lint_t0 )) s"
  fi

  if [ "$tests" = 1 ]; then
    local list=() n_total rdir pid n_seen=0 line runner alive
    for t in .method/scripts/tests/test_*.sh .claude/hooks/tests/test_*.sh .method/scripts/tests/test_*.py; do
      [ -e "$t" ] && list+=("$t")
    done
    n_total=${#list[@]}
    echo full >"$RDIR/scope"
    if [ "$partial" = 1 ] && [ "$n_total" -gt 0 ]; then
      if sel="$(select_tests "${list[@]}")"; then
        local all_n=$n_total
        list=()
        while IFS= read -r t; do [ -z "$t" ] || list+=("$t"); done <<<"$sel"
        n_total=${#list[@]}
        echo affected >"$RDIR/scope"
        echo "tests: affected only ($n_total of $all_n): the diff and the gate tests; --full runs all"
      else
        echo "tests: a changed file has no test map: running all"
      fi
    fi
    passed=0 failed=0
    # bash 3.2 with set -u rejects "${list[@]}" when the list is empty (FHDumont/ai-engineering-team-template#110).
    # Skip the runner entirely; there is no test file to hand to xargs.
    if [ "$n_total" -gt 0 ]; then
    # Each test runs in the background, up to AI_METHOD_TEST_JOBS at once, with its own
    # temporary folder (tests/lib.sh makes one per run); output and exit code go to
    # files and are reported afterwards, in the fixed order of the list. Each finished
    # test appends its name to done.log, which feeds the progress.
    rdir="$RDIR"
    : >"$rdir/done.log"
    # shellcheck disable=SC2016  # the runner is a script for the child shell
    runner='n="$(printf %s "$2" | tr / _)"; t0=$(date +%s)
      case "$2" in *.py) python3 "$2" >"$1/$n.out" 2>&1 ;; *) bash "$2" >"$1/$n.out" 2>&1 ;; esac
      echo $? >"$1/$n.rc"; echo $(( $(date +%s) - t0 )) >"$1/$n.secs"; basename "$2" >>"$1/done.log"'
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
    if [ "$n_total" -gt 0 ]; then
      echo "slowest tests:"
      for t in "${list[@]}"; do
        printf '%s %s\n' "$(cat "$rdir/$(printf %s "$t" | tr / _).secs" 2>/dev/null || echo 0)" "$t"
      done | sort -rn -k1,1 | head -5 | while read -r secs name; do echo "  $secs s  $name"; done
    fi
    if [ -f .github/validate-repo.sh ]; then
      local repo_t0
      echo "repo: .github/validate-repo.sh"
      repo_t0="$(now_epoch)"
      bash .github/validate-repo.sh || fail=1
      echo $(( $(now_epoch) - repo_t0 )) >"$RDIR/t_repo"
      echo "time: repository block $(cat "$RDIR/t_repo") s"
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
# The repository block is its own measure, so the repo is charged for its part only.
if [ -s "$RDIR/t_repo" ]; then
  history_add validate-repo "$(slots_repo_name)" "$(issue_from_branch "$(current_branch)")" 0 "$(cat "$RDIR/t_repo")"
fi
warn_over_expected "validate.sh" "$(( $(now_epoch) - t0 ))" 240 || true
if [ -s "${AI_METHOD_OVER_EXPECTED:-}" ]; then
  echo "over-expected:"
  cat "$AI_METHOD_OVER_EXPECTED"
fi
# The local cache: a full green run on a clean tree is the result --prepare reuses.
if [ "$rc" = 0 ] && [ "$lint" = 1 ] && [ "$tests" = 1 ] && [ "$incremental" = 0 ]; then
  if git diff --quiet && git diff --cached --quiet; then
    trace_event phase_validate sha="$(git rev-parse HEAD)" secs="$(( $(now_epoch) - t0 ))" scope="$(cat "$RDIR/scope" 2>/dev/null || echo full)"
  fi
fi
exit "$rc"
