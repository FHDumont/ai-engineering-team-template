#!/usr/bin/env bash
# block-bot-comment.sh: PreToolUse (Bash) hook for comments an agent posts by hand.
#
# Applies to gh issue comment, gh pr comment and gh issue|pr close --comment.
# Blocks (exit 2, reason on stderr) when:
#  - the text has no authorship header line (scripts/lib/author.sh): the owner, the
#    manager, the children and the bots share one account, and a comment without the
#    header is read as the owner's;
#  - the text cites a bot of .github/bots.tsv (slug or name, any case; BOTS_FILE
#    overrides) or carries an <!-- ask:...: --> marker: a loose comment never
#    notifies the bot, so the request goes through scripts/ask-bot.sh (--append
#    for new information on an open question).
# The text is the command, its arguments and the files named by --body-file/-F; a
# heredoc stays in the command, so it is seen too.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$here/../../scripts/lib/common.sh"

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
[ -n "$cmd" ] || exit 0
[ -n "$cwd" ] || cwd="$PWD"

printf '%s' "$cmd" | stdin_grep -qE '(^|[;&| ])gh( +(-R|--repo)[ =]+[^ ]+)? +((issue|pr) +comment|(issue|pr) +close)( |$)' || exit 0
# close without --comment posts no comment.
if printf '%s' "$cmd" | stdin_grep -qE 'gh( +(-R|--repo)[ =]+[^ ]+)? +(issue|pr) +close'; then
  printf '%s' "$cmd" | stdin_grep -qE '(--comment|-c)([ =]|$)' || exit 0
fi

text="$cmd
$(printf '%s' "$cmd" | python3 -c 'import shlex, sys
try:
    for word in shlex.split(sys.stdin.read()):
        flag, sep, value = word.partition("=")
        print(value if sep and flag.startswith("-") else word)
except ValueError:
    pass' 2>/dev/null || true)"
files="$(printf '%s' "$cmd" | grep -oE '(--body-file|--file|-F)[ =]+[^ ;&|]+' | sed -E 's/^(--body-file|--file|-F)[ =]+//' || true)"
for f in $files; do
  f="${f%\"}"; f="${f#\"}"; f="${f%\'}"; f="${f#\'}"
  case "$f" in -) continue ;; /*) ;; *) f="$cwd/$f" ;; esac
  [ -f "$f" ] && text="$text
$(cat "$f")"
done

# shellcheck source=scripts/lib/author.sh
source "$here/../../scripts/lib/author.sh"
if ! printf '%s' "$text" | has_author_header; then
  echo "blocked by block-bot-comment: a comment from an agent starts with the authorship header (AGENTS.md rule 6):" >&2
  echo '**De:** <papel> · **Para:** <papel> · **Pedido:** <ask_id ou o quê> · **Responde a:** <link ou —>' >&2
  echo "scripts/lib/author.sh: author_header; no header means the owner wrote it" >&2
  exit 2
fi

bots="${BOTS_FILE:-}"
[ -n "$bots" ] || bots="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$here/../..")/.github/bots.tsv"
if [ -f "$bots" ]; then
  while IFS=$'\t' read -r slug name _; do
    case "$slug" in ''|'#'*) continue ;; esac
    for term in "$slug" "$name"; do
      [ -n "$term" ] || continue
      if printf '%s' "$text" | stdin_grep -qiF -- "$term"; then
        echo "blocked by block-bot-comment: the comment cites the bot \"$term\"; a request to a bot goes through scripts/ask-bot.sh <bot> <issue> \"text\" (--append for new information on an open question); a loose comment never notifies the bot" >&2
        exit 2
      fi
    done
  done <"$bots"
fi
if printf '%s' "$text" | stdin_grep -qF '<!-- ask:'; then
  echo "blocked by block-bot-comment: <!-- ask: markers come only from scripts/ask-bot.sh" >&2
  exit 2
fi
exit 0
