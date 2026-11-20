#!/usr/bin/env bash
# Tests of label-issue.sh.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"
LABEL="$SCRIPTS/label-issue.sh"

# Stateful fake gh: the issue labels are kept in $TMP/labels and edit changes them.
cat >"$TMP/handler.sh" <<'H'
case "$1 $2" in
  "issue view") cat "$TMP/labels" ;;
  "issue edit")
    [ -z "${FAKE_EDIT_NOOP:-}" ] || exit 0
    shift 2
    while [ $# -gt 0 ]; do
      case "$1" in
        --add-label) echo "$2" >>"$TMP/labels"; shift 2 ;;
        --remove-label) grep -vxF -- "$2" "$TMP/labels" >"$TMP/labels.new" || true; mv "$TMP/labels.new" "$TMP/labels"; shift 2 ;;
        *) shift ;;
      esac
    done ;;
esac
H
export TMP
use_fake_gh "$TMP/handler.sh"
printf 'type:bug\npriority:low\n' >"$TMP/labels"
assert_status 0 "applies labels" "$LABEL" 5 --type bug --priority high --area scripts --group app
assert_contains "$(last_output)" "(read back)" "success is declared after reading back"
calls="$(gh_calls)"
assert_contains "$calls" "--add-label priority:high" "adds priority"
assert_contains "$calls" "--remove-label priority:low" "removes the previous priority"
assert_not_contains "$calls" "label create group:app" "known group label is not recreated"
assert_status 1 "refuses unknown label" "$LABEL" 5 --add nope
assert_status 2 "needs a number" "$LABEL" abc

# Failure: gh exits 0 but the label does not land (read back), or gh fails.
printf 'type:bug\n' >"$TMP/labels"
assert_status 1 "fails when the label is not on the issue after the edit" env FAKE_EDIT_NOOP=1 "$LABEL" 5 --priority high
assert_contains "$(last_output)" "priority:high is not on #5" "names the label that is missing"
printf 'type:bug\npriority:low\n' >"$TMP/labels"
assert_status 1 "fails when a removed label is still there" env FAKE_EDIT_NOOP=1 "$LABEL" 5 --remove priority:low
assert_status 1 "fails when gh issue edit fails" env FAKE_GH_FAIL='^issue edit' "$LABEL" 5 --priority high
assert_contains "$(last_output)" "could not label #5" "says the edit failed"
finish
