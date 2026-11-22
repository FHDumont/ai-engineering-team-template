#!/usr/bin/env bash
# Tests of the registry and the remote branch at the end of a phase:
# close-phase.sh --cleanup takes the line out of .worktrees/parallel-active.tsv and
# deletes the remote branch; open-parallel.sh refuses a registry with leftovers and
# never leaves half a group.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

repo="$(make_repo)"
copy_scripts "$repo"
printf '.worktrees/\n.process/\n' >"$repo/.gitignore"
mkdir -p "$repo/docs/specs"
printf '# Spec\n\nFases #7, #8, #21 e #22.\n' >"$repo/docs/specs/base.md"
git -C "$repo" add scripts .gitignore docs
git -C "$repo" commit --quiet -m "chore: scripts"
git clone --quiet --bare "$repo" "$TMP/remote.git"
git -C "$repo" remote add origin "$TMP/remote.git"
git -C "$repo" fetch --quiet origin
git -C "$repo" branch --quiet --set-upstream-to=origin/main main
REGISTRY="$repo/.worktrees/parallel-active.tsv"

cat >"$TMP/handler.sh" <<'H'
case "$*" in
  "issue view"*"--json state,title,labels"*) echo '{"state":"OPEN","title":"Fase teste","labels":[{"name":"type:chore"}]}' ;;
  "pr list"*"--state merged"*) echo 12 ;;
esac
H
use_fake_gh "$TMP/handler.sh"

# --cleanup after the merge: the line of the phase leaves the registry, the line of a
# phase still open stays, a line whose worktree is gone leaves, the remote branch is deleted.
phase() { # phase <issue>: worktree and branch pushed
  git -C "$repo" worktree add --quiet -b "feat/issue-$1-x" "$repo/.worktrees/issue-$1" main
  git -C "$repo/.worktrees/issue-$1" push --quiet origin "feat/issue-$1-x"
}
phase 7; phase 8
printf '7\tfeat/issue-7-x\t%s\n8\tfeat/issue-8-x\t%s\n9\tfeat/issue-9-x\t%s\n' \
  "$repo/.worktrees/issue-7" "$repo/.worktrees/issue-8" "$repo/.worktrees/issue-9" >"$REGISTRY"
# A server left running in the worktree is stopped, and the end message says to archive.
# Own process group, same session: the caller's group (a pipe) is spared.
python3 -c 'import os,sys; os.setpgid(0,0); os.chdir(sys.argv[1]); os.execvp("sleep", ["sleep", "300"])' \
  "$repo/.worktrees/issue-7" >/dev/null 2>&1 &
leftover=$!
sleep 1
assert_status 0 "cleanup of a merged phase" sh -c "cd '$repo/.worktrees/issue-7' && scripts/close-phase.sh --cleanup"
assert_contains "$(last_output)" "stopped process $leftover" "cleanup stops the process left in the worktree"
assert_contains "$(last_output)" "Archive this session in the Claude app" "the end message says to archive"
assert_contains "$(last_output)" "Do not delete it" "the end message says not to delete"
sleep 1
state="$(ps -o stat= -p "$leftover" 2>/dev/null || true)"
case "$state" in ""|Z*) state=dead ;; *) state=alive ;; esac
assert_eq dead "$state" "the leftover process is gone"
assert_eq "8	feat/issue-8-x	$repo/.worktrees/issue-8" "$(cat "$REGISTRY")" "only the line of the phase still open stays in the registry"
assert_eq "" "$(git -C "$repo" ls-remote --heads origin feat/issue-7-x)" "cleanup deletes the remote branch"
assert_contains "$(last_output)" "deleted remote branch feat/issue-7-x" "says the remote branch was deleted"
assert_eq "" "$(git -C "$repo" branch --list 'feat/issue-7-x')" "cleanup deletes the local branch"
assert_eq 1 "$(git -C "$repo" ls-remote --heads origin feat/issue-8-x | wc -l | tr -d ' ')" "the remote branch of another phase stays"
assert_status 0 "cleanup of the last phase" sh -c "cd '$repo/.worktrees/issue-8' && scripts/close-phase.sh --cleanup"
assert_eq "" "$(cat "$REGISTRY")" "the registry is empty after the last cleanup"

