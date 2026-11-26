#!/usr/bin/env bash
# GitHub App token per role (issue #35). A fake gh records GH_TOKEN.
# The owner creates the app; nothing here creates one.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

cat >"$TMP/handler.sh" <<'H'
case "$*" in
  "issue comment"*) cat >"$TMP/posted"; echo "https://github.com/owner/repo/issues/3#issuecomment-1" ;;
  "api repos/owner/repo/issues/comments/1"*) cat "$TMP/posted" 2>/dev/null || true ;;
  "issue edit"*"--add-label"*) echo ask:bot-a >>"$TMP/labels" ;;
  "issue view"*"--json labels"*) cat "$TMP/labels" 2>/dev/null || true ;;
esac
H
export TMP
use_fake_gh "$TMP/handler.sh"
mv "$TMP/bin/gh" "$TMP/bin/gh.real"
cat >"$TMP/bin/gh" <<EOF
#!/bin/sh
printf '%s\n' "\${GH_TOKEN-unset}" >>"$TMP/tokens"
exec "$TMP/bin/gh.real" "\$@"
EOF
chmod +x "$TMP/bin/gh"
cat >"$TMP/bin/curl" <<'EOF'
#!/bin/sh
exit 22
EOF
chmod +x "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH"
export PROCESS_ENV_FILE="$TMP/none.env"
: >"$PROCESS_ENV_FILE"
chmod 600 "$PROCESS_ENV_FILE"
export BOT_WEBHOOK_BOT_A_URL="https://hooks.example/bot" BOT_WEBHOOK_BOT_A_SECRET="s3cr3t-value"
export NOTIFY_RETRY_WAIT=0
unset GH_APP_METHOD_TOKEN ROLE_APP_REQUIRE
use_owner_token() {
  local n
  n="$(printf '%s_%s' GH TOKEN)"
  export "${n}=owner-token"
}

ask() {
  : >"$TMP/tokens"
  : >"$TMP/labels"
  "$SCRIPTS/ask-bot.sh" bot-a 3 "pergunta" >/dev/null 2>&1 || true
}

use_owner_token
export GH_APP_METHOD_TOKEN="app-token-35"
ask
assert_eq "app-token-35" "$(head -1 "$TMP/tokens")" "a configured app token is what gh sees on the comment"

unset GH_APP_METHOD_TOKEN
ask
assert_eq "owner-token" "$(head -1 "$TMP/tokens")" "without an app token the comment uses the owner's gh"

export ROLE_APP_REQUIRE=1
: >"$FAKE_GH_LOG"
assert_status 14 "refuses until the app exists" "$SCRIPTS/ask-bot.sh" bot-a 3 "pergunta"
assert_contains "$(last_output)" "Refusing until the app exists" "the refusal names the missing app"
assert_not_contains "$(gh_calls)" "issue comment" "a missing app posts nothing"
unset ROLE_APP_REQUIRE

# open-issue.sh creates the issue with the same two paths.
cat >"$TMP/handler.sh" <<'H'
case "$1 $2" in
  "issue create") echo "https://github.com/owner/repo/issues/9" ;;
  "issue view") printf 'type:finding\narea:docs\nsize:small\n' ;;
  "auth status") printf "  - Token scopes: 'project', 'repo'\n" ;;
  "variable list") ;;
esac
H
export FAKE_GH_HANDLER="$TMP/handler.sh"
use_owner_token
export GH_APP_METHOD_TOKEN="app-token-35"
: >"$TMP/tokens"
"$SCRIPTS/open-issue.sh" --type finding --title x --section Objetivo o \
  --section "Pronto quando" "- [ ] y" --section "Arquivos ou áreas afetadas" "docs/" \
  --section "Achado em" "PR #6 · tamanho: small" >/dev/null 2>&1 || true
assert_eq "app-token-35" "$(head -1 "$TMP/tokens")" "open-issue uses the app token when it is set"
unset GH_APP_METHOD_TOKEN
: >"$TMP/tokens"
"$SCRIPTS/open-issue.sh" --type finding --title x --section Objetivo o \
  --section "Pronto quando" "- [ ] y" --section "Arquivos ou áreas afetadas" "docs/" \
  --section "Achado em" "PR #6 · tamanho: small" >/dev/null 2>&1 || true
assert_eq "owner-token" "$(head -1 "$TMP/tokens")" "open-issue uses the owner's gh without an app token"

# close-phase.sh comments go through the same role.
assert_contains "$(cat "$SCRIPTS/close-phase.sh")" "role_exec method" "close-phase comments as the method role"

finish
