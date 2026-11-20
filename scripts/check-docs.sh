#!/usr/bin/env bash
#: check-docs.sh: check the limits of the AI docs and the design against the repository.
#:
#: Usage: check-docs.sh
#:
#: Limits: AGENTS.md with 300-500 words; docs/STATE.md <= 500; docs/BOTS.md <= 450;
#: plan skill <= 400; CLAUDE.md is only "@AGENTS.md"; one line in
#: docs/adr/INDEX.md per ADR (current or archived) and no orphan lines; no
#: history section in the AI files.
#:
#: Design (docs/process-design.md), read from the first column of each table:
#: - "## Regras-base": five numbered rules, four columns, an exit code in each,
#:   every lock path exists, and none of the words that leave a second path
#:   (pode, podem, ou, exceção, se falhar);
#: - "## 6. Scripts": lists exactly the files of scripts/;
#: - "### 6.2 Hooks": lists exactly the files of .claude/hooks/ and .githooks/;
#: - "## 7. Arquivos": every path without a placeholder (<...> or *) exists.
#:
#: Lists every problem and exits 1.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"
case "${1:-}" in -h|--help) print_help "$0"; exit 0 ;; esac
ROOT="${REPO_ROOT:-$(cd "$HERE/.." && pwd)}"
cd "$ROOT"

fail=0
problem() { echo "fail: $*"; fail=1; }
words() { wc -w <"$1" | tr -d ' '; }

limit() { # limit <file> <min> <max>
  [ -f "$1" ] || { problem "$1 missing"; return; }
  local n; n="$(words "$1")"
  if [ "$n" -lt "$2" ] || [ "$n" -gt "$3" ]; then
    problem "$1 has $n words (allowed $2-$3)"
  fi
}
limit AGENTS.md 300 500
limit docs/STATE.md 1 500
limit docs/BOTS.md 1 450
limit .claude/skills/plan/SKILL.md 1 400

if [ "$(tr -d '[:space:]' <CLAUDE.md 2>/dev/null)" != "@AGENTS.md" ]; then
  problem 'CLAUDE.md must contain only "@AGENTS.md"'
fi

# History lives in git, not in the AI files.
for f in AGENTS.md CONTEXT.md docs/STATE.md docs/BOTS.md; do
  [ -f "$f" ] || continue
  if grep -inE '^#+ *(histórico|historico|history|changelog|log de|fases anteriores)' "$f" >/dev/null; then
    problem "$f has a history section (history lives in git and PRs)"
  fi
done

index=docs/adr/INDEX.md
if [ -f "$index" ]; then
  for f in docs/adr/ADR-*.md docs/adr/archive/ADR-*.md; do
    [ -e "$f" ] || continue
    num="$(basename "$f" | sed -E 's/^(ADR-[0-9]+).*/\1/')"
    count="$(grep -cE "^\| *\[?$num\b" "$index" || true)"
    [ "$count" = 1 ] || problem "$index must have exactly one line for $num (has $count)"
    case "$f" in
      docs/adr/archive/*) grep -E "^\| *\[?$num\b" "$index" | grep -qi 'substitu' || problem "$num is archived but not marked substituída in $index" ;;
    esac
  done
  while read -r num; do
    [ -n "$num" ] || continue
    found=""
    for f in docs/adr/"$num"-*.md docs/adr/archive/"$num"-*.md; do [ -e "$f" ] && found=1; done
    [ -n "$found" ] || problem "$index lists $num but the file is missing"
  done <<<"$(grep -oE '^\| *\[?ADR-[0-9]+' "$index" | grep -oE 'ADR-[0-9]+' || true)"
else
  problem "$index missing"
fi

# The design describes the repository: its tables are checked against the files.
design=docs/process-design.md
# section <heading>: the lines under that heading, up to the next "## " or "### ".
section() {
  awk -v h="$1" '$0 == h { p = 1; next } p && /^##[#]? / { exit } p' "$design"
}
# first_column: the backticked tokens of the first column of each table row read from stdin.
first_column() {
  awk -F '|' '/^\| *`/ { print $2 }' | grep -oE '`[^`]+`' | tr -d '`' || true
}
# files_of <dir>: the files directly inside <dir>, as paths from the root.
files_of() {
  local f
  for f in "$1"/*; do [ -f "$f" ] && echo "$f"; done
  return 0
}
# same_files <what> <listed> <actual>: both lists hold the same paths.
same_files() {
  local p
  while read -r p; do
    [ -n "$p" ] || continue
    echo "$3" | grep -qxF "$p" || problem "$design: the $1 table cites $p, which does not exist"
  done <<<"$2"
  while read -r p; do
    [ -n "$p" ] || continue
    echo "$2" | grep -qxF "$p" || problem "$design: the $1 table omits $p"
  done <<<"$3"
}
if [ -f "$design" ]; then
  rules="$(section '## Regras-base' | grep -E '^\| *[0-9]+\. ' || true)"
  count="$(printf '%s' "$rules" | grep -c . || true)"
  [ "$count" = 5 ] || problem "$design has $count base rules (expected 5)"
  while read -r row; do
    [ -n "$row" ] || continue
    num="$(echo "$row" | sed -E 's/^\| *([0-9]+)\..*/\1/')"
    [ "$(echo "$row" | awk -F '|' '{ print NF }')" = 6 ] || problem "$design: base rule $num must have 4 columns"
    echo "$row" | awk -F '|' '{ print $4 }' | grep -q '[0-9]' || problem "$design: base rule $num has no exit code"
    locks="$(echo "$row" | awk -F '|' '{ print $3 }' | grep -oE '`[^`]+`' | tr -d '`' | awk '{ print $1 }' || true)"
    [ -n "$locks" ] || problem "$design: base rule $num names no script or hook"
    while read -r p; do
      [ -z "$p" ] || [ -e "$p" ] || problem "$design: base rule $num names $p, which does not exist"
    done <<<"$locks"
  done <<<"$rules"
  loose="$(section '## Regras-base' | grep -niE '(^|[^[:alnum:]])(pode|podem|ou|exceção|se falhar)([^[:alnum:]]|$)' || true)"
  [ -z "$loose" ] || problem "$design: the base rules leave a second path (pode, ou, exceção, se falhar): $(echo "$loose" | head -3 | cut -c1-80 | paste -sd';' -)"

  same_files scripts "$(section '## 6. Scripts' | first_column | grep '^scripts/' || true)" "$(files_of scripts)"
  same_files hooks "$(section '### 6.2 Hooks' | first_column | grep -E '^(\.claude/hooks|\.githooks)/' || true)" \
    "$(files_of .claude/hooks; files_of .githooks)"
  while read -r p; do
    [ -n "$p" ] || continue
    case "$p" in *'<'*|*'*'*) continue ;; esac
    [ -e "$p" ] || problem "$design: the file table cites $p, which does not exist"
  done <<<"$(section '## 7. Arquivos' | first_column)"

else
  problem "$design missing"
fi

[ "$fail" = 0 ] && echo "ok: docs within limits"
exit "$fail"
