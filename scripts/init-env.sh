#!/usr/bin/env bash
#: init-env.sh: create the repo's .env (outside git) with empty keys.
#:
#: Usage: init-env.sh [<bot-slug>...]   (default: every bot of .github/bots.tsv)
#:
#: Creates ~/.<repo-slug>/ with chmod 700 and the .env with chmod 600 (or the
#: path in PROCESS_ENV_FILE), with empty BOT_WEBHOOK_<SLUG>_URL= and
#: BOT_WEBHOOK_<SLUG>_SECRET=. Never reads or writes values and never
#: overwrites an existing .env: it only appends the missing keys. The repo
#: owner pastes the values in an editor. Prints only the file path.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=scripts/lib/secret.sh
source "$HERE/lib/secret.sh"
case "${1:-}" in -h|--help) print_help "$0"; exit 0 ;; esac

slugs=("$@")
if [ "${#slugs[@]}" = 0 ]; then
  while read -r s; do [ -z "$s" ] || slugs+=("$s"); done <<<"$(bot_slugs)"
fi
[ "${#slugs[@]}" -gt 0 ] || die "no bot given and none in .github/bots.tsv" 2

# Always writes to the new path, never to the legacy one.
file="${PROCESS_ENV_FILE:-$HOME/.$(secret_repo_slug)/.env}"
dir="$(dirname "$file")"
[ -d "$dir" ] || { mkdir -p "$dir"; chmod 700 "$dir"; }
[ -f "$file" ] || { : >"$file"; }
chmod 600 "$file"

for s in "${slugs[@]}"; do
  case "$s" in ''|*[!a-z0-9-]*) die "invalid bot slug: $s" 2 ;; esac
  for field in url secret; do
    var="$(bot_webhook_var "$s" "$field")"
    grep -qE "^(export )?$var=" "$file" || printf '%s=\n' "$var" >>"$file"
  done
done
printf '%s\n' "$file"
