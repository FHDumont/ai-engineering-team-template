#!/usr/bin/env bash
# Tests of setup-repo.sh: the --dry-run diff, applying, and idempotence.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"
SETUP="$SCRIPTS/setup-repo.sh"

# "Already compliant" state: all the tsv labels, settings and protection correct.
labels_json="$(grep -v '^#' "$REPO/.github/labels.tsv" | jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t") | {name: .[0], color: .[1], description: .[2]})')"
cat >"$TMP/conform.sh" <<H
case "\$*" in
  "label list"*) echo '$labels_json' ;;
  "api repos/owner/repo --jq"*) echo '{"allow_auto_merge":true,"allow_merge_commit":false,"allow_squash_merge":false,"allow_rebase_merge":true,"delete_branch_on_merge":true}' ;;
  "api repos/owner/repo/branches/main/protection") cat <<'J'
{"required_status_checks":{"strict":false,"checks":[{"context":"review/independent","app_id":null},{"context":"CI","app_id":15368}]},
 "enforce_admins":{"enabled":true},"required_pull_request_reviews":{"required_approving_review_count":0},
 "required_linear_history":{"enabled":true},"allow_force_pushes":{"enabled":false},"allow_deletions":{"enabled":false}}
J
  ;;
esac
H
use_fake_gh "$TMP/conform.sh"
out="$("$SETUP")"
assert_contains "$out" "no changes" "idempotent: conforming repo is left alone"
assert_not_contains "$(gh_calls)" "-X PUT" "no protection write when conforming"
assert_not_contains "$(gh_calls)" "label create" "no label write when conforming"

# "New" state: default GitHub labels, settings and no protection.
cat >"$TMP/fresh.sh" <<'H'
case "$*" in
  "label list"*) echo '[{"name":"bug","color":"d73a4a","description":"x"},{"name":"wontfix","color":"ffffff","description":"x"},{"name":"type:chore","color":"C5DEF5","description":"Manutenção, processo ou ferramenta"}]' ;;
  "api repos/owner/repo --jq"*) echo '{"allow_auto_merge":false,"allow_merge_commit":true,"allow_squash_merge":true,"allow_rebase_merge":true,"delete_branch_on_merge":false}' ;;
  "api repos/owner/repo/branches/main/protection")
    # FAKE_PLAN=free: the plan has no branch protection (private repo on a free account).
    if [ -n "${FAKE_PLAN:-}" ]; then
      echo '{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.","status":"403"}'
      echo "gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)" >&2; exit 1
    fi
    # After the PUT the protection reads back as applied, unless FAKE_PUT_LOST.
    if [ -f "$TMP/protected" ]; then
      cat <<'J'
{"required_status_checks":{"strict":false,"checks":[{"context":"review/independent","app_id":null},{"context":"CI","app_id":15368}]},
 "enforce_admins":{"enabled":true},"required_pull_request_reviews":{"required_approving_review_count":0},
 "required_linear_history":{"enabled":true},"allow_force_pushes":{"enabled":false},"allow_deletions":{"enabled":false}}
J
    else
      echo '{"message":"Branch not protected"}'; exit 1
    fi ;;
  "api -X PUT"*) cat >"$FAKE_GH_LOG.body.$RANDOM"; [ -n "${FAKE_PUT_LOST:-}" ] || touch "$TMP/protected" ;;
  "api -X PATCH"*) cat >"$FAKE_GH_LOG.body.$RANDOM" ;;
esac
H
export TMP
use_fake_gh "$TMP/fresh.sh"
out="$("$SETUP" --dry-run)"
assert_contains "$out" "would: rename label bug -> type:bug" "dry-run shows rename"
assert_contains "$out" "would: delete default label wontfix" "dry-run shows default deletion"
assert_contains "$out" "would: protect main" "dry-run shows protection"
assert_not_contains "$out" "update label type:chore" "color case is ignored"
assert_not_contains "$(gh_calls)" "label create" "dry-run writes nothing"
assert_not_contains "$(gh_calls)" "-X PUT" "dry-run does not protect"

