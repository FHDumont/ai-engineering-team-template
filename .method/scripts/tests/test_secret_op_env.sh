#!/usr/bin/env bash
# Tests of the `op read` environment in .method/scripts/lib/secret.sh: no request to the password
# manager desktop app (OP_BIOMETRIC_UNLOCK_ENABLED=false) and the token only in the command.
# security and op are stubs on PATH; nothing touches the real credential store or password manager.
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

mkdir -p "$TMP/bin"
cat >"$TMP/bin/security" <<'F'
#!/usr/bin/env bash
echo "TOKEN-env-check-77"
F
# Fake op: records the environment it received and only answers with the token and no biometrics.
cat >"$TMP/bin/op" <<'F'
#!/usr/bin/env bash
echo "bio=${OP_BIOMETRIC_UNLOCK_ENABLED-unset} token=${OP_SERVICE_ACCOUNT_TOKEN-unset}" >>"$FAKE_OP_ENV_LOG"
[ "${OP_BIOMETRIC_UNLOCK_ENABLED-}" = false ] || { echo "[ERROR] would prompt the desktop app" >&2; exit 1; }
[ "${OP_SERVICE_ACCOUNT_TOKEN-}" = "TOKEN-env-check-77" ] || { echo "no token" >&2; exit 1; }
echo "https://op.example/hook"
F
chmod +x "$TMP/bin/security" "$TMP/bin/op"
export PATH="$TMP/bin:$PATH"
export FAKE_OP_ENV_LOG="$TMP/op-env.log"
: >"$FAKE_OP_ENV_LOG"
export PROCESS_ENV_FILE="$TMP/none.env"
export USER="tester"
# The caller tries to force biometrics: secret.sh must override it in the command.
export OP_BIOMETRIC_UNLOCK_ENABLED=true
unset OP_SERVICE_ACCOUNT_TOKEN MY_SECRET

# shellcheck source=.method/scripts/lib/secret.sh
source "$SCRIPTS/lib/secret.sh"

rc=0
secret_get MY_SECRET "op://Vault/item/url" >"$TMP/get.out" 2>"$TMP/get.err" || rc=$?
assert_eq "0" "$rc" "op read succeeds with the biometric prompt off and the token set"
assert_eq "https://op.example/hook" "$(cat "$TMP/get.out")" "value is printed"
assert_eq "bio=false token=TOKEN-env-check-77" "$(cat "$FAKE_OP_ENV_LOG")" "op sees OP_BIOMETRIC_UNLOCK_ENABLED=false and the token"
assert_eq "true" "$OP_BIOMETRIC_UNLOCK_ENABLED" "caller's OP_BIOMETRIC_UNLOCK_ENABLED is untouched"
assert_eq "" "${OP_SERVICE_ACCOUNT_TOKEN:-}" "token is not left in the shell"
assert_not_contains "$(env)" "TOKEN-env-check-77" "token is not exported"
assert_not_contains "$(cat "$TMP/get.out" "$TMP/get.err")" "TOKEN-env-check-77" "token is not printed"

# op_ready (vault list asks for the desktop app) no longer exists.
# shellcheck source=.method/scripts/lib/common.sh
source "$SCRIPTS/lib/common.sh"
rc=0
declare -F op_ready >/dev/null || rc=$?
assert_eq "1" "$rc" "op_ready is gone from common.sh"

# settings.json denies op and direct reading of the credential store.
settings="$(cat "$REPO/.claude/settings.json")"
assert_contains "$settings" '"Bash(op *)"' "settings.json denies op"
assert_contains "$settings" '"Bash(security find-generic-password*)"' "settings.json denies find-generic-password"
assert_not_contains "$settings" "CLAUDE_CODE_SUBAGENT_EFFORT" "settings.json has no default subagent effort"
finish
