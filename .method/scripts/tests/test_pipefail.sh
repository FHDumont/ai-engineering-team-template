#!/usr/bin/env bash
# pipefail + grep -q: a match must not look like a miss because the writer got SIGPIPE.
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

HOOK="$REPO/.claude/hooks/block-attribution.sh"
trailer="Co-Authored-By: Claude <noreply@anthropic.com>"

# Command larger than the pipe buffer: git commit at the start, trailer at the end.
# On the old hook the first grep -q matches and closes the pipe; pipefail then looks
# like "not a commit" and the hook exits 0.
payload="$(python3 - "$REPO" "$trailer" <<'PY'
import json, sys
repo, trailer = sys.argv[1], sys.argv[2]
cmd = 'git commit -m "feat: x\n\n' + ("x\n" * 80000) + trailer + '"'
json.dump({"tool_input": {"command": cmd}, "cwd": repo}, sys.stdout)
PY
)"

rc=0
printf '%s' "$payload" | "$HOOK" >/dev/null 2>"$TMP/hook.err" || rc=$?
assert_eq 2 "$rc" "hook exit is 2 on a huge commit with an attribution trailer"
assert_contains "$(cat "$TMP/hook.err")" "block-attribution" "hook names itself on the huge commit"

rc=0
trap '' PIPE
printf '%s' "$payload" | "$HOOK" >/dev/null 2>"$TMP/hook.err" || rc=$?
trap - PIPE
assert_eq 2 "$rc" "the same huge commit is refused with SIGPIPE ignored"

# stdin_grep always consumes stdin, so the name at the front of a large list is found.
# shellcheck source=.method/scripts/lib/common.sh
source "$SCRIPTS/lib/common.sh"
list="$(printf '%s\n' PROCESS_OFFER_PROJECT; python3 -c 'print("\n".join("VAR%05d" % i for i in range(20000)))')"
if command -v stdin_grep >/dev/null; then
  rc=0
  printf '%s\n' "$list" | stdin_grep -qxF PROCESS_OFFER_PROJECT || rc=$?
  assert_eq 0 "$rc" "stdin_grep finds the name at the start of a large list"
else
  bad "stdin_grep is missing from .method/scripts/lib/common.sh"
fi

# Static: no production script with pipefail decides with `| grep -q`.
offenders=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  case "$f" in
    .method/scripts/tests/*|*/.method/scripts/tests/*|.claude/hooks/tests/*|*/.claude/hooks/tests/*) continue ;;
  esac
  grep -qE 'set -euo pipefail|set -eo pipefail|pipefail' "$f" || continue
  hits="$(grep -nE '[^[:space:]] \| grep -[a-zA-Z]*q' "$f" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
  [ -z "$hits" ] || offenders="$offenders$f:"$'\n'"$hits"$'\n'
done < <(cd "$REPO" && printf '%s\n' .method/scripts/*.sh .method/scripts/lib/* .claude/hooks/* .githooks/*)
yml="$REPO/.github/workflows/ci.yml"
hits="$(grep -nE '[^[:space:]] \| grep -[a-zA-Z]*q' "$yml" || true)"
[ -z "$hits" ] || offenders="$offenders$yml:"$'\n'"$hits"$'\n'

assert_eq "" "$offenders" "no grep -q at the end of a pipe under pipefail in production scripts"
finish
