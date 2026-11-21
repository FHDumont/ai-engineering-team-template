#!/usr/bin/env bash
#: ask-bot.sh: ask a bot on an issue, notify it and wait for the reply.
#:
#: Usage: ask-bot.sh <bot> <issue> "question text" [--timeout seconds]
#:        ask-bot.sh --retry <ask_id> [--issue N] [--timeout seconds]
#:        ask-bot.sh --append <ask_id> "more text" [--issue N] [--timeout seconds]
#:
#: 1. Checks that a secret provider exists (scripts/lib/secret.sh: environment
#:    variable, .env outside the repo or a password manager service account) without
#:    triggering a desktop app authorization: with none, stops before
#:    posting anything.
#: 2. Comments the question on the issue (the record) with <!-- ask:<bot>:<id> -->
#:    and reads the comment back; without it, exits 1 and the bot is not notified.
#: 3. notify-bot.sh calls the bot's webhook with the comment link.
#: 4. wait-reply.sh waits for the marked reply (default 15 min).
#: If the notification fails (exit 4), the issue keeps ask:<bot> and no wait runs.
#: --retry: finds the comment with <!-- ask:<bot>:<ask_id> --> on the issue
#: (default: the branch's issue) and only calls notify-bot.sh again for it,
#: without posting another question; then waits for the reply. No such comment:
#: error, nothing is posted. The same provider check runs before notifying.
#: --append: adds a follow-up to a question already asked (same ask id), as a new
#: comment with the authorship header and <!-- ask-append:<bot>:<id> -->, notifies the
#: bot with the new comment link and waits for the reply to that id. Never opens a
#: second question. Every comment this script posts starts with the authorship header
#: (De, Para, Pedido, Responde a; scripts/lib/author.sh): without it the bot and the
#: owner cannot tell who wrote what. A bare "gh issue comment" to a bot is never seen.
#: Records bot_append on --append and bot_ask events (retry=1 on --retry) in the trace; wait-reply.sh records bot_reply.
#: If the session drops, resume only the wait with: wait-reply.sh <issue> <id>.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=scripts/lib/secret.sh
source "$HERE/lib/secret.sh"
# shellcheck source=scripts/lib/author.sh
source "$HERE/lib/author.sh"

[ $# -gt 0 ] || { print_help "$0"; exit 2; }
case "$1" in -h|--help) print_help "$0"; exit 0 ;; esac

# Without a secret provider the notification would fail after the question is already posted.
# secret_ready already explains the problem on stderr.
require_secret() {
  secret_ready "$(bot_webhook_var "$1" url)" "$(bot_webhook_var "$1" secret)" ||
    die "no usable secret provider for $1 (nothing was posted)"
}

# post_comment <issue> <body>: posts, reads back by its id and prints the URL.
post_comment() {
  local issue="$1" body="$2" repo url cid
  repo="$(repo_slug)"
  url="$(printf '%s' "$body" | gh issue comment "$issue" --repo "$repo" --body-file - | tail -1)" ||
    die "comment not posted on #$issue: gh issue comment failed (the bot was not notified)"
  cid="$(printf '%s\n' "$url" | sed -n -E 's/.*#issuecomment-([0-9]+)$/\1/p')"
  [ -n "$cid" ] || die "comment not posted on #$issue: gh issue comment returned no comment URL (the bot was not notified)"
  printf '%s' "$url"
}

timeout=900
if [ "$1" = "--append" ]; then
  [ $# -ge 3 ] || die "usage: ask-bot.sh --append <ask_id> \"more text\" [--issue N]" 2
  id="$2" text="$3"; shift 3
  valid_ask_id "$id" || die "invalid ask id: $id (expected 14 digits, a dash and digits)" 2
  issue=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --issue) issue="$2"; shift 2 ;;
      --timeout) timeout="$2"; shift 2 ;;
      *) die "unknown option: $1 (see --help)" 2 ;;
    esac
  done
  [ -n "$issue" ] || issue="$(issue_from_branch "$(current_branch)")"
  [ -n "$issue" ] || die "no issue: pass --issue N (the branch has no issue number)" 2
  repo="$(repo_slug)"
  found="$(gh api "repos/$repo/issues/$issue/comments" --paginate --slurp | jq -r --arg id "$id" '
    add // [] | map(select(.body | test("<!-- ask:[a-z0-9-]+:" + $id + " -->"))) | first // empty
    | ((.body | capture("<!-- ask:(?<b>[a-z0-9-]+):" + $id + " -->").b) + " " + .html_url)')"
  [ -n "$found" ] || die "no question comment with <!-- ask:<bot>:$id --> on #$issue (nothing posted)"
  bot="${found%% *}" qurl="${found#* }"
  require_secret "$bot"
  body="$(printf '%s\n\n%s\n\n<!-- ask-append:%s:%s -->' "$(author_header "$bot" "$id" "$qurl")" "$text" "$bot" "$id")"
  url="$(post_comment "$issue" "$body")"
  cid="${url##*#issuecomment-}"
  gh api "repos/$repo/issues/comments/$cid" --jq .body 2>/dev/null | grep -qF "<!-- ask-append:$bot:$id -->" ||
    die "follow-up not confirmed on read back (comment $cid of #$issue has no marker); the bot was not notified"
  echo "appended to $bot question on #$issue (id $id): $url"
  trace_event bot_append "bot=$bot" "ask_id=$id" "issue=$issue" "comment=$url"
