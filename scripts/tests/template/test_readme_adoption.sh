#!/usr/bin/env bash
# Test of the adoption chapters of README.md: every path and script command they
# cite exists in this repository, and the topics the issue asks for are covered.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/../lib.sh"

readme="$REPO/README.md"
section() { # section <heading>: the text of a "## " section of the README
  awk -v h="## $1" '$0 == h {on=1; next} /^## / {on=0} on' "$readme"
}
adopt="$(section "Adotar num repositório que já existe")"
update="$(section "Atualizar um repositório que já usa o método")"

assert_contains "$adopt" "1. **Pré-requisitos." "the adoption chapter has numbered steps"
assert_not_contains "$adopt" "TODO" "the chapter has no placeholder"
[ -n "$update" ] && ok || bad "the update section is missing"
assert_contains "$update" "linhas de método do" "the update guide reviews the method lines of STATE"
assert_contains "$update" "time-targets.tsv" "the update guide asks for the time target when it is missing"
assert_contains "$update" "machine-limits.env" "the update guide asks for the machine limits when they are missing"
assert_contains "$update" "divergências locais" "the update guide says where local divergences are recorded"
assert_contains "$update" "caminho absoluto" "the update guide says which copies apply during the update phase"
assert_contains "$(cat "$REPO/.claude/skills/execute/SKILL.md")" "caminho absoluto" "the execute skill tells the child to read the worktree skills by path"

# Topics the chapter must cover.
for topic in "gh auth status" "proteção de branch" "branch de adoção" "O que sai" "O que entra" \
  "O que NÃO se copia" "workflow_dispatch" "# deploy-paths:" "scripts/validate.sh" \
  "scripts/check-docs.sh" "configurar o repo" "labels antigas" "Primeira fase" \
  "Inventarie os hooks" "deny"; do
  assert_contains "$adopt" "$topic" "the chapter covers: $topic"
done
assert_contains "$adopt" "deploy-example.yml" "the chapter says deploy-example.yml is not copied"
assert_contains "$adopt" "docs/specs/" "the chapter says docs/specs/ is not copied"
assert_contains "$adopt" "CHANGELOG.md" "the chapter says CHANGELOG.md is not copied"
assert_contains "$(cat "$REPO/README.md")" "meta de tempo" "the quick start mentions the time target"
readme="$(cat "$REPO/README.md")"
warn_at="$(printf '%s\n' "$readme" | awk '/Antes de ligar a proteção/{print NR; exit}')"
setup_at="$(printf '%s\n' "$readme" | awk '/O agente roda `scripts\/setup-repo.sh`/{print NR; exit}')"
assert_contains "$readme" 'fix/issue-*' "the README names the phase branch the warning is about"
assert_contains "$readme" '--owner-ok' "the README names --owner-ok"
if [ -n "$warn_at" ] && [ -n "$setup_at" ] && [ "$warn_at" -lt "$setup_at" ]; then
  ok
else
  bad "the README warns before setup turns protection on (warning line ${warn_at:-none}, setup line ${setup_at:-none})"
