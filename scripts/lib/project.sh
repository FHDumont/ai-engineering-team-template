#!/usr/bin/env bash
# project.sh: functions of the GitHub Projects board (runs nothing when sourced).
#
#   project_set_status <issue> "Todo"|"In Progress"|"Done"
#   project_set_phase_filter / project_refresh_phase_filter: filter of the "Fase atual" view
#   project_preflight: checks, before any effect, that the board accepts writes
#
# One rule for every write on the board. A repo without the variable
# PROCESS_PROJECT_NUMBER (offer declined or not accepted yet) has no board:
# nothing is tried and nothing is printed. A repo with a board whose write
# fails (missing `project` scope included) gets `error: <cause>` and
# `fix: <command>` on stderr and the function returns 1; the caller exits != 0.
# Success is only declared after the fact is read back.

# Every gh scope the method uses, in one place. A scope fix is always this one
# command with the whole list, run by the owner: asking for a single scope would
# drop the others from a login that other sessions and tools may share.
GH_SCOPES="gist,project,read:org,repo,workflow"
GH_LOGIN_CMD="gh auth login -h github.com -p https -w -s $GH_SCOPES"
PROJECT_FIX_SCOPE="$GH_LOGIN_CMD (only the owner runs it and logs in on the browser; an agent never types the device code)"
PROJECT_FIX_SETUP="scripts/setup-repo.sh --project (recreates what the board is missing)"

project_fail() { # project_fail <cause> <fix>
  echo "error: $1" >&2
  echo "fix: $2" >&2
  return 1
}

# Board number of the repo on stdout (empty: no board). Returns 1, with the
# cause, when the repository variables cannot be read.
project_board() { # project_board <owner/repo>
  local out
  if [ "${PROJECT_BOARD_REPO:-}" = "$1" ]; then
    printf '%s\n' "${PROJECT_BOARD_NUM-}"
    return 0
  fi
  if ! out="$(gh variable list --repo "$1" --json name,value --jq '.[] | select(.name == "PROCESS_PROJECT_NUMBER") | .value' 2>&1)"; then
    project_fail "could not read the repository variable PROCESS_PROJECT_NUMBER of $1: $(printf '%s' "$out" | head -1)" "gh auth status (check the login and the repo scope), then run the script again"
    return 1
  fi
  PROJECT_BOARD_REPO="$1"
  PROJECT_BOARD_NUM="$out"
  printf '%s\n' "$out"
}

# Before any side effect of the caller: a configured board must accept writes.
project_preflight() {
  local repo num
  repo="$(repo_slug 2>/dev/null)" || return 0
  num="$(project_board "$repo")" || return 1
  [ -n "$num" ] || return 0
  project_has_scopes ||
    project_fail "board #$num cannot be written: the gh token has no 'project' scope" "$PROJECT_FIX_SCOPE"
}

# Status of a board item, read from the API (empty when unreadable).
project_item_status() { # project_item_status <item id>
  gh api graphql -f query='query($i:ID!){node(id:$i){... on ProjectV2Item{fieldValueByName(name:"Status"){... on ProjectV2ItemFieldSingleSelectValue{name}}}}}' \
    -f i="$1" --jq '.data.node.fieldValueByName.name // ""' 2>/dev/null || true
}

