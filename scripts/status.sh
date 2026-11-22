#!/usr/bin/env bash
#: status.sh: print the status block (in Portuguese) that ends every stop.
#:
#: Usage: status.sh --state trabalhando|esperando|pronto [--need "exact action"] \
#:          [--next "next step"] [--issue N] [--offline]
#:
#: pronto runs scripts/end-check.sh (of the phase, with an issue; of the group,
#: without one) and exits 1 when it fails: the state is then trabalhando or
#: esperando. pronto with --need exits 1: an owner action pending is esperando.
#:
#: A phase session (with an issue) records phase_status in the trace. The main
#: session (on main, no issue) prints, before the block, each open phase
#: (.worktrees/issue-<n>) as "#n — title — state", from the last phase_status of
#: the phase, and puts in "Você precisa" the pending action of each phase that is
#: in "esperando você". Each line ends with the real pair of the child session
#: ("modelo/esforço: sonnet/medium", from the phase_session the check-env.sh recorded);
#: with no phase_session yet, the pair the spec asks, marked "(pedido)".
#:
#: Without --issue, the number comes from the branch name (...issue-12...). The
#: end mode (end:lab-test / end:auto-close) is read from the issue and used as the
#: next step when none is given. On main it warns only when code edits are
#: pending (outside docs/specs/ and .process/): planning and post-close do not warn.
#: --offline does not call GitHub.
#: When a long script of the phase is running (scripts/progress.sh), the current step
#: goes at the end of the state ("trabalhando — validate.sh: tests 23/49 ..., 3m10s")
#: and of the phase line on main: one line, read from the progress files, never the log.
set -euo pipefail
trap "" PIPE
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"

state="" need="" next="" issue="" offline=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --state) state="$2"; shift 2 ;;
    --need) need="$2"; shift 2 ;;
    --next) next="$2"; shift 2 ;;
    --issue) issue="$2"; shift 2 ;;
    --offline) offline=1; shift ;;
    *) die "unknown option: $1 (see --help)" 2 ;;
  esac
done
case "$state" in
  trabalhando|pronto) ;;
  esperando) state="esperando você" ;;
  "esperando você") ;;
  *) die "--state must be trabalhando, esperando or pronto" 2 ;;
esac

branch="$(current_branch)"
[ -n "$issue" ] || issue="$(issue_from_branch "$branch")"

# pronto is never taken on trust: no owner action pending and a clean end, read back.
if [ "$state" = pronto ]; then
  [ -z "$need" ] || die "pronto takes no --need: with an owner action pending the state is esperando"
  check_args=()
  [ -z "$issue" ] || check_args+=(--issue "$issue")
  [ "$offline" = 0 ] || check_args+=(--offline)
  if ! check_out="$("$HERE/end-check.sh" ${check_args[@]+"${check_args[@]}"} 2>&1)"; then
    printf '%s\n' "$check_out" >&2
    die "pronto refused: the end is not clean (scripts/end-check.sh above); the state is trabalhando or esperando"
  fi
fi

# Current step of the long script of a phase (empty when none runs).
step_of() { # step_of <issue>
  local repo
  repo="$(basename "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)")")"
  "$HERE/progress.sh" --repo "$repo" --issue "$1" 2>/dev/null | sed -n '1p' | grep -v '^nothing running' | sed "s/^$repo #$1 //" || true
}

end=""
if [ -n "$issue" ] && [ "$offline" = 0 ] && command -v gh >/dev/null 2>&1; then
  end="$(gh issue view "$issue" --json labels --jq '[.labels[].name | select(startswith("end:"))][0] // ""' 2>/dev/null || true)"
fi
if [ -z "$next" ]; then
  case "$end" in
    end:lab-test) next="ao terminar, parar para o teste no lab (fase #$issue)" ;;
    end:auto-close) next="ao terminar, fechar a fase #$issue pelo portão" ;;
    *) next="seguir a spec${issue:+ da issue #$issue}" ;;
  esac