# An untracked file of the main checkout identical to the one the merge brings (the
# spec written by the planning on main and committed on the phase branch) does not
# abort the update of main; a different one is never removed.
phase 9
printf '# Spec\n\nFase #9.\n' >"$repo/docs/specs/nine.md"
mkdir -p "$repo/.worktrees/issue-9/docs/specs"
cp "$repo/docs/specs/nine.md" "$repo/.worktrees/issue-9/docs/specs/nine.md"
git -C "$repo/.worktrees/issue-9" add docs/specs/nine.md
git -C "$repo/.worktrees/issue-9" commit --quiet -m "docs(specs): add the spec of issue #9"
git -C "$repo/.worktrees/issue-9" push --quiet origin feat/issue-9-x:main
: >"$REGISTRY"
assert_status 0 "cleanup with an identical untracked spec in the main checkout" sh -c "cd '$repo/.worktrees/issue-9' && scripts/close-phase.sh --cleanup"
assert_contains "$(last_output)" "removed the untracked copy of docs/specs/nine.md" "says the loose copy left"
assert_eq "$(git -C "$repo" rev-parse origin/main)" "$(git -C "$repo" rev-parse main)" "main is updated past the loose copy"
assert_eq "" "$(git -C "$repo" status --porcelain)" "the spec is tracked and clean after the update"
phase 10
echo other >"$repo/loose.txt"
echo mine >"$repo/.worktrees/issue-10/loose.txt"
git -C "$repo/.worktrees/issue-10" add loose.txt
git -C "$repo/.worktrees/issue-10" commit --quiet -m "feat: loose"
git -C "$repo/.worktrees/issue-10" push --quiet origin feat/issue-10-x:main
assert_status 1 "cleanup keeps an untracked file that differs from main" sh -c "cd '$repo/.worktrees/issue-10' && scripts/close-phase.sh --cleanup"
assert_eq "other" "$(cat "$repo/loose.txt")" "the different file is left as it was"
rm "$repo/loose.txt"
assert_status 0 "cleanup goes on once the file is out of the way" sh -c "cd '$repo/.worktrees/issue-10' && scripts/close-phase.sh --cleanup"

# --cleanup on main: only prunes the lines whose worktree is gone.
printf '9\tfeat/issue-9-x\t%s\n' "$repo/.worktrees/issue-9" >"$REGISTRY"
assert_status 0 "cleanup on main" sh -c "cd '$repo' && scripts/close-phase.sh --cleanup"
assert_eq "" "$(cat "$REGISTRY")" "cleanup on main drops the leftover line"

# open-parallel.sh refuses a registry with a leftover line and opens nothing.
printf '9\tfeat/issue-9-x\t%s\n' "$repo/.worktrees/issue-9" >"$REGISTRY"
assert_status 1 "open-parallel refuses a registry with leftovers" sh -c "cd '$repo' && scripts/open-parallel.sh 21 22 --no-check"
assert_contains "$(last_output)" "leftover lines (#9)" "names the leftover line"
assert_contains "$(last_output)" "close-phase.sh --cleanup" "says how to clean it"
assert_eq "" "$(git -C "$repo" branch --list '*issue-2*')" "no branch is created with leftovers"
: >"$REGISTRY"

# Half a group never stays: the second phase fails to open, the first is undone.
mkdir -p "$repo/.worktrees/issue-22"
assert_status 1 "open-parallel fails when one phase does not open" sh -c "cd '$repo' && scripts/open-parallel.sh 21 22 --no-check"
assert_contains "$(last_output)" "the group was not opened" "says the group was not opened"
assert_eq 0 "$([ -d "$repo/.worktrees/issue-21" ] && echo 1 || echo 0)" "the phase already opened is undone"
assert_eq "" "$(git -C "$repo" branch --list '*issue-21*')" "its branch is deleted"
assert_eq "" "$(cat "$REGISTRY")" "nothing is registered for half a group"
rmdir "$repo/.worktrees/issue-22"

# The whole group opens: one line per phase.
assert_status 0 "open-parallel opens the group" sh -c "cd '$repo' && scripts/open-parallel.sh 21 22 --no-check"
assert_eq "21 22" "$(cut -f1 "$REGISTRY" | paste -sd' ' -)" "one registry line per phase"
# A second group while the first is open is not a leftover.
assert_status 0 "another group opens beside an active one" sh -c "cd '$repo' && scripts/open-parallel.sh 7 8 --no-check"
assert_eq "21 22 7 8" "$(cut -f1 "$REGISTRY" | paste -sd' ' -)" "the active lines stay"
# An issue that is already registered is refused.
assert_status 1 "open-parallel refuses an issue already registered" sh -c "cd '$repo' && scripts/open-parallel.sh 21 9 --no-check"

