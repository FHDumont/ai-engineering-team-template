#!/usr/bin/env bash
# Helpers for the Bash tests: asserts, temporary git repository and fake gh.
# Load with: source "$(dirname "$0")/lib.sh"
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$TESTS_DIR/../.." && pwd)"
# shellcheck disable=SC2034  # used by the tests that load this file
SCRIPTS="$REPO/scripts"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
# No test writes to the real trace (.process/events.jsonl of the main checkout).
export PROCESS_EVENTS_FILE="$TMP/events.jsonl"
# No test depends on the bots of this repository: every one reads the fixture.
export BOTS_FILE="$TESTS_DIR/fixtures/bots.tsv"
# No test inherits the session of whoever runs it: each one names its own.
unset CLAUDE_CODE_SESSION_ID
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
