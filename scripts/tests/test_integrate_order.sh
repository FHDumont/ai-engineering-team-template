#!/usr/bin/env bash
# Issues that change the roadmap are opened before gen-docs.sh (issue #157).
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

skill="$(cat "$REPO/.claude/skills/integrate/SKILL.md")"
design="$(cat "$REPO/docs/process-design.md")"
line() { printf '%s\n' "$skill" | grep -n "$1" | head -1 | cut -d: -f1; }
g="$(line 'scripts/gen-docs.sh')"
t="$(line 'Tempo é só informativo')"
a="$(line 'Achados leves')"
before() { # before <earlier> <later> <description>
  if [ -n "$1" ] && [ -n "$2" ] && [ "$1" -lt "$2" ]; then ok; else bad "$3 (lines '$1' then '$2')"; fi
}
before "$t" "$g" "the time lines are read before gen-docs.sh"
before "$a" "$g" "group findings are opened before gen-docs.sh"
assert_contains "$skill" "Nada que muda o roadmap" "the skill says nothing that changes the roadmap happens after gen-docs"
assert_contains "$design" "Nada que muda o roadmap" "the design says nothing that changes the roadmap happens after gen-docs"
order="$(printf '%s\n' "$skill" | grep -oE 'scripts/gen-docs\.sh|scripts/deploy\.sh|archive_session|scripts/end-check\.sh' | awk '!seen[$0]++' | paste -sd' ' -)"
assert_eq "scripts/gen-docs.sh scripts/deploy.sh archive_session scripts/end-check.sh" "$order" "the end step keeps gen-docs, deploy, archive, end-check"

finish