# integrate-parallel.sh with an empty registry has nothing to wait for.
: >"$REGISTRY"
assert_status 0 "integrate with an empty registry" sh -c "cd '$repo' && scripts/integrate-parallel.sh --dry-run --interval 0"
assert_contains "$(last_output)" "nothing to wait for" "says there is nothing to wait for"

# --cleanup with its stdout piped to a sibling whose cwd is the worktree (issue #120).
# ps delegates to the real binary; lsof and kill are fakes, so nothing is signaled.
# case-120-start
repo120="$(make_repo)"
copy_scripts "$repo120"
printf '.worktrees/\n.process/\n' >"$repo120/.gitignore"
git -C "$repo120" add scripts .gitignore
git -C "$repo120" commit --quiet -m "chore: scripts"
git clone --quiet --bare "$repo120" "$TMP/remote120.git"
git -C "$repo120" remote add origin "$TMP/remote120.git"
git -C "$repo120" fetch --quiet origin
git -C "$repo120" branch --quiet --set-upstream-to=origin/main main
git -C "$repo120" worktree add --quiet -b "feat/issue-120-x" "$repo120/.worktrees/issue-120" main
wt120="$repo120/.worktrees/issue-120"
cat >"$TMP/handler120.sh" <<'H'
case "$*" in
  "pr list"*"--state merged"*) echo 120 ;;
esac
H
use_fake_gh "$TMP/handler120.sh"
export FAKE_GH_HINT=1
printf 'enable -n kill\n' >"$TMP/bin/disable-kill"
# 8301 is another session (an observer). 8302 shares this session and has its own
# process group (a server of the phase). Neither pid is a real process.
sid120="$(python3 -c 'import os; print(os.getsid(0))')"
printf '%s\t%s\t%s\t%s\t%s\n' \
  "8301" "1" "830101" "830101" "cat" \
  "8302" "1" "830202" "$sid120" "sleep 300" >"$TMP/ps120.tab"
export FAKE_PS_TAB="$TMP/ps120.tab" FAKE_REAL_PS="/bin/ps"
cat >"$TMP/bin/ps" <<'PS'
#!/bin/sh
tab="${FAKE_PS_TAB:?}"
real="${FAKE_REAL_PS:-/bin/ps}"
spec="" pid="" prev=""
for arg in "$@"; do
  if [ "$prev" = "-p" ]; then pid="$arg"; fi
  if [ "$prev" = "-o" ] || [ "$prev" = "-axo" ]; then spec="$arg"; fi
  prev="$arg"
done
emit() {
  fpid=$(printf '%s' "$1" | awk -F '\t' '{ print $1 }')
  fppid=$(printf '%s' "$1" | awk -F '\t' '{ print $2 }')
  fpgid=$(printf '%s' "$1" | awk -F '\t' '{ print $3 }')
  fsid=$(printf '%s' "$1" | awk -F '\t' '{ print $4 }')
  fcmd=$(printf '%s' "$1" | awk -F '\t' '{ print $5 }')
  case "$spec" in
    ppid=) printf '%s\n' "$fppid" ;;
    command=) printf '%s\n' "$fcmd" ;;
    pgid=) printf '%s\n' "$fpgid" ;;
    sess=) printf '%s\n' "$fsid" ;;
    stat=) printf 'S\n' ;;
    "pid=,command=") printf '%s %s\n' "$fpid" "$fcmd" ;;
    "pid=,ppid=") printf '%s %s\n' "$fpid" "$fppid" ;;
    *) printf '%s %s\n' "$fpid" "$fcmd" ;;
  esac
}
if [ -n "$pid" ]; then
  row=$(awk -F '\t' -v p="$pid" '$1 == p { print; exit }' "$tab")
  if [ -n "$row" ]; then emit "$row"; exit 0; fi
