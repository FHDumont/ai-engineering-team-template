#!/usr/bin/env bash
# Helpers for the Bash tests: asserts, temporary git repository and fake gh.
# Load with: source "$(dirname "$0")/lib.sh"
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# template/ is one level deeper; its tests still see the repository root.
case "$TESTS_DIR" in
  */template) REPO="$(cd "$TESTS_DIR/../../../.." && pwd)" ;;
  *) REPO="$(cd "$TESTS_DIR/../../.." && pwd)" ;;
esac
# shellcheck disable=SC2034  # used by the tests that load this file
SCRIPTS="$REPO/.method/scripts"
TMP="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/tmp.XXXXXXXX")" && pwd -P)"
# No test leaves a process alive (issue #66): whatever the test started in the
# background, or left with its folder as the cwd or in its command line, is stopped at
# the end, also when an assertion failed or the test got INT/TERM. A test that sets its
# own trap calls test_sweep in it. The search by cwd (issue #83) looks only at the detached
# processes (parent 1, a few of them): lsof over every process of the machine was the
# dearest step, paid by each test. In the CI (CI set) the machine is the runner's and the
# search stays the full one, since a detached process may have another parent there.
# shellcheck source=.method/scripts/lib/procs.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/procs.sh"
test_sweep() {
  local p own="" left
  left="$( { proc_descendants "$$"; if [ -n "${CI:-}" ]; then procs_in_dir "$TMP"; else procs_orphans "$TMP"; fi; pgrep -f "$TMP" 2>/dev/null || true; } | sort -un)"
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

# Paths the suite may scan (#99). Project code outside this list is invisible to it.
# .method/scripts/tests/template holds checks that exist only in this template and is excluded.
method_paths() {
  cat <<'EOF'
AGENTS.md
CLAUDE.md
CONTEXT.md
.claude/agents/triage.md
.claude/agents/close-reviewer.md
.claude/skills/triage/SKILL.md
.claude/skills/plan/SKILL.md
.claude/skills/execute/SKILL.md
.claude/skills/close-phase/SKILL.md
.claude/skills/integrate/SKILL.md
.claude/skills/integrate/integration.md
.claude/skills/ask-bot/SKILL.md
.claude/skills/setup/SKILL.md
.claude/hooks
.claude/commands
.claude/settings.json
.cursor
.githooks
.github/ISSUE_TEMPLATE
.github/pull_request_template.md
.github/labels.tsv
.github/sensitive-paths
.github/required-checks
.github/headless
.github/workflows/ci.yml
.github/workflows/issues-label.yml
docs/process-design.md
docs/BOTS.md
docs/STATE.md
docs/adr
docs/diagrams
docs/repo-notes.md
.method/scripts
EOF
}
# method_existing <repo>: those paths that exist, one per line.
method_existing() {
  local root="$1" p
  while IFS= read -r p; do
    [ -n "$p" ] && [ -e "$root/$p" ] && printf '%s\n' "$p"
  done < <(method_paths)
}
# method_grep <repo> <git grep options and pattern>: search only the method paths.
method_grep() {
  local root="$1" p paths=()
  shift
  while IFS= read -r p; do
    [ -n "$p" ] && paths+=("$p")
  done < <(method_existing "$root")
  [ "${#paths[@]}" -gt 0 ] || return 0
  git -C "$root" grep "$@" -- "${paths[@]}" ':!.method/scripts/tests/template'
}
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
# shellcheck source=.method/scripts/lib/slots.sh
source "$REPO/.method/scripts/lib/slots.sh"
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

# Copies .method/scripts/ into a temporary repo with validate.sh and check-docs.sh replaced by
# stubs: no test reaches the real suite again through the copy (close-phase.sh
# --prepare, check-env.sh). Every test that needs the scripts in a repo copies them here.
copy_scripts() { # copy_scripts <repo>
  mkdir -p "$1/.method/scripts"
  cp -R "$SCRIPTS/." "$1/.method/scripts/"
  printf '#!/usr/bin/env bash\necho "ok: stub $*"\n' >"$1/.method/scripts/validate.sh"
  printf '#!/usr/bin/env bash\necho "ok: stub $*"\n' >"$1/.method/scripts/check-docs.sh"
}

finish() {
  echo "$(basename "$0"): $((COUNT - FAILS))/$COUNT passed"
  [ "$FAILS" = 0 ]
}