project_set_status() {
  local issue="$1" status="$2" repo num owner item pid fields fid oid what out got
  repo="$(repo_slug 2>/dev/null)" || return 0
  num="$(project_board "$repo")" || return 1
  [ -n "$num" ] || return 0
  owner="${repo%%/*}"
  what="could not set the board status of #$issue to '$status' (board #$num)"
  if ! project_has_scopes; then
    project_fail "$what: the gh token has no 'project' scope" "$PROJECT_FIX_SCOPE"; return 1
  fi
  if ! out="$(gh project item-add "$num" --owner "$owner" --url "https://github.com/$repo/issues/$issue" --format json --jq .id 2>&1)" || [ -z "$out" ]; then
    project_fail "$what: the issue was not added to the board: $(printf '%s' "${out:-no item id returned}" | head -1)" "$PROJECT_FIX_SETUP"; return 1
  fi
  item="$out"
  pid="$(gh project view "$num" --owner "$owner" --format json --jq .id 2>/dev/null || true)"
  fields="$(gh project field-list "$num" --owner "$owner" --format json 2>/dev/null || true)"
  fid="$(printf '%s' "$fields" | jq -r '.fields[]? | select(.name == "Status") | .id' 2>/dev/null || true)"
  oid="$(printf '%s' "$fields" | jq -r --arg s "$status" '.fields[]? | select(.name == "Status") | .options[]? | select(.name == $s) | .id' 2>/dev/null || true)"
  if [ -z "$pid" ] || [ -z "$fid" ] || [ -z "$oid" ]; then
    project_fail "$what: the board or its Status field with the option '$status' could not be read" "$PROJECT_FIX_SETUP"; return 1
  fi
  if ! out="$(gh project item-edit --id "$item" --project-id "$pid" --field-id "$fid" --single-select-option-id "$oid" 2>&1 >/dev/null)"; then
    project_fail "$what: the API refused the update: $(printf '%s' "$out" | head -1)" "$PROJECT_FIX_SETUP"; return 1
  fi
  got="$(project_item_status "$item")"
  if [ "$got" != "$status" ]; then
    project_fail "$what: not confirmed on read back (the board says '${got:-nothing}')" "$PROJECT_FIX_SETUP"; return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Filter of the "Fase atual" view (used by new-phase.sh and close-phase.sh).
#
#   project_set_phase_filter <filter>
#   project_refresh_phase_filter <root of the main checkout> [issue to include] [issue to exclude]
#
# Same rule as the status (top of the file): no board, nothing; with a board, a
# failure becomes `error:` + `fix:` and return 1. Success is only declared after
# the filter is read back.
# ---------------------------------------------------------------------------
PROJECT_PHASE_VIEW="Fase atual"
PROJECT_NEUTRAL_FILTER="is:open"

# True if gh can read and write the board (prints nothing). The `project`
# scope already includes reading, and `gh auth status` does not list `read:project` next
# to it; so `project` is enough. `read:project` alone is not enough to write.
project_has_scopes() {
  [ "${PROJECT_SCOPES_OK:-}" = 1 ] && return 0
  if gh auth status 2>&1 | grep "Token scopes:" | stdin_grep -qF "'project'"; then
    PROJECT_SCOPES_OK=1
    return 0
  fi
  return 1
}

# `id<TAB>filter` of the view by name (empty when it does not exist or the read fails).
project_view_row() { # project_view_row <owner> <num> <view name>
  local kind=user
  [ "$(project_owner_type "$1")" = "Organization" ] && kind=organization
  gh api graphql -f query="query(\$o:String!,\$n:Int!){$kind(login:\$o){projectV2(number:\$n){views(first:50){nodes{id name filter}}}}}" \
    -f o="$1" -F n="$2" 2>/dev/null |
    jq -r --arg v "$3" '[.data[]?.projectV2.views.nodes[]? | select(.name == $v)][0] // empty | [.id, (.filter // "")] | @tsv' 2>/dev/null || true
}

project_set_phase_filter() {
  local filter="$1" repo num owner row vid what out
  repo="$(repo_slug 2>/dev/null)" || return 0
  num="$(project_board "$repo")" || return 1
  [ -n "$num" ] || return 0
  owner="${repo%%/*}"
  what="could not set the '$PROJECT_PHASE_VIEW' filter of board #$num"
  if ! project_has_scopes; then
    project_fail "$what: the gh token has no 'project' scope" "$PROJECT_FIX_SCOPE"; return 1
  fi
  row="$(project_view_row "$owner" "$num" "$PROJECT_PHASE_VIEW")"
  vid="${row%%$'\t'*}"
  if [ -z "$vid" ]; then
    project_fail "$what: the view does not exist or could not be read" "$PROJECT_FIX_SETUP"; return 1
  fi
  if ! out="$(gh api graphql -f query='mutation($v:ID!,$f:String!){updateProjectV2View(input:{viewId:$v,filter:$f}){projectV2View{id}}}' \
    -f v="$vid" -f f="$filter" 2>&1 >/dev/null)"; then
    project_fail "$what: the API refused the update: $(printf '%s' "$out" | head -1)" "$PROJECT_FIX_SETUP"; return 1
  fi
  row="$(project_view_row "$owner" "$num" "$PROJECT_PHASE_VIEW")"
  if [ "${row#*$'\t'}" != "$filter" ]; then
    project_fail "$what: not confirmed on read back (expected $filter, got '${row#*$'\t'}')" "$PROJECT_FIX_SETUP"; return 1
  fi
  echo "ok: '$PROJECT_PHASE_VIEW' filter is now $filter (read back)" >&2
}

# Group (label group:*) of the issue; empty if it has none.
project_issue_group() { # project_issue_group <issue>
  gh issue view "$1" --json labels --jq '[.labels[].name | select(startswith("group:"))][0] // "" | sub("^group:"; "")' 2>/dev/null || true
}

# View filter from groups (one per line on stdin): with no group, the neutral one.
project_phase_filter_for() {
  local g out=""
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    case ",$out," in *,\"group:$g\",*) continue ;; esac
    out="${out:+$out,}\"group:$g\""
  done
  if [ -z "$out" ]; then echo "$PROJECT_NEUTRAL_FILTER"; else echo "label:$out"; fi
}

# Recomputes the filter with the groups of the active phases: those of .worktrees/parallel-active.tsv
# whose worktree still exists, plus the issue to include, minus the issue to exclude.
project_refresh_phase_filter() {
  local main_root="$1" include="${2:-}" exclude="${3:-}" registry n path groups=""
  registry="$main_root/.worktrees/parallel-active.tsv"
  if [ -f "$registry" ]; then
    while IFS=$'\t' read -r n _ path; do
      [ -n "$n" ] && [ "$n" != "$exclude" ] && [ "$n" != "$include" ] && [ -d "$path" ] || continue
      groups="$groups$(project_issue_group "$n")"$'\n'
    done <"$registry"
  fi
  if [ -n "$include" ]; then groups="$groups$(project_issue_group "$include")"$'\n'; fi
  project_set_phase_filter "$(printf '%s' "$groups" | project_phase_filter_for)"
}

# ---------------------------------------------------------------------------
# Idempotent board setup (used by `setup-repo.sh --project`).
#
# Rule: nothing is declared done just because the command exited 0; each fact is
# read back. Output lines: `ok: ...` (proven), `warning: ...`/`pending:`
# (the session resolves it in the browser) and `needs-owner: ...` (login/authorization only).
# Counter of browser pendings: PROJECT_PENDING.
# ---------------------------------------------------------------------------
PROJECT_API_VERSION="2026-03-10"
PROJECT_PENDING=0

# Scopes required of gh. If one is missing, returns 1 with the real step (no success claimed).
project_require_scopes() {
  if ! project_has_scopes; then
    echo "needs-owner: gh token is missing scope: project"
    echo "next: $PROJECT_FIX_SCOPE"
    return 1
  fi
  echo "ok: gh scope project present (includes read)"
}

# Board number stored in the repository variable (empty if none).
project_number() { # project_number <owner/repo>
  gh variable list --repo "$1" --json name,value --jq '.[] | select(.name == "PROCESS_PROJECT_NUMBER") | .value' 2>/dev/null || true
}

# Owner type (User|Organization), read from the API.
project_owner_type() { # project_owner_type <owner>
  gh api "users/$1" --jq .type 2>/dev/null || true
}

# Numbers of the boards linked to the repository (the link read back).
project_linked_numbers() { # project_linked_numbers <owner/repo>
  gh api graphql -f query='query($o:String!,$r:String!){repository(owner:$o,name:$r){projectsV2(first:50){nodes{number}}}}' \
    -f o="${1%%/*}" -f r="${1#*/}" --jq '.data.repository.projectsV2.nodes[].number' 2>/dev/null || true
}

# Links the repo to the board if not yet linked and reads it back.
project_ensure_link() { # project_ensure_link <owner/repo> <num>
  local repo="$1" num="$2"
  if project_linked_numbers "$repo" | stdin_grep -qxF "$num"; then
    echo "ok: board #$num already linked to $repo"; return 0
  fi
  gh project link "$num" --owner "${repo%%/*}" --repo "$repo" >/dev/null 2>&1 || true
  if project_linked_numbers "$repo" | stdin_grep -qxF "$num"; then
    echo "ok: board #$num linked to $repo (read back)"; return 0
  fi
  echo "error: board #$num is not linked to $repo (link not confirmed on read back)"
  return 1
}

# Existing views: one per line, `name<TAB>LAYOUT`.
project_list_views() { # project_list_views <owner> <num>
  local kind=user
  [ "$(project_owner_type "$1")" = "Organization" ] && kind=organization
  gh api graphql -f query="query(\$o:String!,\$n:Int!){$kind(login:\$o){projectV2(number:\$n){views(first:50){nodes{name layout}}}}}" \
    -f o="$1" -F n="$2" --jq ".data.$kind.projectV2.views.nodes[] | [.name, .layout] | @tsv" 2>/dev/null || true
}

# Default set: name|layout|filter|group by (fields, comma)|vertical grouping (board).
# "Fase atual" starts with a neutral filter; new-phase.sh swaps in the group:* of the open phase.
project_default_views() {
  cat <<'V'
Board por Status|board|||Status
Em execução|board|status:"In Progress"||Status
Fase atual|table|is:open||
Por prioridade e área|table||Labels|
Roadmap por group|table||Labels|
Esperando o dono|table|label:"needs-owner-ok"||
Bugs abertos|table|is:open label:"type:bug"||
V
}

# JSON array of the numeric ids of the requested fields (comma-separated names);
# returns 1 when a field does not exist.
project_field_ids() { # project_field_ids <tsv name<TAB>id> <names>
  local f id out="[]"
  [ -n "$2" ] || { echo "[]"; return 0; }
  for f in $(printf '%s' "$2" | tr ',' ' '); do
    id="$(printf '%s\n' "$1" | awk -F'\t' -v n="$f" '$1 == n {print $2}')"
    [ -n "$id" ] || return 1
    out="$(printf '%s' "$out" | jq -c --argjson i "$id" '. + [$i]')"
  done
  echo "$out"
}

# Creates the missing views (by name, no duplicates). An API refusal becomes `pending:`.
project_ensure_views() { # project_ensure_views <owner> <num>
  local owner="$1" num="$2" base existing fields
  # The path takes the login: with the numeric id the REST API answers 404.
  base="users/$owner/projectsV2/$num"
  [ "$(project_owner_type "$owner")" = "Organization" ] && base="orgs/$owner/projectsV2/$num"
  existing="$(project_list_views "$owner" "$num")"
  # Numeric ids of the fields (REST wants the integer id, not the node id).
  fields="$(gh api "$base/fields" -H "X-GitHub-Api-Version: $PROJECT_API_VERSION" --jq '.[] | [.name, (.id | tostring)] | @tsv' 2>/dev/null || true)"
  local name layout filter group vgroup group_ids vgroup_ids body want
  while IFS='|' read -r name layout filter group vgroup; do
    [ -n "$name" ] || continue
    if printf '%s\n' "$existing" | cut -f1 | stdin_grep -qxF "$name"; then
      echo "ok: view exists: $name"; continue
    fi
    if ! group_ids="$(project_field_ids "$fields" "$group")" || ! vgroup_ids="$(project_field_ids "$fields" "$vgroup")"; then
      echo "pending: view '$name' not created (grouping field not found by the API); create it in the browser"
      PROJECT_PENDING=$((PROJECT_PENDING + 1)); continue
    fi
    body="$(jq -n -c --arg n "$name" --arg l "$layout" --arg f "$filter" --argjson g "$group_ids" --argjson v "$vgroup_ids" \
      '{name: $n, layout: $l} + (if $f != "" then {filter: $f} else {} end) + (if ($g | length) > 0 then {group_by: $g} else {} end) + (if ($v | length) > 0 then {vertical_group_by: $v} else {} end)')"
    if ! printf '%s' "$body" | gh api -X POST "$base/views" -H "X-GitHub-Api-Version: $PROJECT_API_VERSION" --input - >/dev/null 2>&1; then
      echo "pending: view '$name' refused by the API; create it in the browser"
      PROJECT_PENDING=$((PROJECT_PENDING + 1)); continue
    fi
    # Counts as created only if the read back returns the expected name and layout.
    want="$(printf '%s' "$layout" | tr '[:lower:]' '[:upper:]')_LAYOUT"
    if project_list_views "$owner" "$num" | stdin_grep -qxF "$(printf '%s\t%s' "$name" "$want")"; then
      echo "ok: view created: $name ($layout, read back)"
    else
      echo "pending: view '$name' not confirmed on read back; check it in the browser"
      PROJECT_PENDING=$((PROJECT_PENDING + 1))
    fi
  done < <(project_default_views)
}

# Native workflows: read only (the public API cannot turn them on). Declared on only with proof.
project_check_workflows() { # project_check_workflows <owner> <num>
  local owner="$1" num="$2" kind=user rows w
  [ "$(project_owner_type "$owner")" = "Organization" ] && kind=organization
  rows="$(gh api graphql -f query="query(\$o:String!,\$n:Int!){$kind(login:\$o){projectV2(number:\$n){workflows(first:30){nodes{name enabled}}}}}" \
    -f o="$owner" -F n="$num" --jq ".data.$kind.projectV2.workflows.nodes[] | [.name, (.enabled | tostring)] | @tsv" 2>/dev/null || true)"
  # "Auto-add to project" is what brings an issue opened in the UI to the board;
  # "Item added to project" only sets the status of what already got in.
  for w in "Auto-add to project" "Item closed" "Pull request merged" "Item added to project"; do
    case "$(printf '%s\n' "$rows" | awk -F'\t' -v n="$w" '$1 == n {print $2}')" in
      true) echo "ok: workflow enabled: $w (read back)" ;;
      false) echo "pending: workflow '$w' is off; turn it on in the browser (the API cannot)"
             PROJECT_PENDING=$((PROJECT_PENDING + 1)) ;;
      *) echo "pending: workflow '$w' not found or unreadable; not declared enabled"
         PROJECT_PENDING=$((PROJECT_PENDING + 1)) ;;
    esac
  done
}