fi
# Main session: every open phase with its last recorded state; the pending
# action of a phase that waits for the owner goes to "Você precisa".
phases="" pending=""
if [ -z "$issue" ] && is_main_branch "$branch"; then
  main_root="$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
  trace="$(events_file "${main_root:-.}" 2>/dev/null || true)"
  TAB="$(printf '\t')"
  while read -r wt; do
    p="$(phase_of_path "$wt")"
    [ -n "$p" ] || continue
    n="${p%%"$TAB"*}" title="" p_state="aberta, sem sessão" p_need="" p_pair="" has_session=""
    if [ "$offline" = 0 ] && command -v gh >/dev/null 2>&1; then
      title="$(gh issue view "$n" --json title --jq .title 2>/dev/null || true)"
    fi
    [ -n "$title" ] || title="$(current_branch "$wt")"
    if [ -f "$trace" ]; then
      last="$(jq -rs --arg i "$n" '[.[] | select(type == "object" and .event == "phase_status" and (.issue | tostring) == $i)]
        | last | select(. != null) | "\(.state)\t\(.need // "")"' "$trace" 2>/dev/null || true)"
      if [ -n "$last" ]; then p_state="${last%%"$TAB"*}"; p_need="${last#*"$TAB"}"; fi
      p_pair="$(jq -rs --arg i "$n" '[.[] | select(type == "object" and .event == "phase_session" and (.issue | tostring) == $i)]
        | last | select(. != null) | "\(.model)/\(.effort)"' "$trace" 2>/dev/null || true)"
      [ -z "$p_pair" ] || has_session=1
    fi
    if [ -z "$has_session" ]; then
      [ "$p_state" != trabalhando ] || p_state="aberta, sem sessão"
      [ -n "$last" ] || p_state="aberta, sem sessão"
    else
      [ -n "$last" ] || p_state=trabalhando
      case "$p_need" in clique*) p_state=trabalhando; p_need="" ;; esac
    fi
    if [ -n "$p_pair" ]; then
      p_pair="modelo/esforço: $p_pair"
    else
      # shellcheck disable=SC2046  # spec paths have no space
      p_pair="$(spec_pairs "$n" $(specs_citing "$n" "$wt" | sed "s#^#$wt/#") 2>/dev/null | head -1 | tr ' ' '/')" || p_pair=""
      [ -z "$p_pair" ] || p_pair="modelo/esforço: $p_pair (pedido)"
    fi
    p_step="$(step_of "$n")"
    phases="$phases- #$n — $title — $p_state${p_step:+ ($p_step)}${p_pair:+ — $p_pair}"$'\n'
    if [ "$p_state" = "esperando você" ] && [ -n "$p_need" ]; then
      pending="${pending:+$pending; }Fase #$n — $title: $p_need"
    fi
  done <<<"$(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')"
  if [ -n "$pending" ]; then
    case "$need" in nada*|"") need="$pending" ;; *) need="$need; $pending" ;; esac
    [ "$state" != trabalhando ] || state="esperando você"
  fi
fi
# "esperando você" with no owner action is incoherent: it becomes "trabalhando".
if [ "$state" = "esperando você" ]; then
  case "$need" in
    nada*) state="trabalhando"; need="" ;;
    "") [ "$end" = "end:lab-test" ] || state="trabalhando" ;;
  esac
fi
# The close-phase shortcut only applies in "esperando você" in lab-test.
if [ "$end" = "end:lab-test" ] && [ "$state" = "esperando você" ]; then
  close_hint='dizer "fechar fase" aqui ou na sessão da fase (atalho /close-phase)'
  need="${need:+$need; }$close_hint"
fi
# A phase session leaves its state in the trace: the main session reads it.
if [ -n "$issue" ]; then
  trace_event phase_status "issue=$issue" "state=$state" "need=$(printf '%s' "$need" | tr '\n' ' ')"
fi
[ -n "$need" ] || need="nada"

# A single write: `| head -1` does not kill the script with SIGPIPE.
warn=""
if is_main_branch "$branch" &&
   git status --porcelain --untracked-files=all 2>/dev/null | cut -c4- | stdin_grep -qvE '^(docs/specs/|\.process/)'; then
  warn=$'\n\nAviso: há edição de código pendente na main; não se trabalha na main (use phase-start.sh).'
fi
[ -z "$phases" ] || phases="Fases abertas:"$'\n'"$phases"$'\n'
cur=""
[ -z "$issue" ] || cur="$(step_of "$issue")"
[ -z "$cur" ] || [ "$state" != trabalhando ] || state="$state — $cur"
printf '%s**Estado:** %s\n\n**Você precisa:** %s\n\n**Próximo passo:** %s%s\n' "$phases" "$state" "$need" "$next" "$warn" 2>/dev/null || true
