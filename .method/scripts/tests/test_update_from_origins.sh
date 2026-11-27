#!/usr/bin/env bash
# The update path is tested here, from real old origins to the tip (#310, #298 to #301).
# For each origin in update-origins.txt: a fake adopter at that commit with its own scripts/ file,
# the command of .github/update-notice.md for an origin before .method/, then validate.sh and check-docs.sh.
# Template only: needs the history of the template (CI fetches it whole) and tests/template.
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

[ -d "$REPO/.method/scripts/tests/template" ] || { echo "skip: not the template repository"; finish; exit 0; }
# UPDATE_TIP: a template commit to update to instead of HEAD (to prove the test red on code before a fix).
tip="${UPDATE_TIP:-$(git -C "$REPO" rev-parse HEAD)}"
# The test job of the CI clones shallow: bring the history once, it only adds objects.
if [ "$(git -C "$REPO" rev-parse --is-shallow-repository)" = true ]; then
  git -C "$REPO" fetch --quiet --unshallow --no-tags origin 2>/dev/null || true
fi
notice="$REPO/.github/update-notice.md"
default_url="https://github.com/FHDumont/ai-engineering-team-template"

# The command block the notice gives for an origin before the .method/ folder.
cmd="$(awk '/<!-- update-cmd:before-method -->/ {f=1; next} f && /^```/ {n++; if (n==2) exit; next} f && n==1 {print}' "$notice")"
if [ -z "$cmd" ]; then bad "update-notice.md has no update-cmd:before-method block"; finish; exit 1; fi

while read -r short _; do
  case "$short" in ""|\#*) continue ;; esac
  if ! origin="$(git -C "$REPO" rev-parse --verify --quiet "$short^{commit}")"; then
    bad "origin $short is not in the history (a shallow clone needs the network for the history)"
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
  # #301: the origin check-docs.sh the notice names exists in the origin.
  shown="$(sed -n 's/.*git -C [^ ]* show \([0-9a-f]*:[^ ]*check-docs.sh\).*/\1/p' "$TMP/update-$short.out" | head -1)"
  if [ -n "$shown" ]; then
    git -C "$REPO" show "$shown" >/dev/null 2>&1 && ok || bad "$short: the notice names $shown, which is not in the origin"
  fi
  # #298: a short sha of the destination resolves.
  (cd "$adopter" && bash .method/scripts/fetch-template.sh "${tip:0:7}" --url "$REPO") >"$TMP/short-$short.out" 2>&1 && ok || { tail -3 "$TMP/short-$short.out"; bad "$short: fetch-template.sh takes a short sha"; }
  git -C "$adopter" add -A
  assert_eq "scripts/app-task.sh" "$(git -C "$adopter" ls-files scripts)" "$short: only the application script stays in scripts/"

  # The adapted files the notice lists are merged by hand; this adopter changed none, so the merge is the tip's file.
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    mkdir -p "$adopter/$(dirname "$f")"
    git -C "$REPO" show "$tip:$f" >"$adopter/$f"
  done < <(sed -n 's/^- \[ \] `adapted`: `\(.*\)`$/\1/p' "$TMP/update-$short.out")
  # What the notice asks of the adopter by hand: repo-notes.md from the model, the old STATE sentence out, the origin recorded and the CI mode.
  [ -f "$adopter/docs/repo-notes.md" ] || git -C "$REPO" show "$tip:docs/repo-notes.md" >"$adopter/docs/repo-notes.md"
  # The sentence the notice item says to take out of docs/STATE.md (it is also what method-diff.sh looks for).
  grep -vF 'o job `tests` roda em todo PR' "$adopter/docs/STATE.md" >"$adopter/docs/STATE.md.new" || true
  mv "$adopter/docs/STATE.md.new" "$adopter/docs/STATE.md"
  (cd "$adopter" && bash .method/scripts/setup-repo.sh --record-origin "$tip") >"$TMP/rec-$short.out" 2>&1 || { tail -5 "$TMP/rec-$short.out"; bad "$short: --record-origin"; }
  printf 'push\n' >"$adopter/.github/ci-mode"
  git -C "$adopter" add -A
  git -C "$adopter" commit --quiet -m "chore: update the method" || true
  # The whole suite three times does not fit the job of the CI: by default validate.sh --lint and the tests that read the
  # paths and docs the update touches; UPDATE_TEST_FULL=1 runs validate.sh --full, as the tag of a group does.
  vargs=(--lint)
  [ "${UPDATE_TEST_FULL:-}" != 1 ] || vargs=(--full)
  if (cd "$adopter" && env -u PROCESS_VALIDATE_RUNNING AI_METHOD_TEST_JOBS="${AI_METHOD_TEST_JOBS:-4}" .method/scripts/validate.sh "${vargs[@]}") >"$TMP/validate-$short.out" 2>&1; then ok; else
    grep -E -A12 'FAIL |not ok:' "$TMP/validate-$short.out" | head -60; tail -5 "$TMP/validate-$short.out"; bad "$short: validate.sh ${vargs[*]} passes after the update"
  fi
  if [ "${UPDATE_TEST_FULL:-}" != 1 ]; then
    for t in test_method_folder.sh test_docs_tools.sh test_issue_refs.sh test_adopter_repo.sh test_settings_allow.sh test_workflow_tools.py; do
      if [ "${t##*.}" = py ]; then runner=python3; else runner=bash; fi
      if (cd "$adopter" && env -u PROCESS_VALIDATE_RUNNING "$runner" ".method/scripts/tests/$t") >"$TMP/t-$short-$t.out" 2>&1; then ok; else
        tail -15 "$TMP/t-$short-$t.out"; bad "$short: $t passes after the update"
      fi
    done
  fi
  if (cd "$adopter" && .method/scripts/check-docs.sh) >"$TMP/docs-$short.out" 2>&1; then ok; else
    head -20 "$TMP/docs-$short.out"; bad "$short: check-docs.sh passes after the update"
  fi
done <"${UPDATE_ORIGINS_FILE:-$TESTS_DIR/update-origins.txt}"
finish
