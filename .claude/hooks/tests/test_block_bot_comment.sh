#!/usr/bin/env bash
# Tests for the block-bot-comment.sh hook.
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "$0")/../../../.method/scripts/tests/lib.sh"
HOOK="$REPO/.claude/hooks/block-bot-comment.sh"

run() { jq -cn --arg c "$1" --arg d "$REPO" '{tool_input: {command: $c}, cwd: $d}' | "$HOOK"; }

h='**De:** fase #34 · **Para:** dono · **Pedido:** aviso · **Responde a:** —'
hb='**De:** fase #34 · **Para:** bot-a · **Pedido:** pergunta · **Responde a:** —'
assert_status 2 "blocks an issue comment without the header" run 'gh issue comment 3 --body "oi"'
assert_status 2 "blocks a PR comment without the header" run 'gh pr comment 3 --body "oi"'
assert_status 2 "blocks close --comment without the header" run 'gh issue close 3 --comment "fim"'
assert_contains "$(last_output)" "authorship header" "says why"
assert_status 0 "allows a comment with the header" run "gh issue comment 3 --body \"$h

texto\""
assert_status 0 "allows gh -R with the header" run "gh -R o/r issue comment 3 --body \"$h

texto\""
assert_status 2 "blocks a request to a bot even with the header" run "gh issue comment 3 --body \"$hb

pergunta\""
assert_contains "$(last_output)" "ask-bot.sh" "points to ask-bot.sh"
assert_status 2 "blocks a body citing the bot slug" run "gh issue comment 3 --body \"$h

@bot-a faça X\""
assert_contains "$(last_output)" "ask-bot.sh" "points to ask-bot.sh for a cited slug"
assert_status 0 "a sentence that only contains the bot name is not a request" run "gh pr comment 3 --body \"$h

peça ao bot a sobre isso\""
assert_status 2 "blocks a hand-made ask marker" run "gh issue comment 3 --body \"$h

x <!-- ask:bot-a:20260101000000-1 -->\""
printf '%s\n\ntexto\n' "$h" >"$TMP/ok.md"
printf 'sem cabeçalho\n' >"$TMP/no.md"
printf '%s\n\ntexto\n' "$hb" >"$TMP/bot.md"
assert_status 0 "allows a header inside --body-file" run "gh issue comment 3 --body-file $TMP/ok.md"
assert_status 2 "blocks a missing header inside --body-file" run "gh issue comment 3 --body-file $TMP/no.md"
assert_status 2 "blocks a bot request inside --body-file" run "gh pr comment 3 --body-file $TMP/bot.md"
assert_status 0 "allows a heredoc with the header" run "gh issue comment 3 --body-file - <<EOF
$h

texto
EOF"
assert_status 2 "blocks a heredoc without the header" run "gh issue comment 3 --body-file - <<EOF
texto
EOF"
assert_status 0 "ignores close without --comment" run 'gh issue close 3'
assert_status 0 "ignores other commands" run 'gh issue view 3'
assert_status 0 "ignores ask-bot.sh itself" run '.method/scripts/ask-bot.sh bot-a 3 "pergunta"'

# Explicit recipient, not a substring (#90). Bots: ops, vendas, acme-site.
custom="$TMP/bots.tsv"
printf 'ops\tops\nvendas\tvendas\nacme-site\tacme-site\n' >"$custom"
para() { printf '**De:** fase #90 · **Para:** %s · **Pedido:** aviso · **Responde a:** —' "$1"; }
runb() { BOTS_FILE="$custom" jq -cn --arg c "$1" --arg d "$REPO" '{tool_input: {command: $c}, cwd: $d}' | BOTS_FILE="$custom" "$HOOK"; }
for who in "ops" "bot vendas" "dono, ops"; do
  assert_status 2 "blocks Para: $who" runb "gh issue comment 3 --body \"$(para "$who")

texto\""
done
assert_status 0 "allows Para: gerenciadora do acme-site" runb "gh issue comment 3 --body \"$(para "gerenciadora do acme-site")

texto\""
assert_status 0 "allows Para: fase #8 (ops do site)" runb "gh issue comment 3 --body \"$(para "fase #8 (ops do site)")

texto\""
assert_status 0 "laptops does not cite ops" runb "gh issue comment 3 --body \"$(para dono)

Os laptops chegaram\""
assert_status 0 "vendas inside a sentence is not a request" runb "gh issue comment 3 --body \"$(para dono)

O texto de vendas ficou pronto\""
assert_status 0 "gh -R does not count as the comment" runb "gh -R owner/acme-site issue comment 3 --body \"$(para dono)

Build verde\""
assert_status 0 "citing the ask prefix in backticks is not a marker" runb "gh issue comment 3 --body \"$(para dono)

a marca \`<!-- ask:\` explica o método\""
assert_status 2 "a body file the hook cannot read says so" runb 'gh issue comment 3 --body-file "$S/texto.md"'
assert_contains "$(last_output)" "não li o --body-file" "names the unread body file"
finish
