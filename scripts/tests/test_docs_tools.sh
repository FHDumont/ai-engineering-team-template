#!/usr/bin/env bash
# Tests of check-docs.sh and archive-adr.sh.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

words() { local _; for _ in $(seq 1 "$1"); do printf 'palavra '; done; echo; }
fixture() {
  local d; d="$(make_repo)"
  mkdir -p "$d/docs/adr/archive" "$d/.claude/skills/plan"
  words 350 >"$d/AGENTS.md"
  echo "@AGENTS.md" >"$d/CLAUDE.md"
  words 100 >"$d/docs/STATE.md"
  words 100 >"$d/docs/BOTS.md"
  words 100 >"$d/.claude/skills/plan/SKILL.md"
  printf '# ADRs\n\n| ADR | Título | Situação |\n|---|---|---|\n| [ADR-001](ADR-001-core.md) | Núcleo | vigente |\n| [ADR-002](ADR-002-next.md) | Próxima | vigente |\n' >"$d/docs/adr/INDEX.md"
  echo "# ADR-001" >"$d/docs/adr/ADR-001-core.md"
  echo "# ADR-002" >"$d/docs/adr/ADR-002-next.md"
  # A design whose tables match the fixture: one script, one hook of each kind.
  mkdir -p "$d/scripts" "$d/.claude/hooks" "$d/.githooks"
  : >"$d/scripts/gate.sh"; : >"$d/.claude/hooks/block-x.sh"; : >"$d/.githooks/pre-commit"
  design >"$d/docs/process-design.md"
  echo "$d"
}
design() {
  cat <<'DOC'
# Desenho

## Regras-base

| Regra | Script e hook que barram | Código de saída | O que o agente faz |
|---|---|---|---|
| 1. Plan | `scripts/gate.sh` | 1 | Escreve a spec |
| 2. Filha | `.claude/hooks/block-x.sh` | 2 | Repassa e para |
| 3. Deploy | `scripts/gate.sh` | 1 | Termina sem deploy |
| 4. Conflito | `scripts/gate.sh --check` | 4 | Resolve e roda de novo |
| 5. Fim | `scripts/gate.sh --state pronto` | 1 | Corrige e roda de novo |

## 6. Scripts

| Script | O que faz | Quem chama |
|---|---|---|
| `scripts/gate.sh` | Barra | agentes |

### 6.2 Hooks

| Hook | Evento | O que barra |
|---|---|---|
| `.claude/hooks/block-x.sh` | PreToolUse | algo |
| `.githooks/pre-commit` | git | commit na `main` |

## 7. Arquivos

| Caminho | O que é |
|---|---|
| `AGENTS.md` | regras |
| `docs/specs/<grupo>.md` | spec |
| `scripts/` | scripts |
DOC
}
# edit_design <fixture> <sed expression>: change the design of the fixture in place.
edit_design() { sed "$2" "$1/docs/process-design.md" >"$1/design.new" && mv "$1/design.new" "$1/docs/process-design.md"; }
CHECK="$SCRIPTS/check-docs.sh"

d="$(fixture)"
assert_status 0 "passes a good fixture" env REPO_ROOT="$d" "$CHECK"
words 600 >"$d/AGENTS.md"
assert_status 1 "fails AGENTS.md over 500 words" env REPO_ROOT="$d" "$CHECK"
words 200 >"$d/AGENTS.md"
assert_status 1 "fails AGENTS.md under 300 words" env REPO_ROOT="$d" "$CHECK"

d="$(fixture)"; words 501 >"$d/docs/STATE.md"
assert_status 1 "fails STATE.md over 500 words" env REPO_ROOT="$d" "$CHECK"
d="$(fixture)"; echo "leia o AGENTS.md" >"$d/CLAUDE.md"
assert_status 1 "fails CLAUDE.md that is not @AGENTS.md" env REPO_ROOT="$d" "$CHECK"
d="$(fixture)"; printf '\n## Histórico\n- fase 1\n' >>"$d/docs/STATE.md"
assert_status 1 "fails history section" env REPO_ROOT="$d" "$CHECK"
d="$(fixture)"; echo "# ADR-003" >"$d/docs/adr/ADR-003-x.md"
assert_status 1 "fails ADR without index line" env REPO_ROOT="$d" "$CHECK"
d="$(fixture)"; rm "$d/docs/adr/ADR-002-next.md"
assert_status 1 "fails index line without file" env REPO_ROOT="$d" "$CHECK"

