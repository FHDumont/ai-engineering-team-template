#!/usr/bin/env bash
# Tests of status.sh: 3-line bold block in Portuguese and a warning on main only with a pending edit.
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

repo="$(make_repo)"
out="$(cd "$repo" && "$SCRIPTS/status.sh" --state pronto --offline --next "nada")"
assert_contains "$out" "**Estado:** pronto" "state line"
assert_contains "$out" "**Você precisa:** nada" "need line defaults to nada"
assert_not_contains "$out" "Aviso" "no main warning on a clean main (right after the close)"

# Planning: a new spec and the trace on main are not a code edit.
mkdir -p "$repo/docs/specs" "$repo/.process"
echo spec >"$repo/docs/specs/2026-01-18-g.md"; echo '{}' >"$repo/.process/events.jsonl"
out="$(cd "$repo" && "$SCRIPTS/status.sh" --state trabalhando --offline --next "nada")"
assert_not_contains "$out" "Aviso" "no main warning while planning a spec"

echo edit >>"$repo/README.md"
out="$(cd "$repo" && "$SCRIPTS/status.sh" --state trabalhando --offline --next "nada")"
assert_contains "$out" "não se trabalha na main" "warns on main with a pending code edit"
git -C "$repo" checkout --quiet -- README.md

# Finder droppings are not a code edit (#324), even when .gitignore does not cover them.
mkdir -p "$repo/docs"; : >"$repo/docs/.DS_Store"; : >"$repo/.DS_Store"
out="$(cd "$repo" && "$SCRIPTS/status.sh" --state trabalhando --offline --next "nada")"
assert_not_contains "$out" "não se trabalha na main" "an untracked .DS_Store is not a pending code edit"
echo code >"$repo/newfile.sh"
out="$(cd "$repo" && "$SCRIPTS/status.sh" --state trabalhando --offline --next "nada")"
assert_contains "$out" "não se trabalha na main" "an untracked code file next to .DS_Store still warns"
rm -f "$repo/newfile.sh" "$repo/.DS_Store"
# The method's own .worktrees/ is not a code edit (FHDumont/ai-engineering-team-template#335), even when .gitignore does not cover it.
mkdir -p "$repo/.worktrees/issue-1"; echo x >"$repo/.worktrees/issue-1/f.sh"; : >"$repo/.worktrees/parallel-active.tsv"
out="$(cd "$repo" && "$SCRIPTS/status.sh" --state trabalhando --offline --next "nada")"
assert_not_contains "$out" "não se trabalha na main" "untracked .worktrees/ is not a pending code edit"
echo code >"$repo/newfile.sh"
out="$(cd "$repo" && "$SCRIPTS/status.sh" --state trabalhando --offline --next "nada")"
assert_contains "$out" "não se trabalha na main" "an untracked code file next to .worktrees/ still warns"
rm -rf "$repo/.worktrees" "$repo/newfile.sh"
rm -rf "$repo/docs" "$repo/.process"

git -C "$repo" switch --quiet -c feat/issue-4-x
cat >"$TMP/handler.sh" <<'H'
case "$*" in
  *"--json comments"*) echo '{"comments":[]}' ;;
  "issue view"*) echo "end:lab-test" ;;
esac
H
use_fake_gh "$TMP/handler.sh"
out="$(cd "$repo" && "$SCRIPTS/status.sh" --state esperando --need "testar no lab o filtro")"
assert_eq "**Estado:** esperando você

**Você precisa:** testar no lab o filtro; dizer \"fechar fase\" aqui ou na sessão da fase (atalho /close-phase)

**Próximo passo:** ao terminar, parar para o teste no lab (fase #4)" "$out" "bold lines separated by blank lines, lab-test shortcut, no main warning"
out="$(cd "$repo" && "$SCRIPTS/status.sh" --state esperando)"
assert_contains "$out" '**Você precisa:** dizer "fechar fase" aqui' "lab-test default need is the shortcut"
# Lab-test stop with an unanswered note to the phase (#122): refused, exit 12.
cat >"$TMP/handler.sh" <<H
case "\$*" in
  *"--json comments"*) cat "$TMP/lab_comments.json" ;;
  "issue view"*) echo "end:lab-test" ;;
