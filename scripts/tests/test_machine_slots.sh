#!/usr/bin/env bash
# Tests of the machine-wide slots: queue, timeout, orphan slot, lock per worktree,
# incremental lint, load warning, history and report.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

SLOTS="$AI_METHOD_CACHE/slots"
mkdir -p "$SLOTS/validate" "$SLOTS/fase"

# The real validate.sh in a temporary repo whose whole suite is one probe test.
repo="$(make_repo)"
mkdir -p "$repo/scripts/lib" "$repo/scripts/tests"
cp "$SCRIPTS/validate.sh" "$SCRIPTS/machine-slots.sh" "$repo/scripts/"
cp "$SCRIPTS/lib/common.sh" "$SCRIPTS/lib/slots.sh" "$SCRIPTS/lib/progress.sh" "$SCRIPTS/lib/machine-limits.env.example" "$repo/scripts/lib/"
RUNS="$TMP/runs"
cat >"$repo/scripts/tests/test_probe.sh" <<P
#!/usr/bin/env bash
echo run >>"$RUNS"
sleep "\${PROBE_SLEEP:-0}"
P
V="$repo/scripts/validate.sh"
slot_info() { # slot_info <class> <n> <pid> <worktree> [issue]
  mkdir -p "$SLOTS/$1/$2"
  printf 'other-repo\t%s\t%s\t%s\t%s\t0\n' "${5:-99}" "$3" "$(( $(date +%s) - 5 ))" "$4" >"$SLOTS/$1/$2/info"
}
validate() { env -u PROCESS_VALIDATE_RUNNING "$@"; }

# Limits file: created from the .example on the first run, and the environment wins.
conf="$AI_METHOD_CONFIG/machine-limits.env"
assert_eq "no" "$([ -f "$conf" ] && echo yes || echo no)" "no limits file before the first run"
assert_status 0 "machine-slots.sh --status runs" "$repo/scripts/machine-slots.sh" --status
assert_eq "yes" "$([ -f "$conf" ] && echo yes || echo no)" "the limits file is created on the first run"
assert_contains "$(cat "$conf")" "AI_METHOD_SLOTS_FASE=3" "the file carries the documented defaults"
for name in $(sed -n 's/^\(AI_METHOD_[A-Z0-9_]*\)=.*/\1/p' "$SCRIPTS/lib/machine-limits.env.example"); do
  assert_eq "1" "$(grep -c "^# ${name#AI_METHOD_} (default" "$SCRIPTS/lib/machine-limits.env.example")" "$name is documented with its default in the .example"
done
assert_contains "$(last_output)" "validate: 0/20 in use" "the environment limit wins over the file"

# Queue: with the only slot held by a live process, validate.sh waits and times out (exit 4).
sleep 60 & holder=$!
slot_info validate 1 "$holder" "$repo"
assert_status 4 "validate.sh waits for a slot and gives up at the timeout" \
  validate env AI_METHOD_SLOTS_VALIDATE=1 AI_METHOD_WAIT_TIMEOUT_SECONDS=2 "$V" --tests
assert_contains "$(last_output)" "waiting for a validate slot" "the queue says it is waiting"
assert_contains "$(last_output)" "other-repo #99" "the queue says who holds the slot"
assert_contains "$(last_output)" "timeout" "the timeout is named"
assert_eq "" "$(cat "$RUNS" 2>/dev/null || true)" "no test ran while waiting"

# Queue: the slot frees while waiting and the run goes on.
( sleep 2; kill "$holder" 2>/dev/null ) &
assert_status 0 "validate.sh runs once the slot is free" \
  validate env AI_METHOD_SLOTS_VALIDATE=1 AI_METHOD_WAIT_TIMEOUT_SECONDS=20 "$V" --tests
assert_eq "1" "$(wc -l <"$RUNS" | tr -d ' ')" "the suite ran once after the wait"
wait 2>/dev/null || true
assert_eq "" "$(ls "$SLOTS/validate")" "the slot is freed at the end"

# Orphan slots: dead process, worktree that is gone.
slot_info validate 1 999999 "$repo"
assert_status 0 "a slot of a dead process is freed by itself" validate env AI_METHOD_SLOTS_VALIDATE=1 "$V" --tests
assert_not_contains "$(last_output)" "waiting for a validate slot" "no wait for the orphan slot"
sleep 60 & alive=$!
slot_info validate 1 "$alive" "$TMP/gone-worktree"
assert_status 0 "a slot of a worktree that no longer exists is freed by itself" validate env AI_METHOD_SLOTS_VALIDATE=1 "$V" --tests
kill "$alive" 2>/dev/null || true
wait "$alive" 2>/dev/null || true

