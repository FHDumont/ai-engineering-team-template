#!/usr/bin/env bash
# Tests of path B: notify-bot, wait-reply, ask-bot and summarize-thread (simulated).
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

# Stateful fake gh: the posted comment is kept in $TMP/posted and joins the list;
# the label set by edit is kept in $TMP/labels.
cat >"$TMP/handler.sh" <<'H'
case "$*" in
  "issue comment"*)
    [ -z "${FAKE_COMMENT_LOST:-}" ] || { cat >/dev/null; echo "https://github.com/owner/repo/issues/3#issuecomment-1"; exit 0; }
    [ -z "${FAKE_COMMENT_NO_URL:-}" ] || { cat >/dev/null; exit 0; }
    cat >"$TMP/posted"; echo "https://github.com/owner/repo/issues/3#issuecomment-1" ;;
  "api repos/owner/repo/issues/comments/1"*) cat "$TMP/posted" 2>/dev/null || true ;;
  "api repos/owner/repo/issues/3/comments"*)
    if [ -f "$TMP/posted" ]; then
      jq -c --rawfile b "$TMP/posted" '.[0] += [{id: 1, created_at: "2026-01-17T11:00:00Z", html_url: "https://github.com/owner/repo/issues/3#issuecomment-1", body: $b}]' "$FAKE_COMMENTS"
    else
      cat "$FAKE_COMMENTS"
    fi ;;
  "issue edit"*"--add-label"*) for a in "$@"; do case "$a" in ask:*) echo "$a" >>"$TMP/labels" ;; esac; done ;;
  "issue view"*"--json labels"*) cat "$TMP/labels" 2>/dev/null || true ;;
esac
H
export TMP
use_fake_gh "$TMP/handler.sh"
# Fake security, op and curl: the secret must never appear in the curl arguments.
# No test touches the real credential store, the real password manager or the user's .env.
cat >"$TMP/bin/security" <<'F'
#!/usr/bin/env bash
[ -z "${FAKE_SECURITY_MISSING:-}" ] || { echo "security: item not found" >&2; exit 44; }
echo "sa-token-123"
F
export PROCESS_ENV_FILE="$TMP/none.env"
unset BOT_WEBHOOK_BOT_A_URL BOT_WEBHOOK_BOT_A_SECRET BOT_WEBHOOK_BOT_B_URL BOT_WEBHOOK_BOT_B_SECRET
cat >"$TMP/bin/op" <<'F'
#!/usr/bin/env bash
echo "$2" >>"$FAKE_OP_LOG"
case "$2" in */url) echo "https://hooks.example/bot" ;; */secret) echo "s3cr3t-value" ;; esac
F
cat >"$TMP/bin/curl" <<'F'
#!/usr/bin/env bash
echo "args: $*" >>"$FAKE_CURL_LOG"
cat >>"$FAKE_CURL_LOG"
n="$(cat "$FAKE_CURL_COUNT" 2>/dev/null || echo 0)"; echo $((n + 1)) >"$FAKE_CURL_COUNT"
exit "${FAKE_CURL_EXIT:-0}"
F
chmod +x "$TMP/bin/security" "$TMP/bin/op" "$TMP/bin/curl"
export FAKE_CURL_LOG="$TMP/curl.log" FAKE_CURL_COUNT="$TMP/curl.count" FAKE_OP_LOG="$TMP/op.log" NOTIFY_RETRY_WAIT=0

assert_status 0 "notifies the bot" "$SCRIPTS/notify-bot.sh" bot-a 3 "https://x/c/1" --ask-id 20260117100100-1
assert_eq "1" "$(cat "$FAKE_CURL_COUNT")" "one attempt on success"
args="$(grep '^args:' "$FAKE_CURL_LOG")"
config="$(grep -v '^args:' "$FAKE_CURL_LOG")"
assert_not_contains "$args" "s3cr3t-value" "secret never in curl arguments"
assert_not_contains "$args" "hooks.example" "webhook URL never in curl arguments"
assert_contains "$args" "--max-time 10" "10 s per call"
assert_contains "$config" 'url = "https://hooks.example/bot"' "URL goes in the stdin config"
assert_contains "$config" 'header = "Authorization: Bearer s3cr3t-value"' "Bearer header in the stdin config"
assert_contains "$config" 'header = "X-Automation-Key: s3cr3t-value"' "X-Automation-Key header in the stdin config"
assert_contains "$args" '"source":"ask-bot"' "payload has the source"
assert_contains "$args" '"repo":"owner/repo"' "payload has repo as owner/name"
assert_contains "$args" '"issue":3' "payload has the issue number"
assert_contains "$args" '"comment_url":"https://x/c/1"' "payload has the comment link"
assert_contains "$args" '"ask_id":"20260117100100-1"' "payload has the ask id"
assert_contains "$args" '"reply_marker":"<!-- bot:bot-a reply-to:20260117100100-1 -->"' "payload has the reply marker"
assert_eq "op://Your Vault/webhook-bot-a/url" "$(head -1 "$FAKE_OP_LOG")" "vault reference with spaces is one argument"