# The design against the repository: the tables of scripts and hooks list
# exactly the files that exist, the file table cites no missing path, and the base rules
# are five rows with a lock that exists and no second path.
d="$(fixture)"; rm "$d/docs/process-design.md"
assert_status 1 "fails without the design" env REPO_ROOT="$d" "$CHECK"
d="$(fixture)"; edit_design "$d" 's#^| `scripts/gate.sh` | Barra | agentes |$#&\
| `scripts/ghost.sh` | Nada | ninguém |#'
assert_status 1 "fails a design that cites a script that does not exist" env REPO_ROOT="$d" "$CHECK"
assert_contains "$(last_output)" "cites scripts/ghost.sh, which does not exist" "names the missing script"
d="$(fixture)"; : >"$d/scripts/new-tool.py"
assert_status 1 "fails a design that omits a script that exists" env REPO_ROOT="$d" "$CHECK"
assert_contains "$(last_output)" "omits scripts/new-tool.py" "names the omitted script"
d="$(fixture)"; : >"$d/.claude/hooks/block-y.sh"
assert_status 1 "fails a design that omits an agent hook" env REPO_ROOT="$d" "$CHECK"
assert_contains "$(last_output)" "omits .claude/hooks/block-y.sh" "names the omitted hook"
d="$(fixture)"; rm "$d/.githooks/pre-commit"
assert_status 1 "fails a design that cites a git hook that does not exist" env REPO_ROOT="$d" "$CHECK"
assert_contains "$(last_output)" "cites .githooks/pre-commit, which does not exist" "names the missing hook"
d="$(fixture)"; rm "$d/AGENTS.md"; words 350 >"$d/AGENTS.txt"
assert_status 1 "fails a file table with a missing path" env REPO_ROOT="$d" "$CHECK"
assert_contains "$(last_output)" "file table cites AGENTS.md, which does not exist" "names the missing path"
d="$(fixture)"; edit_design "$d" '/^| 5\. Fim/d'
assert_status 1 "fails a base-rule table without five rules" env REPO_ROOT="$d" "$CHECK"
assert_contains "$(last_output)" "has 4 base rules (expected 5)" "counts the base rules"
d="$(fixture)"; edit_design "$d" 's#| 1 | Escreve a spec |#| 1 | Escreve a spec ou pergunta |#'
assert_status 1 "fails a base rule with a second path" env REPO_ROOT="$d" "$CHECK"
assert_contains "$(last_output)" "base rules leave a second path" "names the second path"
d="$(fixture)"; edit_design "$d" 's#| 2\. Filha | `.claude/hooks/block-x.sh` |#| 2. Filha | `.claude/hooks/gone.sh` |#'
assert_status 1 "fails a base rule whose lock does not exist" env REPO_ROOT="$d" "$CHECK"
assert_contains "$(last_output)" "base rule 2 names .claude/hooks/gone.sh, which does not exist" "names the missing lock"
d="$(fixture)"; edit_design "$d" 's#| 1 | Termina sem deploy |#|  | Termina sem deploy |#'
assert_status 1 "fails a base rule without an exit code" env REPO_ROOT="$d" "$CHECK"

# archive-adr: moves, swaps the link and marks it superseded; check-docs stays green.
d="$(fixture)"
git -C "$d" add docs >/dev/null 2>&1; git -C "$d" commit --quiet -m "docs: adrs"
assert_status 0 "archives ADR-001" env REPO_ROOT="$d" "$SCRIPTS/archive-adr.sh" 001 --by 002
assert_eq "yes" "$([ -f "$d/docs/adr/archive/ADR-001-core.md" ] && echo yes)" "file moved to archive/"
line="$(grep 'ADR-001' "$d/docs/adr/INDEX.md")"
assert_contains "$line" "(archive/ADR-001-core.md)" "index link points to archive"
assert_contains "$line" "substituída por ADR-002" "index marks replaced"
assert_status 0 "check-docs passes after archiving" env REPO_ROOT="$d" "$CHECK"
assert_status 1 "refuses unknown replacement" env REPO_ROOT="$d" "$SCRIPTS/archive-adr.sh" 002 --by 009
# Failure: an ADR without an index row is not declared archived, and nothing moves.
d="$(fixture)"
grep -v 'ADR-001' "$d/docs/adr/INDEX.md" >"$d/index.new"; mv "$d/index.new" "$d/docs/adr/INDEX.md"
assert_status 1 "fails when the index has no line for the ADR" env REPO_ROOT="$d" "$SCRIPTS/archive-adr.sh" 001 --by 002
assert_contains "$(last_output)" "has no line in docs/adr/INDEX.md" "says the index line is missing"
assert_eq "yes" "$([ -f "$d/docs/adr/ADR-001-core.md" ] && echo yes)" "nothing is moved"
finish
