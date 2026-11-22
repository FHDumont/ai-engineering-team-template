# shellcheck shell=bash
# Shared setup of test_phase_filter.sh and test_phase_filter_errors.sh (sourced, after lib.sh):
# a temporary repo with a remote and the fake gh of the board.
repo="$(make_repo)"
copy_scripts "$repo"
printf '.worktrees/\n' >"$repo/.gitignore"
# Every phase needs a spec that cites the issue (new-phase.sh refuses without it).
mkdir -p "$repo/docs/specs"
printf '# Spec\n\nFases #20, #21, #22 e #23.\n' >"$repo/docs/specs/base.md"
git -C "$repo" add scripts .gitignore docs
git -C "$repo" commit --quiet -m "chore: scripts"
git clone --quiet --bare "$repo" "$TMP/remote.git"
git -C "$repo" remote add origin "$TMP/remote.git"
git -C "$repo" fetch --quiet origin
git -C "$repo" branch --quiet --set-upstream-to=origin/main main

# Fake gh: the view filter lives in $TMP/filter; the mutation writes it.
cat >"$TMP/handler.sh" <<'H'
case "$*" in
  "auth status"*) printf "  - Token scopes: %s\n" "${FAKE_SCOPES-'gist', 'project', 'read:project', 'repo'}" ;;
  "variable list"*) [ -n "${FAKE_NO_BOARD:-}" ] || echo 7 ;;
  "issue view"*"--json state,title,labels"*) echo '{"state":"OPEN","title":"Fase teste","labels":[{"name":"type:chore"}]}' ;;
  "issue view 20 --json labels"*|"issue view 22 --json labels"*|"issue view 23 --json labels"*) echo alpha ;;
  "issue view 21 --json labels"*) echo beta ;;
  "pr list"*) echo 99 ;;
  "project item-add"*) echo ITEM ;;
  "project view"*) echo PID ;;
  "project field-list"*) echo '{"fields":[{"name":"Status","id":"FID","options":[{"name":"In Progress","id":"OP"},{"name":"Done","id":"OD"},{"name":"Todo","id":"OT"}]}]}' ;;
  "project item-edit"*)
    [ -z "${FAKE_STATUS_LOST:-}" ] || exit 0
    case "$*" in *"option-id OT"*) echo Todo ;; *"option-id OP"*) echo "In Progress" ;; *"option-id OD"*) echo Done ;; esac >"$TMP/status" ;;
  "api graphql"*"fieldValueByName"*) cat "$TMP/status" 2>/dev/null || true ;;
  "api users/owner --jq .type") echo User ;;
  "api graphql"*"nodes{id name filter}"*)
    jq -cn --arg f "$(cat "$TMP/filter" 2>/dev/null || true)" '{data: {user: {projectV2: {views: {nodes: [{id: "VID", name: "Fase atual", filter: $f}, {id: "V2", name: "Outra", filter: "x"}]}}}}}' ;;
  "api graphql"*"updateProjectV2View"*)
    [ -z "${FAKE_REFUSE:-}" ] || exit 1
    [ -z "${FAKE_NOREAD:-}" ] || exit 0
    for a in "$@"; do case "$a" in f=*) printf '%s' "${a#f=}" >"$TMP/filter" ;; esac; done ;;
esac
H
export TMP
use_fake_gh "$TMP/handler.sh"
filter() { cat "$TMP/filter" 2>/dev/null || true; }
mutations() { gh_calls | grep -c "updateProjectV2View" || true; }