# A secret with quotes and a backslash does not break curl's config.
cat >"$TMP/bin/op" <<'F'
#!/usr/bin/env bash
case "$2" in */url) echo "https://hooks.example/bot" ;; */secret) printf '%s\n' 'a"b\c' ;; esac
F
: >"$FAKE_CURL_LOG"
assert_status 0 "notifies with a quoted secret" "$SCRIPTS/notify-bot.sh" bot-a 3 "https://x/c/1" --ask-id 20260117100100-1
assert_contains "$(cat "$FAKE_CURL_LOG")" 'header = "X-Automation-Key: a\"b\\c"' "secret is escaped in the config"

rm -f "$FAKE_CURL_COUNT"
assert_status 4 "forced webhook failure exits 4" env FAKE_CURL_EXIT=22 "$SCRIPTS/notify-bot.sh" bot-a 3 "https://x/c/1"
assert_eq "3" "$(cat "$FAKE_CURL_COUNT")" "1 attempt + 2 retries"
assert_contains "$(gh_calls)" "issue edit 3 --repo owner/repo --add-label ask:bot-a" "labels ask:<bot> on failure"
assert_contains "$(last_output)" "labeled ask:bot-a on #3 (read back)" "the label is read back"
# Failure: the notice failed and the label did not land either; it does not say it labeled.
rm -f "$TMP/labels"
assert_status 5 "webhook and label both failing exits 5" env FAKE_CURL_EXIT=22 FAKE_GH_FAIL='^issue edit' "$SCRIPTS/notify-bot.sh" bot-a 3 "https://x/c/1"
assert_contains "$(last_output)" "the label ask:bot-a is not on #3" "says the label is missing"
assert_not_contains "$(last_output)" "labeled ask:bot-a" "never claims the label"
assert_status 1 "unknown bot" "$SCRIPTS/notify-bot.sh" nobody 3 x

# wait-reply: only the mark counts, posted after the question.
cat >"$TMP/comments.json" <<'J'
[[{"created_at":"2026-01-17T10:00:00Z","html_url":"u0","body":"<!-- bot:bot-a reply-to:20260117100100-1 --> antiga, antes da pergunta"},
  {"created_at":"2026-01-17T10:01:00Z","html_url":"u1","body":"Pergunta\n\n<!-- ask:bot-a:20260117100100-1 -->"},
  {"created_at":"2026-01-17T10:02:00Z","html_url":"u2","body":"resposta sem marca"},
  {"created_at":"2026-01-17T10:03:00Z","html_url":"u3","body":"Texto ok <!-- bot:bot-a reply-to:20260117100100-1 -->"},
  {"created_at":"2026-01-17T10:04:00Z","html_url":"u4","body":"<!-- bot:bot-a reply-to:zz --> outra pergunta"},
  {"created_at":"2026-01-17T10:05:00Z","html_url":"u5","body":"Sem resposta\n\n<!-- ask:bot-a:20260117100199-9 -->"}]]
J
export FAKE_COMMENTS="$TMP/comments.json"
out="$("$SCRIPTS/wait-reply.sh" 3 20260117100100-1 --timeout 1 --interval 0)"
assert_contains "$out" "Texto ok" "returns the marked reply"
assert_not_contains "$out" "antiga" "ignores replies before the question"
assert_not_contains "$out" "sem marca" "ignores unmarked comments"
assert_not_contains "$out" "outra pergunta" "ignores other ask ids"
assert_status 3 "times out without a reply" "$SCRIPTS/wait-reply.sh" 3 20260117100199-9 --timeout 0 --interval 0
# Failures: without reading the comments, or without the question, there is nothing to wait for.
assert_status 1 "wait-reply fails when the comments cannot be read" env FAKE_GH_FAIL='issues/3/comments' "$SCRIPTS/wait-reply.sh" 3 20260117100100-1 --timeout 0 --interval 0
assert_contains "$(last_output)" "could not read the comments of #3" "says the read failed"
assert_status 1 "wait-reply fails without the question comment" "$SCRIPTS/wait-reply.sh" 3 20260117100177-7 --timeout 0 --interval 0
assert_contains "$(last_output)" "nothing to wait for" "says there is no question"

