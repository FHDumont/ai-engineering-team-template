#!/usr/bin/env bash
#: init-env.sh: create the repo's .env (outside git) with empty keys.
#:
#: Usage: init-env.sh [<bot-slug>...]   (default: every bot of .github/bots.tsv)
#:
#: Creates $DUMONTECH_HOME/projetos/<repo-slug>/ (default ~/.dumontech) with
#: chmod 700 and the .env with chmod 600 (or the path in PROCESS_ENV_FILE), with
#: empty BOT_WEBHOOK_<SLUG>_URL=, BOT_WEBHOOK_<SLUG>_SECRET=,
#: GH_APP_BOT_<SLUG>_TOKEN= and one GH_APP_METHOD_TOKEN=. An .env that already
#: exists in an older path (~/.<repo-slug>/, ~/.config/<repo-slug>/) is kept
#: where it is (nothing is moved or deleted); only the missing keys are appended.
#: While $DUMONTECH_HOME/shared/bots.env exists the bot keys live there, so only
#: GH_APP_METHOD_TOKEN= is written; the shared file is never created or edited.
#: Never reads or writes values and never overwrites an existing .env. The repo
#: owner pastes the values in an editor. Prints only the file path.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=.method/scripts/lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=.method/scripts/lib/secret.sh
source "$HERE/lib/secret.sh"
# shellcheck source=.method/scripts/lib/role.sh
source "$HERE/lib/role.sh"
case "${1:-}" in -h|--help) print_help "$0"; exit 0 ;; esac

slugs=("$@")
if [ "${#slugs[@]}" = 0 ]; then
  while read -r s; do [ -z "$s" ] || slugs+=("$s"); done <<<"$(bot_slugs)"
fi
[ "${#slugs[@]}" -gt 0 ] || die "no bot given and none in .github/bots.tsv" 2

# An existing .env (any known path) is kept; a new one goes to the new path.
file="$(secret_env_file)"
# Creates the missing folders one by one, each with chmod 700.
mkdirs() {
  local d="$1"
  [ -d "$d" ] && return 0
  mkdirs "$(dirname "$d")"
  mkdir "$d"; chmod 700 "$d"
}
mkdirs "$(dirname "$file")"
[ -f "$file" ] || { : >"$file"; }
chmod 600 "$file"

shared=0
[ ! -f "$(secret_shared_file)" ] || shared=1
for s in "${slugs[@]}"; do
  case "$s" in ''|*[!a-z0-9-]*) die "invalid bot slug: $s" 2 ;; esac
  [ "$shared" = 0 ] || continue
  for field in url secret; do
    var="$(bot_webhook_var "$s" "$field")"
    grep -qE "^(export )?$var=" "$file" || printf '%s=\n' "$var" >>"$file"
  done
  var="$(role_token_var "$s")"
  grep -qE "^(export )?$var=" "$file" || printf '%s=\n' "$var" >>"$file"
done
var="$(role_token_var method)"
grep -qE "^(export )?$var=" "$file" || printf '%s=\n' "$var" >>"$file"
printf '%s\n' "$file"
