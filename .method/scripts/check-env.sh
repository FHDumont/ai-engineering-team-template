#!/usr/bin/env bash
#: check-env.sh: pre-flight check of the environment before a phase starts.
#:
#: Usage: check-env.sh
#:
#: Checks: tools of the method (git, gh, jq, python3, shellcheck: a missing one
#: is named with the command that installs it), the declared dependencies of the
#: product (requirements*.txt and package.json files tracked in git: a missing
#: package or an absent node_modules is named with its folder). A Python package
#: the system python3 lacks is only a `warn:` (validate.sh may use its own venv);
#: an absent node_modules warns when CHECK_ENV_OPENING=1 (new-phase.sh sets it
#: while opening) and fails in the child session until the environment exists.
#: Nothing is ever installed. The message names the
#: lockfile manager (npm ci, pnpm install --frozen-lockfile, yarn install
#: --frozen-lockfile) and never suggests pip install into the global Python, nor
#: npm install when a lockfile exists. A missing tool of the method still blocks.
#: Also checks: branch other than main, git hooks installed (core.hooksPath=.githooks;
#: installs it if missing) and a bot secret provider (.method/scripts/lib/secret.sh; it
#: only checks, prints nothing and never triggers a password manager
#: authorization) when the phase spec cites bots. It never runs the test suite:
#: opening a phase relies on the green "CI" check of the base commit of main
#: (phase-start.sh) and the suite runs at the end (close-phase.sh --prepare) and in
#: CI; running it at every opening costs minutes and machine load for no new fact.
#: Exits 1 on the first problem that blocks work.
#: On a phase branch (issue-<n> in its name) some docs/specs/*.md must cite #<n>.
#: Session pair: in a Claude session (CLAUDE_CODE_SESSION_ID) of a phase branch it
#: reads the real model and effort of the session and compares them with the pair
#: the spec asks ("modelo: ... · esforço: ..."). Each one must be the one of the
#: spec or the one of the session that opened the phase; otherwise it exits 1
#: before any step, records phase_pair_mismatch and no phase_session (the merge
#: gate stays closed). The phase_session event carries model, effort,
#: requested_model and requested_effort. It then prints, per step pair of the
#: spec, whether the step runs in this session (same pair) or in a subagent.
#: "Spec cites bots": some docs/specs/*.md mentions the branch's issue (#N) and, in its
#: general header or in the section of that phase, has "ask-bot", a "Bots" section/line,
#: or a bot slug from .github/bots.tsv as @slug. A name in backticks is not a citation.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# Logical root: "$HERE/../.." would be .method/scripts.
ROOT="$(cd "$HERE/../.." && pwd)"
# shellcheck source=.method/scripts/lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=.method/scripts/lib/secret.sh
source "$HERE/lib/secret.sh"

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    *) die "unknown option: $1 (see --help)" 2 ;;
  esac
done

require_cmd git gh jq python3
command -v shellcheck >/dev/null 2>&1 ||
  die "missing tool of the method: shellcheck (install: brew install shellcheck, or apt-get install shellcheck)"
echo "ok: tools of the method"

# Declared dependencies of the product, read without running anything of it.
# Opening (CHECK_ENV_OPENING=1) warns and installs nothing. The child session still fails.
missing_dep() { # missing_dep <detail>
  if [ "${CHECK_ENV_OPENING:-}" = 1 ]; then
    echo "warn: missing dependency: $1"
    return 0
  fi
  die "missing dependency: $1"
}
# Nearest lockfile from <dir> up to the repo root: pnpm, yarn, then npm.
# The command never writes a lockfile (npm ci, or a frozen install).
node_install_hint() { # node_install_hint <relative dir> <repo top>
  local rel="$1" top="$2" d="" cmd=""
  if [ "$rel" = . ]; then d="$top"; else d="$top/$rel"; fi
  while :; do
    if [ -f "$d/pnpm-lock.yaml" ]; then cmd="pnpm install --frozen-lockfile"; break; fi
    if [ -f "$d/yarn.lock" ]; then cmd="yarn install --frozen-lockfile"; break; fi
    if [ -f "$d/package-lock.json" ] || [ -f "$d/npm-shrinkwrap.json" ]; then cmd="npm ci"; break; fi
    [ "$d" = "$top" ] && break
    d="$(dirname "$d")"
  done
  if [ -z "$cmd" ]; then
    cmd="npm ci"
    if [ "$rel" = . ]; then d="$top"; else d="$top/$rel"; fi
  fi
  if [ "$d" = "$top" ]; then
    printf '%s' "$cmd"
  else
    printf 'cd %s && %s' "${d#"$top"/}" "$cmd"
  fi
}
check_declared_deps() {
  local f dir missing top names hint warned=0
  top="$(git rev-parse --show-toplevel)"
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    dir="$(dirname "$f")"
    missing="$(python3 -I - "$f" <<'PY'
import re, sys
from importlib import metadata
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.split("#", 1)[0].strip()
    if not line or line.startswith("-"):
        continue
    name = re.split(r"[<>=!~;\[ ]", line, maxsplit=1)[0]
    if not name:
        continue
    try:
        metadata.version(name)
    except metadata.PackageNotFoundError:
        print(name)
PY
)"
    if [ -n "$missing" ]; then
      names="$(echo "$missing" | paste -sd' ' -)"
      # Only a warning: validate.sh may run the tests in a throwaway venv, so the system
      # python3 lacking the package is not a block. Nothing is installed.
      echo "warn: missing dependency: $names (folder $dir): declared in $f"
      warned=1
    fi
  done <<<"$(git ls-files 'requirements*.txt' '*/requirements*.txt')"
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    dir="$(dirname "$f")"
    jq -e '(.dependencies // {}) + (.devDependencies // {}) | length > 0' "$f" >/dev/null 2>&1 || continue
    if [ ! -d "$dir/node_modules" ]; then
      hint="$(node_install_hint "$dir" "$top")"
      missing_dep "node_modules (folder $dir): $hint"
      warned=1
    fi
  done <<<"$(git ls-files package.json '*/package.json')"
  [ "$warned" = 0 ] || return 0
  echo "ok: declared dependencies"
}
check_declared_deps