# Phase slots: held while the worktree lives (the process of new-phase.sh is long gone),
# freed with a history line once it is gone.
mkdir -p "$TMP/wt-live"
slot_info fase 1 999999 "$TMP/wt-live" 11
slot_info fase 2 999999 "$TMP/wt-gone" 12
assert_status 0 "--check fase 1 passes with one free slot of 3" env AI_METHOD_SLOTS_FASE=3 "$repo/scripts/machine-slots.sh" --check fase 1
assert_eq "1" "$(ls "$SLOTS/fase" | wc -l | tr -d ' ')" "only the slot of the live worktree is left"
assert_status 75 "--check fase 3 exits 75 when two are not free" env AI_METHOD_SLOTS_FASE=3 "$repo/scripts/machine-slots.sh" --check fase 3
assert_contains "$(last_output)" "other-repo #11" "the refusal says who holds the slot"
assert_contains "$(cat "$AI_METHOD_CACHE/history.tsv")" "$(printf 'fase\tother-repo\t12\t')" "a phase slot freed by its worktree records its duration"

# One run per worktree: the second call waits for the first and prints its result.
: >"$RUNS"
rm -rf "$SLOTS/fase"; mkdir -p "$SLOTS/fase"
( PROBE_SLEEP=4 validate env AI_METHOD_SLOTS_VALIDATE=2 "$V" --tests >"$TMP/first.out" 2>&1; echo $? >"$TMP/first.rc" ) &
sleep 1.5
assert_status 0 "a second validate.sh in the same worktree waits and returns the result" validate env AI_METHOD_SLOTS_VALIDATE=2 "$V" --tests
assert_contains "$(last_output)" "already running in this worktree" "the second call says it waits"
assert_contains "$(last_output)" "tests: 1 passed, 0 failed" "the second call prints the result of the first"
wait
assert_eq "1" "$(wc -l <"$RUNS" | tr -d ' ')" "the suite ran once for the two calls"
assert_eq "0" "$(cat "$TMP/first.rc")" "the first call finished"
assert_eq "" "$(find "$AI_METHOD_CACHE/locks" -name '*.lock' -maxdepth 1)" "the lock is freed at the end"

# Incremental lint: only the files changed against main. A fake shellcheck (the machine
# may not have the real one) fails on any file with the word BAD and logs what it was given.
mkdir -p "$TMP/bin"
cat >"$TMP/bin/shellcheck" <<'F'
#!/usr/bin/env bash
for f in "$@"; do
  case "$f" in -*) continue ;; esac
  echo "checked $f" >>"${SC_LOG:-/dev/null}"
  if grep -q BAD "$f"; then echo "$f: BAD"; exit 1; fi
done
F
chmod +x "$TMP/bin/shellcheck"
export SC_LOG="$TMP/shellcheck.log" PATH="$TMP/bin:$PATH"
lrepo="$(make_repo)"
mkdir -p "$lrepo/scripts/lib"
cp "$SCRIPTS/validate.sh" "$lrepo/scripts/"
cp "$SCRIPTS/lib/common.sh" "$SCRIPTS/lib/slots.sh" "$SCRIPTS/lib/progress.sh" "$SCRIPTS/lib/machine-limits.env.example" "$lrepo/scripts/lib/"
printf '#!/usr/bin/env bash\necho BAD\n' >"$lrepo/old_bad.sh"
git -C "$lrepo" add scripts old_bad.sh
git -C "$lrepo" commit --quiet -m "chore: scripts"
git -C "$lrepo" checkout --quiet -b feat/issue-5-x
printf '#!/usr/bin/env bash\necho ok\n' >"$lrepo/new_good.sh"
printf '#!/usr/bin/env bash\necho BAD\n' >"$lrepo/new_bad.sh"
git -C "$lrepo" add new_good.sh new_bad.sh
git -C "$lrepo" commit --quiet -m "feat: new"
LV="$lrepo/scripts/validate.sh"
assert_status 1 "--lint fails on a changed script with a problem" validate env -u CI "$LV" --lint
assert_contains "$(last_output)" "new_bad.sh" "the changed script is reported"
assert_not_contains "$(cat "$SC_LOG")" "old_bad.sh" "the unchanged script is not linted"
git -C "$lrepo" rm -q -f new_bad.sh; git -C "$lrepo" commit --quiet -m "fix: drop"
assert_status 0 "--lint passes when only clean scripts changed" validate env -u CI "$LV" --lint
assert_contains "$(last_output)" "incremental" "the output says it was incremental"
assert_status 1 "--lint --full lints everything" validate env -u CI "$LV" --lint --full
assert_contains "$(last_output)" "old_bad.sh" "--full reaches the unchanged script"
assert_status 1 "--lint in the CI lints everything" validate env CI=true "$LV" --lint
assert_status 1 "no option lints everything" validate env -u CI "$LV" --lint --tests