out="$("$SETUP")"
calls="$(gh_calls)"
assert_contains "$calls" "label edit bug --repo owner/repo --name type:bug" "renames with gh label edit --name"
assert_contains "$calls" "label delete wontfix --repo owner/repo --yes" "deletes default labels"
assert_contains "$calls" "api -X PUT repos/owner/repo/branches/main/protection" "applies protection"
assert_contains "$calls" "api -X PATCH repos/owner/repo" "applies settings"
body="$(cat "$FAKE_GH_LOG".body.* | jq -s -c 'map(select(.required_status_checks)) | first')"
assert_eq '["CI@15368","review/independent@any"]' "$(echo "$body" | jq -c '[.required_status_checks.checks[] | .context + "@" + ((.app_id // "any") | tostring)]')" "requires CI (from Actions) + review/independent"
assert_eq "false true 0 true false false" "$(echo "$body" | jq -r '[.required_status_checks.strict, .enforce_admins, .required_pull_request_reviews.required_approving_review_count, .required_linear_history, .allow_force_pushes, .allow_deletions] | map(tostring) | join(" ")')" "protection matches §10.1"
settings="$(cat "$FAKE_GH_LOG".body.* | jq -s -c 'map(select(has("allow_squash_merge"))) | first')"
assert_eq '{"allow_auto_merge":true,"allow_merge_commit":false,"allow_rebase_merge":true,"allow_squash_merge":false,"delete_branch_on_merge":true}' "$(echo "$settings" | jq -S -c .)" "settings match §10.1"
assert_contains "$out" "(read back)" "protection is declared after reading back"

# Protection: a plan without branch protection has its own message; a PUT that does not
# show up on read-back is not declared done.
for flags in "--only protection" "--only protection --dry-run"; do
  : >"$FAKE_GH_LOG"
  # shellcheck disable=SC2086
  assert_status 6 "plan without branch protection exits 6 ($flags)" env FAKE_PLAN=free "$SETUP" $flags
  assert_contains "$(last_output)" "branch protection is not available for owner/repo on the current GitHub plan" "plan: own message ($flags)"
  assert_contains "$(last_output)" "make the repository public or upgrade the plan" "plan: says the fix ($flags)"
  assert_not_contains "$(last_output)" "done: protect" "plan: never declares the protection done ($flags)"
  assert_not_contains "$(gh_calls)" "-X PUT" "plan: never tries the write ($flags)"
done
rm -f "$TMP/protected"
assert_status 1 "protection not confirmed on read back fails" env FAKE_PUT_LOST=1 "$SETUP" --only protection
assert_contains "$(last_output)" "not confirmed on read back" "unconfirmed protection: says so"
assert_not_contains "$(last_output)" "done: protect" "unconfirmed protection is not declared done"
rm -f "$TMP/protected"

# Offers: pending until the "no"; the "no" is stored as a repository variable.
cat >"$TMP/offers.sh" <<'H'
case "$*" in
  "variable list"*) [ -n "${OFFER_VARS:-}" ] && printf '%s\n' $OFFER_VARS ;;
  "api repos/owner/repo --jq .private") echo "${OFFER_PRIVATE:-true}" ;;
esac
H
use_fake_gh "$TMP/offers.sh"
out="$(OFFER_VARS="" "$SETUP" --offers)"
assert_contains "$out" "offer:project" "offers project when unanswered"
assert_contains "$out" "offer:runner" "offers runner when unanswered"
out="$(OFFER_VARS="PROCESS_OFFER_PROJECT PROCESS_OFFER_RUNNER" "$SETUP" --offers)"
assert_contains "$out" "none pending" "declined offers do not come back"
out="$(OFFER_VARS="CI_RUNS_ON PROCESS_OFFER_PROJECT" "$SETUP" --offers)"
assert_not_contains "$out" "offer:runner" "no runner offer when CI_RUNS_ON exists"
out="$(OFFER_PRIVATE=false OFFER_VARS="PROCESS_OFFER_PROJECT" "$SETUP" --offers)"
assert_not_contains "$out" "offer:runner" "no runner offer on a public repo"
"$SETUP" --decline runner >/dev/null
"$SETUP" --decline project >/dev/null
calls="$(gh_calls)"
assert_contains "$calls" "variable set PROCESS_OFFER_RUNNER --repo owner/repo --body declined" "decline runner records the variable"
assert_contains "$calls" "variable set PROCESS_OFFER_PROJECT --repo owner/repo --body declined" "decline project records the variable"
assert_not_contains "$calls" "project create" "declining creates nothing"

