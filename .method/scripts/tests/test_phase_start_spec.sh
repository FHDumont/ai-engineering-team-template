#!/usr/bin/env bash
# Tests of the single phase entry, loose copy of a group spec, mentions in passing and group guards.
# shellcheck source=.method/scripts/tests/phase_start_common.sh
source "$(dirname "$0")/phase_start_common.sh"

# A group spec opened one phase at a time: the loose copy stays in the main
# checkout while another open issue of the spec has no phase, so the second phase,
# opened before the merge of the first, still finds its spec.
spec later.md 13
printf '\n## Fase #14 — y\n\n1. Etapa.\n' >>"$repo/docs/specs/later.md"
export FAKE_OPEN="13 14"
assert_status 0 "phase-start opens the first phase of a group spec alone" sh -c "cd '$repo' && .method/scripts/phase-start.sh 13 --no-check"
assert_contains "$(last_output)" "kept the loose copy of docs/specs/later.md" "says the loose copy stays for the phase not open yet"
assert_status 0 "the second phase of the spec opens before the merge of the first" sh -c "cd '$repo' && .method/scripts/phase-start.sh 14 --no-check"
assert_eq "docs/specs/later.md" "$(git -C "$repo/.worktrees/issue-14" show --name-only --format= HEAD)" "the second phase gets the spec on its branch"
assert_eq "" "$(git -C "$repo" status --porcelain)" "the loose copy leaves with the last phase of the spec"
unset FAKE_OPEN

# #194: a phase that was already opened (phase_opened in the trace) and merged, whose issue stays
# open by design, does not hold the loose copy: it has no worktree because it is done.
spec merged.md 31
printf '\n## Fase #32 — y\n\n1. Etapa. modelo: sonnet · esforço: low · motivo: leve\n' >>"$repo/docs/specs/merged.md"
printf '{"event":"phase_opened","issue":"31","session_id":"s0"}\n' >>"$PROCESS_EVENTS_FILE"
export FAKE_OPEN="31 32"
assert_status 0 "phase-start opens the second phase after the first was opened and merged" sh -c "cd '$repo' && .method/scripts/phase-start.sh 32 --no-check"
assert_not_contains "$(last_output)" "kept the loose copy" "an opened phase with an open issue does not keep the loose copy"
assert_eq "" "$(git -C "$repo" status --porcelain)" "the loose copy of the spec is gone"
unset FAKE_OPEN

# #50: an open issue only cited in the text of the spec (solved inside the phase, or
# roadmap) has no phase to open: it does not hold the loose copy.
spec cited.md 17
printf '# Spec (a #18 é roadmap)\n\n%s' "$(cat "$repo/docs/specs/cited.md")" >"$repo/docs/specs/cited.md.new" && mv "$repo/docs/specs/cited.md.new" "$repo/docs/specs/cited.md"
printf '\n## Notas\n\nA #18 fica para depois.\n' >>"$repo/docs/specs/cited.md"
export FAKE_OPEN="17 18"
assert_status 0 "phase-start opens the phase whose spec cites another open issue in the text" sh -c "cd '$repo' && .method/scripts/phase-start.sh 17 --no-check"
assert_not_contains "$(last_output)" "kept the loose copy" "an issue cited only in the text does not keep the loose copy"
assert_eq "" "$(git -C "$repo" status --porcelain)" "the loose copy is removed when no other phase section is open"
unset FAKE_OPEN

# A mention in passing is not a spec: an issue cited only inside the section of
# another phase does not pass the guard and inherits no pair.
spec passing.md 15
printf 'Depende da #16, que fica para depois.\n' >>"$repo/docs/specs/passing.md"
assert_status 1 "phase-start refuses an issue cited only in the section of another phase" sh -c "cd '$repo' && .method/scripts/phase-start.sh 16 --no-check"
assert_contains "$(last_output)" "no spec" "a mention in passing is not a spec"
assert_status 0 "the issue of the section still has its spec" sh -c "cd '$repo' && .method/scripts/new-phase.sh 15 --dry-run"
rm "$repo/docs/specs/passing.md"
# shellcheck source=.method/scripts/lib/common.sh
source "$SCRIPTS/lib/common.sh"
printf '# Spec (issues #1 e #2)\n\nIntro #9.\n\n## Fase #1 — a\n\nVer #3.\n\n## Notas\n\n#4\n' >"$TMP/cites.md"
assert_eq "1 2 4 9" "$(spec_open_issues "$TMP/cites.md" "1 2 3 4 9 33" | paste -sd' ' -)" "title, intro, heading and a section without issue cite; the section of another phase does not"
# The guards of a group run at the same time; the failure of one still refuses the whole group, saying why.
spec guards.md 19
assert_status 1 "a group with a closed issue is refused by the parallel guards" sh -c "cd '$repo' && .method/scripts/phase-start.sh 19 9 --no-check"
assert_contains "$(last_output)" "issue #9 is not open" "the guard of the closed issue says why"
rm "$repo/docs/specs/guards.md"
assert_status 2 "phase-start needs an issue number" sh -c "cd '$repo' && .method/scripts/phase-start.sh"
finish
