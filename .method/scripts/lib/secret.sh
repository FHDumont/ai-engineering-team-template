#!/usr/bin/env bash
# Reads the bots' secrets without ever prompting a desktop app.
# Load with: source "$HERE/lib/secret.sh"   (not meant to be executed directly)
#
# Lookup order (the first provider that has the secret wins):
#   1. an environment variable with the requested name (CI);
#   2. optional: a password manager service account (CLI `op`). Its token comes
#      from the OS credential store (macOS `security`, service
#      op-service-account, account $USER) and exists only in the environment of
#      `op read` (together with OP_BIOMETRIC_UNLOCK_ENABLED=false, so op never
#      talks to the desktop app); it is never exported, printed or written;
#   3. default: a .env file outside the repo (PROCESS_ENV_FILE, default
#      ~/.<repo-slug>/.env, the slug being the repo name in `git remote`), only
#      when it is chmod 600; read line by line, never run with `source`.
# Never calls `op vault list`, `op whoami` or `op signin` (they force the desktop app).
#
# Functions:
#   secret_env_file                            path of this repo's .env
#   secret_get <VAR_NAME> [<op://reference>]   prints the value on stdout
#   secret_ready <VAR_NAME>...                 checks there is a provider, prints no secret
#   bot_webhook_var <slug> <url|secret>        variable name of one webhook field
# Return codes (message on stderr on every error):
#   0 ok; 10 no provider configured; 11 credential store locked;
#   12 provider configured, but without this secret; 13 .env with open permissions.
# Tests replace `security` and `op` with stubs in PATH and the .env with PROCESS_ENV_FILE.

SECRET_NONE=10 SECRET_LOCKED=11 SECRET_MISSING=12 SECRET_BAD_PERMS=13
SECRET_STORE_SERVICE="op-service-account"

# Repo name (no owner, no .git) from the `git remote` origin; with no remote,
# the folder name of the main checkout.
secret_repo_slug() {
  local url dir
  url="$(git remote get-url origin 2>/dev/null || true)"
  if [ -n "$url" ]; then
    url="${url%/}"; url="${url%.git}"; url="${url##*[/:]}"
    [ -z "$url" ] || { printf '%s\n' "$url"; return 0; }
  fi
  dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [ -n "$dir" ]; then dir="$(dirname "$dir")"; else dir="$PWD"; fi
  basename "$dir"
}

# Path of the .env (outside the repo): PROCESS_ENV_FILE or ~/.<repo-slug>/.env.
# The legacy ~/.config/<repo-slug>/.env is used only while the new one is missing.
secret_env_file() {
  local slug
  if [ -n "${PROCESS_ENV_FILE:-}" ]; then
    printf '%s\n' "$PROCESS_ENV_FILE"
    return
  fi
  slug="$(secret_repo_slug)"
  if [ ! -e "$HOME/.$slug/.env" ] && [ -e "$HOME/.config/$slug/.env" ]; then
    printf '%s/.config/%s/.env\n' "$HOME" "$slug"
  else
    printf '%s/.%s/.env\n' "$HOME" "$slug"
  fi
}

# Variable name of one webhook field of a bot: BOT_WEBHOOK_<SLUG>_<FIELD>.
bot_webhook_var() {
  printf 'BOT_WEBHOOK_%s_%s\n' \
    "$(printf '%s' "$1" | tr 'a-z-' 'A-Z_')" "$(printf '%s' "$2" | tr 'a-z' 'A-Z')"
}

# Error messages (stderr).
_secret_err() { printf 'error: %s\n' "$*" >&2; }
# Hint about the service account token (empty or truncated), said only when nothing works.
_SECRET_SA_HINT=""
_secret_hint() { [ -z "$_SECRET_SA_HINT" ] || _secret_err "$_SECRET_SA_HINT"; }
_secret_empty_hint() {
  printf '%s' "the credential store item $SECRET_STORE_SERVICE is empty; store the service account token again or use the .env (see docs/BOTS.md)"
}
_secret_msg_none() {
  _secret_err "no secret provider configured. Set the variable in the environment, or create $(secret_env_file) with chmod 600 (scripts/init-env.sh), or store a password manager service account token in the OS credential store under the service $SECRET_STORE_SERVICE (see docs/BOTS.md)"
}
_secret_msg_locked() {
  _secret_err "the OS credential store is locked (User interaction is not allowed). Unlock it and run again (macOS: security unlock-keychain)"
}