# ask-bot: comments with the mark, notifies and waits.
rm -f "$FAKE_CURL_COUNT"
assert_status 4 "ask-bot stops when notify fails" env FAKE_CURL_EXIT=7 "$SCRIPTS/ask-bot.sh" bot-a 3 "Opinião sobre o texto?"
assert_contains "$(gh_calls)" "issue comment 3 --repo owner/repo --body-file -" "posts the question"
# Failures: a question that was not posted does not notify the bot.
for lost in FAKE_COMMENT_NO_URL FAKE_COMMENT_LOST; do
  rm -f "$FAKE_CURL_COUNT" "$TMP/posted"
  assert_status 1 "ask-bot fails when the question is not posted ($lost)" env "$lost=1" "$SCRIPTS/ask-bot.sh" bot-a 3 "Opinião?" --timeout 0
  assert_contains "$(last_output)" "the bot was not notified" "says the bot was not notified ($lost)"
  assert_eq "" "$(cat "$FAKE_CURL_COUNT" 2>/dev/null || true)" "never notifies without the question ($lost)"
done
rm -f "$FAKE_CURL_COUNT" "$TMP/posted"
assert_status 1 "ask-bot fails when gh issue comment fails" env FAKE_GH_FAIL='^issue comment' "$SCRIPTS/ask-bot.sh" bot-a 3 "Opinião?" --timeout 0
assert_eq "" "$(cat "$FAKE_CURL_COUNT" 2>/dev/null || true)" "never notifies when the comment fails"

# ask-bot: events in the trace, the secret provider check and --retry.
# Fake op that returns url and secret (the service account token comes from the fake security).
cat >"$TMP/bin/op" <<'F'
#!/usr/bin/env bash
case "$2" in */url) echo "https://hooks.example/bot" ;; */secret) echo "s3cr3t-value" ;; esac
F
export PROCESS_EVENTS_FILE="$TMP/events.jsonl"
: >"$PROCESS_EVENTS_FILE"
: >"$FAKE_GH_LOG"
rm -f "$FAKE_CURL_COUNT"
# The new id never has a reply in the example JSON: the wait ends in a timeout (3).
assert_status 3 "ask-bot posts, notifies and then waits" "$SCRIPTS/ask-bot.sh" bot-a 3 "Opinião?" --timeout 0
assert_eq "1" "$(grep -c '^issue comment' "$FAKE_GH_LOG")" "ask-bot posts one question"
assert_eq "1" "$(cat "$FAKE_CURL_COUNT")" "ask-bot notifies once"
events="$(cat "$PROCESS_EVENTS_FILE")"
assert_eq "1" "$(printf '%s\n' "$events" | jq -s '[.[] | select(.event == "bot_ask")] | length')" "records one bot_ask"
assert_eq "bot-a" "$(printf '%s\n' "$events" | jq -rs '[.[] | select(.event == "bot_ask")][0].bot')" "bot_ask has the bot"
assert_contains "$events" '"comment":"https://github.com/owner/repo/issues/3#issuecomment-1"' "bot_ask has the comment link"
"$SCRIPTS/wait-reply.sh" 3 20260117100100-1 --timeout 1 --interval 0 >/dev/null
assert_eq "1" "$(jq -s '[.[] | select(.event == "bot_reply" and .bot == "bot-a" and .ask_id == "20260117100100-1")] | length' "$PROCESS_EVENTS_FILE")" "wait-reply records bot_reply"

