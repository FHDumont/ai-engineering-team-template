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
words 700 >"$d/AGENTS.md"
assert_status 0 "passes AGENTS.md of 700 words (limit 800)" env REPO_ROOT="$d" "$CHECK"
words 801 >"$d/AGENTS.md"
assert_status 1 "fails AGENTS.md over 800 words" env REPO_ROOT="$d" "$CHECK"
words 200 >"$d/AGENTS.md"
assert_status 1 "fails AGENTS.md under 300 words" env REPO_ROOT="$d" "$CHECK"

d="$(fixture)"; words 800 >"$d/docs/STATE.md"
assert_status 0 "passes STATE.md of 800 words" env REPO_ROOT="$d" "$CHECK"
words 801 >"$d/docs/STATE.md"
assert_status 1 "fails STATE.md over 800 words" env REPO_ROOT="$d" "$CHECK"
assert_contains "$(last_output)" "allowed 1-800" "the message names the STATE.md limit"
assert_contains "$("$CHECK" --help)" "300-800" "--help names the AGENTS.md limit"
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
# Names of one repository stay out of the method: docs/repo-notes.md lists them.
d="$(fixture)"; printf '# Notas do repositório\n\n## Nomes só deste repositório\n\n- `AcmeBot`\n\n## Outra\n\n- `scripts/gate.sh`\n' >"$d/docs/repo-notes.md"
assert_status 0 "passes a design that cites no repository-only name" env REPO_ROOT="$d" "$CHECK"
echo "Pergunte ao AcmeBot." >>"$d/docs/process-design.md"
assert_status 1 "fails a design that cites a repository-only name" env REPO_ROOT="$d" "$CHECK"
assert_contains "$(last_output)" "cites the repository-only name AcmeBot" "names the repository-only name"
# The same list covers AGENTS.md and the skills; the path docs/repo-notes.md itself is allowed.
d="$(fixture)"; printf '# Notas do repositório\n\n## Nomes só deste repositório\n\n- `AcmeBot`\n- `repo-notes`\n' >"$d/docs/repo-notes.md"
echo "Notas: docs/repo-notes.md." >>"$d/AGENTS.md"; echo "Veja docs/repo-notes.md." >>"$d/.claude/skills/plan/SKILL.md"
assert_status 0 "passes method files that only cite the path docs/repo-notes.md" env REPO_ROOT="$d" "$CHECK"
echo "Pergunte ao AcmeBot." >>"$d/AGENTS.md"
assert_status 1 "fails an AGENTS.md that cites a repository-only name" env REPO_ROOT="$d" "$CHECK"
assert_contains "$(last_output)" "AGENTS.md cites the repository-only name AcmeBot" "names the file and the repository-only name"
d="$(fixture)"; printf '# Notas do repositório\n\n## Nomes só deste repositório\n\n- `AcmeBot`\n' >"$d/docs/repo-notes.md"
mkdir -p "$d/.claude/skills/ask-bot"; echo "Pergunte ao AcmeBot." >"$d/.claude/skills/ask-bot/notes.md"
assert_status 1 "fails a skill that cites a repository-only name" env REPO_ROOT="$d" "$CHECK"
assert_contains "$(last_output)" ".claude/skills/ask-bot/notes.md cites the repository-only name AcmeBot" "names the skill file"
d="$(fixture)"; mkdir -p "$d/.claude/skills/ask-bot"; echo "Pergunte ao AcmeBot." >"$d/.claude/skills/ask-bot/SKILL.md"
assert_status 0 "with no docs/repo-notes.md there is no list to check" env REPO_ROOT="$d" "$CHECK"