esac
H
use_fake_gh "$TMP/handler.sh"
jq -n --arg b $'**De:** gerenciadora · **Para:** fase #4 · **Pedido:** parar · **Responde a:** —\nsegure' \
  '{comments: [{body: $b, url: "https://github.com/owner/repo/issues/4#c9"}]}' >"$TMP/lab_comments.json"
assert_status 12 "lab-test stop is refused with an unanswered note" \
  sh -c "cd '$repo' && '$SCRIPTS/status.sh' --state esperando --need 'testar no lab o filtro'"
assert_contains "$(last_output)" "issues/4#c9" "names the unanswered note"
assert_not_contains "$(last_output)" "**Estado:**" "prints no status block when a note is pending"
cat >"$TMP/handler.sh" <<'H'
case "$*" in
  *"--json comments"*) echo '{"comments":[]}' ;;
  "issue view"*) echo "end:lab-test" ;;
esac
H
use_fake_gh "$TMP/handler.sh"
assert_not_contains "$out" '`' "no backtick or code fence"
# Reader that exits at once: the old code (one echo per line) died with SIGPIPE.
first="$(cd "$repo" && { "$SCRIPTS/status.sh" --state trabalhando --offline | true; echo "rc=${PIPESTATUS[0]}"; })"
assert_contains "$first" "rc=0" "no SIGPIPE failure with leitor que sai"
# Coherence: waiting with no action becomes working and has no shortcut; ready takes no shortcut.
out="$(cd "$repo" && "$SCRIPTS/status.sh" --state esperando --need "nada")"
assert_contains "$out" "**Estado:** trabalhando" "esperando + nada becomes trabalhando"
assert_not_contains "$out" "fechar fase" "no close shortcut while trabalhando"
out="$(cd "$repo" && "$SCRIPTS/status.sh" --state esperando --need "nada, só aguardando")"
assert_contains "$out" "**Estado:** trabalhando" "need starting with nada becomes trabalhando"
assert_status 2 "rejects unknown state" "$SCRIPTS/status.sh" --state x --offline

# pronto is checked, never taken on trust: on a phase branch that was not merged
# end-check.sh fails and the state is refused.
assert_status 1 "pronto is refused on a phase branch without a merge" sh -c "cd '$repo' && '$SCRIPTS/status.sh' --state pronto --offline"
assert_contains "$(last_output)" "fail: local branch of phase #4 still exists (feat/issue-4-x)" "shows what end-check.sh found"
assert_contains "$(last_output)" "pronto refused" "says pronto was refused"
assert_not_contains "$(last_output)" "**Estado:**" "prints no block for a refused pronto"
# pronto with --need is refused, even when the end is clean.
git -C "$repo" switch --quiet main
git -C "$repo" branch -D feat/issue-4-x >/dev/null
assert_status 1 "pronto with --need is refused" sh -c "cd '$repo' && '$SCRIPTS/status.sh' --state pronto --offline --need 'aprovar o merge'"
assert_contains "$(last_output)" "pronto takes no --need" "says why"
assert_status 0 "pronto passes with a clean end" sh -c "cd '$repo' && '$SCRIPTS/status.sh' --state pronto --offline --issue 4"
assert_contains "$(last_output)" "**Estado:** pronto" "prints the block when end-check.sh passes"
assert_not_contains "$(last_output)" "fechar fase" "no close shortcut on pronto"
# The main session runs the whole end check: an extra branch refuses pronto.
git -C "$repo" branch feat/issue-9-y
assert_status 1 "pronto is refused in the main session with an extra branch" sh -c "cd '$repo' && '$SCRIPTS/status.sh' --state pronto --offline"
assert_contains "$(last_output)" "fail: extra local branch (feat/issue-9-y)" "shows the leftover"
git -C "$repo" branch -D feat/issue-9-y >/dev/null

# Main session: each open phase as "#n — title — state", from the last status the
# phase session recorded, and the pending decision in "Você precisa".
cat >"$TMP/handler.sh" <<'H'
case "$*" in
  "issue view 5 --json title"*) echo "Fim coerente" ;;
  "issue view 6 --json title"*) echo "Modelo e esforço" ;;
  "issue view"*) echo "end:auto-close" ;;