# --project: fake gh with state in files (link, views, workflows, scopes).
cat >"$TMP/project.sh" <<'H'
case "$*" in
  "auth status"*) printf "  - Token scopes: %s\n" "${FAKE_SCOPES-'gist', 'project', 'read:org', 'read:project', 'repo'}" ;;
  "project create"*) echo 7 ;;
  "issue list"*) printf '3\n5\n' ;;
  "variable list"*) if [ -n "${FAKE_BOARD_VAR:-}" ]; then echo "$FAKE_BOARD_VAR"; elif [ -f "$TMP/boardvar" ]; then cat "$TMP/boardvar"; fi ;;
  "variable set PROCESS_PROJECT_NUMBER"*) echo 7 >"$TMP/boardvar" ;;
  "project link"*) [ -n "${FAKE_LINK_FAILS:-}" ] || touch "$TMP/linked" ;;
  "project item-add"*) echo ITEM ;;
  "project view"*) echo PID ;;
  "project field-list"*) echo '{"fields":[{"name":"Status","id":"FID","options":[{"name":"Todo","id":"OT"},{"name":"In Progress","id":"OP"},{"name":"Done","id":"OD"}]}]}' ;;
  "project item-edit"*)
    [ -z "${FAKE_STATUS_LOST:-}" ] || exit 0
    case "$*" in *"option-id OT"*) echo Todo ;; *"option-id OP"*) echo "In Progress" ;; *"option-id OD"*) echo Done ;; esac >"$TMP/status" ;;
  "api graphql"*"fieldValueByName"*) cat "$TMP/status" 2>/dev/null || true ;;
  "api users/owner --jq .type") echo User ;;
  # The real REST API answers 404 with the numeric id in the path; only the login works.
  "api users/99/"*) exit 1 ;;
  "api users/owner/projectsV2/7/fields"*) printf 'Status\t11\nLabels\t12\n' ;;
  "api graphql"*"projectsV2(first:50)"*) [ -f "$TMP/linked" ] && echo 7 || true ;;
  "api graphql"*"views(first"*) cat "$TMP/views.tsv" 2>/dev/null || true ;;
  "api graphql"*"workflows(first"*) cat "$TMP/workflows.tsv" 2>/dev/null || true ;;
  "api -X POST users/owner/projectsV2/7/views"*)
    body="$(cat)"
    printf '%s\n' "$body" >>"$TMP/view-bodies.jsonl"
    name="$(echo "$body" | jq -r .name)"
    [ "$name" = "${FAKE_REFUSE_VIEW:-}" ] && exit 1
    layout="$(echo "$body" | jq -r '.layout | ascii_upcase')_LAYOUT"
    printf '%s\t%s\n' "$name" "$layout" >>"$TMP/views.tsv" ;;
esac
H
export TMP
use_fake_gh "$TMP/project.sh"
reset_board() { rm -f "$TMP/boardvar" "$TMP/linked" "$TMP/views.tsv" "$TMP/workflows.tsv" "$TMP/view-bodies.jsonl"; : >"$FAKE_GH_LOG"; }

# Missing scope: shows the real step, creates and links nothing and does not declare success.
reset_board
rc=0; out="$(FAKE_SCOPES="'gist', 'repo'" "$SETUP" --project 2>&1)" || rc=$?
assert_eq 1 "$rc" "missing scope exits 1"
assert_contains "$out" "gh auth refresh --scopes project,read:project" "missing scope prints the real step"
assert_contains "$out" "never types the device code" "scope step forbids typing the code"
assert_not_contains "$out" "done:" "missing scope is not declared as success"
assert_not_contains "$(gh_calls)" "project create" "missing scope creates nothing"
assert_not_contains "$(gh_calls)" "project link" "missing scope links nothing"
reset_board
out="$(FAKE_SCOPES="'read:project', 'repo'" "$SETUP" --project 2>&1)" || true
assert_contains "$out" "missing scope: project" "read:project alone cannot write"
reset_board
out="$(FAKE_SCOPES="'project', 'repo'" "$SETUP" --project 2>&1)" || true
assert_not_contains "$out" "needs-owner:" "project alone covers reading (gh does not list read:project with it)"