# #188: a script that exists but is not in the manifest is not "missing": say how to fix it.
d="$(fixture)"; mkdir -p "$d/.github"; printf 'scripts/gate.sh\n.claude/hooks/block-x.sh\n.githooks/pre-commit\n' >"$d/.github/method-files.txt"
: >"$d/scripts/only-here.sh"
edit_design "$d" 's#^| `scripts/gate.sh` | Barra | agentes |$#&\
| `scripts/only-here.sh` | Do repo | ninguém |#'
assert_status 1 "fails a documented script that is only in this repository and not in the manifest" env REPO_ROOT="$d" "$CHECK"
assert_contains "$(last_output)" "scripts/only-here.sh exists but is not in .github/method-files.txt" "says the file exists and the manifest lacks it"
assert_contains "$(last_output)" "add it to the manifest" "says how to fix it"
assert_not_contains "$(last_output)" "only-here.sh, which does not exist" "does not claim the file is missing"
# #193: AGENTS.md points to docs/repo-notes.md; a repository updated from an old version lacks it.
d="$(fixture)"; echo "Regras do projeto: docs/repo-notes.md." >>"$d/AGENTS.md"
assert_status 0 "a missing docs/repo-notes.md only warns" env REPO_ROOT="$d" "$CHECK"
assert_contains "$(last_output)" "warn: AGENTS.md points to docs/repo-notes.md, which does not exist" "warns about the missing notes"
printf '# Notas\n\n## Nomes só deste repositório\n\n- `AcmeBot`\n' >"$d/docs/repo-notes.md"
assert_status 0 "no warning once the file exists" env REPO_ROOT="$d" "$CHECK"
assert_not_contains "$(last_output)" "repo-notes.md, which does not exist" "silent when the notes exist"
assert_contains "$(cat "$REPO/docs/repo-notes.md" 2>/dev/null)" "## Nomes só deste repositório" "the template ships a model of docs/repo-notes.md"

# A hook cited in settings.json that does not exist fails the check.
d="$(fixture)"
mkdir -p "$d/.claude/hooks"
printf '%s\n' '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"\"${CLAUDE_PROJECT_DIR}\"/.claude/hooks/gone.sh"}]}]}}' >"$d/.claude/settings.json"
assert_status 1 "fails a settings.json that cites a missing hook" env REPO_ROOT="$d" "$CHECK"
assert_contains "$(last_output)" "gone.sh" "names the missing hook cited in settings.json"
d="$(fixture)"
mkdir -p "$d/.claude/hooks"
: >"$d/.claude/hooks/block-x.sh"
printf '%s\n' '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"\"${CLAUDE_PROJECT_DIR}\"/.claude/hooks/block-x.sh"}]}]}}' >"$d/.claude/settings.json"
assert_status 0 "passes when every cited hook exists" env REPO_ROOT="$d" "$CHECK"

# Issue templates are Markdown: a YAML issue form is refused; only config.yml may be YAML.
d="$(fixture)"; mkdir -p "$d/.github/ISSUE_TEMPLATE"
printf 'blank_issues_enabled: false\n' >"$d/.github/ISSUE_TEMPLATE/config.yml"; : >"$d/.github/ISSUE_TEMPLATE/bug.md"
assert_status 0 "passes Markdown templates and config.yml" env REPO_ROOT="$d" "$CHECK"
for form in bug.yml feature.yaml; do
  d="$(fixture)"; mkdir -p "$d/.github/ISSUE_TEMPLATE"; printf 'name: x\nbody: []\n' >"$d/.github/ISSUE_TEMPLATE/$form"
  assert_status 1 "fails the issue form $form" env REPO_ROOT="$d" "$CHECK"
  assert_contains "$(last_output)" ".github/ISSUE_TEMPLATE/$form is an issue form" "names the issue form $form"
done
forms="$(cd "$REPO" && git ls-files -co --exclude-standard .github/ISSUE_TEMPLATE | grep -E '\.ya?ml$' | grep -vxF .github/ISSUE_TEMPLATE/config.yml || true)"
assert_eq "" "$forms" "this repository has no issue form"

