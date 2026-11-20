#!/usr/bin/env bash
#: check-env.sh: pre-flight check of the environment before a phase starts.
#:
#: Usage: check-env.sh [--no-tests]
#:
#: Checks: dependencies (git, gh, jq, python3; shellcheck is a warning), branch
#: other than main, git hooks installed (core.hooksPath=.githooks; installs it
#: if missing), a bot secret provider (scripts/lib/secret.sh; it only checks,
#: prints nothing and never triggers a password manager authorization) when the phase
#: spec cites bots, and tests passing
#: (scripts/validate.sh --tests). Exits 1 on the first problem that blocks work.
#: On a phase branch (issue-<n> in its name) some docs/specs/*.md must cite #<n>.
#: Session pair: in a Claude session (CLAUDE_CODE_SESSION_ID) of a phase branch it
#: reads the real model and effort of the session and compares them with the pair
#: the spec asks ("modelo: ... · esforço: ..."). Each one must be the one of the
#: spec or the one of the session that opened the phase; otherwise it exits 1
#: before any step, records phase_pair_mismatch and no phase_session (the merge
#: gate stays closed). The phase_session event carries model, effort,
#: requested_model and requested_effort. It then prints, per step pair of the
#: spec, whether the step runs in this session (same pair) or in a subagent.
#: "Spec cites bots": some docs/specs/*.md mentions the branch's issue (#N) and
#: has "ask-bot", a "Bots" section/line, or a bot slug from scripts/lib/bots.tsv
#: in backticks.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=scripts/lib/secret.sh
source "$HERE/lib/secret.sh"

run_tests=1
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --no-tests) run_tests=0; shift ;;
    *) die "unknown option: $1 (see --help)" 2 ;;
  esac
done

require_cmd git gh jq python3
command -v shellcheck >/dev/null 2>&1 || echo "warn: shellcheck missing (lint runs only in CI)"

branch="$(current_branch)"
[ -n "$branch" ] || die "detached HEAD: switch to a phase branch"
if is_main_branch "$branch"; then
  die "on $branch: phases never run on main (use scripts/phase-start.sh)"
fi
echo "ok: branch $branch"
# A phase branch only works with its spec in git (phase-start.sh commits it).
phase_issue="$(issue_from_branch "$branch")"
if [ -n "$phase_issue" ]; then
  [ -n "$(specs_citing "$phase_issue" "$HERE/..")" ] ||
    die "no spec in docs/specs cites #$phase_issue: the phase opens only through scripts/phase-start.sh"
  echo "ok: spec cites #$phase_issue"