# No secret provider: posts nothing and does not call curl.
: >"$FAKE_GH_LOG"
rm -f "$FAKE_CURL_COUNT"
assert_status 1 "ask-bot stops without a secret provider" env FAKE_SECURITY_MISSING=1 "$SCRIPTS/ask-bot.sh" bot-a 3 "Opinião?"
assert_contains "$(last_output)" "no secret provider configured" "explains the missing provider"
assert_contains "$(last_output)" "nothing was posted" "says nothing was posted"
assert_eq "" "$(gh_calls)" "nothing reaches GitHub without a provider"
assert_eq "" "$(cat "$FAKE_CURL_COUNT" 2>/dev/null || true)" "curl is never called without a provider"
# The same goes for notify-bot: it stops before curl, with no label.
assert_status 1 "notify-bot stops without a secret provider" env FAKE_SECURITY_MISSING=1 "$SCRIPTS/notify-bot.sh" bot-a 3 "https://x/c/1"
assert_eq "" "$(gh_calls)" "notify-bot labels nothing without a provider"
assert_eq "" "$(cat "$FAKE_CURL_COUNT" 2>/dev/null || true)" "notify-bot never calls curl without a provider"
# Locked credential store: message with the fix, nothing posted.
cat >"$TMP/bin/security.locked" <<'F'
#!/usr/bin/env bash
echo "security: User interaction is not allowed." >&2; exit 36
F
cp "$TMP/bin/security" "$TMP/bin/security.ok"
cp "$TMP/bin/security.locked" "$TMP/bin/security"
assert_status 1 "ask-bot stops with a locked credential store" "$SCRIPTS/ask-bot.sh" bot-a 3 "Opinião?"
assert_contains "$(last_output)" "security unlock-keychain" "locked credential store shows the fix"
assert_eq "" "$(gh_calls)" "nothing reaches GitHub with a locked credential store"
cp "$TMP/bin/security.ok" "$TMP/bin/security"
# The environment provider is enough, with no credential store.
: >"$FAKE_CURL_LOG"
assert_status 0 "env provider notifies without the credential store or op" env FAKE_SECURITY_MISSING=1 \
  BOT_WEBHOOK_BOT_A_URL="https://env.example/h" BOT_WEBHOOK_BOT_A_SECRET="env-secret" \
  "$SCRIPTS/notify-bot.sh" bot-a 3 "https://x/c/1" --ask-id 20260117100100-1
assert_contains "$(cat "$FAKE_CURL_LOG")" 'url = "https://env.example/h"' "env webhook URL is used"

# --retry: only notifies again, with no new comment.
: >"$FAKE_GH_LOG"
: >"$PROCESS_EVENTS_FILE"
rm -f "$FAKE_CURL_COUNT"
assert_status 0 "retry notifies again" "$SCRIPTS/ask-bot.sh" --retry 20260117100100-1 --issue 3 --timeout 0
assert_not_contains "$(gh_calls)" "issue comment" "retry posts no new comment"
assert_eq "1" "$(cat "$FAKE_CURL_COUNT")" "retry calls the webhook"
assert_contains "$(cat "$FAKE_CURL_LOG")" '"comment_url":"u1"' "retry notifies with the original comment link"
assert_contains "$(cat "$FAKE_CURL_LOG")" '"reply_marker":"<!-- bot:bot-a reply-to:20260117100100-1 -->"' "retry keeps the ask id and bot"
retry_event="$(jq -c 'select(.event == "bot_ask")' "$PROCESS_EVENTS_FILE")"
assert_contains "$retry_event" '"retry":"1"' "retry event has retry=1"
assert_contains "$retry_event" '"ask_id":"20260117100100-1"' "retry event has the ask id"
assert_status 1 "retry without the comment fails" "$SCRIPTS/ask-bot.sh" --retry 20260117100177-7 --issue 3 --timeout 0
assert_contains "$(last_output)" "nothing posted" "retry error is clear"
: >"$FAKE_GH_LOG"
assert_status 1 "retry stops without a secret provider" env FAKE_SECURITY_MISSING=1 "$SCRIPTS/ask-bot.sh" --retry 20260117100100-1 --issue 3 --timeout 0
assert_not_contains "$(gh_calls)" "issue comment" "retry without a provider posts nothing"

