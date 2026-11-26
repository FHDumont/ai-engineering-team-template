#!/usr/bin/env bash
#: check-docs.sh: check the limits of the AI docs and the design against the repository.
#:
#: Usage: check-docs.sh
#:
#: Limits: AGENTS.md with 300-800 words; docs/STATE.md <= 800; docs/BOTS.md <= 450;
#: plan skill <= 400; CLAUDE.md is only "@AGENTS.md"; one line in
#: docs/adr/INDEX.md per ADR (current or archived) and no orphan lines; no
#: history section in the AI files.
#:
#: Design (docs/process-design.md), read from the first column of each table:
#: - "## Regras-base": five numbered rules, four columns, an exit code in each,
#:   every lock path exists, and none of the words that leave a second path
#:   (pode, podem, ou, exceção, se falhar);
#: - "## 6. Scripts": lists exactly the method scripts. With
#:   .github/method-files.txt, that file is the list (one path per line);
#:   a script of the repository that is not in it is not required. Without
#:   the file, the list is every file directly in .method/scripts/;
#: - "### 6.2 Hooks": the same, for .claude/hooks/ and .githooks/;
#: - "## 7. Arquivos": every path without a placeholder (<...> or *) exists.
#:   CHANGELOG.md and ROADMAP.md may both be absent until the first group; if
#:   either exists, both must.
#:
#: Repository-only names: the design, AGENTS.md and the skills (.claude/skills/*/*.md) cite
#: no name listed under "## Nomes só deste repositório" of docs/repo-notes.md, when that file
#: exists; the path docs/repo-notes.md itself is allowed.
#:
#: Issue templates: .github/ISSUE_TEMPLATE/ has no YAML issue form; only
#: config.yml is YAML.
#:
#: Lists every problem and exits 1.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=.method/scripts/lib/common.sh
source "$HERE/lib/common.sh"
case "${1:-}" in -h|--help) print_help "$0"; exit 0 ;; esac
ROOT="${REPO_ROOT:-$(cd "$HERE/../.." && pwd)}"
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
limit AGENTS.md 300 800
limit docs/STATE.md 1 800
# Method facts live in the design. These sentences were true once and stayed
# in STATE after the behavior changed (FHDumont/ai-engineering-team-template#118).
if [ -f docs/STATE.md ]; then
  if grep -q 'roda em todo PR' docs/STATE.md || grep -q 'saindo 6 sem proteção' docs/STATE.md; then
    problem "docs/STATE.md repeats a method fact that is no longer true (the design is the source)"
  fi