esac
H
printf '.worktrees/\n' >"$repo/.gitignore"
git -C "$repo" add .gitignore; git -C "$repo" commit --quiet -m "chore: ignore"
git -C "$repo" worktree add --quiet -b fix/issue-5-a "$repo/.worktrees/issue-5" main
git -C "$repo" worktree add --quiet -b fix/issue-6-b "$repo/.worktrees/issue-6" main
(cd "$repo/.worktrees/issue-5" && "$SCRIPTS/status.sh" --state esperando --need "responder ao cartão do merge" >/dev/null)
(cd "$repo/.worktrees/issue-5" && "$SCRIPTS/status.sh" --state trabalhando >/dev/null)
(cd "$repo/.worktrees/issue-6" && "$SCRIPTS/status.sh" --state trabalhando >/dev/null)
out="$(cd "$repo" && "$SCRIPTS/status.sh" --state trabalhando --next "esperar as fases")"
assert_eq "Fases abertas:
- #5 — Fim coerente — aberta, sem sessão
- #6 — Modelo e esforço — aberta, sem sessão

**Estado:** trabalhando

**Você precisa:** nada

**Próximo passo:** esperar as fases" "$out" "the main session lists each open phase with its last state"
# The real pair of the child (phase_session of check-env.sh) is on the line of each phase;
# without it, the pair the spec asks, marked "pedido".
mkdir -p "$repo/.worktrees/issue-5/docs/specs"
printf '# Spec\n\n## Fase #5 — a\n\n1. Etapa. modelo: fable · esforço: high · motivo: x\n' >"$repo/.worktrees/issue-5/docs/specs/five.md"
printf '{"event":"phase_session","issue":"6","model":"sonnet","effort":"medium"}\n' >>"$PROCESS_EVENTS_FILE"
out="$(cd "$repo" && "$SCRIPTS/status.sh" --state trabalhando --next "esperar as fases")"
assert_contains "$out" "- #5 — Fim coerente — aberta, sem sessão — modelo/esforço: fable/high (pedido)" "no phase_session yet: open without a session, never trabalhando"
assert_contains "$out" "- #6 — Modelo e esforço — trabalhando — modelo/esforço: sonnet/medium" "a card that already became a session is trabalhando"
assert_not_contains "$out" "sonnet/medium (pedido)" "the real pair is not marked pedido"
(cd "$repo/.worktrees/issue-5" && "$SCRIPTS/status.sh" --state esperando --need "responder ao cartão do merge" >/dev/null)
out="$(cd "$repo" && "$SCRIPTS/status.sh" --state trabalhando --next "esperar as fases")"
assert_contains "$out" "- #5 — Fim coerente — esperando você" "the phase that waits for the owner shows its state"
assert_contains "$out" "**Você precisa:** Fase #5 — Fim coerente: responder ao cartão do merge" "the pending decision is in Você precisa"
assert_contains "$out" "**Estado:** esperando você" "a pending decision makes the main session wait for the owner"
out="$(cd "$repo" && "$SCRIPTS/status.sh" --state esperando --need "aprovar a spec" --next "x")"
assert_contains "$out" "**Você precisa:** aprovar a spec; Fase #5 — Fim coerente: responder ao cartão do merge" "the pending decision joins the need of the main session"
out="$(cd "$repo/.worktrees/issue-6" && "$SCRIPTS/status.sh" --state trabalhando)"
assert_not_contains "$out" "Fases abertas" "a phase session lists no phase"
printf '{"event":"phase_session","issue":"5","model":"sonnet","effort":"low"}\n' >>"$PROCESS_EVENTS_FILE"
(cd "$repo/.worktrees/issue-5" && "$SCRIPTS/status.sh" --state esperando --need 'clique no cartão "Fase #5"' >/dev/null)
out="$(cd "$repo" && "$SCRIPTS/status.sh" --state trabalhando --next "esperar as fases")"
assert_contains "$out" "- #5 — Fim coerente — trabalhando" "a card that already became a session is trabalhando"
assert_not_contains "$out" "clique no cartão" "does not wait for a card click after the session exists"
# Waiting for the manager is not an owner action, and the close hint is not doubled (#111).
out="$(cd "$repo/.worktrees/issue-6" && "$SCRIPTS/status.sh" --state gerenciadora --offline --next "seguir" --need "gerenciadora: responder a instalação")"
assert_contains "$out" "**Estado:** esperando a gerenciadora" "a wait for the manager is its own state"
assert_not_contains "$out" "fechar fase" "a manager wait does not invite the owner to close"
out="$(cd "$repo" && "$SCRIPTS/status.sh" --state trabalhando --offline --next "esperar as fases")"
assert_not_contains "$out" "instalação" "the main session does not ask the owner for a manager wait"
out="$(cd "$repo/.worktrees/issue-6" && "$SCRIPTS/status.sh" --state esperando --offline --next "parar" --need 'dizer "fechar fase" aqui')"
assert_eq "$(printf '%s\n' "$out" | grep -c 'fechar fase')" "1" "the close hint is not repeated when the need already says it"
cat >"$TMP/handler.sh" <<'H'
case "$*" in
  *"--json comments"*) echo '{"comments":[]}' ;;
  "issue view"*) echo "end:lab-test" ;;
