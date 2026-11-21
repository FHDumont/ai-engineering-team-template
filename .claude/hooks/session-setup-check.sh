#!/usr/bin/env bash
# session-setup-check.sh: SessionStart hook. Once per session, when the repository
# is not configured for the method (scripts/setup-repo.sh --check exits 7), it adds to the context that the setup is
# pending and that the first step is the setup skill.
# It only warns; the lock is scripts/phase-start.sh. It never blocks or delays a
# session: without jq, gh, a remote or network, or when the check takes longer
# than SETUP_CHECK_TIMEOUT seconds (default 5), it says nothing. Always exits 0.
# A check that passed is remembered in .process/setup-ok of the main checkout:
# later sessions do not read GitHub again (phase-start.sh still checks every time).
here="$(cd "$(dirname "$0")" && pwd)"
check="$here/../../scripts/setup-repo.sh"
command -v jq >/dev/null 2>&1 && command -v gh >/dev/null 2>&1 && [ -x "$check" ] || exit 0

input="$(head -c 1000000)"
dir="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -d "$dir" ] || dir="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$dir" 2>/dev/null || exit 0
git remote get-url origin >/dev/null 2>&1 || exit 0

# Once per session: the marker lives next to the trace, outside git.
session="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9_-')"
main_root="$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
marker=""
[ -z "$session" ] || [ -z "$main_root" ] || marker="$main_root/.process/setup-notice/$session"
[ -z "$marker" ] || [ ! -e "$marker" ] || exit 0
[ -z "$main_root" ] || [ ! -e "$main_root/.process/setup-ok" ] || exit 0

out="$(mktemp 2>/dev/null)" || exit 0
trap 'rm -f "$out"' EXIT
"$check" --check >"$out" 2>&1 &
pid=$!
# The watchdog keeps no pipe of the hook open, so a kill never leaves the session waiting.
( sleep "${SETUP_CHECK_TIMEOUT:-5}"; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 &
watch=$!
rc=0
wait "$pid" 2>/dev/null || rc=$?
kill "$watch" 2>/dev/null
wait "$watch" 2>/dev/null # reaps the watchdog, so the shell prints no "Terminated" line
case "$rc" in
  0) [ -z "$main_root" ] || { mkdir -p "$main_root/.process" 2>/dev/null && : >"$main_root/.process/setup-ok" 2>/dev/null; }
     exit 0 ;;
  7) echo "Setup pending: this repository is not configured for the method. First step, before any other work: load the setup skill (the owner's sentence is \"configurar o repo\"). Until then scripts/phase-start.sh and scripts/open-issue.sh refuse. What scripts/setup-repo.sh --check found:" ;;
  *) exit 0 ;;
esac
cat "$out"
if [ -n "$marker" ]; then mkdir -p "$(dirname "$marker")" 2>/dev/null && : >"$marker" 2>/dev/null; fi
exit 0
