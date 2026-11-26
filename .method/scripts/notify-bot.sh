#!/usr/bin/env bash
#: notify-bot.sh: call a bot's webhook directly with the link to the question comment.
#:
#: Usage: notify-bot.sh <bot> <issue> <comment-url> [--ask-id ID] [--retry-wait seconds]
#:
#: The webhook URL and secret come from scripts/lib/secret.sh (variables
#: BOT_WEBHOOK_<SLUG>_URL and _SECRET; the .env outside the repo; or, optionally,
#: a password manager service account, fields `url` and `secret` of the item
#: referenced in .github/bots.tsv) at call
#: time and never go to a file, a process argument or a log: the URL and both
#: headers (`Authorization: Bearer` and `X-Automation-Key`) go in curl's config
#: on stdin. JSON body: source, bot, repo (owner/name), issue, comment_url,
#: ask_id and reply_marker (<!-- bot:<slug> reply-to:<ask_id> -->). Each call
#: has 10 s. One attempt plus 2 retries; if all fail, labels the issue
#: ask:<bot>, reads the label back and exits 4; when the label is not there
#: either, it says so and exits 5. With no secret provider (or a locked credential store, or a
#: too-open .env) it exits 1 before calling curl. Bots: .github/bots.tsv.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=scripts/lib/secret.sh
source "$HERE/lib/secret.sh"

[ $# -gt 0 ] || { print_help "$0"; exit 2; }
case "$1" in -h|--help) print_help "$0"; exit 0 ;; esac
[ $# -ge 3 ] || die "usage: notify-bot.sh <bot> <issue> <comment-url>" 2
bot="$1" issue="$2" url="$3"; shift 3
ask_id="" wait="${NOTIFY_RETRY_WAIT:-10}"
while [ $# -gt 0 ]; do
  case "$1" in
    --ask-id) ask_id="$2"; shift 2 ;;
    --retry-wait) wait="$2"; shift 2 ;;
    *) die "unknown option: $1 (see --help)" 2 ;;
  esac
done

bot_slugs | stdin_grep -qxF -- "$bot" || die "unknown bot: $bot (see .github/bots.tsv)"
ref="$(awk -F'\t' -v b="$bot" '$1 == b {print $3}' "$(bots_file)")"
repo="$(repo_slug)"
marker="<!-- bot:$bot reply-to:$ask_id -->"

# Escapes a value for a quoted string in curl's config (\ and ").
conf_quote() {
  local v="${1//\\/\\\\}"
  printf '%s' "${v//\"/\\\"}"
}

attempt() {
  local hook secret payload rc=0
  # Secrets only in local variables; `op` and `curl` get nothing through a visible argument.
  # The reference may have spaces (vault name): always quoted.
  hook="$(secret_get "$(bot_webhook_var "$bot" url)" "${ref:+$ref/url}")" || rc=$?
  # Configuration problem (no provider, locked credential store, open .env): retrying does not help.
  case "$rc" in 10|11|13) exit 1 ;; 0) ;; *) return 1 ;; esac
  secret="$(secret_get "$(bot_webhook_var "$bot" secret)" "${ref:+$ref/secret}")" || return 1
  payload="$(jq -cn --arg bot "$bot" --arg repo "$repo" --arg issue "$issue" --arg url "$url" \
    --arg id "$ask_id" --arg marker "$marker" \
    '{source: "ask-bot", bot: $bot, repo: $repo, issue: ($issue | tonumber), comment_url: $url,
      ask_id: $id, reply_marker: $marker}')"
  hook="$(conf_quote "$hook")" secret="$(conf_quote "$secret")"
  printf 'url = "%s"\nheader = "Authorization: Bearer %s"\nheader = "X-Automation-Key: %s"\nheader = "Content-Type: application/json"\n' \
    "$hook" "$secret" "$secret" |
    curl --silent --show-error --fail --max-time 10 --output /dev/null --config - --data "$payload"
}

for n in 1 2 3; do
  if attempt; then
    echo "notified $bot (attempt $n)"
    exit 0
  fi
  [ "$n" = 3 ] || sleep "$wait"
done

# The label is what the routine of the bot sweeps: it only counts when read back.
gh issue edit "$issue" --repo "$repo" --add-label "ask:$bot" >/dev/null 2>&1 || true
if gh issue view "$issue" --repo "$repo" --json labels --jq '.labels[].name' 2>/dev/null | stdin_grep -qxF "ask:$bot"; then
  echo "failed to notify $bot after 3 attempts; labeled ask:$bot on #$issue (read back)"
  exit 4
fi
echo "error: failed to notify $bot after 3 attempts and the label ask:$bot is not on #$issue (read back): the bot will not see the question" >&2
echo "fix: scripts/label-issue.sh $issue --add ask:$bot, or scripts/ask-bot.sh --retry <ask_id> --issue $issue" >&2
exit 5
