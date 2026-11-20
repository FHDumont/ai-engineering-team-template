#!/usr/bin/env bash
# Tests of scripts/lib/secret.sh: environment, Service Account, .env, no provider and locked credential store.
# security and op are stubs on PATH; nothing touches the real credential store, password manager or .env.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

mkdir -p "$TMP/bin"
# Fake security: returns the token, or fails like the real one (missing item / locked credential store).
cat >"$TMP/bin/security" <<'F'
#!/usr/bin/env bash
echo "$*" >>"$FAKE_SECURITY_LOG"
case "${FAKE_SECURITY_MODE:-ok}" in
  ok) echo "TOKEN-never-leak-42" ;;
  empty) echo "" ;;
  short) echo "TOKEN-truncated-128" ;;
  missing) echo "security: item not found" >&2; exit 44 ;;
  locked) echo "security: User interaction is not allowed." >&2; exit 36 ;;
esac
F
# Fake op: only answers if the token arrives in the environment of the command itself.
cat >"$TMP/bin/op" <<'F'
#!/usr/bin/env bash
echo "$*" >>"$FAKE_OP_LOG"
if [ "${OP_SERVICE_ACCOUNT_TOKEN:-}" = "TOKEN-truncated-128" ]; then
  echo "[ERROR] error initializing client: Validation: (failed to session.DecodeSACredentials)" >&2; exit 1
fi
[ "${OP_SERVICE_ACCOUNT_TOKEN:-}" = "TOKEN-never-leak-42" ] || { echo "no token" >&2; exit 1; }
[ "$1" = read ] || exit 1
case "$2" in
  "op://Vault With Spaces/item/url") echo "https://op.example/hook" ;;
  *) echo "[ERROR] item not found" >&2; exit 1 ;;
esac
F
chmod +x "$TMP/bin/security" "$TMP/bin/op"
export PATH="$TMP/bin:$PATH"
export FAKE_SECURITY_LOG="$TMP/security.log" FAKE_OP_LOG="$TMP/op.log"
: >"$FAKE_SECURITY_LOG"; : >"$FAKE_OP_LOG"
export PROCESS_ENV_FILE="$TMP/none.env"
unset OP_SERVICE_ACCOUNT_TOKEN MY_SECRET
export USER="tester"

# shellcheck source=scripts/lib/secret.sh
source "$SCRIPTS/lib/secret.sh"

# get <expected code> <description> <name> [ref]: runs secret_get and keeps stdout/stderr/status.
get() {
  local want="$1" what="$2" rc=0
  shift 2
  secret_get "$@" >"$TMP/get.out" 2>"$TMP/get.err" || rc=$?
  if [ "$rc" = "$want" ]; then ok; else bad "$what (status $rc, expected $want): $(head -c 300 "$TMP/get.err")"; fi
}

# 1. The environment wins over everything and calls neither security nor op.
MY_SECRET="from-env" get 0 "env provider" MY_SECRET "op://Vault With Spaces/item/url"
assert_eq "from-env" "$(cat "$TMP/get.out")" "env value is printed"
assert_eq "" "$(cat "$FAKE_SECURITY_LOG")" "env provider does not touch security"
assert_eq "" "$(cat "$FAKE_OP_LOG")" "env provider does not call op"

# 2. Service Account: credential store token only in the op environment.
get 0 "service account provider" MY_SECRET "op://Vault With Spaces/item/url"
assert_eq "https://op.example/hook" "$(cat "$TMP/get.out")" "op value is printed"
assert_contains "$(cat "$FAKE_SECURITY_LOG")" "find-generic-password -s op-service-account -a tester -w" "reads the token from the credential store"
assert_eq "read op://Vault With Spaces/item/url" "$(cat "$FAKE_OP_LOG")" "op gets only read and the reference"
assert_not_contains "$(cat "$TMP/get.out" "$TMP/get.err")" "TOKEN-never-leak-42" "token is not in stdout or stderr"
assert_eq "" "${OP_SERVICE_ACCOUNT_TOKEN:-}" "token is not left in the caller's environment"
assert_not_contains "$(env)" "TOKEN-never-leak-42" "token is not in any exported variable"
# Not even with xtrace on in the caller.
rc=0
bash -x -c 'source "$1/lib/secret.sh"; secret_get MY_SECRET "op://Vault With Spaces/item/url"' _ "$SCRIPTS" >"$TMP/x.out" 2>"$TMP/x.err" || rc=$?
assert_eq "0" "$rc" "works under set -x"
assert_not_contains "$(cat "$TMP/x.out" "$TMP/x.err")" "TOKEN-never-leak-42" "token does not leak under set -x"
# Item that op cannot find: provider configured, secret missing (12).
get 12 "missing item" MY_SECRET "op://Vault With Spaces/other/url"
assert_contains "$(cat "$TMP/get.err")" "not found" "explains the missing secret"
assert_not_contains "$(cat "$TMP/get.err")" "TOKEN-never-leak-42" "token is not in the error"

