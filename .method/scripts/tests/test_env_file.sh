#!/usr/bin/env bash
# Tests of the .env path (secret_env_file) and of init-env.sh: default
# $DUMONTECH_HOME/projetos/<repo-slug>/.env, older paths, override through PROCESS_ENV_FILE, permissions 700/600 and empty keys.
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

export HOME="$TMP/home"
mkdir -p "$HOME" "$TMP/repo"
unset PROCESS_ENV_FILE
git -C "$TMP/repo" init -q
git -C "$TMP/repo" remote add origin "https://github.com/acme/meu-repo.git"

path() { (cd "$TMP/repo" && bash -c 'source "$1/lib/secret.sh"; secret_env_file' _ "$SCRIPTS"); }

NEW="$DUMONTECH_HOME/projetos"
# Default: $DUMONTECH_HOME/projetos/<repo-slug>/.env (DUMONTECH_HOME defaults to ~/.dumontech).
assert_eq "$NEW/meu-repo/.env" "$(path)" "default path uses the repo name from the remote"
git -C "$TMP/repo" remote set-url origin "git@github.com:acme/outro.git"
assert_eq "$NEW/outro/.env" "$(path)" "default path with an ssh remote"
assert_eq "$HOME/.dumontech/projetos/outro/.env" "$(env -u DUMONTECH_HOME bash -c 'cd "$1" && source "$2/lib/secret.sh"; secret_env_file' _ "$TMP/repo" "$SCRIPTS")" "DUMONTECH_HOME defaults to ~/.dumontech"

# Search order: new path, then ~/.<slug>/.env, then the legacy ~/.config/<slug>/.env.
mkdir -p "$HOME/.config/outro"; : >"$HOME/.config/outro/.env"
assert_eq "$HOME/.config/outro/.env" "$(path)" "legacy ~/.config path is used while the others are missing"
warn="$(cd "$TMP/repo" && bash -c 'source "$1/lib/secret.sh"; _secret_env_file_check' _ "$SCRIPTS" 2>&1 || true)"
assert_contains "$warn" "legacy" "legacy .env use prints a warning"
assert_contains "$warn" "$NEW/outro/.env" "the warning names the new path"
mkdir -p "$HOME/.outro"; : >"$HOME/.outro/.env"
assert_eq "$HOME/.outro/.env" "$(path)" "the home .<slug>/.env wins over .config"
warn="$(cd "$TMP/repo" && bash -c 'source "$1/lib/secret.sh"; _secret_env_file_check' _ "$SCRIPTS" 2>&1 || true)"
assert_not_contains "$warn" "legacy" "the home .<slug>/.env works without a warning"
git -C "$TMP/repo" remote set-url origin "git@github.com:acme/mais-um.git"
assert_eq "$NEW/mais-um/.env" "$(path)" "the old file of one repo is not used by another"
git -C "$TMP/repo" remote set-url origin "git@github.com:acme/outro.git"

# init-env with an old .env: keeps it where it is, appends the missing keys, creates nothing new.
(cd "$TMP/repo" && "$SCRIPTS/init-env.sh" bot-a >"$TMP/init.out" 2>/dev/null)
assert_eq "$HOME/.outro/.env" "$(cat "$TMP/init.out")" "init-env works on the existing old file"
assert_eq "BOT_WEBHOOK_BOT_A_URL=
BOT_WEBHOOK_BOT_A_SECRET=
GH_APP_BOT_A_TOKEN=
GH_APP_METHOD_TOKEN=" "$(cat "$HOME/.outro/.env")" "init-env appends the missing keys to the old file"
[ ! -e "$NEW/outro" ] && ok || bad "init-env creates nothing in the new path when an old file exists"
assert_eq "0" "$(wc -c <"$HOME/.config/outro/.env" | tr -d ' ')" "init-env leaves the other old file alone"
rm -rf "$HOME/.outro"

