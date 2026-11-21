#!/usr/bin/env bash
# Tests of the process cleanup of the end of a phase (lib/procs.sh) and of
# sessions.sh, with fake processes: scripts named claude and server that only sleep,
# and a parent whose path says Claude.app. Every process is spawned by the test, in
# a temporary directory, and stopped by it at the end.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPTS/lib/common.sh"
# shellcheck source=scripts/lib/procs.sh
source "$SCRIPTS/lib/procs.sh"

assert_eq 90 "$(etime_seconds 01:30)" "etime mm:ss"
assert_eq 3723 "$(etime_seconds 01:02:03)" "etime hh:mm:ss"
assert_eq 90061 "$(etime_seconds 1-01:01:01)" "etime dd-hh:mm:ss"

mkdir -p "$TMP/fake" "$TMP/wt/sub" "$TMP/Claude.app/Contents" "$TMP/other"
# The child of the fake claude lives in / (a candidate only by its parent).
printf '#!/usr/bin/env bash\n(cd /; exec sleep 300)\n' >"$TMP/fake/claude"
printf '#!/usr/bin/env bash\ncd "$1"; exec sleep 300\n' >"$TMP/fake/server"
printf '#!/usr/bin/env bash\ncd "$1"; "$2" -p task --session-id sid-app >/dev/null 2>&1\n' >"$TMP/Claude.app/Contents/app.sh"
chmod +x "$TMP/fake/"* "$TMP/Claude.app/Contents/app.sh"
PIDS=""
trap 'kill $PIDS 2>/dev/null || true; rm -rf "$TMP"' EXIT
spawn() { "$@" >/dev/null 2>&1 & PIDS="$PIDS $!"; }
export PROCS_APP_MARK="$TMP/Claude.app"
# A zombie of this shell counts as dead.
alive() { case "$(ps -o stat= -p "$1" 2>/dev/null)" in ""|Z*) echo dead ;; *) echo alive ;; esac; }

spawn "$TMP/fake/server" "$TMP/wt/sub"; srv=$!         # test server inside the worktree
spawn "$TMP/fake/server" "$TMP/other"; elsewhere=$!    # a process of another directory
spawn "$TMP/Claude.app/Contents/app.sh" "$TMP/wt" "$TMP/fake/claude"; appchild=$! # claude of the app, cwd in the worktree
(cd "$TMP/other" || exit; exec "$TMP/fake/claude" -p task --session-id sid-123 >/dev/null 2>&1) &
head=$!; PIDS="$PIDS $head"
sleep 1
# The claude of the app is the child of the script that has Claude.app in its path.
appclaude="$(ps -axo pid=,ppid= | awk -v p="$appchild" '$2 == p { print $1; exit }')"

# Worktree sweep: stops the server, keeps the other directory and the app session.
out="$(procs_cleanup_worktree "$TMP/wt" 11 "")"
assert_eq dead "$(alive "$srv")" "the process inside the worktree is stopped"
assert_eq alive "$(alive "$elsewhere")" "a process of another directory stays"
assert_eq alive "$(alive "$appclaude")" "a claude of the Claude.app stays"
assert_contains "$out" "stopped process $srv" "says what it stopped"

# Headless child of the trace: a wrong session id is not stopped; the right one is.
echo "{\"event\":\"phase_headless\",\"issue\":\"11\",\"pid\":\"$head\",\"child_session\":\"sid-999\"}" >"$TMP/trace.jsonl"
procs_cleanup_worktree "$TMP/wt" 11 "$TMP/trace.jsonl" >/dev/null
assert_eq alive "$(alive "$head")" "a pid whose command lacks the session id is not stopped"
echo "{\"event\":\"phase_headless\",\"issue\":\"11\",\"pid\":\"$head\",\"child_session\":\"sid-123\"}" >"$TMP/trace.jsonl"
procs_cleanup_worktree "$TMP/wt" 11 "$TMP/trace.jsonl" >/dev/null
sleep 1
assert_eq dead "$(alive "$head")" "the headless child of the trace is stopped"
assert_eq alive "$(alive "$appclaude")" "the app session still stays"

# sessions.sh: --list, --close-idle (headless only), --stale.
export AI_METHOD_IDLE_HOURS=4
S="$SCRIPTS/sessions.sh"
(cd "$TMP/other" || exit; exec "$TMP/fake/claude" -p idle >/dev/null 2>&1) &
hl=$!; PIDS="$PIDS $hl"
sleep 1
assert_status 0 "sessions.sh --list" "$S" --list
assert_contains "$(last_output)" "headless" "--list shows the headless session"
assert_contains "$(last_output)" " app " "--list shows the app session"
assert_status 0 "--close-idle with the default hours" "$S" --close-idle --under "$TMP"
assert_eq alive "$(alive "$hl")" "a young headless session stays"
assert_status 0 "--close-idle --dry-run" "$S" --close-idle --older-than 0 --under "$TMP" --dry-run
assert_eq alive "$(alive "$hl")" "dry-run stops nothing"
assert_status 0 "--close-idle --older-than 0 stops it" "$S" --close-idle --older-than 0 --under "$TMP"
sleep 1
assert_eq dead "$(alive "$hl")" "an idle headless session is stopped"
assert_eq alive "$(alive "$appclaude")" "--close-idle never stops a child of the Claude.app"

repo="$(make_repo)"
d="$TMP/sessions/acct/org"; mkdir -p "$d"
now=$(($(date +%s) * 1000))
mk() { printf '{"title":"%s","sessionId":"%s","cwd":"%s","isArchived":%s,"lastActivityAt":%s}\n' "$1" "$2" "$3" "$4" "$5" >"$d/$2.json"; }
mk "Old phase" local_old "$repo/.worktrees/issue-1" false $((now - 10 * 3600000))
mk "Archived" local_arch "$repo" true $((now - 10 * 3600000))
mk "Fresh" local_new "$repo" false "$now"
mk "Other repo" local_oth "$TMP/other" false $((now - 10 * 3600000))
out="$(cd "$repo" && AI_METHOD_SESSIONS_DIR="$TMP/sessions" "$S" --stale)"
assert_contains "$out" "Old phase" "--stale lists a parked, not archived session of the repo"
assert_not_contains "$out" "Archived" "--stale skips an archived session"
assert_not_contains "$out" "Fresh" "--stale skips a recent session"
assert_not_contains "$out" "Other repo" "--stale skips another repository"
assert_status 2 "unknown option" "$S" --bogus
finish
