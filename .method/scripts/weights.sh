#!/usr/bin/env bash
#: weights.sh: reads the weights of the method (scripts/lib/weights.tsv).
#:
#: Usage: weights.sh [<weight> | --check]
#:
#: No argument: lists "weight model effort", one per line. With a weight (light,
#: medium, strong, reviewer, triage): prints "model effort", the pair to pass to
#: the Agent tool or to write in the spec line "modelo: ... · esforço: ...".
#: --check: exits 1 unless the file has the five weights, each one once, with a
#: model and an effort among low, medium, high, xhigh and max.
#: To change a pair, edit scripts/lib/weights.tsv: no agent, skill or script
#: names a model.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"
FILE="$HERE/lib/weights.tsv"
WEIGHTS="light medium strong reviewer triage"

rows() { grep -v -e '^#' -e '^[[:space:]]*$' "$FILE"; }

check() {
  local w n bad=0
  [ -f "$FILE" ] || die "missing $FILE"
  for w in $WEIGHTS; do
    n="$(rows | awk -F'\t' -v w="$w" '$1 == w' | wc -l | tr -d ' ')"
    if [ "$n" != 1 ]; then echo "error: weight $w appears $n time(s) in $FILE (expected 1)" >&2; bad=1; fi
  done
  while IFS=$'\t' read -r w model effort rest; do
    case " $WEIGHTS " in *" $w "*) ;; *) echo "error: unknown weight '$w' in $FILE" >&2; bad=1 ;; esac
    if [ -z "$model" ] || [ -n "${rest:-}" ]; then echo "error: weight $w needs exactly a model and an effort" >&2; bad=1; fi
    case "$effort" in low|medium|high|xhigh|max) ;; *) echo "error: weight $w has effort '$effort' (use low, medium, high, xhigh or max)" >&2; bad=1 ;; esac
  done < <(rows)
  return "$bad"
}

case "${1:-}" in
  -h|--help) print_help "$0" ;;
  --check) check && echo "ok: $FILE" ;;
  "") check && rows | tr '\t' ' ' ;;
  -*) die "unknown option: $1 (see --help)" 2 ;;
  *)
    check
    pair="$(rows | awk -F'\t' -v w="$1" '$1 == w {print $2, $3}')"
    [ -n "$pair" ] || die "unknown weight: $1 (one of: $WEIGHTS)"
    echo "$pair" ;;
esac