fi
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
      docs/adr/archive/*) grep -E "^\| *\[?$num\b" "$index" | stdin_grep -qi 'substitu' || problem "$num is archived but not marked substituída in $index" ;;
    esac
  done
  while read -r num; do
    [ -n "$num" ] || continue
    found=""
    for f in docs/adr/"$num"-*.md docs/adr/"$num".md docs/adr/archive/"$num"-*.md docs/adr/archive/"$num".md; do
      [ -e "$f" ] && found=1
    done
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
    echo "$3" | stdin_grep -qxF "$p" && continue
    if [ -e "$p" ] && [ -n "${manifest_note:-}" ]; then
      problem "$design: the $1 table cites $p: $p exists but is not in $manifest_note; add it to the manifest (a file only of this repository that the design cites goes there too)"
    else
      problem "$design: the $1 table cites $p, which does not exist"
    fi
  done <<<"$2"
  while read -r p; do
    [ -n "$p" ] || continue
    echo "$2" | stdin_grep -qxF "$p" || problem "$design: the $1 table omits $p"
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
    echo "$row" | awk -F '|' '{ print $4 }' | stdin_grep -q '[0-9]' || problem "$design: base rule $num has no exit code"
    locks="$(echo "$row" | awk -F '|' '{ print $3 }' | grep -oE '`[^`]+`' | tr -d '`' | awk '{ print $1 }' || true)"
    [ -n "$locks" ] || problem "$design: base rule $num names no script or hook"
    while read -r p; do
      [ -z "$p" ] || [ -e "$p" ] || problem "$design: base rule $num names $p, which does not exist"
    done <<<"$locks"
  done <<<"$rules"
  loose="$(section '## Regras-base' | grep -niE '(^|[^[:alnum:]])(pode|podem|ou|exceção|se falhar)([^[:alnum:]]|$)' || true)"
  [ -z "$loose" ] || problem "$design: the base rules leave a second path (pode, ou, exceção, se falhar): $(echo "$loose" | head -3 | cut -c1-80 | paste -sd';' -)"

  # The method manifest, when the repository has one, is the list the design
  # must match. A file of the application in the same folder stays out of it.
  manifest=.github/method-files.txt
  if [ -f "$manifest" ]; then
    method_list="$(grep -vE '^[[:space:]]*(#|$)' "$manifest" || true)"
    while read -r p; do
      [ -n "$p" ] || continue
      [ -e "$p" ] || problem "$manifest lists $p, which does not exist"
    done <<<"$method_list"
    manifest_note="$manifest"
    method_scripts="$(printf '%s\n' "$method_list" | grep '^\.method/scripts/' || true)"
    method_hooks="$(printf '%s\n' "$method_list" | grep -E '^(\.claude/hooks|\.githooks)/' || true)"
  else
    method_scripts="$(files_of .method/scripts)"
    method_hooks="$(files_of .claude/hooks; files_of .githooks)"
  fi
  same_files scripts "$(section '## 6. Scripts' | first_column | grep '^\.method/scripts/' || true)" "$method_scripts"
  same_files hooks "$(section '### 6.2 Hooks' | first_column | grep -E '^(\.claude/hooks|\.githooks)/' || true)" \
    "$method_hooks"
  # CHANGELOG.md and ROADMAP.md are generated at the end of the first group.
  # Both may be absent until then. Once either exists, both are required.
  generated_missing=""
  while read -r p; do
    [ -n "$p" ] || continue
    case "$p" in *'<'*|*'*'*) continue ;; esac
    [ -e "$p" ] && continue
    case "$p" in
      CHANGELOG.md|ROADMAP.md) generated_missing="${generated_missing:+$generated_missing }$p" ;;
      *) problem "$design: the file table cites $p, which does not exist" ;;
    esac
  done <<<"$(section '## 7. Arquivos' | first_column)"
  case "$generated_missing" in
    ""|"CHANGELOG.md ROADMAP.md"|"ROADMAP.md CHANGELOG.md") ;;
    *) problem "$design: the file table cites $generated_missing, which does not exist" ;;
  esac

else
  problem "$design missing"
fi

# Names of one repository stay out of the method: the design, AGENTS.md and the
# skills cite none of the names docs/repo-notes.md lists. The one exception is defined
# here: the path of that file itself, which the method may cite.
repo_notes=docs/repo-notes.md
if [ -f "$repo_notes" ]; then
  names="$(awk '$0 == "## Nomes só deste repositório" { p = 1; next } p && /^## / { exit } p && /^- / { print }' "$repo_notes" | grep -oE '`[^`]+`' | tr -d '`' || true)"
  for f in "$design" AGENTS.md .claude/skills/*/*.md; do
    [ -f "$f" ] || continue
    while read -r name; do
      [ -n "$name" ] || continue
      awk -v allowed="$repo_notes" -v name="$name" '
        { while ((i = index($0, allowed)) > 0) $0 = substr($0, 1, i - 1) substr($0, i + length(allowed)) }
        index($0, name) { found = 1; exit }
        END { exit !found }' "$f" && problem "$f cites the repository-only name $name (it belongs in $repo_notes)"
    done <<<"$names"
  done
fi

# AGENTS.md points to docs/repo-notes.md; a repository updated from an older version lacks it.
if [ -f AGENTS.md ] && grep -q 'docs/repo-notes\.md' AGENTS.md && [ ! -f "$repo_notes" ]; then
  echo "warn: AGENTS.md points to $repo_notes, which does not exist: create it from the template model (section '## Nomes só deste repositório') and move the project rules there"
fi

# A hook cited in .claude/settings.json must exist: a missing path fails closed.
if [ -f .claude/settings.json ]; then
  python3 - "$ROOT" <<'PY' || problem ".claude/settings.json cites a hook that does not exist"
import json, os, re, sys
root = sys.argv[1]
data = json.load(open(os.path.join(root, ".claude/settings.json"), encoding="utf-8"))
fail = 0
def walk(obj):
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k == "command" and isinstance(v, str):
                yield v
            else:
                yield from walk(v)
    elif isinstance(obj, list):
        for item in obj:
            yield from walk(item)
for cmd in walk(data.get("hooks") or {}):
    path = re.sub(r'^"?\$\{CLAUDE_PROJECT_DIR\}"?/?', "", cmd).strip().strip('"')
    if not path or path.startswith("$"):
        continue
    if not os.path.isfile(os.path.join(root, path)):
        print("missing hook cited in settings.json:", path)
        fail = 1
sys.exit(fail)
PY
fi

# Issue templates are Markdown, not issue forms (design §8.2): only config.yml is YAML.
for f in .github/ISSUE_TEMPLATE/*.yml .github/ISSUE_TEMPLATE/*.yaml; do
  [ -e "$f" ] || continue
  [ "$f" = .github/ISSUE_TEMPLATE/config.yml ] && continue
  problem "$f is an issue form (issue templates are Markdown; only config.yml is YAML)"
done

[ "$fail" = 0 ] && echo "ok: docs within limits"
exit "$fail"
