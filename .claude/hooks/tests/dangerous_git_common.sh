#!/usr/bin/env bash
# Shared preparation of the test_block_dangerous_git_*.sh files (not a test itself):
# the hook, a repository on a phase branch, a checkout on main, and the run/blocked/allowed helpers.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../scripts/tests/lib.sh"
HOOK="$REPO/.claude/hooks/block-dangerous-git.sh"

repo="$(make_repo)"
git -C "$repo" switch --quiet -c feat/issue-1-x
# A checkout on main, for the cases that `cd` or `-C` to it before a commit.
# shellcheck disable=SC2034  # used by the files that source this one
main_repo="$(make_repo)"

run() { # run <cwd> <command>
  jq -cn --arg c "$2" --arg d "$1" '{tool_input: {command: $c}, cwd: $d}' | "$HOOK"
}
blocked() { assert_status 2 "blocks: $2" run "$1" "$2"; }
allowed() { assert_status 0 "allows: $2" run "$1" "$2"; }
