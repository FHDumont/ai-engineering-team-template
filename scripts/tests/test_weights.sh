#!/usr/bin/env bash
# Tests of the weights file (scripts/lib/weights.tsv), of scripts/weights.sh and of
# the rule that no agent or skill names a model.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

# The five weights, each with a model and an effort.
list="$("$SCRIPTS/weights.sh")"
assert_eq "light medium reviewer strong triage" "$(echo "$list" | cut -d' ' -f1 | sort | paste -sd' ' -)" "the file has the five weights"
assert_status 0 "the file passes its own check" "$SCRIPTS/weights.sh" --check
# The defaults run on a plan that only has sonnet at low or medium effort.
assert_eq "sonnet" "$(echo "$list" | cut -d' ' -f2 | sort -u | paste -sd' ' -)" "no default weight asks for a model above sonnet"
assert_eq "" "$(echo "$list" | cut -d' ' -f3 | grep -vxE 'low|medium' || true)" "no default weight asks for an effort above medium"
assert_eq "$(echo "$list" | sed -n 's/^reviewer //p')" "$("$SCRIPTS/weights.sh" reviewer)" "a weight prints its pair"
assert_status 1 "an unknown weight is refused" "$SCRIPTS/weights.sh" forte
assert_status 2 "an unknown option is refused" "$SCRIPTS/weights.sh" --nope

# A bigger plan raises a weight by editing the file; a broken file is refused.
mkdir -p "$TMP/s/lib"
cp "$SCRIPTS/weights.sh" "$TMP/s/" && cp "$SCRIPTS/lib/common.sh" "$TMP/s/lib/"
sed 's/^reviewer.*/reviewer	big-model	high/' "$SCRIPTS/lib/weights.tsv" >"$TMP/s/lib/weights.tsv"
assert_eq "big-model high" "$("$TMP/s/weights.sh" reviewer)" "the pair comes from the file"
grep -v '^triage' "$SCRIPTS/lib/weights.tsv" >"$TMP/s/lib/weights.tsv"
assert_status 1 "a file without one of the weights is refused" "$TMP/s/weights.sh" reviewer
assert_contains "$(last_output)" "triage" "names the missing weight"
sed 's/^light.*/light	sonnet	huge/' "$SCRIPTS/lib/weights.tsv" >"$TMP/s/lib/weights.tsv"
assert_status 1 "an unknown effort is refused" "$TMP/s/weights.sh" --check

# No agent or skill names a model or fixes a pair in its front matter.
for f in "$REPO"/.claude/agents/*.md "$REPO"/.claude/skills/*/*.md; do
  name="${f#"$REPO"/}"
  assert_eq "" "$(grep -nwiE 'opus|sonnet|haiku|fable' "$f" || true)" "$name names no model"
done
for f in "$REPO"/.claude/agents/*.md; do
  assert_eq "" "$(grep -nE '^(model|effort):' "$f" || true)" "${f#"$REPO"/} fixes no pair in the front matter"
done
close="$(cat "$REPO/.claude/skills/close-phase/SKILL.md")"
assert_contains "$close" "scripts/weights.sh reviewer" "close-phase takes the reviewer pair from the file"
assert_contains "$(cat "$REPO/.claude/skills/triage/SKILL.md")" "scripts/weights.sh triage" "triage takes its pair from the file"
assert_contains "$(cat "$REPO/.claude/skills/plan/SKILL.md")" "scripts/weights.sh <peso>" "plan takes the pair of a step from the file"
# The rule of the steps compares pairs, never model names.
execute="$(cat "$REPO/.claude/skills/execute/SKILL.md")"
assert_contains "$execute" "par igual roda nesta sessão" "execute runs a step of the session pair in the session"
assert_contains "$execute" "par diferente vai a um subagente" "execute sends a step of another pair to a subagent"

finish