fi
assert_contains "$(cat "$REPO/AGENTS.md")" "docs/repo-notes.md" "AGENTS.md points at the project rules"
n="$(wc -w <"$REPO/AGENTS.md" | tr -d ' ')"
max="$(sed -n 's/^limit AGENTS.md [0-9]* \([0-9]*\)$/\1/p' "$SCRIPTS/check-docs.sh")"
[ -n "$max" ] && [ "$n" -le $((max - 20)) ] && ok || bad "AGENTS.md has $n words (leave room under ${max:-?}, the limit of check-docs.sh)"
# The update chapter records the CI mode, creates the repo notes, names the manifest and asks no test phase.
assert_contains "$update" ".github/ci-mode" "the update guide records the CI mode"
assert_contains "$update" "docs/repo-notes.md" "the update guide creates docs/repo-notes.md"
assert_contains "$update" ".github/method-files.txt" "the update guide says a script only of the repo goes in the manifest"
assert_not_contains "$update" "fase \`test\`" "the update guide asks for no post-merge test phase"
assert_contains "$adopt" "git worktree add" "adoption uses a worktree"
assert_not_contains "$adopt" "git switch -c" "adoption does not switch the main checkout"
assert_contains "$adopt" "não apague" "adoption does not wipe an existing glossary"
assert_contains "$adopt" "CONTEXT.md" "adoption names the glossary"
assert_contains "$adopt" "compartilhad" "adoption warns that the hook path is shared by every worktree"
assert_contains "$adopt" ".process/" "adoption warns where the trace is written"
assert_contains "$adopt" "pendências" "adoption migrates open items from the old process"
assert_contains "$adopt" "código que já existe" "the language rule does not rewrite existing code"
assert_contains "$adopt" "script do método" "the owner-runs-scripts rule is about the method"
assert_contains "$adopt" "Antes de ligar a proteção" "the adoption chapter warns before setup turns protection on"
assert_contains "$adopt" '--owner-ok' "the adoption chapter names --owner-ok"
assert_contains "$adopt" "repositório privado" "a private repo is told the CI cost before taking ci.yml"
assert_contains "$adopt" "recusar" "the chapter says what happens when the owner refuses CI on main"
assert_contains "$adopt" "só nos pull requests" "refusal keeps CI on pull requests"
assert_contains "$(cat "$REPO/docs/process-design.md")" "código que já existe" "the design does not rewrite existing code"
assert_contains "$(cat "$REPO/docs/process-design.md")" "script do método" "the design scopes the owner rule to the method"

# Every `code span` that is a path or a script command must exist here.
check_spans() { # check_spans <text>
  local span first
  printf '%s\n' "$1" | grep -o '`[^`]*`' | tr -d '`' | sort -u | while IFS= read -r span; do
    first="${span%% *}"
    case "$first" in
      python3) first="$(printf '%s' "$span" | awk '{print $2}')" ;;
      git|gh|'#'*|'--'*|'<'*) continue ;;
      # Lines of the adopter's .gitignore and names that are not files of this repo.
      .process/|.worktrees/|__pycache__/|review/independent|package.json|.github/ci-mode) continue ;;
    esac
    case "$first" in *'<'*|*'*'*|*'{'*|'') continue ;; esac
    case "$first" in
      */*|*.md|*.yml|*.tsv|*.json|*.sh|*.py)
        [ -e "$REPO/$first" ] || echo "missing path: $span" ;;
    esac
    # A flag of a script must appear in that script's source (its --help).
    case "$first" in
      scripts/*.sh|scripts/*.py)
        for flag in $(printf '%s' "$span" | grep -oE -- '--[a-z-]+'); do
          grep -q -- "$flag" "$REPO/$first" || echo "unknown flag $flag in: $span"
        done ;;
    esac
  done
}
problems="$(check_spans "$adopt"; check_spans "$update")"
assert_eq "" "$problems" "every path and command cited by the chapters exists"

# The folders listed in "O que entra" are all there.
for p in AGENTS.md CLAUDE.md CONTEXT.md .claude/agents .claude/commands .claude/hooks .claude/skills \
  .claude/settings.json .cursor/rules .githooks .github/ISSUE_TEMPLATE .github/workflows/ci.yml \
  .github/required-checks docs/process-design.md docs/adr docs/diagrams scripts/lib scripts/tests; do
  [ -e "$REPO/$p" ] && ok || bad "template path missing: $p"
done

# The spans the checker reads must be non-empty, so the test cannot pass on nothing.
n="$(printf '%s\n' "$adopt" | grep -o '`[^`]*`' | wc -l | tr -d ' ')"
[ "$n" -gt 30 ] && ok || bad "the chapter cites too few paths ($n)"

[ "$FAILS" = 0 ] || { echo "$FAILS of $COUNT checks failed"; exit 1; }
echo "ok: $COUNT checks"