# New board, link missing -> linked and checked, views created, workflows only read.
reset_board
out="$("$SETUP" --project 2>&1)"
calls="$(gh_calls)"
assert_contains "$calls" "project create --owner owner" "board is created when none is stored"
assert_contains "$calls" "project link 7 --owner owner --repo owner/repo" "board is linked to the repo"
assert_contains "$out" "linked to owner/repo (read back)" "link is confirmed by reading back"
assert_contains "$calls" "variable set PROCESS_PROJECT_NUMBER --repo owner/repo --body 7" "project number is stored"
assert_contains "$calls" "project item-add 7 --owner owner --url https://github.com/owner/repo/issues/3" "open issue 3 enters the board"
assert_contains "$calls" "project item-add 7 --owner owner --url https://github.com/owner/repo/issues/5" "open issue 5 enters the board"
assert_contains "$calls" "project item-edit --id ITEM --project-id PID --field-id FID --single-select-option-id OT" "issues start as Todo"
assert_contains "$calls" "X-GitHub-Api-Version: 2026-03-10" "views use the REST api version header"
assert_eq 7 "$(wc -l <"$TMP/view-bodies.jsonl" | tr -d ' ')" "all 7 default views are created"
assert_contains "$out" "ok: view created: Em execução (board, read back)" "created view is read back"
assert_eq '{"name":"Board por Status","layout":"board","vertical_group_by":[11]}' "$(head -1 "$TMP/view-bodies.jsonl")" "board view groups vertically by Status id"
assert_contains "$out" "pending: workflow 'Item closed' not found or unreadable; not declared enabled" "workflows without proof are not declared enabled"
assert_contains "$out" "partial:" "pending items make the result partial, not done"
assert_not_contains "$out" "done: project board" "no success claim with pending items"

# Idempotence: board, link, views and workflows already exist -> nothing is duplicated or recreated.
reset_board
touch "$TMP/linked"
for v in "Board por Status:BOARD" "Em execução:BOARD" "Fase atual:TABLE" "Por prioridade e área:TABLE" "Roadmap por group:TABLE" "Esperando o dono:TABLE" "Bugs abertos:TABLE"; do
  printf '%s\t%s_LAYOUT\n' "${v%%:*}" "${v##*:}" >>"$TMP/views.tsv"
done
printf 'Item closed\ttrue\nPull request merged\ttrue\nItem added to project\ttrue\nAuto-add to project\ttrue\n' >"$TMP/workflows.tsv"
out="$(FAKE_BOARD_VAR=7 "$SETUP" --project 2>&1)"
calls="$(gh_calls)"
assert_not_contains "$calls" "-X POST" "existing views are not created again"
assert_not_contains "$calls" "project create" "existing board is reused"
assert_not_contains "$calls" "project link" "existing link is not redone"
assert_not_contains "$calls" "item-edit" "existing board keeps its item statuses"
assert_contains "$out" "view exists: Bugs abertos" "existing view is reported by name"
assert_contains "$out" "already linked" "existing link is confirmed by reading"
assert_contains "$out" "workflow enabled: Pull request merged (read back)" "enabled workflow is proven by reading"
assert_contains "$out" "done: project board #7 ready" "everything proven -> done"

# Without Auto-add to project, an issue opened in the interface does not enter the board: pending, never done.
printf 'Item closed\ttrue\nPull request merged\ttrue\nItem added to project\ttrue\n' >"$TMP/workflows.tsv"
out="$(FAKE_BOARD_VAR=7 "$SETUP" --project 2>&1)"
assert_contains "$out" "pending: workflow 'Auto-add to project'" "missing auto-add is pending"
assert_not_contains "$out" "done: project board" "no success claim without auto-add"

# Partial view already existing: only adds what is missing.
reset_board
touch "$TMP/linked"
printf 'Board por Status\tBOARD_LAYOUT\n' >"$TMP/views.tsv"
out="$(FAKE_BOARD_VAR=7 "$SETUP" --project 2>&1)"
assert_eq 6 "$(wc -l <"$TMP/view-bodies.jsonl" | tr -d ' ')" "only the 6 missing views are created"

# View refused by the API: becomes a pending item for the browser, never "created".
reset_board
touch "$TMP/linked"
out="$(FAKE_BOARD_VAR=7 FAKE_REFUSE_VIEW="Roadmap por group" "$SETUP" --project 2>&1)"
assert_contains "$out" "pending: view 'Roadmap por group' refused by the API" "refused view is a pending warning"
assert_not_contains "$out" "view created: Roadmap por group" "refused view is not declared created"
assert_contains "$out" "view created: Bugs abertos" "other views still get created"

