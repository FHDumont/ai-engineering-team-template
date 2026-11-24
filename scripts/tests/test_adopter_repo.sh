#!/usr/bin/env bash
# The method tests read only the files of the method: a repo that adopts the method and has
# its own scripts, ADRs and ci.yml stays green (#245).
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

fake="$TMP/adopter"
mkdir -p "$fake"
(cd "$REPO" && git ls-files -co --exclude-standard -z | tar --null -T - -cf -) | tar -x -C "$fake"
git -C "$fake" init -q
git -C "$fake" config user.email t@example.org
git -C "$fake" config user.name t
git -C "$fake" config commit.gpgsign false

# What an application adds: a script that cites #n, an ADR of its own with the old
# heartbeat interval, a script outside scripts/ without the guard, and a ci.yml with
# no app filter line.
was=8
printf '#!/usr/bin/env bash\n# see #12\n' >"$fake/scripts/app_report.sh"
printf 'Check every %s min\n' "$was" >"$fake/docs/adr/ADR-900-app-decision.md"
mkdir -p "$fake/infra/scripts"
printf '#!/usr/bin/env bash\nset -euo pipefail\necho x | grep -q x\n' >"$fake/infra/scripts/deploy.sh"
grep -v 'echo "app=' "$fake/.github/workflows/ci.yml" >"$fake/ci.yml.new"
mv "$fake/ci.yml.new" "$fake/.github/workflows/ci.yml"
git -C "$fake" add -A
git -C "$fake" commit -q -m "chore: adopter files"

for t in test_issue_refs.sh test_phase_texts.sh test_pipefail.sh; do
  rc=0
  (cd "$fake" && bash "scripts/tests/$t" >"$TMP/$t.out" 2>&1) || rc=$?
  assert_eq 0 "$rc" "$t passes in a repo with application files ($(tail -3 "$TMP/$t.out" | tr '\n' ' '))"
done

rc=0
out="$(cd "$fake" && python3 -c "
import sys
sys.path.insert(0, 'scripts/tests')
import test_workflow_tools as t
print(t.app_filter_sample())" 2>&1)" || rc=$?
assert_eq 0 "$rc" "app_filter_sample has a default path without the app line ($out)"
finish
