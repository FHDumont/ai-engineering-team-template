#!/usr/bin/env bash
# block-card-title.sh: PreToolUse (AskUserQuestion) hook. While a phase is open
# (.worktrees/issue-<n> in the main checkout), every card to the owner starts with
# "Fase #<n> — <title>": the owner always sees which phase is asking (AGENTS.md, rule 2).
# In the session of a phase (phase_session of an issue it did not open) the number
# is the one of its phase. With no phase open (setup, triage, first planning) any
# card passes. Blocks with exit 2; fails closed on input it cannot read.
set -euo pipefail

deny() {
  echo "blocked by block-card-title: $1" >&2
  exit 2
}

here="$(cd "$(dirname "$0")" && pwd)"
input="$(cat)"
count="$(printf '%s' "$input" | jq -r '(.tool_input.questions // []) | length' 2>/dev/null)" || deny "invalid hook input"
[ "$count" != 0 ] || exit 0
sid="$(printf '%s' "$input" | jq -r '.session_id // empty')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"

# shellcheck source=.method/scripts/lib/common.sh
source "$here/../../.method/scripts/lib/common.sh"
main_root="$(git -C "${cwd:-.}" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')" || exit 0
[ -n "$main_root" ] || exit 0
open=""
for d in "$main_root"/.worktrees/issue-*; do
  [ -d "$d" ] || continue
  n="$(phase_of_path "$d" | cut -f1)"
  [ -z "$n" ] || open="$open $n"
done
[ -n "$open" ] || exit 0

# The phases of this session: phase_session of an issue it did not open, still open.
own=""
trace="$(phase_trace_file "$main_root" 2>/dev/null || true)"
if [ -n "$sid" ] && [ -f "$trace" ]; then
  mine="$(jq -rs --arg s "$sid" '
    [.[] | select(type == "object" and .session_id == $s)] as $e
    | [$e[] | select(.event == "phase_opened") | (.issue | tostring)] as $opened
    | [$e[] | select(.event == "phase_session") | (.issue | tostring) | select(. as $i | $opened | index($i) | not)]
    | unique | .[]' "$trace" 2>/dev/null || true)"
  for n in $mine; do
    case " $open " in *" $n "*) own="${own:+$own|}$n" ;; esac
  done
fi
number="[0-9]+"
[ -z "$own" ] || number="($own)"

bad="$(printf '%s' "$input" | jq -r --arg re "^Fase #$number — [^ ]" \
  '[.tool_input.questions[] | (.question // "") | select(test($re) | not)] | length' 2>/dev/null)" || deny "invalid hook input"
[ "$bad" = 0 ] && exit 0
if [ -n "$own" ]; then
  deny "every card of this phase session starts with \"Fase #${own//|/ or #} — <title>:\" ($bad question(s) do not)"
fi
deny "a phase is open (#$(echo $open | sed 's/ /, #/g')): every card starts with \"Fase #<n> — <title>:\" ($bad question(s) do not)"