# wait-reply warns early (stderr) about a question without the authorship header.
cat >"$TMP/loose.json" <<'J'
[[{"created_at":"2026-01-17T10:01:00Z","html_url":"q","body":"Pergunta solta\n\n<!-- ask:bot-a:20260117100100-1 -->"}]]
J
err="$(FAKE_COMMENTS="$TMP/loose.json" "$SCRIPTS/wait-reply.sh" 3 20260117100100-1 --timeout 0 --interval 0 2>&1 >/dev/null || true)"
assert_contains "$err" "has no authorship header" "wait-reply warns about a loose question"
assert_contains "$err" "ask-bot.sh --retry 20260117100100-1 --issue 3" "the warning names the fix"
cat >"$TMP/headed.json" <<'J'
[[{"created_at":"2026-01-17T10:01:00Z","html_url":"q","body":"**De:** a · **Para:** bot-a · **Pedido:** p · **Responde a:** —\n\nP\n\n<!-- ask:bot-a:20260117100100-1 -->"}]]
J
err="$(FAKE_COMMENTS="$TMP/headed.json" "$SCRIPTS/wait-reply.sh" 3 20260117100100-1 --timeout 0 --interval 0 2>&1 >/dev/null || true)"
assert_not_contains "$err" "warning" "no warning for a question with the header"
# Late warning: no reply after --warn-after, suggests --retry and keeps waiting (exit 3 at the timeout).
rc=0
err="$(FAKE_COMMENTS="$TMP/headed.json" "$SCRIPTS/wait-reply.sh" 3 20260117100100-1 --timeout 0 --interval 0 --warn-after 0 2>&1 >/dev/null)" || rc=$?
assert_eq "3" "$rc" "still times out after the late warning"
assert_contains "$err" "no reply to 20260117100100-1 on #3 after 0s" "late warning says the bot did not react"
assert_contains "$err" "ask-bot.sh --retry 20260117100100-1 --issue 3" "late warning suggests --retry"
err="$(FAKE_COMMENTS="$TMP/headed.json" "$SCRIPTS/wait-reply.sh" 3 20260117100100-1 --timeout 0 --interval 0 2>&1 >/dev/null || true)"
assert_not_contains "$err" "no reply to" "no late warning before --warn-after (default 180s)"

# Authorship header: the question and the follow-up start with De, Para, Pedido, Responde a.
rm -f "$TMP/posted"
AUTHOR_FROM="fase #34" "$SCRIPTS/ask-bot.sh" bot-a 3 "Opinião?" --timeout 0 >/dev/null 2>&1 || true
first_line="$(head -1 "$TMP/posted")"
assert_contains "$first_line" "**De:** fase #34 · **Para:** bot-a · **Pedido:** 2026" "question opens with the header"
assert_contains "$first_line" "**Responde a:** —" "a new question replies to nothing"
assert_contains "$(cat "$TMP/posted")" "<!-- ask:bot-a:" "question keeps the ask marker"
: >"$FAKE_GH_LOG"; : >"$PROCESS_EVENTS_FILE"; rm -f "$FAKE_CURL_COUNT" "$TMP/posted"
# The fixture only has the reply from before the append: the wait must not accept it.
assert_status 3 "append does not accept the reply posted before it" env AUTHOR_FROM="gerenciadora" "$SCRIPTS/ask-bot.sh" --append 20260117100100-1 "Mais um detalhe" --issue 3 --timeout 0
assert_not_contains "$(last_output)" "Texto ok" "append wait prints no old reply"
rm -f "$TMP/posted" "$FAKE_CURL_COUNT"
python3 - "$TMP/comments.json" "$TMP/comments-new.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d[0].append({"created_at": "2026-01-17T12:00:00Z", "html_url": "u9", "body": "Resposta nova <!-- bot:bot-a reply-to:20260117100100-1 -->"})
json.dump(d, open(sys.argv[2], "w"))
PY
assert_status 0 "append waits for a reply posted after it" env FAKE_COMMENTS="$TMP/comments-new.json" AUTHOR_FROM="gerenciadora" "$SCRIPTS/ask-bot.sh" --append 20260117100100-1 "Mais um detalhe" --issue 3 --timeout 0
assert_contains "$(last_output)" "Resposta nova" "append prints the new reply"
assert_not_contains "$(last_output)" "Texto ok" "append prints only the new reply"
# wait-reply --after <comment id> (the posted append has id 1 in the fake); no --after: as before.
export FAKE_COMMENTS="$TMP/comments-new.json"
assert_status 0 "wait-reply --after takes the reply posted after that comment" "$SCRIPTS/wait-reply.sh" 3 20260117100100-1 --timeout 0 --interval 0 --after 1
assert_not_contains "$(last_output)" "Texto ok" "--after skips the old reply"
assert_status 0 "wait-reply without --after takes the first reply" "$SCRIPTS/wait-reply.sh" 3 20260117100100-1 --timeout 0 --interval 0
assert_contains "$(last_output)" "Texto ok" "no --after keeps today's behavior"
assert_status 1 "wait-reply --after fails for an unknown comment" "$SCRIPTS/wait-reply.sh" 3 20260117100100-1 --timeout 0 --interval 0 --after 999
export FAKE_COMMENTS="$TMP/comments.json"
rm -f "$TMP/posted"
assert_status 1 "append without the question fails" "$SCRIPTS/ask-bot.sh" --append 20260117100177-7 "x" --issue 3 --timeout 0
assert_contains "$(last_output)" "nothing posted" "append error is clear"

