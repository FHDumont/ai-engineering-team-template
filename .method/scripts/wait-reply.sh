#!/usr/bin/env bash
#: wait-reply.sh: wait for a bot's reply to a question, recognized by its marker.
#:
#: Usage: wait-reply.sh <issue> <ask-id> [--timeout seconds] [--interval seconds] [--warn-after seconds] [--after comment-id]
#:
#: Accepts only comments with <!-- bot:<slug> reply-to:<ask-id> --> posted after
#: the question (<!-- ask:<bot>:<ask-id> -->): the owner, Claude and the bots
#: share one account, so the author means nothing. Default wait: 15 minutes.
#: --after ID: count only replies posted at or after the comment with that id (ask-bot.sh
#: --append passes its follow-up comment, so the earlier reply is not taken as the answer
#: to it); exits 1 if that comment is not on the issue. Without it: after the question.
#: Prints the reply bodies and exits 0; exits 3 on timeout; exits 1 when the
#: comments cannot be read or the question is not on the issue.
#: Early warning (stderr, once, before the first wait): a question comment without the
#: authorship header (scripts/lib/author.sh) was not posted by ask-bot.sh, so the bot
#: may never have been notified; run ask-bot.sh --retry <id> instead of waiting in vain.
#: --warn-after S (default 180): with no reply after S seconds, warns once on stderr that
#: the bot did not react, suggests ask-bot.sh --retry, and keeps waiting until the timeout.
#: When the reply is found it records a bot_reply event (bot, ask_id) in the trace.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=scripts/lib/author.sh
source "$HERE/lib/author.sh"

[ $# -gt 0 ] || { print_help "$0"; exit 2; }
case "$1" in -h|--help) print_help "$0"; exit 0 ;; esac
[ $# -ge 2 ] || die "usage: wait-reply.sh <issue> <ask-id>" 2
issue="$1" id="$2"; shift 2
valid_ask_id "$id" || die "invalid ask id: $id (expected 14 digits, a dash and digits)" 2
timeout=900 interval=30 warn_after=180 late_warned="" after=""
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout) timeout="$2"; shift 2 ;;
    --interval) interval="$2"; shift 2 ;;
    --warn-after) warn_after="$2"; shift 2 ;;
    --after) after="$2"; shift 2 ;;
    *) die "unknown option: $1 (see --help)" 2 ;;
  esac
done
repo="$(repo_slug)"

start="$(date +%s)"
warned=""
while :; do
  comments="$(gh api "repos/$repo/issues/$issue/comments" --paginate --slurp)" ||
    die "could not read the comments of #$issue (gh api failed): no reply can be seen"
  # No question with this id: there is nothing to wait for, and a timeout would lie.
  printf '%s' "$comments" | jq -e --arg id "$id" 'add // [] | any(.[]; .body | test("<!-- ask:[a-z0-9-]+:" + $id + " -->"))' >/dev/null ||
    die "no question comment with <!-- ask:<bot>:$id --> on #$issue: nothing to wait for"
  if [ -z "$warned" ]; then
    warned=1
    qbody="$(printf '%s' "$comments" | jq -r --arg id "$id" 'add // [] | map(select(.body | test("<!-- ask:[a-z0-9-]+:" + $id + " -->"))) | first | .body')"
    printf '%s' "$qbody" | has_author_header ||
      echo "warning: the question $id on #$issue has no authorship header, so ask-bot.sh did not post it and the bot may never have been notified; run: ask-bot.sh --retry $id --issue $issue" >&2
  fi
  if [ -n "$after" ]; then
    printf '%s' "$comments" | jq -e --arg a "$after" 'add // [] | any(.[]; (.id | tostring) == $a)' >/dev/null ||
      die "no comment with id $after on #$issue: nothing to wait after"
  fi
  replies="$(printf '%s' "$comments" | jq -r --arg id "$id" --arg a "$after" '
    add // [] |
    (if $a == "" then map(select(.body | test("<!-- ask:[a-z0-9-]+:" + $id + " -->"))) | first | .created_at
     else map(select((.id | tostring) == $a)) | first | .created_at end) as $asked |
    if $asked == null then empty else
      .[] | select(.created_at >= $asked)
          | select(.body | test("<!-- bot:[a-z0-9-]+ reply-to:" + $id + " -->"))
          | "--- " + .html_url + "\n" + .body
    end')"
  if [ -n "$replies" ]; then
    echo "$replies"
    # The bot comes from the reply marker (the first one that appears).
    rbot="$(printf '%s\n' "$replies" | sed -n -E "s/.*<!-- bot:([a-z0-9-]+) reply-to:$id -->.*/\1/p" | head -1)"
    trace_event bot_reply "bot=$rbot" "ask_id=$id" "issue=$issue"
    exit 0
  fi
  if [ -z "$late_warned" ] && [ $(( $(date +%s) - start )) -ge "$warn_after" ]; then
    late_warned=1
    echo "warning: no reply to $id on #$issue after ${warn_after}s; the bot may not have been notified or has not reacted. Run: ask-bot.sh --retry $id --issue $issue (still waiting until the timeout)" >&2
  fi
  if [ $(( $(date +%s) - start + interval )) -gt "$timeout" ]; then
    echo "timeout: no reply to $id on #$issue after ${timeout}s (resume with wait-reply.sh $issue $id)"
    exit 3
  fi
  sleep "$interval"
done
