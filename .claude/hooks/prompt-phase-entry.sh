#!/usr/bin/env bash
# prompt-phase-entry.sh: UserPromptSubmit hook. When the prompt starts with
# "executar #<n>" (or "executar a issue <n>"), it adds to the context the single
# entry of a phase: the plan skill, then .method/scripts/phase-start.sh <n>, which refuses
# an issue without a spec. It never blocks a prompt: it always exits 0.
set -euo pipefail

input="$(cat)"
prompt="$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null || true)"
first="${prompt%%$'\n'*}"
issue="$(printf '%s' "$first" |
  sed -n -E 's/^[[:space:]]*[Ee][Xx][Ee][Cc][Uu][Tt][Aa][Rr][[:space:]]+([Aa][[:space:]]+)?([Ii][Ss][Ss][Uu][Ee][[:space:]]+)?#?([0-9]+).*/\3/p' || true)"
[ -n "$issue" ] || exit 0
cat <<MSG
Phase entry for issue #$issue: load the plan skill (never the execute skill). A phase opens only through .method/scripts/phase-start.sh $issue, which exits non-zero while no approved spec in docs/specs cites #$issue; the execute skill runs only in the child session that phase-start.sh describes.
MSG