# summarize-thread: creates, then edits in place.
printf '[[%s]]' "$(for i in $(seq 1 10); do printf '{"id":%d,"body":"c%d"},' "$i" "$i"; done | sed 's/,$//')" >"$TMP/comments.json"
assert_status 0 "needs summary after 10 comments" "$SCRIPTS/summarize-thread.sh" 3 --check
echo "Acordado: X" >"$TMP/summary.md"
assert_status 0 "creates the summary" "$SCRIPTS/summarize-thread.sh" 3 --summary-file "$TMP/summary.md"
assert_contains "$(last_output)" "created summary" "first time creates"
rm -f "$TMP/posted"  # the handler appends the posted comment to the list
echo '[[{"id":77,"body":"<!-- agreed-summary -->\nvelho"}]]' >"$TMP/comments.json"
assert_status 0 "updates the summary" "$SCRIPTS/summarize-thread.sh" 3 --summary-file "$TMP/summary.md"
assert_contains "$(gh_calls)" "api -X PATCH repos/owner/repo/issues/comments/77" "edits in place"

# ask_id format: a regex metacharacter is refused before any call.
for bad in 'a.*' 'x" or true' '1)(2'; do
  assert_status 2 "retry refuses ask id '$bad'" "$SCRIPTS/ask-bot.sh" --retry "$bad" --issue 3 --timeout 0
  assert_status 2 "wait-reply refuses ask id '$bad'" "$SCRIPTS/wait-reply.sh" 3 "$bad" --timeout 0 --interval 0
done
assert_contains "$(last_output)" "invalid ask id" "invalid ask id error is clear"
# The bots are data of the repository (.github/bots.tsv, or BOTS_FILE): the code names none.
printf '# slug\tname\treference\nsolo\tSolo Bot\t\n' >"$TMP/bots.tsv"
assert_status 1 "a bot missing from the bots file is refused" env BOTS_FILE="$TMP/bots.tsv" "$SCRIPTS/ask-bot.sh" bot-a 3 "Opinião?"
assert_contains "$(last_output)" "unknown bot: bot-a (see .github/bots.tsv)" "the error names the bots file"
: >"$FAKE_CURL_LOG"; : >"$FAKE_OP_LOG"
assert_status 0 "a bot with no reference is notified from the environment" env BOTS_FILE="$TMP/bots.tsv" FAKE_SECURITY_MISSING=1 \
  BOT_WEBHOOK_SOLO_URL=https://env.example/hook BOT_WEBHOOK_SOLO_SECRET=env-secret "$SCRIPTS/notify-bot.sh" solo 3 "https://x/c/1"
assert_eq "" "$(cat "$FAKE_OP_LOG")" "no reference, no op call"
rows="$(BOTS_FILE="$TMP/bots.tsv" bash -c 'source "$1/lib/common.sh"; label_rows "$2"' _ "$SCRIPTS" "$REPO/.github/labels.tsv")"
assert_contains "$rows" "ask:solo	ededed	O bot Solo Bot não foi avisado" "labels.tsv gets one ask:<slug> row per bot"
assert_not_contains "$rows" "<slug>" "no placeholder row is left"
assert_not_contains "$rows" "#" "comment lines are dropped"
assert_eq "$(grep -vc -e '^#' -e '<slug>' "$REPO/.github/labels.tsv")" "$(BOTS_FILE="$TMP/missing.tsv" bash -c 'source "$1/lib/common.sh"; label_rows "$2"' _ "$SCRIPTS" "$REPO/.github/labels.tsv" | wc -l | tr -d ' ')" "with no bots file the fixed labels remain"
assert_status 0 "label-issue accepts the ask label of a bot" env BOTS_FILE="$TMP/bots.tsv" "$SCRIPTS/label-issue.sh" 3 --add ask:solo --dry-run
assert_status 1 "label-issue refuses the ask label of an unknown bot" env BOTS_FILE="$TMP/bots.tsv" "$SCRIPTS/label-issue.sh" 3 --add ask:bot-a --dry-run
[ ! -e "$SCRIPTS/lib/bots.tsv" ] && ok || bad ".method/scripts/lib/ holds no bot list"

