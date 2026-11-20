#!/usr/bin/env bash
# Tests of the .env path (secret_env_file) and of init-env.sh: default
# ~/.<repo-slug>/.env, override through PROCESS_ENV_FILE, permissions 700/600 and empty keys.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

export HOME="$TMP/home"
mkdir -p "$HOME" "$TMP/repo"
unset PROCESS_ENV_FILE
git -C "$TMP/repo" init -q
git -C "$TMP/repo" remote add origin "https://github.com/acme/my-repo.git"

path() { (cd "$TMP/repo" && bash -c 'source "$1/lib/secret.sh"; secret_env_file' _ "$SCRIPTS"); }

# Default: ~/.<repo-slug>/.env, the slug being the repo name in the remote.
assert_eq "$HOME/.my-repo/.env" "$(path)" "default path uses the repo name from the remote"
git -C "$TMP/repo" remote set-url origin "git@github.com:acme/other.git"
assert_eq "$HOME/.other/.env" "$(path)" "default path with an ssh remote"

# Override.
assert_eq "$TMP/x/custom.env" "$(PROCESS_ENV_FILE="$TMP/x/custom.env" path)" "PROCESS_ENV_FILE overrides the path"

# init-env.sh: folder 700, file 600, empty keys, no overwrite.
(cd "$TMP/repo" && "$SCRIPTS/init-env.sh" bot-a >"$TMP/init.out")
f="$HOME/.other/.env"
assert_eq "$f" "$(cat "$TMP/init.out")" "init-env prints only the path"
assert_eq "700" "$(stat -c %a "$HOME/.other" 2>/dev/null || stat -f %Lp "$HOME/.other")" "folder is 700"
assert_eq "600" "$(stat -c %a "$f" 2>/dev/null || stat -f %Lp "$f")" "file is 600"
assert_eq "BOT_WEBHOOK_BOT_A_URL=
BOT_WEBHOOK_BOT_A_SECRET=" "$(cat "$f")" "keys are empty"
printf 'BOT_WEBHOOK_BOT_A_URL=keep\n' >"$f"
(cd "$TMP/repo" && "$SCRIPTS/init-env.sh" bot-a >/dev/null)
assert_eq "BOT_WEBHOOK_BOT_A_URL=keep
BOT_WEBHOOK_BOT_A_SECRET=" "$(cat "$f")" "existing values are kept; only missing keys are added"
(cd "$TMP/repo" && PROCESS_ENV_FILE="$TMP/y/o.env" "$SCRIPTS/init-env.sh" >/dev/null)
assert_eq "600" "$(stat -c %a "$TMP/y/o.env" 2>/dev/null || stat -f %Lp "$TMP/y/o.env")" "override path is created with 600"
assert_status 2 "invalid slug is refused" "$SCRIPTS/init-env.sh" "Bad Slug"

finish
