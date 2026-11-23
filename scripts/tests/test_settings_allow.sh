#!/usr/bin/env bash
# The method's allow list names each script; it never grants scripts/* or a
# generic git push. Adoption must show the permission diff before the new
# settings are what the session uses.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

settings="$REPO/.claude/settings.json"
allow="$(jq -r '.permissions.allow[]' "$settings")"

assert_not_contains "$allow" 'Bash(scripts/*)' "allow does not grant scripts/*"
assert_not_contains "$allow" 'Bash(./scripts/*)' "allow does not grant ./scripts/*"
assert_not_contains "$allow" 'Bash(git push *)' "allow does not grant a generic git push"
# A glob that would cover every script in scripts/ is refused, even if written
# with a different prefix or without the Bash() wrapper in a future edit.
while IFS= read -r line; do
  case "$line" in
    *'scripts/*'*|*'./scripts/'*)
      bad "allow still has a scripts glob: $line" ;;
  esac
done <<<"$allow"

# Every method script is listed by name so adoption does not widen to app scripts.
missing=""
for f in "$REPO"/scripts/*.sh "$REPO"/scripts/*.py; do
  [ -f "$f" ] || continue
  name="${f#"$REPO"/}"
  echo "$allow" | grep -qxF "Bash($name *)" || missing="$missing $name"
done
assert_eq "" "$missing" "allow lists every method script by name"

adopt="$(awk '$0 == "## Adotar num repositório que já existe" {on=1; next} /^## / {on=0} on' "$REPO/README.md")"
# The template README has the chapter. A project replaces that file, so the
# prose is checked only while the chapter is still here.
if [ -n "$adopt" ]; then
  assert_contains "$adopt" "diff" "adoption shows the permission diff"
  assert_contains "$adopt" "ok" "adoption waits for the owner's ok before the new settings are used"
fi
assert_contains "$(awk '/^### 10.4 / {on=1; next} /^### / {on=0} on' "$REPO/docs/process-design.md")" "pelo nome" "the design says allow lists scripts by name"
finish