# Value of the environment variable (indirect name). Empty counts as absent.
_secret_from_env() {
  local v="${!1:-}"
  [ -n "$v" ] || return 1
  printf '%s\n' "$v"
}

# Service account token, read from the OS credential store. 0: prints the
# token; 1: not configured (no `security`, no `op` or no item); 3: empty item;
# 11: store locked. On success `security -w` writes nothing to stderr, so the
# 2>&1 only mixes in errors.
_secret_sa_token() {
  command -v security >/dev/null 2>&1 || return 1
  command -v op >/dev/null 2>&1 || return 1
  local out rc=0
  out="$(security find-generic-password -s "$SECRET_STORE_SERVICE" -a "${USER:-$(id -un)}" -w 2>&1)" || rc=$?
  if [ "$rc" != 0 ]; then
    if [ "$rc" = 36 ]; then return "$SECRET_LOCKED"; fi
    case "$out" in *"User interaction is not allowed"*) return "$SECRET_LOCKED" ;; esac
    return 1
  fi
  # Empty item (a write that failed): 3, so the caller can explain.
  [ -n "$out" ] || return 3
  printf '%s' "$out"
}

# File permissions in octal (GNU and BSD stat).
_secret_mode() {
  local m
  m="$(stat -c %a "$1" 2>/dev/null)" || m="$(stat -f %Lp "$1" 2>/dev/null)" || return 1
  printf '%s' "$m"
}