# An untracked file with a bot name is found before it is committed (#117).
# Built in a copy: the real .method/scripts/ is never written (#281).
bot_repo="$(make_repo)"
mkdir -p "$bot_repo/.method/scripts"
printf 'solo-bot-untracked\n' >"$bot_repo/.method/scripts/untracked-bot-name.txt"
bot_hits="$(cd "$bot_repo" && git ls-files -co --exclude-standard .method/scripts | tr '\n' '\0' | xargs -0 grep -nHF -- 'solo-bot-untracked' 2>/dev/null || true)"
assert_contains "$bot_hits" "untracked-bot-name.txt" "an untracked file with a forbidden token is found"

# Names of one repository (the list of docs/repo-notes.md, when the file exists) stay out of
# the method's code. An empty list must not make grep fail. A name that appears only
# outside the method paths is the project's and is not a hit.
repo_only_names() { # repo_only_names <file>
  awk '$0 == "## Nomes só deste repositório" { p = 1; next } p && /^## / { exit } p && /^- / { print }' "$1" | grep -oE '`[^`]+`' | tr -d '`' || true
}
name_hits() { # name_hits <repo> <names, one per line>
  local repo="$1" names="$2" name hits="" one paths
  [ -n "$names" ] || return 0
  # The set check-docs.sh scans: the design, AGENTS.md, skills, and the method's scripts
  # and hooks. STATE, BOTS, CONTEXT and the ADRs belong to the repository and may cite its names.
  paths="$(method_existing "$repo" | grep -E '^(docs/process-design\.md|AGENTS\.md|\.claude/(skills|hooks)|\.githooks|\.method/scripts)$' || true)"
  [ -n "$paths" ] || return 0
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    # shellcheck disable=SC2086
    one="$(cd "$repo" && git grep -nI --untracked -F -e "$name" -- $paths ':!.method/scripts/tests/template' ':!.github/bots.tsv' ':!docs/repo-notes.md' 2>/dev/null || true)"
    hits="$hits$one"
  done <<<"$names"
  printf '%s' "$hits" | cut -c1-120
}
if [ -f "$REPO/docs/repo-notes.md" ]; then
  assert_eq "" "$(name_hits "$REPO" "$(repo_only_names "$REPO/docs/repo-notes.md")")" "the method's code cites no repository-only name"
fi
empty_repo="$(make_repo)"
mkdir -p "$empty_repo/.method/scripts" "$empty_repo/docs" "$empty_repo/.github/workflows"
echo 'method' >"$empty_repo/.method/scripts/keep.sh"
printf '# Notas\n\n## Nomes só deste repositório\n\n(nenhum nome)\n' >"$empty_repo/docs/repo-notes.md"
printf 'name: build\nruns-on: project-runner-99\n' >"$empty_repo/.github/workflows/build.yml"
git -C "$empty_repo" add .method docs .github && git -C "$empty_repo" commit --quiet -m "chore: fixture"
assert_eq "" "$(name_hits "$empty_repo" "$(repo_only_names "$empty_repo/docs/repo-notes.md")")" "an empty name list does not fail the scan"
printf '\n- `project-runner-99`\n' >>"$empty_repo/docs/repo-notes.md"
assert_eq "" "$(name_hits "$empty_repo" "$(repo_only_names "$empty_repo/docs/repo-notes.md")")" "a name only outside the method is not a hit"
mkdir -p "$empty_repo/docs/adr"
echo 'project-runner-99' >"$empty_repo/docs/STATE.md"
echo 'project-runner-99' >"$empty_repo/docs/BOTS.md"
echo 'project-runner-99' >"$empty_repo/docs/adr/0001-x.md"
assert_eq "" "$(name_hits "$empty_repo" "$(repo_only_names "$empty_repo/docs/repo-notes.md")")" "a name in STATE, BOTS or an ADR is not a hit"
echo 'project-runner-99' >>"$empty_repo/.method/scripts/keep.sh"
assert_contains "$(name_hits "$empty_repo" "$(repo_only_names "$empty_repo/docs/repo-notes.md")")" ".method/scripts/keep.sh" "a name inside a method file is a hit"

finish
