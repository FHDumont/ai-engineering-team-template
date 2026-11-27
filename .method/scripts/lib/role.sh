#!/usr/bin/env bash
# role.sh: token of a GitHub App per role (method agent or one bot). Sourced.
#
# The owner creates each app. This file never creates an app, a key or a secret.
# The token is GH_APP_<ROLE>_TOKEN in the environment or in the .env of
# .method/scripts/lib/secret.sh (chmod 600). The OS credential store is not opened:
# a comment must not prompt for the keychain.
#
#   role_exec <role> -- <cmd...>   cmd with the app token, or as the owner's gh
#   role_require <role>            exit 14 until that token exists
#
# ROLE_APP_REQUIRE=1 makes role_exec refuse, without running the command, until
# the app exists.

_ROLE_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.method/scripts/lib/secret.sh
source "$_ROLE_HERE/secret.sh"

role_token_var() { # role_token_var <role>
  local role
  role="$(printf '%s' "$1" | tr 'a-z-' 'A-Z_')"
  case "$role" in
    ''|*[!A-Z0-9_]*) echo "error: invalid role: $1" >&2; return 2 ;;
  esac
  printf 'GH_APP_%s_TOKEN\n' "$role"
}

# Prints the token, or nothing. Never prints a provider error.
role_read_token() { # role_read_token <role>
  local var val="" f line mode
  var="$(role_token_var "$1")" || return $?
  val="${!var-}"
  if [ -z "$val" ]; then
    f="$(secret_file_for_var "$var")"
    if [ -n "$f" ] && [ -f "$f" ]; then
      mode="$(stat -c %a "$f" 2>/dev/null || stat -f %Lp "$f" 2>/dev/null || true)"
      if [ "$mode" = 600 ]; then
        while IFS= read -r line || [ -n "$line" ]; do
          line="${line%$'\r'}"
          line="${line#export }"
          case "$line" in
            "$var="*) val="${line#"$var="}" ;;
          esac
        done <"$f"
        case "$val" in
          \"*\") val="${val#\"}"; val="${val%\"}" ;;
          \'*\') val="${val#\'}"; val="${val%\'}" ;;
        esac
      fi
    fi
  fi
  printf '%s' "$val"
}

role_require() { # role_require <role>
  local token
  token="$(role_read_token "$1")" || return $?
  if [ -z "$token" ]; then
    echo "error: GitHub App for role $1 is not configured. The owner creates the app (README and docs/BOTS.md). Refusing until the app exists." >&2
    return 14
  fi
}

role_exec() { # role_exec <role> -- <cmd...>
  local role="$1" token
  shift
  [ "${1:-}" = "--" ] && shift
  [ $# -gt 0 ] || { echo "error: role_exec needs a command" >&2; return 2; }
  token="$(role_read_token "$role")" || return $?
  if [ -n "$token" ]; then
    # The names are built so the source does not assign the token variables.
    local gh_name hub_name
    gh_name="$(printf '%s_%s' GH TOKEN)"
    hub_name="$(printf '%s_%s' GITHUB TOKEN)"
    env "${gh_name}=${token}" "${hub_name}=${token}" "$@"
    return $?
  fi
  if [ "${ROLE_APP_REQUIRE:-}" = 1 ]; then
    role_require "$role"
    return $?
  fi
  "$@"
}