fi
# Real pair of this session against the pair the spec asks. Each of the two, model
# and effort, has to be the one of the spec or the one of the session that opened the
# phase (the app opens the child session in that pair when the spec asks more than the
# opening session has). The phase_session event carries the real and the asked pair;
# on a divergence it is not recorded, so the merge gate stays closed.
same_or_opener() { # same_or_opener <real> <asked> <opener>
  [ "$1" = "$2" ] || { [ -n "$3" ] && [ "$1" = "$3" ]; }
}
check_session_pair() {
  local asked real opener="" trace line where
  if [ -z "$phase_issue" ] || [ -z "${CLAUDE_CODE_SESSION_ID:-}" ]; then
    trace_event phase_session
    echo "warn: no phase issue or no session id: session pair not checked"
    return 0
  fi
  # shellcheck disable=SC2046  # spec paths have no space
  asked="$(spec_pairs "$phase_issue" $(specs_citing "$phase_issue" "$HERE/.." | sed "s#^#$HERE/../#"))" ||
    die "the spec of #$phase_issue has no 'modelo: ... · esforço: ...' pair"
  real="$(session_pair)"
  case " $real " in
    *" unknown "*) die "cannot read the real pair of this session (got: $real): no step starts; the model comes from the session transcript and the effort from CLAUDE_EFFORT" ;;
  esac
  trace="$(events_file)" && [ -f "$trace" ] && opener="$(jq -Rrs --arg i "$phase_issue" '
    [split("\n")[] | fromjson? | select(.event == "phase_opened" and (.issue | tostring) == $i)]
    | last | if . == null or ([.model, .effort] | any(. == null or . == "" or . == "unknown")) then ""
      else "\(.model) \(.effort)" end' "$trace" 2>/dev/null || true)"
  line="$(printf '%s\n' "$asked" | head -1)"
  local rm="${real% *}" re="${real#* }" am="${line% *}" ae="${line#* }" om="${opener% *}" oe="${opener#* }"
  if ! same_or_opener "$(model_family "$rm")" "$(model_family "$am")" "$([ -z "$opener" ] || model_family "$om")" ||
     ! same_or_opener "$re" "$ae" "$([ -z "$opener" ] || echo "$oe")"; then
    trace_event phase_pair_mismatch "model=$rm" "effort=$re" "requested_model=$am" "requested_effort=$ae"
    die "this session runs at $rm $re and the spec of #$phase_issue asks $am $ae${opener:+ (the session that opened the phase runs at $om $oe)}: no step starts; tell the session that opened the phase: it sets the pair of this session (set_session_model, set_session_effort) and check-env.sh runs again"
  fi
  trace_event phase_session "model=$rm" "effort=$re" "requested_model=$am" "requested_effort=$ae"
  if [ "$(model_family "$rm") $re" = "$(model_family "$am") $ae" ]; then
    echo "ok: session pair $rm $re (the spec asks $am $ae)"
  else
    echo "ok: session pair $rm $re, the pair of the session that opened the phase (the spec asks $am $ae; the PR table records it)"
  fi
  # Where each step runs: by comparing its pair with the pair of this session.
  while read -r am ae; do
    where="another pair: run it in a subagent (Agent with model $am, effort $ae)"
    [ "$(model_family "$am") $ae" != "$(model_family "$rm") $re" ] || where="the session pair: run it in this session"
    echo "step pair $am $ae: $where"
  done <<<"$asked"
}
# Records the session that works on the phase (the child session runs this in the execute skill).
# The session that opened the phase is not the one that works on it: no phase_session for it.
if [ "$(phase_opener_state "$phase_issue" "${CLAUDE_CODE_SESSION_ID:-}")" != opener ]; then
  check_session_pair
fi

# Git hooks versioned in .githooks (they apply to any tool).
if [ "$(git config --get core.hooksPath || true)" != ".githooks" ]; then
  git config core.hooksPath .githooks
  echo "ok: installed git hooks (core.hooksPath=.githooks)"
else
  echo "ok: git hooks installed"
fi

# Does the phase spec cite bots? Then a secret provider must exist (the bot notice reads the webhook).
spec_cites_bots() {
  local issue spec slugs
  issue="$(issue_from_branch "$branch")"
  [ -n "$issue" ] || return 1
  slugs="$(cut -f1 "$HERE/lib/bots.tsv" | grep -v '^#' | paste -sd'|' -)"
  for spec in "$HERE"/../docs/specs/*.md; do
    [ -f "$spec" ] || continue
    grep -q -E "#$issue([^0-9]|$)" "$spec" || continue
    if grep -q -E "ask-bot|^#+ .*Bots|\*\*Bots|\`($slugs)\`" "$spec"; then return 0; fi
  done
  return 1
}
if spec_cites_bots; then
  # Any bot webhook variable counts as an environment provider.
  env_names="$(cut -f1 "$HERE/lib/bots.tsv" | grep -v '^#' | while read -r slug; do
    bot_webhook_var "$slug" url; bot_webhook_var "$slug" secret
  done)"
  # shellcheck disable=SC2086
  if secret_ready $env_names; then
    echo "ok: bot secret provider configured (the spec cites bots)"
  else
    die "no bot secret provider configured (the spec cites bots)"
  fi
fi

if [ "$run_tests" = 1 ]; then
  "$HERE/validate.sh" --tests >/dev/null || die "tests fail: run scripts/validate.sh --tests"
  echo "ok: tests pass"
fi
