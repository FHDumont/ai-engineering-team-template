#!/usr/bin/env bash
# Tests of the single phase entry, check-env without a spec, phase_opened order and a group of phases.
# shellcheck source=scripts/tests/phase_start_common.sh
source "$(dirname "$0")/phase_start_common.sh"

# check-env: a phase branch without a spec for its issue is refused.
git -C "$repo" fetch --quiet origin
git -C "$repo" worktree add --quiet -b feat/issue-55-nospec "$repo/.worktrees/issue-55" origin/main
assert_status 1 "check-env refuses a phase branch without a spec" sh -c "cd '$repo/.worktrees/issue-55' && scripts/check-env.sh"
assert_contains "$(last_output)" "no spec" "check-env says the spec is missing"

# phase_opened is recorded before the worktree exists: it is there even when the worktree fails.
spec eleven.md 11
git -C "$repo" branch feat/issue-11-listar-issues
rc=0; (cd "$repo" && scripts/new-phase.sh 11 --no-check) >/dev/null 2>&1 || rc=$?
assert_eq 1 "$((rc != 0))" "worktree creation fails on an existing branch"
assert_eq "11" "$(events | jq -r 'select(.event == "phase_opened" and .issue == "11") | .issue')" "phase_opened comes before the worktree"
rm "$repo/docs/specs/eleven.md"

# A test issue follows the same path, and a spec of the group serves two phases.
spec group.md 10 "modelo: fable · esforço: medium · motivo: padrão"
printf '\n## Fase #12 — y\n\n1. Etapa.\n' >>"$repo/docs/specs/group.md"
assert_status 0 "phase-start opens a group in parallel, test issue included" sh -c "cd '$repo' && scripts/phase-start.sh 10 12 --no-check"
out="$(last_output)"
assert_contains "$out" "phase #10" "arguments for the test issue"
assert_contains "$out" "phase #12" "arguments for the second issue"
assert_contains "$out" "model: fable" "pair of the section"
assert_contains "$out" "Manager heartbeat of phases #10 #12:" "one heartbeat names every phase of the group"
assert_eq 1 "$(grep -c "create the manager heartbeat" <<<"$out")" "one heartbeat for the whole group"
assert_contains "$out" 'clique nos cartões "Fase #10" e "Fase #12" na sessão "TITULO"' "the stop sentence names every card of the group"
assert_eq 2 "$(cut -f1 "$repo/.worktrees/parallel-active.tsv" | grep -c .)" "registers the parallel phases"
for n in 10 12; do
  assert_eq "docs/specs/group.md" "$(git -C "$repo/.worktrees/issue-$n" show --name-only --format= HEAD)" "spec committed on the branch of #$n"
done
assert_eq "" "$(git -C "$repo" status --porcelain)" "main checkout clean after the group"

finish
