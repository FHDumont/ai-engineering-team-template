#!/usr/bin/env bash
# Tests of the .env path (secret_env_file) and of init-env.sh: default
# ~/.<repo-slug>/.env, override through PROCESS_ENV_FILE, permissions 700/600 and empty keys.
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

export HOME="$TMP/home"
mkdir -p "$HOME" "$TMP/repo"
unset PROCESS_ENV_FILE
git -C "$TMP/repo" init -q
git -C "$TMP/repo" remote add origin "https://github.com/acme/meu-repo.git"

path() { (cd "$TMP/repo" && bash -c 'source "$1/lib/secret.sh"; secret_env_file' _ "$SCRIPTS"); }

# Default: ~/.<repo-slug>/.env, the slug being the repo name in the remote.
assert_eq "$HOME/.meu-repo/.env" "$(path)" "default path uses the repo name from the remote"
git -C "$TMP/repo" remote set-url origin "git@github.com:acme/outro.git"
assert_eq "$HOME/.outro/.env" "$(path)" "default path with an ssh remote"

# The legacy ~/.config/<repo-slug>/.env is used only while the new one is missing.
mkdir -p "$HOME/.config/outro"; : >"$HOME/.config/outro/.env"
assert_eq "$HOME/.config/outro/.env" "$(path)" "legacy path is used while the new one is missing"
warn="$(cd "$TMP/repo" && bash -c 'source "$1/lib/secret.sh"; _secret_env_file_check' _ "$SCRIPTS" 2>&1 || true)"
assert_contains "$warn" "legacy" "legacy .env use prints a warning"
assert_contains "$warn" "$HOME/.outro/.env" "the warning names the new path"
git -C "$TMP/repo" remote set-url origin "git@github.com:acme/mais-um.git"
assert_eq "$HOME/.mais-um/.env" "$(path)" "the legacy file of one repo is not used by another"
git -C "$TMP/repo" remote set-url origin "git@github.com:acme/outro.git"
(cd "$TMP/repo" && "$SCRIPTS/init-env.sh" >/dev/null)
[ -f "$HOME/.outro/.env" ] && ok || bad "init-env writes to the new path"
assert_eq "BOT_WEBHOOK_BOT_A_URL=
BOT_WEBHOOK_BOT_A_SECRET=
GH_APP_BOT_A_TOKEN=
BOT_WEBHOOK_BOT_B_URL=
BOT_WEBHOOK_BOT_B_SECRET=
GH_APP_BOT_B_TOKEN=
GH_APP_METHOD_TOKEN=" "$(cat "$HOME/.outro/.env")" "init-env defaults to every bot of the bots file"
assert_eq "0" "$(wc -c <"$HOME/.config/outro/.env" | tr -d ' ')" "init-env leaves the legacy file alone"
assert_eq "$HOME/.outro/.env" "$(path)" "new path wins when it exists"
assert_status 2 "init-env with no bot and no bots file is refused" env BOTS_FILE="$TMP/missing.tsv" sh -c "cd '$TMP/repo' && '$SCRIPTS/init-env.sh'"
rm -rf "$HOME/.config/outro" "$HOME/.outro"

# Override.
assert_eq "$TMP/x/custom.env" "$(PROCESS_ENV_FILE="$TMP/x/custom.env" path)" "PROCESS_ENV_FILE overrides the path"

# init-env.sh: folder 700, file 600, empty keys, no overwrite.
(cd "$TMP/repo" && "$SCRIPTS/init-env.sh" bot-b >"$TMP/init.out")
f="$HOME/.outro/.env"
assert_eq "$f" "$(cat "$TMP/init.out")" "init-env prints only the path"
assert_eq "700" "$(stat -c %a "$HOME/.outro" 2>/dev/null || stat -f %Lp "$HOME/.outro")" "folder is 700"
assert_eq "600" "$(stat -c %a "$f" 2>/dev/null || stat -f %Lp "$f")" "file is 600"
assert_eq "BOT_WEBHOOK_BOT_B_URL=
BOT_WEBHOOK_BOT_B_SECRET=
GH_APP_BOT_B_TOKEN=
GH_APP_METHOD_TOKEN=" "$(cat "$f")" "keys are empty"
printf 'BOT_WEBHOOK_BOT_B_URL=keep\n' >"$f"
(cd "$TMP/repo" && "$SCRIPTS/init-env.sh" bot-b >/dev/null)
assert_eq "BOT_WEBHOOK_BOT_B_URL=keep
BOT_WEBHOOK_BOT_B_SECRET=
GH_APP_BOT_B_TOKEN=
GH_APP_METHOD_TOKEN=" "$(cat "$f")" "existing values are kept; only missing keys are added"
(cd "$TMP/repo" && PROCESS_ENV_FILE="$TMP/y/o.env" "$SCRIPTS/init-env.sh" >/dev/null)
assert_eq "600" "$(stat -c %a "$TMP/y/o.env" 2>/dev/null || stat -f %Lp "$TMP/y/o.env")" "override path is created with 600"
assert_status 2 "invalid slug is refused" "$SCRIPTS/init-env.sh" "Bad Slug"

finish