fi
exec "$real" "$@"
PS
cat >"$TMP/bin/lsof" <<'LSOF'
#!/bin/sh
tab="${FAKE_LSOF_TAB:?}"
pids=""
while [ $# -gt 0 ]; do
  case "$1" in
    -p) pids="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [ -z "$pids" ]; then
  awk -F '\t' '{ printf "p%s\nn%s\n", $1, $2 }' "$tab"
else
  awk -F '\t' -v pids="$pids" '
    {
      n = split(pids, a, ",")
      for (i = 1; i <= n; i++) if (a[i] == $1) printf "p%s\nn%s\n", $1, $2
    }
  ' "$tab"
fi
exit 0
LSOF
cat >"$TMP/bin/kill" <<'KILL'
#!/bin/sh
log="${FAKE_KILL_LOG:?}"
dead="${FAKE_PS_DEAD:?}"
trace="${PROCESS_EVENTS_FILE:-}"
early="${FAKE_KILL_EARLY:-}"
sig=""
for arg in "$@"; do
  case "$arg" in
    -*) sig="${arg#-}" ;;
    *)
      if [ "$sig" = "0" ]; then
        if [ -f "$dead" ] && grep -qx "$arg" "$dead"; then exit 1; fi
        exit 0
      fi
      if [ -n "$trace" ] && [ -n "$early" ] && ! grep -q "\"pid\":\"$arg\"" "$trace" 2>/dev/null; then
        printf '%s\n' "$arg" >>"$early"
      fi
      printf '%s\n' "$arg" >>"$dead"
      printf '%s %s\n' "${sig:-TERM}" "$arg" >>"$log"
      ;;
  esac
done
exit 0
KILL
chmod +x "$TMP/bin/ps" "$TMP/bin/lsof" "$TMP/bin/kill"
: >"$TMP/dead120"
: >"$TMP/kill120"
: >"$TMP/early120"
export FAKE_PS_DEAD="$TMP/dead120" FAKE_KILL_LOG="$TMP/kill120" FAKE_KILL_EARLY="$TMP/early120"
fifo120="$TMP/fifo120"
mkfifo "$fifo120"
out120="$TMP/out120"
: >"$out120"
(
  cd "$wt120" || exit 1
  while IFS= read -r line; do
    printf '%s\n' "$line" >>"$out120"
    if grep -E -q "(^| )$$( |$)" "$FAKE_KILL_LOG" 2>/dev/null; then exit 0; fi
  done <"$fifo120"
) &
sib120=$!
printf '%s\t%s\n' "$sib120" "$wt120" "8301" "$wt120" "8302" "$wt120" >"$TMP/lsof120.tab"
export FAKE_LSOF_TAB="$TMP/lsof120.tab"
rc120=0
env PATH="$TMP/bin:$PATH" BASH_ENV="$TMP/bin/disable-kill" FAKE_GH_HINT=1 \
  bash -c 'cd "$1" && exec "$2" --cleanup' _ "$wt120" "$wt120/scripts/close-phase.sh" >"$fifo120" 2>&1 || rc120=$?
wait "$sib120" 2>/dev/null || true
assert_eq 0 "$rc120" "cleanup piped to a sibling in the worktree exits 0"
assert_eq "" "$(git -C "$repo120" branch --list 'feat/issue-120-x')" "cleanup deletes the local branch"
assert_not_contains "$(cat "$TMP/kill120")" "TERM $sib120" "the pipe reader is not signaled"
assert_not_contains "$(cat "$TMP/kill120")" "TERM 8301" "a process of another session that only has this cwd is not signaled"
assert_contains "$(cat "$TMP/kill120")" "TERM 8302" "a server of this session in its own process group is stopped"
assert_eq "" "$(cat "$TMP/early120")" "every signaled process is in the trace before the signal"
assert_contains "$(cat "$PROCESS_EVENTS_FILE")" "\"pid\":\"8302\"" "the trace names the stopped pid"
assert_contains "$(cat "$PROCESS_EVENTS_FILE")" "sleep" "the trace names the command"
assert_contains "$(cat "$PROCESS_EVENTS_FILE")" "$wt120" "the trace names the directory"
assert_not_contains "$(cat "$out120")" "hint:" "gh hint lines are not forwarded"
last120="$(awk 'NF { line = $0 } END { print line }' "$out120")"
assert_contains "$last120" "Archive this session" "the last line of cleanup is the result"
# case-120-end
finish
