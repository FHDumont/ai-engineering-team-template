#!/usr/bin/env bash
# Helpers for the Bash tests: asserts, temporary git repository and fake gh.
# Load with: source "$(dirname "$0")/lib.sh"
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$TESTS_DIR/../.." && pwd)"
# shellcheck disable=SC2034  # used by the tests that load this file
SCRIPTS="$REPO/scripts"
TMP="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/tmp.XXXXXXXX")" && pwd -P)"
# No test leaves a process alive (issue #66): whatever the test started in the
# background, or left with its folder as the cwd or in its command line, is stopped at
# the end, also when an assertion failed or the test got INT/TERM. A test that sets its
# own trap calls test_sweep in it. Under validate.sh (AI_METHOD_SWEEP_AT_END=1) the
# search by cwd (lsof, the dearest step, paid by every test) is left to the sweep that
# validate.sh runs once at the end over the folder of the whole run: what a test leaves
# there is still stopped, listed, and fails the run.
# shellcheck source=scripts/lib/procs.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/procs.sh"
test_sweep() {
  local p own="" left
  left="$( { proc_descendants "$$"; [ -n "${AI_METHOD_SWEEP_AT_END:-}" ] || procs_in_dir "$TMP"; pgrep -f "$TMP" 2>/dev/null || true; } | sort -un)"
  [ -n "$left" ] || return 0
  own="$(proc_chain "$$" | tr '\n' ' ')"
  for p in $left; do
    case " $own " in *" $p "*) continue ;; esac
    proc_alive "$p" || continue
    printf '%s\n' "$p"
  done | xargs kill -KILL 2>/dev/null || true
}
trap 'test_sweep; rm -rf "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# No test writes to the real trace (.process/events.jsonl of the main checkout).
export PROCESS_EVENTS_FILE="$TMP/events.jsonl"
# No test depends on the bots of this repository: every one reads the fixture.
export BOTS_FILE="$TESTS_DIR/fixtures/bots.tsv"
# The time limit of the tests comes from the real machine-limits.env (issue #71): only
# these two values are read, before the folder is swapped, and nothing is created there.
for _v in AI_METHOD_TEST_TIMEOUT_SECONDS AI_METHOD_WARN_LOAD1; do
  if [ -z "$(eval "printf %s \"\${$_v:-}\"")" ]; then
    _l="$(grep -s "^$_v=" "${AI_METHOD_CONFIG:-$HOME/.config/ai-method}/machine-limits.env" | tail -1 || true)"
    [ -z "$_l" ] || export "$_v=${_l#*=}"
  fi
done
# No test touches the slots, limits and history of the machine.
export AI_METHOD_CACHE="$TMP/ai-method-cache" AI_METHOD_CONFIG="$TMP/ai-method-config"
export AI_METHOD_POLL_SECONDS=1 AI_METHOD_SLOTS_VALIDATE=20 AI_METHOD_SLOTS_FASE=20
# No test inherits the session of whoever runs it: each one names its own.
unset CLAUDE_CODE_SESSION_ID
# Time limit of the tests (issue #71): the parameter of machine-limits.env, grown by the load.
# shellcheck source=scripts/lib/slots.sh
source "$REPO/scripts/lib/slots.sh"
: "${AI_METHOD_TEST_TIMEOUT_SECONDS:=600}" "${AI_METHOD_WARN_LOAD1:=8}"
# test_limited <command...>: runs the command under the alarm of that limit.
test_limited() { perl -e 'alarm shift; exec @ARGV' "$(slots_test_timeout)" "$@"; }
FAILS=0
COUNT=0

ok() { COUNT=$((COUNT + 1)); }
bad() { COUNT=$((COUNT + 1)); FAILS=$((FAILS + 1)); echo "not ok: $1"; }

assert_eq() { # assert_eq <expected> <actual> <description>
  if [ "$1" = "$2" ]; then ok; else bad "$3 (expected '$1', got '$2')"; fi
}
assert_contains() { # assert_contains <text> <excerpt> <description>
  case "$1" in *"$2"*) ok ;; *) bad "$3 (missing '$2' in: $(printf '%s' "$1" | head -c 400))" ;; esac
}
assert_not_contains() {
  case "$1" in *"$2"*) bad "$3 (unexpected '$2')" ;; *) ok ;; esac
}
# assert_status <expected code> <description> <command...>
assert_status() {
  local want="$1" what="$2" rc=0
  shift 2
  "$@" >"$TMP/last.out" 2>&1 || rc=$?
  if [ "$rc" = "$want" ]; then ok; else bad "$what (exit $rc, expected $want): $(head -c 400 "$TMP/last.out")"; fi
}
last_output() { cat "$TMP/last.out"; }

# Fake gh: records each call in $FAKE_GH_LOG and runs the handler of the test.
use_fake_gh() { # use_fake_gh <handler-file>
  mkdir -p "$TMP/bin"
  cp "$TESTS_DIR/fakes/gh" "$TMP/bin/gh"
  chmod +x "$TMP/bin/gh"
  export PATH="$TMP/bin:$PATH"
  export FAKE_GH_LOG="$TMP/gh.log" FAKE_GH_HANDLER="$1" GH_REPO="owner/repo"
  : >"$FAKE_GH_LOG"
}
gh_calls() { cat "$FAKE_GH_LOG"; }
# State of the repository setup the fake gh answers to `setup-repo.sh --check`:
# ok (default), nolabels, noprotection, offer or freeplan. Call it after use_fake_gh.
fake_setup() { # fake_setup [<state>]
  export FAKE_SETUP="${1:-ok}" FAKE_SETUP_LABELS="$TMP/setup-labels.json"
  [ -f "$FAKE_SETUP_LABELS" ] || bash -c 'source "$1/lib/common.sh"; label_rows "$2"' _ "$SCRIPTS" "$REPO/.github/labels.tsv" |
    jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t") | {name: .[0], color: .[1], description: .[2]})' >"$FAKE_SETUP_LABELS"
}

# Temporary git repository with one commit on main; prints the path.
make_repo() {
  local dir="$TMP/repo-$RANDOM"
  mkdir -p "$dir"
  git -C "$dir" init --quiet -b main
  git -C "$dir" config user.email test@example.org
  git -C "$dir" config user.name test
  git -C "$dir" config commit.gpgsign false
  echo seed >"$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit --quiet -m "chore: seed"
  echo "$dir"
}

# Copies scripts/ into a temporary repo with validate.sh and check-docs.sh replaced by
# stubs: no test reaches the real suite again through the copy (close-phase.sh
# --prepare, check-env.sh). Every test that needs the scripts in a repo copies them here.
copy_scripts() { # copy_scripts <repo>
  cp -R "$SCRIPTS" "$1/scripts"
  printf '#!/usr/bin/env bash\necho "ok: stub $*"\n' >"$1/scripts/validate.sh"
  printf '#!/usr/bin/env bash\necho "ok: stub $*"\n' >"$1/scripts/check-docs.sh"
}

finish() {
  echo "$(basename "$0"): $((COUNT - FAILS))/$COUNT passed"
  [ "$FAILS" = 0 ]
}