# Old-folder notices (stderr, once per run, never a value, nothing moved or deleted).
export TMPDIR="$TMP/tmpdir"; mkdir -p "$TMPDIR"
# shellcheck disable=SC2069 # stderr only, on purpose
notice() { (cd "$TMP/repo" && bash -c 'source "$1/lib/secret.sh"; secret_env_file >/dev/null; _secret_env_file_check; _secret_env_file_check; echo "rc=$?" >&2' _ "$SCRIPTS" 2>&1 >/dev/null); }
snap() { find "$HOME" -type f -exec cksum {} + 2>/dev/null | sort; }
rm -rf "$HOME/.outro" "$HOME/.config/outro" "$NEW/outro"
# Only the new path: no notice.
mkdir -p "$NEW/outro"; printf 'K=secretvalue\n' >"$NEW/outro/.env"; chmod 600 "$NEW/outro/.env"
assert_eq "" "$(notice | grep -v '^rc=')" "only the new path: no notice"
# New and old together: the old folder is not read any more, with the removal command.
mkdir -p "$HOME/.outro" "$HOME/.config/outro"; printf 'K=oldvalue\n' >"$HOME/.outro/.env"; : >"$HOME/.config/outro/.env"
before="$(snap)"
out="$(notice)"
assert_contains "$out" "$HOME/.outro is not read any more" "leftover notice names the old folder"
assert_contains "$out" "rm -r $HOME/.outro" "leftover notice has the exact removal command"
assert_contains "$out" "rm -r $HOME/.config/outro" "leftover notice covers the legacy folder"
assert_eq "1" "$(printf '%s\n' "$out" | grep -c "$HOME/.outro is not read")" "the notice is printed once per run"
assert_not_contains "$out" "oldvalue" "the notice has no secret value"
assert_contains "$out" "rc=0" "the notice does not change the exit code"
assert_eq "$before" "$(snap)" "leftover notice leaves the old folders intact"
[ -d "$HOME/.outro" ] && [ -d "$HOME/.config/outro" ] && ok || bad "old folders still exist"
# Only the old path: still read, with the migration command.
rm -rf "$NEW/outro" "$HOME/.config/outro"; rm -f "$TMPDIR"/*
chmod 600 "$HOME/.outro/.env"; before="$(snap)"
out="$(notice)"
assert_contains "$out" "using the old .env $HOME/.outro/.env" "old path in use notice"
assert_contains "$out" "mkdir -p $NEW/outro && chmod 700 $DUMONTECH_HOME $NEW $NEW/outro && mv $HOME/.outro/.env $NEW/outro/.env && chmod 600 $NEW/outro/.env && rm -r $HOME/.outro" "migration command is exact"
assert_eq "1" "$(printf '%s\n' "$out" | grep -c 'using the old')" "the old-path notice is printed once per run"
assert_not_contains "$out" "oldvalue" "the old-path notice has no secret value"
assert_eq "$before" "$(snap)" "old-path notice leaves the old folder intact"
# The legacy ~/.config folder alone.
rm -rf "$HOME/.outro"; mkdir -p "$HOME/.config/outro"; : >"$HOME/.config/outro/.env"; chmod 600 "$HOME/.config/outro/.env"; rm -f "$TMPDIR"/*
assert_contains "$(notice)" "rm -r $HOME/.config/outro" "the legacy folder gets the migration command"
# PROCESS_ENV_FILE: no notice.
rm -f "$TMPDIR"/*
assert_eq "" "$(PROCESS_ENV_FILE="$TMP/p.env" notice | grep -v '^rc=')" "PROCESS_ENV_FILE is silent"
# init-env prints the same notice on stderr and still prints only the path on stdout.
rm -f "$TMPDIR"/*
(cd "$TMP/repo" && "$SCRIPTS/init-env.sh" bot-a >"$TMP/init.out" 2>"$TMP/init.err")
assert_eq "$HOME/.config/outro/.env" "$(cat "$TMP/init.out")" "init-env stdout is only the path"
assert_contains "$(cat "$TMP/init.err")" "mv $HOME/.config/outro/.env $NEW/outro/.env" "init-env prints the migration command"
[ -f "$HOME/.config/outro/.env" ] && ok || bad "init-env leaves the old file in place"
rm -rf "$HOME/.config/outro" "$DUMONTECH_HOME"; rm -f "$TMPDIR"/*

# No old file: the new path is created, folders 700 and file 600.
rm -rf "$HOME/.config/outro"
(cd "$TMP/repo" && "$SCRIPTS/init-env.sh" >"$TMP/init.out")
f="$NEW/outro/.env"
assert_eq "$f" "$(cat "$TMP/init.out")" "init-env prints only the new path"
for d in "$DUMONTECH_HOME" "$NEW" "$NEW/outro"; do
  assert_eq "700" "$(stat -c %a "$d" 2>/dev/null || stat -f %Lp "$d")" "created folder $d is 700"
done
assert_eq "600" "$(stat -c %a "$f" 2>/dev/null || stat -f %Lp "$f")" "file is 600"
assert_eq "BOT_WEBHOOK_BOT_A_URL=
BOT_WEBHOOK_BOT_A_SECRET=
GH_APP_BOT_A_TOKEN=
BOT_WEBHOOK_BOT_B_URL=
BOT_WEBHOOK_BOT_B_SECRET=
GH_APP_BOT_B_TOKEN=
GH_APP_METHOD_TOKEN=" "$(cat "$f")" "init-env defaults to every bot of the bots file"
assert_eq "$f" "$(path)" "the new path is found once it exists"
assert_status 2 "init-env with no bot and no bots file is refused" env BOTS_FILE="$TMP/missing.tsv" sh -c "cd '$TMP/repo' && '$SCRIPTS/init-env.sh'"

# With the shared bots file present, the repo .env gets no bot keys; the shared file is not touched.
rm -rf "$NEW/outro"
mkdir -p "$DUMONTECH_HOME/shared"; printf 'BOT_WEBHOOK_BOT_A_URL=v\n' >"$DUMONTECH_HOME/shared/bots.env"; chmod 600 "$DUMONTECH_HOME/shared/bots.env"
(cd "$TMP/repo" && "$SCRIPTS/init-env.sh" >/dev/null)
assert_eq "GH_APP_METHOD_TOKEN=" "$(cat "$f")" "with shared/bots.env, init-env writes no bot keys"
assert_eq "BOT_WEBHOOK_BOT_A_URL=v" "$(cat "$DUMONTECH_HOME/shared/bots.env")" "init-env never edits shared/bots.env"
rm -rf "$NEW/outro" "$DUMONTECH_HOME/shared"
f="$NEW/outro/.env"
(cd "$TMP/repo" && "$SCRIPTS/init-env.sh" bot-b >/dev/null)

# Override.
assert_eq "$TMP/x/custom.env" "$(PROCESS_ENV_FILE="$TMP/x/custom.env" path)" "PROCESS_ENV_FILE overrides the path"

# init-env.sh: folder 700, file 600, empty keys, no overwrite.
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
