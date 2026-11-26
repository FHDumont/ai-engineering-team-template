#!/usr/bin/env bash
# block-agent-pair.sh: PreToolUse (Agent) hook. Every agent or subagent opens with an
# explicit model and effort (AGENTS.md, rule 8): a call without one of them is blocked
# with exit 2. The agents of the repo (close-reviewer, triage) declare no pair: theirs
# is the one of their weight in .method/scripts/lib/weights.tsv, and any other pair is blocked.
# Fails closed on input it cannot read.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

input="$(cat)"
missing="$(printf '%s' "$input" | jq -r '
  [(.tool_input // {}) as $i | ("model", "effort") | select(($i[.] // "") == "")] | join(" and ")' 2>/dev/null)" || {
  echo "blocked by block-agent-pair: invalid hook input" >&2
  exit 2
}
if [ -n "$missing" ]; then
  echo "blocked by block-agent-pair: the Agent call has no $missing; pass model and effort explicitly (the pair of the spec step)" >&2
  exit 2
fi
case "$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // ""')" in
  close-reviewer) weight=reviewer ;;
  triage) weight=triage ;;
  *) exit 0 ;;
esac
want="$("$here/../../.method/scripts/weights.sh" "$weight" 2>/dev/null)" || {
  echo "blocked by block-agent-pair: cannot read the $weight weight (.method/scripts/weights.sh $weight)" >&2
  exit 2
}
got="$(printf '%s' "$input" | jq -r '.tool_input | "\(.model) \(.effort)"')"
[ "$got" = "$want" ] && exit 0
echo "blocked by block-agent-pair: this agent opens with the $weight weight of .method/scripts/lib/weights.tsv (model ${want% *}, effort ${want#* }), not with ${got% *} and ${got#* }" >&2
exit 2
