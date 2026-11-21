#!/usr/bin/env bash
# Test of the adoption chapters of README.md: every path and script command they
# cite exists in this repository, and the topics the issue asks for are covered.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

readme="$REPO/README.md"
section() { # section <heading>: the text of a "## " section of the README
  awk -v h="## $1" '$0 == h {on=1; next} /^## / {on=0} on' "$readme"
}
adopt="$(section "Adotar num repositório que já existe")"
update="$(section "Atualizar um repositório que já usa o método")"

assert_contains "$adopt" "1. **Pré-requisitos." "the adoption chapter has numbered steps"
assert_not_contains "$adopt" "TODO" "the chapter has no placeholder"
[ -n "$update" ] && ok || bad "the update section is missing"

# Topics the chapter must cover.
for topic in "gh auth status" "proteção de branch" "branch de adoção" "O que sai" "O que entra" \
  "O que NÃO se copia" "workflow_dispatch" "# deploy-paths:" "scripts/validate.sh" \
  "scripts/check-docs.sh" "configurar o repo" "labels antigas" "Primeira fase"; do
  assert_contains "$adopt" "$topic" "the chapter covers: $topic"
done
assert_contains "$adopt" "deploy-example.yml" "the chapter says deploy-example.yml is not copied"
assert_contains "$adopt" "docs/specs/" "the chapter says docs/specs/ is not copied"
assert_contains "$adopt" "CHANGELOG.md" "the chapter says CHANGELOG.md is not copied"

# Every `code span` that is a path or a script command must exist here.
check_spans() { # check_spans <text>
  local span first
  printf '%s\n' "$1" | grep -o '`[^`]*`' | tr -d '`' | sort -u | while IFS= read -r span; do
    first="${span%% *}"
    case "$first" in
      python3) first="$(printf '%s' "$span" | awk '{print $2}')" ;;
      git|gh|'#'*|'--'*|'<'*) continue ;;
      # Lines of the adopter's .gitignore and names that are not files of this repo.
      .process/|.worktrees/|__pycache__/|review/independent|package.json) continue ;;
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
  docs/process-design.md docs/adr docs/diagrams scripts/lib scripts/tests; do
  [ -e "$REPO/$p" ] && ok || bad "template path missing: $p"
done

# The spans the checker reads must be non-empty, so the test cannot pass on nothing.
n="$(printf '%s\n' "$adopt" | grep -o '`[^`]*`' | wc -l | tr -d ' ')"
[ "$n" -gt 30 ] && ok || bad "the chapter cites too few paths ($n)"

[ "$FAILS" = 0 ] || { echo "$FAILS of $COUNT checks failed"; exit 1; }
echo "ok: $COUNT checks"