# Link not confirmed on read-back: error, without declaring success.
reset_board
rc=0; out="$(FAKE_BOARD_VAR=7 FAKE_LINK_FAILS=1 "$SETUP" --project 2>&1)" || rc=$?
assert_eq 1 "$rc" "unconfirmed link exits 1"
assert_contains "$out" "is not linked to owner/repo" "unconfirmed link is reported"
assert_not_contains "$out" "done:" "unconfirmed link is not success"
assert_not_contains "$(gh_calls)" "-X POST" "no views are created before the link is proven"
(export FAKE_BOARD_VAR=7; source "$SCRIPTS/lib/common.sh"; source "$SCRIPTS/lib/project.sh"; project_set_status 3 "Done")
assert_contains "$(gh_calls)" "--single-select-option-id OD" "project_set_status moves the item to Done"

# lib/project.sh: with no board, silence; with a board, failure with cause and fix.
board() { ( source "$SCRIPTS/lib/common.sh"; source "$SCRIPTS/lib/project.sh"; "$@" ); }
reset_board
assert_status 0 "no board: project_set_status does nothing" board project_set_status 3 Done
assert_eq "" "$(last_output)" "no board: prints nothing"
assert_not_contains "$(gh_calls)" "project " "no board: never calls gh project"
assert_status 0 "no board: the filter does nothing" board project_set_phase_filter is:open
assert_eq "" "$(last_output)" "no board: the filter prints nothing"
assert_status 1 "board without scope: project_set_status fails" env FAKE_BOARD_VAR=7 FAKE_SCOPES="'repo'" bash -c "source '$SCRIPTS/lib/common.sh'; source '$SCRIPTS/lib/project.sh'; project_set_status 3 Done"
assert_contains "$(last_output)" "error: could not set the board status of #3 to 'Done' (board #7): the gh token has no 'project' scope" "missing scope: cause"
assert_contains "$(last_output)" "fix: gh auth refresh --scopes project,read:project" "missing scope: fix command"
assert_status 1 "board without scope: the filter fails" env FAKE_BOARD_VAR=7 FAKE_SCOPES="'repo'" bash -c "source '$SCRIPTS/lib/common.sh'; source '$SCRIPTS/lib/project.sh'; project_set_phase_filter is:open"
assert_contains "$(last_output)" "fix: gh auth refresh" "filter without scope: fix command"
assert_status 1 "item-add failing fails" env FAKE_BOARD_VAR=7 FAKE_GH_FAIL='^project item-add' FAKE_GH_FAIL_MSG="could not add item" bash -c "source '$SCRIPTS/lib/common.sh'; source '$SCRIPTS/lib/project.sh'; project_set_status 3 Done"
assert_contains "$(last_output)" "the issue was not added to the board: could not add item" "item-add failure: cause from gh"
assert_status 1 "preflight fails without scope" env FAKE_BOARD_VAR=7 FAKE_SCOPES="'repo'" bash -c "source '$SCRIPTS/lib/common.sh'; source '$SCRIPTS/lib/project.sh'; project_preflight"
assert_status 0 "preflight passes without a board" env FAKE_SCOPES="'repo'" bash -c "source '$SCRIPTS/lib/common.sh'; source '$SCRIPTS/lib/project.sh'; project_preflight"

# --dry-run --project: only reads; creates no board, variable, link or view.
reset_board
out="$("$SETUP" --dry-run --project 2>&1)"
calls="$(gh_calls)"
assert_contains "$out" "would: create the project board" "dry-run says the board would be created"
for write in "project create" "variable set" "project link" "-X POST" "item-add" "item-edit"; do
  assert_not_contains "$calls" "$write" "dry-run --project never runs: $write"
done
reset_board
printf 'Board por Status\tBOARD_LAYOUT\n' >"$TMP/views.tsv"
out="$(FAKE_BOARD_VAR=7 "$SETUP" --project --dry-run 2>&1)"
calls="$(gh_calls)"
assert_contains "$out" "would: link board #7 to owner/repo" "dry-run shows the missing link"
assert_contains "$out" "would: create view: Fase atual" "dry-run shows a missing view"
assert_not_contains "$out" "would: create view: Board por Status" "dry-run skips an existing view"
for write in "project create" "variable set" "project link" "-X POST"; do
  assert_not_contains "$calls" "$write" "dry-run --project on an existing board never runs: $write"
done
assert_status 2 "decline rejects unknown offers" "$SETUP" --decline bogus
finish
