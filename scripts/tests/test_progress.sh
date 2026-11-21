#!/usr/bin/env bash
# Tests of the progress of the long scripts: lib/progress.sh (format, append only, prune)
# and the calls of validate.sh. phase-start.sh and new-phase.sh are in test_phase_start.sh.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

dir="$AI_METHOD_CACHE/progress"
repo="$(make_repo)"
name="$(basename "$repo")"

# The library: start, step with and without a count, end; one JSON line each, append only.
run_lib() { # run_lib <issue> <exit status>
  (cd "$repo" && bash -c 'source "$1/lib/progress.sh"; progress_start demo.sh "$2"; progress_step "first step";
    progress_step "tests a.sh" 3 49; progress_end "$3"' _ "$SCRIPTS" "$1" "$2")
}
run_lib 40 0
f="$dir/$name-40.jsonl"
assert_eq "4" "$(wc -l <"$f" | tr -d ' ')" "one line per event"
assert_eq "start step step end" "$(jq -r .state "$f" | paste -sd' ' -)" "states in order"
assert_eq "demo.sh" "$(sed -n 3p "$f" | jq -r .script)" "script field"
assert_eq "$name" "$(sed -n 3p "$f" | jq -r .repo)" "repo field"
assert_eq "40" "$(sed -n 3p "$f" | jq -r .issue)" "issue is a number"
assert_eq "number" "$(sed -n 3p "$f" | jq -r '.pid | type')" "pid is a number"
assert_eq "tests a.sh 3 49" "$(sed -n 3p "$f" | jq -r '"\(.step) \(.done) \(.total)"')" "step with count"
assert_eq "null null" "$(sed -n 2p "$f" | jq -r '"\(.done) \(.total)"')" "step without count has null counts"
assert_eq "number" "$(sed -n 4p "$f" | jq -r '.elapsed_s | type')" "elapsed_s is a number"
assert_eq "true" "$(sed -n 1p "$f" | jq -r '.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$")')" "ts is UTC ISO"
for k in ts repo issue script pid step "done" total elapsed_s state; do
  assert_eq "true" "$(sed -n 2p "$f" | jq --arg k "$k" 'has($k)')" "field $k present"
done

# A second run appends: the first lines stay as they were.
first="$(sed -n 1p "$f")"
run_lib 40 0
assert_eq "8" "$(wc -l <"$f" | tr -d ' ')" "a second run appends"
assert_eq "$first" "$(sed -n 1p "$f")" "the first line is not rewritten"

# A failure ends with state fail; no phase writes to <repo>-main.jsonl with a null issue.
run_lib 41 3
assert_eq "fail" "$(jq -r .state "$dir/$name-41.jsonl" | tail -1)" "non-zero exit is state fail"
assert_eq "exit 3" "$(jq -r .step "$dir/$name-41.jsonl" | tail -1)" "fail records the status"
run_lib "" 0
assert_eq "null" "$(sed -n 1p "$dir/$name-main.jsonl" | jq -r .issue)" "no phase: issue null in the main file"

# Files older than 7 days go away at the next start; recent ones stay.
touch -t 202001010000 "$dir/old-1.jsonl"
touch "$dir/new-1.jsonl"
run_lib 42 0
assert_eq "no" "$([ -e "$dir/old-1.jsonl" ] && echo yes || echo no)" "a file older than 7 days is pruned"
assert_eq "yes" "$([ -e "$dir/new-1.jsonl" ] && echo yes || echo no)" "a recent file stays"
bash -c 'source "$1/lib/progress.sh"; progress_remove "$2" 40' _ "$SCRIPTS" "$name"
assert_eq "no" "$([ -e "$f" ] && echo yes || echo no)" "progress_remove deletes the file of a phase"

# Nothing recorded without a start, and an unwritable folder never fails the caller.
rm -rf "$dir"
bash -c 'source "$1/lib/progress.sh"; progress_step x; progress_end 0' _ "$SCRIPTS"
assert_eq "no" "$([ -e "$dir" ] && echo yes || echo no)" "a step with no start writes nothing"
mkdir -p "$TMP/ro"; : >"$TMP/ro/file"
assert_status 0 "an unwritable cache does not fail the caller" env AI_METHOD_CACHE="$TMP/ro/file" bash -c 'cd "$1" && source "$2/lib/progress.sh"; progress_start d.sh 1; progress_step x; progress_end 0' _ "$repo" "$SCRIPTS"

# validate.sh: lint and each test go to the progress file; the printed output has no progress.
vrepo="$(make_repo)"
vname="$(basename "$vrepo")"
mkdir -p "$vrepo/scripts/lib" "$vrepo/scripts/tests"
cp "$SCRIPTS/validate.sh" "$vrepo/scripts/validate.sh"
cp "$SCRIPTS/lib/common.sh" "$SCRIPTS/lib/slots.sh" "$SCRIPTS/lib/progress.sh" "$SCRIPTS/lib/machine-limits.env.example" "$vrepo/scripts/lib/"
printf '#!/usr/bin/env bash\nexit 0\n' >"$vrepo/scripts/tests/test_a.sh"
printf '#!/usr/bin/env bash\nexit 0\n' >"$vrepo/scripts/tests/test_b.sh"
git -C "$vrepo" checkout --quiet -b feat/issue-55-x
assert_status 0 "validate.sh --tests passes" env -u PROCESS_VALIDATE_RUNNING "$vrepo/scripts/validate.sh" --tests
assert_not_contains "$(last_output)" "progress" "validate.sh prints no progress"
assert_not_contains "$(last_output)" "jsonl" "validate.sh prints no progress path"
vf="$dir/$vname-55.jsonl"
assert_eq "start step step end" "$(jq -r .state "$vf" | paste -sd' ' -)" "validate.sh records start, two tests, end"
assert_eq "validate.sh" "$(sed -n 1p "$vf" | jq -r .script)" "validate.sh names itself"
assert_eq "tests test_a.sh 1 2" "$(sed -n 2p "$vf" | jq -r '"\(.step) \(.done) \(.total)"')" "first test with its count"
assert_eq "tests test_b.sh 2 2" "$(sed -n 3p "$vf" | jq -r '"\(.step) \(.done) \(.total)"')" "second test with its count"
printf '#!/usr/bin/env bash\nexit 1\n' >"$vrepo/scripts/tests/test_b.sh"
assert_status 1 "validate.sh --tests fails with a failing test" env -u PROCESS_VALIDATE_RUNNING "$vrepo/scripts/validate.sh" --tests
assert_eq "fail" "$(jq -r .state "$vf" | tail -1)" "a failed validate.sh ends with state fail"

finish