branch="$(current_branch)"
[ -n "$branch" ] || die "detached HEAD: switch to a phase branch"
if is_main_branch "$branch"; then
  die "on $branch: phases never run on main (use .method/scripts/phase-start.sh)"
fi
echo "ok: branch $branch"
# A phase branch only works with its spec in git (phase-start.sh commits it).
phase_issue="$(issue_from_branch "$branch")"
if [ -n "$phase_issue" ]; then
  [ -n "$(specs_citing "$phase_issue" "$ROOT")" ] ||
    die "no spec in docs/specs cites #$phase_issue: the phase opens only through .method/scripts/phase-start.sh"
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
  # Outside a phase there is nothing to record: an empty issue used to mark the
  # session as a phase session and deploy.sh then refused it forever.
  if [ -z "$phase_issue" ]; then
    echo "warn: no phase issue or no session id: session pair not checked"
    return 0
  fi
  if [ -z "${CLAUDE_CODE_SESSION_ID:-}" ]; then
    trace_event phase_session
    echo "warn: no phase issue or no session id: session pair not checked"
    return 0
  fi
  # shellcheck disable=SC2046  # spec paths have no space
  asked="$(spec_pairs "$phase_issue" $(specs_citing "$phase_issue" "$ROOT" | sed "s#^#$ROOT/#"))" ||
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
# The session that opened the phase is not the one that works on it: no phase_session for it,
# including the check new-phase.sh runs while opening (CHECK_ENV_OPENING=1).
if [ "${CHECK_ENV_OPENING:-}" != 1 ] && [ "$(phase_opener_state "$phase_issue" "${CLAUDE_CODE_SESSION_ID:-}")" != opener ]; then
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
  local issue spec slugs text
  issue="$(issue_from_branch "$branch")"
  [ -n "$issue" ] || return 1
  slugs="$(bot_slugs | paste -sd'|' -)"
  for spec in "$ROOT"/docs/specs/*.md; do
    [ -f "$spec" ] || continue
    grep -q -E "#$issue([^0-9]|$)" "$spec" || continue
    # Only the general header (before the first phase section) and this phase's section count.
    text="$(awk -v n="$issue" '
      /^## Fase #[0-9]+/ { sec = ($0 ~ "^## Fase #" n "([^0-9]|$)"); seen = 1; next }
      !seen || sec { print }' "$spec")"
    # Explicit only: ask-bot, a Bots section or line, or @slug. A backtick name is not a citation.
    if printf '%s\n' "$text" | stdin_grep -q -E "ask-bot([^/]|$)|^#+ .*Bots|\*\*Bots|(^|[^[:alnum:]])Bots([^[:alnum:]]|$)|(^|[^A-Za-z0-9_])@($slugs)([^A-Za-z0-9_-]|$)"; then return 0; fi
  done
  return 1
}
if spec_cites_bots; then
  # Any bot webhook variable counts as an environment provider.
  env_names="$(bot_slugs | while read -r slug; do
    bot_webhook_var "$slug" url; bot_webhook_var "$slug" secret
  done)"
  # shellcheck disable=SC2086
  if secret_ready $env_names; then
    echo "ok: bot secret provider configured (the spec cites bots)"
  else
    die "no bot secret provider configured (the spec cites bots)"
  fi
fi