# Checks that the .env exists and has closed permissions. 0 ok; 1 missing; 13 too open.
_secret_env_file_check() {
  local f mode
  f="$(secret_env_file)"
  [ -f "$f" ] || return 1
  if [ -z "${PROCESS_ENV_FILE:-}" ]; then
    case "$f" in
      "$HOME"/.config/*/.env) _secret_err "warning: using the legacy $f; move it to $HOME/.$(secret_repo_slug)/.env" ;;
    esac
  fi
  mode="$(_secret_mode "$f")" || mode=""
  case "$mode" in
    ''|*[!0-7]*) _secret_err "cannot read the permissions of $f"; return "$SECRET_BAD_PERMS" ;;
  esac
  if [ $((8#$mode & 63)) -ne 0 ]; then
    _secret_err "$f has permissions $mode, too open for secrets; run: chmod 600 $f"
    return "$SECRET_BAD_PERMS"
  fi
  return 0
}

# Reads NAME=value from the .env without executing it. Accepts `export NAME=value` and surrounding quotes.
_secret_from_env_file() {
  local name="$1" f line val=""
  f="$(secret_env_file)"
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    line="${line#export }"
    case "$line" in
      "$name="*) val="${line#"$name="}" ;;
    esac
  done <"$f"
  case "$val" in
    \"*\") val="${val#\"}"; val="${val%\"}" ;;
    \'*\') val="${val#\'}"; val="${val%\'}" ;;
  esac
  [ -n "$val" ] || return 1
  printf '%s\n' "$val"
}

# Names (never values) of the BOT_WEBHOOK_* keys in the .env, comma separated.
_secret_webhook_keys() {
  local f line k out=""
  f="$(secret_env_file)"
  [ -f "$f" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#export }"
    case "$line" in
      BOT_WEBHOOK_*=*) k="${line%%=*}"; out="${out:+$out, }$k" ;;
    esac
  done <"$f"
  printf '%s' "$out"
}

_secret_get() {
  local name="$1" ref="${2:-}" v tok="" rc configured=0 operr keys
  _SECRET_SA_HINT=""
  case "$name" in
    ''|[0-9]*|*[!A-Za-z0-9_]*) _secret_err "invalid secret name: $name"; return 2 ;;
  esac

  # 1. environment
  if _secret_from_env "$name"; then return 0; fi

  # 2. password manager service account (optional)
  if [ -n "$ref" ]; then
    rc=0
    tok="$(_secret_sa_token)" || rc=$?
    if [ "$rc" = "$SECRET_LOCKED" ]; then _secret_msg_locked; return "$SECRET_LOCKED"; fi
    [ "$rc" != 3 ] || _SECRET_SA_HINT="$(_secret_empty_hint)"
    if [ "$rc" = 0 ]; then
      configured=1
      # The token and OP_BIOMETRIC_UNLOCK_ENABLED=false exist only in the
      # environment of this command: with the token, op talks straight to the
      # API and never to the desktop app (no biometric prompt on screen). The
      # stderr of op is read only to recognize an invalid token (op does not
      # repeat the token in the error).
      operr="$(mktemp "${TMPDIR:-/tmp}/secret.XXXXXX")" || operr=/dev/null
      if v="$(OP_BIOMETRIC_UNLOCK_ENABLED=false OP_SERVICE_ACCOUNT_TOKEN="$tok" op read "$ref" 2>"$operr")" && [ -n "$v" ]; then
        tok=""
        [ "$operr" = /dev/null ] || rm -f "$operr"
        printf '%s\n' "$v"
        return 0
      fi
      tok=""
      if [ "$operr" != /dev/null ]; then
        # The interactive `security -w` prompt cuts the password at 128 characters: truncated token.
        grep -q 'DecodeSACredentials' "$operr" 2>/dev/null &&
          _SECRET_SA_HINT="the service account token in the credential store is invalid or truncated (the interactive security -w prompt cuts at 128 characters); store it again or use the .env (see docs/BOTS.md)"
        rm -f "$operr"
      fi
    fi
  fi

  # 3. .env outside the repo (default)
  rc=0
  _secret_env_file_check || rc=$?
  if [ "$rc" = "$SECRET_BAD_PERMS" ]; then return "$SECRET_BAD_PERMS"; fi
  if [ "$rc" = 0 ]; then
    configured=1
    if _secret_from_env_file "$name"; then return 0; fi
  fi

  if [ "$configured" = 0 ]; then _secret_msg_none; _secret_hint; return "$SECRET_NONE"; fi
  _secret_err "secret $name not found in any configured provider"
  case "$name" in
    BOT_WEBHOOK_*)
      keys="$(_secret_webhook_keys)"
      _secret_err "expected name: $name; BOT_WEBHOOK_* keys in the .env: ${keys:-none}" ;;
  esac
  _secret_hint
  return "$SECRET_MISSING"
}

# Reads a secret and prints it on stdout (one line). See the codes in the header.
# xtrace is turned off in here so the caller's `set -x` does not show the token.
secret_get() {
  local _x=0 _rc=0
  case "$-" in *x*) _x=1; set +x ;; esac
  _secret_get "$@" || _rc=$?
  if [ "$_x" = 1 ]; then set -x; fi
  return "$_rc"
}

_secret_ready() {
  local n rc=0 sa
  for n in "$@"; do
    if [ -n "${!n:-}" ]; then return 0; fi
  done
  _secret_sa_token >/dev/null || rc=$?
  sa="$rc"
  if [ "$rc" = "$SECRET_LOCKED" ]; then _secret_msg_locked; return "$SECRET_LOCKED"; fi
  if [ "$rc" = 0 ]; then return 0; fi
  rc=0
  _secret_env_file_check || rc=$?
  if [ "$rc" = 0 ]; then return 0; fi
  if [ "$rc" = "$SECRET_BAD_PERMS" ]; then return "$SECRET_BAD_PERMS"; fi
  _secret_msg_none
  [ "$sa" != 3 ] || _secret_err "$(_secret_empty_hint)"
  return "$SECRET_NONE"
}

# Checks that some provider exists (without reading or printing a real secret).
# The names are the environment variables that count as a provider. Same codes as secret_get.
secret_ready() {
  local _x=0 _rc=0
  case "$-" in *x*) _x=1; set +x ;; esac
  _secret_ready "$@" || _rc=$?
  if [ "$_x" = 1 ]; then set -x; fi
  return "$_rc"
}