esac
H
use_fake_gh "$TMP/handler.sh"
out="$(cd "$repo/.worktrees/issue-6" && "$SCRIPTS/status.sh" --state esperando --next "parar" --need 'dizer "fechar fase" aqui')"
assert_eq "$(printf '%s\n' "$out" | grep -c 'fechar fase')" "1" "lab-test does not append the hint when the need already says it"
# The session that opened the phase does not record phase_status from the worktree (#125).
mkdir -p "$repo/.process"
jq -cn '{event: "phase_opened", session_id: "mgr", issue: "6"}' >"$repo/.process/events.jsonl"
assert_status 2 "the opener does not record the phase from its worktree" \
  env CLAUDE_CODE_SESSION_ID=mgr bash -c "cd '$repo/.worktrees/issue-6' && '$SCRIPTS/status.sh' --state trabalhando --offline"
assert_contains "$(last_output)" "from the main checkout" "says where the opener runs status"
# #214: a reopened issue reads only what comes after its last phase_opened; a worktree
# under .worktrees/issue-<n> that is not on a phase branch is not a phase.
repo2="$(make_repo)"
printf '.worktrees/\n' >"$repo2/.gitignore"
git -C "$repo2" add .gitignore; git -C "$repo2" commit --quiet -m "chore: ignore"
git -C "$repo2" worktree add --quiet -b fix/issue-9-z "$repo2/.worktrees/issue-9" main
git -C "$repo2" worktree add --quiet --detach "$repo2/.worktrees/issue-10" main
cat >"$TMP/handler.sh" <<'H'
case "$*" in
  "issue view 9 --json title"*) echo "Reaberta" ;;
  "issue view"*) echo "end:auto-close" ;;
esac
H
use_fake_gh "$TMP/handler.sh"
EV="$TMP/ev214.jsonl"
{
  echo '{"event":"phase_opened","issue":"9"}'
  echo '{"event":"phase_session","issue":"9","model":"opus","effort":"high"}'
  echo '{"event":"phase_status","issue":"9","state":"esperando você","need":"X antigo"}'
  echo '{"event":"phase_closed","issue":"9"}'
  echo '{"event":"phase_opened","issue":"9"}'
} >"$EV"
out="$(cd "$repo2" && env PROCESS_EVENTS_FILE="$EV" "$SCRIPTS/status.sh" --state trabalhando --next "esperar")"
assert_not_contains "$out" "X antigo" "the need of the previous phase is not shown"
assert_not_contains "$out" "opus/high" "the pair of the previous session is not shown"
assert_contains "$out" "- #9 — Reaberta — aberta, sem sessão" "no session after the last open: aberta, sem sessão"
assert_not_contains "$out" "#10" "a worktree off a phase branch is not a phase"
assert_eq "1" "$(printf '%s\n' "$out" | grep -c '^- #')" "one phase per phase branch"
echo '{"event":"phase_session","issue":"9","model":"sonnet","effort":"low"}' >>"$EV"
out="$(cd "$repo2" && env PROCESS_EVENTS_FILE="$EV" "$SCRIPTS/status.sh" --state trabalhando --next "esperar")"
assert_contains "$out" "- #9 — Reaberta — trabalhando — modelo/esforço: sonnet/low" "the session after the last open counts"

finish
