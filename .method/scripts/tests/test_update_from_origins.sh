#!/usr/bin/env bash
# The update path is tested here, from real old origins to the tip (#310, #298 to #301).
# For each origin in update-origins.txt: a fake adopter at that commit with its own scripts/ file,
# the command of .github/update-notice.md for an origin before .method/, then validate.sh and check-docs.sh.
# Template only: needs the history of the template (CI fetches it whole) and tests/template.
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

[ -d "$REPO/.method/scripts/tests/template" ] || { echo "skip: not the template repository"; finish; exit 0; }
tip="$(git -C "$REPO" rev-parse HEAD)"
notice="$REPO/.github/update-notice.md"
default_url="https://github.com/FHDumont/ai-engineering-team-template"

# The command block the notice gives for an origin before the .method/ folder.
cmd="$(awk '/<!-- update-cmd:before-method -->/ {f=1; next} f && /^```/ {n++; if (n==2) exit; next} f && n==1 {print}' "$notice")"
if [ -z "$cmd" ]; then bad "update-notice.md has no update-cmd:before-method block"; finish; exit 1; fi

while read -r short _; do
  case "$short" in ""|\#*) continue ;; esac
  if ! origin="$(git -C "$REPO" rev-parse --verify --quiet "$short^{commit}")"; then
    bad "origin $short is not in the history (the CI fetches it whole)"
    continue
  fi
  adopter="$TMP/adopter-$short"
  mkdir -p "$adopter"
  git -C "$REPO" archive "$origin" | tar -C "$adopter" -xf -
  git -C "$adopter" init --quiet -b main
  git -C "$adopter" config user.email test@example.org
  git -C "$adopter" config user.name test
  git -C "$adopter" config commit.gpgsign false
  mkdir -p "$adopter/scripts" "$adopter/.github"
  printf '#!/usr/bin/env bash\necho app\n' >"$adopter/scripts/app-task.sh"
  chmod +x "$adopter/scripts/app-task.sh"
  printf '%s\n' "$origin" >"$adopter/.github/method-origin"
  git -C "$adopter" add -A
  git -C "$adopter" commit --quiet -m "chore: adopt at $short"

  run="${cmd//<destino-completo>/$tip}"
  run="${run//$default_url/$REPO}"
  if (cd "$adopter" && bash -c "set -e; $run") >"$TMP/update-$short.out" 2>&1; then ok; else
    tail -15 "$TMP/update-$short.out"; bad "$short: the command of the notice updates the adopter"; continue
  fi
  assert_eq "yes" "$([ -x "$adopter/.method/scripts/validate.sh" ] && echo yes || echo no)" "$short: the adopter has .method/scripts/validate.sh"
  assert_eq "scripts/app-task.sh" "$(git -C "$adopter" ls-files scripts)" "$short: only the application script stays in scripts/"

  # What the notice asks of the adopter by hand: the origin recorded and the CI mode.
  (cd "$adopter" && bash .method/scripts/setup-repo.sh --record-origin "$tip") >"$TMP/rec-$short.out" 2>&1 || { tail -5 "$TMP/rec-$short.out"; bad "$short: --record-origin"; }
  printf 'pr\n' >"$adopter/.github/ci-mode"
  git -C "$adopter" add -A
  git -C "$adopter" commit --quiet -m "chore: update the method" || true
  if (cd "$adopter" && env -u PROCESS_VALIDATE_RUNNING AI_METHOD_TEST_JOBS="${AI_METHOD_TEST_JOBS:-4}" .method/scripts/validate.sh --full) >"$TMP/validate-$short.out" 2>&1; then ok; else
    grep -E 'FAIL |not ok:|error' "$TMP/validate-$short.out" | head -20; bad "$short: validate.sh --full passes after the update"
  fi
  if (cd "$adopter" && .method/scripts/check-docs.sh) >"$TMP/docs-$short.out" 2>&1; then ok; else
    head -20 "$TMP/docs-$short.out"; bad "$short: check-docs.sh passes after the update"
  fi
done <"$TESTS_DIR/update-origins.txt"
finish