# archive-adr: moves, swaps the link and marks it "substituída"; check-docs stays green.
d="$(fixture)"
git -C "$d" add docs >/dev/null 2>&1; git -C "$d" commit --quiet -m "docs: adrs"
assert_status 0 "archives ADR-001" env REPO_ROOT="$d" "$SCRIPTS/archive-adr.sh" 001 --by 002
assert_eq "yes" "$([ -f "$d/docs/adr/archive/ADR-001-core.md" ] && echo yes)" "file moved to archive/"
line="$(grep 'ADR-001' "$d/docs/adr/INDEX.md")"
assert_contains "$line" "(archive/ADR-001-core.md)" "index link points to archive"
assert_contains "$line" "substituída por ADR-002" "index marks replaced"
assert_status 0 "check-docs passes after archiving" env REPO_ROOT="$d" "$CHECK"
assert_status 1 "refuses unknown replacement" env REPO_ROOT="$d" "$SCRIPTS/archive-adr.sh" 002 --by 009
# Failure: an ADR with no line in the index is not declared archived, and nothing moves.
d="$(fixture)"
grep -v 'ADR-001' "$d/docs/adr/INDEX.md" >"$d/index.new"; mv "$d/index.new" "$d/docs/adr/INDEX.md"
assert_status 1 "fails when the index has no line for the ADR" env REPO_ROOT="$d" "$SCRIPTS/archive-adr.sh" 001 --by 002
assert_contains "$(last_output)" "has no line in docs/adr/INDEX.md" "says the index line is missing"
assert_eq "yes" "$([ -f "$d/docs/adr/ADR-001-core.md" ] && echo yes)" "nothing is moved"

# CHANGELOG.md and ROADMAP.md are generated at the end of the first group (#100).
d="$(fixture)"
edit_design "$d" '/^| `scripts\/` | scripts |$/a\
| `CHANGELOG.md` | gerado no fim do primeiro grupo |\
| `ROADMAP.md` | gerado no fim do primeiro grupo |'
assert_status 0 "generated files are optional before the first group" env REPO_ROOT="$d" "$CHECK"
printf 'x\n' >"$d/CHANGELOG.md"
assert_status 1 "one generated file requires the other" env REPO_ROOT="$d" "$CHECK"
assert_contains "$(last_output)" "ROADMAP.md" "names the generated file that is still missing"
printf 'y\n' >"$d/ROADMAP.md"
assert_status 0 "both generated files present passes" env REPO_ROOT="$d" "$CHECK"

# Facts of the method do not age inside STATE.md (#118).
d="$(fixture)"
printf '\no job tests roda em todo PR\n' >>"$d/docs/STATE.md"
assert_status 1 "fails a STATE that says tests run on every PR" env REPO_ROOT="$d" "$CHECK"
assert_contains "$(last_output)" "STATE.md repeats a method fact that is no longer true" "names the stale fact"
d="$(fixture)"
printf '\nsetup-repo.sh saindo 6 sem proteção\n' >>"$d/docs/STATE.md"
assert_status 1 "fails a STATE that says setup exits 6 without protection" env REPO_ROOT="$d" "$CHECK"

# The design lists the method manifest, not every file an application drops in scripts/ (#101).
d="$(fixture)"
mkdir -p "$d/.github"
printf 'scripts/gate.sh\n.claude/hooks/block-x.sh\n.githooks/pre-commit\n' >"$d/.github/method-files.txt"
: >"$d/scripts/app-only.sh"
assert_status 0 "an application script outside the method manifest passes" env REPO_ROOT="$d" "$CHECK"
printf 'scripts/gate.sh\nscripts/missing-method.sh\n.claude/hooks/block-x.sh\n.githooks/pre-commit\n' >"$d/.github/method-files.txt"
assert_status 1 "a manifest entry that is not on disk fails" env REPO_ROOT="$d" "$CHECK"
assert_contains "$(last_output)" "method-files.txt lists scripts/missing-method.sh, which does not exist" "names the missing manifest entry"

# ADR-NNN.md (no title in the file name) is a real ADR (#102).
d="$(fixture)"
echo "# ADR-003" >"$d/docs/adr/ADR-003.md"
printf '| [ADR-003](ADR-003.md) | Sem título | vigente |\n' >>"$d/docs/adr/INDEX.md"
assert_status 0 "accepts ADR-NNN.md without a title" env REPO_ROOT="$d" "$CHECK"
assert_status 0 "archives an ADR named ADR-NNN.md" env REPO_ROOT="$d" "$SCRIPTS/archive-adr.sh" 003 --by 002
assert_eq "yes" "$([ -f "$d/docs/adr/archive/ADR-003.md" ] && echo yes)" "untitled ADR moved to archive/"
assert_status 0 "check-docs passes after archiving ADR-NNN.md" env REPO_ROOT="$d" "$CHECK"

finish
