#!/usr/bin/env bash
# Tests of the weights file (scripts/lib/weights.tsv), of scripts/weights.sh and of
# the rule that no agent or skill names a model.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

# Shape of a weights file, whatever models it names: the five weights, each with a
# model and a known effort.
check_weights() { # check_weights <scripts dir> <which file>
  local list
  list="$("$1/weights.sh")"
  assert_eq "light medium reviewer strong triage" "$(echo "$list" | cut -d' ' -f1 | sort | paste -sd' ' -)" "$2 has the five weights"
  assert_status 0 "$2 passes its own check" "$1/weights.sh" --check
  assert_eq "" "$(echo "$list" | grep -vxE '[a-z]+ [^ ]+ (low|medium|high|xhigh|max)' || true)" "every weight of $2 has a model and a known effort"
  assert_eq "$(echo "$list" | sed -n 's/^reviewer //p')" "$("$1/weights.sh" reviewer)" "a weight of $2 prints its pair"
}
check_weights "$SCRIPTS" "the file"
assert_status 1 "an unknown weight is refused" "$SCRIPTS/weights.sh" forte
assert_status 2 "an unknown option is refused" "$SCRIPTS/weights.sh" --nope

# A bigger plan edits only the file: with another model and effort in the five
# lines, the same checks pass.
mkdir -p "$TMP/big/lib"
cp "$SCRIPTS/weights.sh" "$TMP/big/" && cp "$SCRIPTS/lib/common.sh" "$TMP/big/lib/"
awk -F'\t' -v OFS='\t' '/^#/ || NF == 0 {print; next} {print $1, "opus", "medium"}' "$SCRIPTS/lib/weights.tsv" >"$TMP/big/lib/weights.tsv"
check_weights "$TMP/big" "a file on a bigger plan"
assert_eq "opus medium" "$("$TMP/big/weights.sh" light)" "the bigger plan gives its own pair"

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

# No method agent or skill names a model or fixes a pair in its front matter.
# A project agent added beside them is outside the method list and is not scanned.
while IFS= read -r rel; do
  case "$rel" in
    .claude/agents/*.md|.claude/skills/*/SKILL.md|.claude/skills/*/*.md) ;;
    *) continue ;;
  esac
  [ -f "$REPO/$rel" ] || continue
  assert_eq "" "$(grep -nwiE 'opus|sonnet|haiku|fable' "$REPO/$rel" || true)" "$rel names no model"
  case "$rel" in
    .claude/agents/*.md)
      assert_eq "" "$(grep -nE '^(model|effort):' "$REPO/$rel" || true)" "$rel fixes no pair in the front matter" ;;
  esac
done < <(method_paths)
close="$(cat "$REPO/.claude/skills/close-phase/SKILL.md")"
assert_contains "$close" "scripts/weights.sh reviewer" "close-phase takes the reviewer pair from the file"
assert_contains "$(cat "$REPO/.claude/skills/triage/SKILL.md")" "scripts/weights.sh triage" "triage takes its pair from the file"
assert_contains "$(cat "$REPO/.claude/skills/plan/SKILL.md")" "scripts/weights.sh <peso>" "plan takes the pair of a step from the file"
# The rule of the steps compares pairs, never model names.
execute="$(cat "$REPO/.claude/skills/execute/SKILL.md")"
assert_contains "$execute" "par igual roda nesta sessão" "execute runs a step of the session pair in the session"
assert_contains "$execute" "par diferente vai a um subagente" "execute sends a step of another pair to a subagent"

finish