# 3. .env: 600 accepted, 644 refused; read without executing.
export FAKE_SECURITY_MODE=missing
cat >"$TMP/p.env" <<'E'
# comment
OTHER=x
export MY_SECRET="quoted value"
INJECT=$(touch "$TMP_PWNED")
E
export TMP_PWNED="$TMP/pwned"
export PROCESS_ENV_FILE="$TMP/p.env"
chmod 600 "$TMP/p.env"
get 0 ".env with 600" MY_SECRET
assert_eq "quoted value" "$(cat "$TMP/get.out")" ".env value is read without quotes"
get 12 "name absent from the .env" ABSENT_NAME
[ ! -e "$TMP/pwned" ] && ok || bad ".env must not be executed"
chmod 644 "$TMP/p.env"
get 13 ".env with 644" MY_SECRET
assert_contains "$(cat "$TMP/get.err")" "chmod 600" "refuses open permissions and says how to fix"
assert_eq "" "$(cat "$TMP/get.out")" "nothing is printed from an open .env"
chmod 640 "$TMP/p.env"
get 13 ".env with 640" MY_SECRET
chmod 400 "$TMP/p.env"
get 0 ".env with 400" MY_SECRET

# 4. No provider.
export PROCESS_ENV_FILE="$TMP/none.env"
get 10 "no provider" MY_SECRET "op://Vault With Spaces/item/url"
assert_contains "$(cat "$TMP/get.err")" "no secret provider configured" "clear message"
assert_contains "$(cat "$TMP/get.err")" "chmod 600" "message mentions the .env option"
assert_status 10 "secret_ready with no provider" bash -c 'source "$1/lib/secret.sh"; secret_ready A B' _ "$SCRIPTS"

# 5. Locked credential store.
export FAKE_SECURITY_MODE=locked
get 11 "locked credential store" MY_SECRET "op://Vault With Spaces/item/url"
assert_contains "$(cat "$TMP/get.err")" "security unlock-keychain" "locked credential store shows the fix"
assert_status 11 "secret_ready with a locked credential store" bash -c 'source "$1/lib/secret.sh"; secret_ready A' _ "$SCRIPTS"
assert_contains "$(last_output)" "security unlock-keychain" "secret_ready shows the fix"

# 6. secret_ready: environment and Service Account are enough, without printing the secret.
export FAKE_SECURITY_MODE=ok
assert_status 0 "secret_ready with the Service Account" bash -c 'source "$1/lib/secret.sh"; secret_ready A' _ "$SCRIPTS"
assert_not_contains "$(last_output)" "TOKEN-never-leak-42" "secret_ready prints no token"
export FAKE_SECURITY_MODE=missing
assert_status 0 "secret_ready with an env var" env A=1 bash -c 'source "$1/lib/secret.sh"; secret_ready A' _ "$SCRIPTS"

# 7. Empty credential store item (a write that failed): does not call op and explains.
export FAKE_SECURITY_MODE=empty
: >"$FAKE_OP_LOG"
get 10 "empty credential store item" MY_SECRET "op://Vault With Spaces/item/url"
assert_contains "$(cat "$TMP/get.err")" "op-service-account is empty" "empty item is explained"
assert_eq "" "$(cat "$FAKE_OP_LOG")" "op is not called with an empty token"
assert_status 10 "secret_ready with an empty credential store item" bash -c 'source "$1/lib/secret.sh"; secret_ready A' _ "$SCRIPTS"
assert_contains "$(last_output)" "op-service-account is empty" "secret_ready explains the empty item"

# 8. Truncated token (security -w prompt at 128 characters): op does not decode it.
export FAKE_SECURITY_MODE=short
get 12 "truncated token" MY_SECRET "op://Vault With Spaces/item/url"
assert_contains "$(cat "$TMP/get.err")" "invalid or truncated" "truncated token is explained"
assert_not_contains "$(cat "$TMP/get.out" "$TMP/get.err")" "TOKEN-truncated-128" "truncated token does not leak"
export FAKE_SECURITY_MODE=missing

# 9. Invalid variable name and webhook name.
get 2 "invalid name" "BAD NAME"
assert_eq "BOT_WEBHOOK_MY_BOT_URL" "$(bot_webhook_var my-bot url)" "webhook variable name"
finish