elif [ "$1" = "--retry" ]; then
  [ $# -ge 2 ] || die "usage: ask-bot.sh --retry <ask_id> [--issue N]" 2
  id="$2"; shift 2
  valid_ask_id "$id" || die "invalid ask id: $id (expected 14 digits, a dash and digits)" 2
  issue=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --issue) issue="$2"; shift 2 ;;
      --timeout) timeout="$2"; shift 2 ;;
      *) die "unknown option: $1 (see --help)" 2 ;;
    esac
  done
  [ -n "$issue" ] || issue="$(issue_from_branch "$(current_branch)")"
  [ -n "$issue" ] || die "no issue: pass --issue N (the branch has no issue number)" 2
  # Finds the question comment by its marker: "<bot> <url>" of the first match.
  found="$(gh api "repos/$(repo_slug)/issues/$issue/comments" --paginate --slurp | jq -r --arg id "$id" '
    add // [] | map(select(.body | test("<!-- ask:[a-z0-9-]+:" + $id + " -->"))) | first // empty
    | ((.body | capture("<!-- ask:(?<b>[a-z0-9-]+):" + $id + " -->").b) + " " + .html_url)')"
  [ -n "$found" ] || die "no question comment with <!-- ask:<bot>:$id --> on #$issue (nothing posted)"
  bot="${found%% *}" url="${found#* }"
  require_secret "$bot"
  echo "retry $bot on #$issue (id $id): $url"
  trace_event bot_ask "bot=$bot" "ask_id=$id" "issue=$issue" "comment=$url" retry=1
else
  [ $# -ge 3 ] || die "usage: ask-bot.sh <bot> <issue> \"question\"" 2
  bot="$1" issue="$2" text="$3"; shift 3
  while [ $# -gt 0 ]; do
    case "$1" in
      --timeout) timeout="$2"; shift 2 ;;
      *) die "unknown option: $1 (see --help)" 2 ;;
    esac
  done
  bot_slugs | grep -qxF -- "$bot" || die "unknown bot: $bot (see .github/bots.tsv)"
  require_secret "$bot"

  id="$(date +%Y%m%d%H%M%S)-$$"
  body="$(printf '%s\n\n%s\n\n<!-- ask:%s:%s -->' "$(author_header "$bot" "$id")" "$text" "$bot" "$id")"
  repo="$(repo_slug)"
  url="$(printf '%s' "$body" | gh issue comment "$issue" --repo "$repo" --body-file - | tail -1)" ||
    die "question not posted on #$issue: gh issue comment failed (the bot was not notified)"
  # Exit 0 does not prove the comment exists: read it back by its id, with the marker.
  cid="$(printf '%s\n' "$url" | sed -n -E 's/.*#issuecomment-([0-9]+)$/\1/p')"
  [ -n "$cid" ] || die "question not posted on #$issue: gh issue comment returned no comment URL (the bot was not notified)"
  gh api "repos/$repo/issues/comments/$cid" --jq .body 2>/dev/null | grep -qF "<!-- ask:$bot:$id -->" ||
    die "question not confirmed on read back (comment $cid of #$issue has no marker); the bot was not notified"
  echo "asked $bot on #$issue (id $id): $url"
  trace_event bot_ask "bot=$bot" "ask_id=$id" "issue=$issue" "comment=$url"
fi

rc=0
"$HERE/notify-bot.sh" "$bot" "$issue" "$url" --ask-id "$id" || rc=$?
[ "$rc" = 0 ] || exit "$rc"
"$HERE/wait-reply.sh" "$issue" "$id" --timeout "$timeout"