# Load: warning only, never a block.
out="$(env AI_METHOD_FAKE_LOAD1=20 AI_METHOD_FAKE_FREE_MEM_MB=100 AI_METHOD_FAKE_SWAP_MB=9000 "$repo/scripts/machine-slots.sh" --status)"
assert_contains "$out" "warn: machine load is high (20)" "high load warns"
assert_contains "$out" "warn: free memory is low (100MB)" "low memory warns"
assert_contains "$out" "warn: swap in use is high (9000MB)" "high swap warns"
out="$(env AI_METHOD_FAKE_LOAD1=1 AI_METHOD_FAKE_FREE_MEM_MB=8000 AI_METHOD_FAKE_SWAP_MB=0 "$repo/scripts/machine-slots.sh" --status)"
assert_not_contains "$out" "warn:" "a quiet machine does not warn"
assert_status 0 "validate.sh runs under a heavy load" validate env AI_METHOD_FAKE_LOAD1=99 "$V" --tests
assert_contains "$(last_output)" "warn: machine load is high" "validate.sh warns about the load"

# History and report.
now="$(date +%s)"
H="$AI_METHOD_CACHE/history.tsv"
rm -f "$H"
printf 'ts\tclass\trepo\tissue\twait_s\tduration_s\n' >"$H"
for d in 10 20 30 40 100; do printf '%s\tvalidate\talpha\t1\t%s\t%s\n' "$now" "$((d / 10))" "$d" >>"$H"; done
printf '%s\tvalidate\tbeta\t2\t0\t7\n' "$now" >>"$H"
printf '%s\tvalidate\talpha\t1\t999\t999\n' "$((now - 30 * 86400))" >>"$H"
assert_status 0 "--report runs" "$repo/scripts/machine-slots.sh" --report
out="$(last_output)"
assert_contains "$out" "6 runs" "the report counts the runs of the last 7 days"
assert_contains "$out" "$(printf 'validate  alpha                 ')" "the report groups by repository"
alpha="$(echo "$out" | grep ' alpha ')"
assert_contains "$alpha" "30" "median duration of alpha is 30"
assert_contains "$alpha" "100" "p90 duration of alpha is 100"
assert_status 0 "--report --days 60 widens the window" "$repo/scripts/machine-slots.sh" --report --days 60
assert_contains "$(last_output)" "7 runs" "the older run joins in a wider window"
# Time targets: method default, own target and over-target (per repository).
me="$(basename "$repo")"
rm -f "$H"
printf 'ts\tclass\trepo\tissue\twait_s\tduration_s\n' >"$H"
printf '%s\tvalidate\t%s\t1\t0\t300\n%s\tfase\t%s\t1\t0\t600\n' "$now" "$me" "$now" "$me" >>"$H"
assert_status 0 "--report with the method default (no file)" "$repo/scripts/machine-slots.sh" --report
assert_contains "$(last_output)" "over-target: validate median 300 s above the target 240 s" "default target: validate over"
assert_not_contains "$(last_output)" "over-target: phase" "default target: phase within 45 min"
mkdir -p "$repo/.github"
printf 'validate\t400\ts\nphase\t5\tmin\n' >"$repo/.github/time-targets.tsv"
assert_status 0 "--report with the project target" "$repo/scripts/machine-slots.sh" --report
assert_not_contains "$(last_output)" "over-target: validate" "own target: validate within 400 s"
assert_contains "$(last_output)" "over-target: phase median 600 s above the target 5 min" "own target: phase over"
rm -f "$repo/.github/time-targets.tsv"
rm -f "$H"
assert_status 0 "validate.sh records wait and duration" validate "$V" --tests
assert_contains "$(cat "$H")" "$(printf 'validate\t')" "validate.sh wrote a history line"
assert_eq "2" "$(wc -l <"$H" | tr -d ' ')" "header plus one line"

finish
