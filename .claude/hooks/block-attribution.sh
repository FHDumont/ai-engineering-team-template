#!/usr/bin/env bash
# block-attribution.sh: PreToolUse (Bash) hook that blocks AI signatures in what goes to GitHub.
#
# Applies to git commit, gh pr create|edit|comment|review|close and gh issue
# create|comment|edit|close. Checks the command, each of its arguments (the body
# passed in --body, --comment or -m is an argument) and the files named by
# --body-file/-F/--file, with scripts/check-attribution.sh.
# A signature opens a line of an argument or of a file; text that only cites
# the rule in the middle of a sentence passes.
# Blocks with exit 2 and the reason on stderr.
set -euo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
[ -n "$cmd" ] || exit 0
[ -n "$cwd" ] || cwd="$PWD"

if ! printf '%s' "$cmd" | grep -qE '(^|[;&| ])(git( +-C +[^ ]+)? +commit|gh( +(-R|--repo)[ =]+[^ ]+)? +(pr +(create|edit|comment|review|close)|issue +(create|comment|edit|close)))( |$)'; then
  exit 0
fi

# The checker lives in the repository of the command (worktree), else next to the hook.
here="$(cd "$(dirname "$0")" && pwd)"
checker="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)/scripts/check-attribution.sh"
[ -x "$checker" ] || checker="$here/../../scripts/check-attribution.sh"

text="$cmd"
# Each argument on its own lines: the value of --body "…" or --body=… starts a line.
args="$(printf '%s' "$cmd" | python3 -c 'import shlex, sys
try:
    for word in shlex.split(sys.stdin.read()):
        flag, sep, value = word.partition("=")
        print(value if sep and flag.startswith("-") else word)
except ValueError:
    pass' 2>/dev/null || true)"
text="$text
$args"
# Append the content of the files named as body or message.
files="$(printf '%s' "$cmd" | grep -oE '(--body-file|--file|-F)[ =]+[^ ;&|]+' | sed -E 's/^(--body-file|--file|-F)[ =]+//' || true)"
for f in $files; do
  f="${f%\"}"; f="${f#\"}"; f="${f%\'}"; f="${f#\'}"
  case "$f" in -) continue ;; /*) ;; *) f="$cwd/$f" ;; esac
  [ -f "$f" ] && text="$text
$(cat "$f")"
done

if ! out="$(printf '%s' "$text" | "$checker" --text-file - 2>&1)"; then
  echo "blocked by block-attribution: no AI attribution in commits, PRs, issues or comments (AGENTS.md)" >&2
  echo "$out" >&2
  exit 2
fi
exit 0
