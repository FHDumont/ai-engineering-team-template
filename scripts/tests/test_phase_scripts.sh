#!/usr/bin/env bash
# Tests of new-phase, open-parallel, integrate-parallel and check-env.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

repo="$(make_repo)"
copy_scripts "$repo"
cp -R "$REPO/.githooks" "$repo/.githooks"
printf '.worktrees/\n' >"$repo/.gitignore"
# Every phase needs a spec that cites the issue (new-phase.sh refuses without it).
mkdir -p "$repo/docs/specs"
printf '# Spec\n\nFases #7, #8 e #9.\n' >"$repo/docs/specs/base.md"
git -C "$repo" add scripts .githooks .gitignore docs
git -C "$repo" commit --quiet -m "chore: scripts"
git clone --quiet --bare "$repo" "$TMP/remote.git"
git -C "$repo" remote add origin "$TMP/remote.git"

cat >"$TMP/handler.sh" <<'H'
case "$*" in
  "issue view 7"*) echo '{"state":"OPEN","title":"Listar issues por área","labels":[{"name":"type:feature"}]}' ;;
  "issue view 8"*|"issue view 9"*) echo '{"state":"OPEN","title":"Datas no fuso errado","labels":[{"name":"type:bug"}]}' ;;
  "pr list"*) echo "${FAKE_PR_STATE:-MERGED}" ;;
esac
H
use_fake_gh "$TMP/handler.sh"

out="$(cd "$repo" && scripts/new-phase.sh 7 --dry-run)"
assert_contains "$out" "branch: feat/issue-7-listar-issues-por-area" "branch from type label and title"
out="$(cd "$repo" && scripts/new-phase.sh 8 --dry-run)"
assert_contains "$out" "branch: fix/issue-8-datas-no-fuso-errado" "bug becomes fix/"

out="$(cd "$repo" && scripts/new-phase.sh 7 --no-check)"
path="$(echo "$out" | tail -1)"
assert_eq "$repo/.worktrees/issue-7" "$path" "worktree under .worktrees/"
assert_eq "feat/issue-7-listar-issues-por-area" "$(git -C "$path" branch --show-current)" "worktree is on the phase branch"
assert_status 1 "refuses an existing worktree" sh -c "cd '$repo' && scripts/new-phase.sh 7 --no-check"

# check-env: fails on main; on the branch it installs the hooks.
assert_status 1 "check-env fails on main" sh -c "cd '$repo' && scripts/check-env.sh --no-tests"
assert_contains "$(last_output)" "never run on main" "explains"
assert_status 0 "check-env passes on the phase branch" sh -c "cd '$path' && scripts/check-env.sh --no-tests"
assert_eq ".githooks" "$(git -C "$path" config core.hooksPath)" "installs core.hooksPath"

# check-env: a spec that cites bots requires a secret provider; a spec without bots does not.
# Fake security and op: no test touches the real credential store or password manager.
mkdir -p "$path/docs/specs"
printf '# Spec\n\nFase da issue #7.\n\n1. Sem bots aqui.\n' >"$path/docs/specs/a.md"
cat >"$TMP/bin/security" <<'F'
#!/usr/bin/env bash
echo "security: item not found" >&2; exit 44
F
printf '#!/usr/bin/env bash\necho "op was called: $*" >>"$FAKE_OP_LOG"\nexit 1\n' >"$TMP/bin/op"
chmod +x "$TMP/bin/security" "$TMP/bin/op"
export FAKE_OP_LOG="$TMP/op.log" PROCESS_ENV_FILE="$TMP/none.env"
assert_status 0 "check-env skips the provider when the spec has no bots" sh -c "cd '$path' && scripts/check-env.sh --no-tests"
printf '# Spec\n\nFase da issue #7.\n\nPergunta ao bot `bot-b` com ask-bot.sh.\n' >"$path/docs/specs/a.md"
assert_status 0 "check-env passes with an env provider" env BOT_WEBHOOK_BOT_B_URL=https://h.example sh -c "cd '$path' && scripts/check-env.sh --no-tests"
assert_contains "$(last_output)" "bot secret provider configured" "reports the provider ok"
assert_not_contains "$(last_output)" "h.example" "does not print the secret"
assert_status 1 "check-env fails when the spec cites bots and there is no provider" sh -c "cd '$path' && scripts/check-env.sh --no-tests"
assert_contains "$(last_output)" "no secret provider configured" "explains the missing provider"
assert_eq "" "$(cat "$FAKE_OP_LOG" 2>/dev/null || true)" "check-env never calls op"
printf '# Spec\n\nFase da issue #8, `bot-b`.\n' >"$path/docs/specs/a.md"
assert_status 0 "check-env ignores specs of other issues" sh -c "cd '$path' && scripts/check-env.sh --no-tests"
rm -f "$path/docs/specs/a.md"

out="$(cd "$repo" && scripts/open-parallel.sh 8 9 --dry-run 2>&1 || true)"
assert_contains "$out" "fix/issue-8" "parallel dry-run lists the phases"
assert_status 2 "parallel needs 2 issues" sh -c "cd '$repo' && scripts/open-parallel.sh 8"

printf '7\tfeat/issue-7-listar-issues-por-area\t%s\n' "$path" >"$repo/.worktrees/parallel-active.tsv"
assert_status 3 "integrate waits and times out while a phase is open" env FAKE_PR_STATE=OPEN sh -c "cd '$repo' && scripts/integrate-parallel.sh --timeout 0 --interval 0"
assert_status 0 "integrate proceeds when all merged" sh -c "cd '$repo' && scripts/integrate-parallel.sh --dry-run --interval 0"
assert_contains "$(last_output)" "all parallel phases merged" "reports all merged"
# integrate never deploys: the end step (gen-docs.sh, deploy.sh, archiving,
# end-check.sh) belongs to the main session, the same for a solo and a parallel group.
printf '#!/usr/bin/env bash\necho called >>"%s"\n' "$TMP/deploy.log" >"$repo/scripts/deploy.sh"
deploy_calls() { if [ -f "$TMP/deploy.log" ]; then wc -l <"$TMP/deploy.log" | tr -d ' '; else echo 0; fi; }
: >"$FAKE_GH_LOG"
assert_status 3 "integrate times out with a phase open" env FAKE_PR_STATE=OPEN sh -c "cd '$repo' && scripts/integrate-parallel.sh --timeout 0 --interval 0"
: >"$FAKE_GH_LOG"
assert_status 0 "integrate merges the group" sh -c "cd '$repo' && scripts/integrate-parallel.sh --interval 0"
assert_eq 0 "$(deploy_calls)" "integrate never calls deploy.sh"
assert_contains "$(last_output)" "next, by the main session, once: scripts/gen-docs.sh, scripts/deploy.sh, archive the child sessions, scripts/end-check.sh" "says the end step of the main session"
assert_eq 0 "$([ -e "$repo/.worktrees/parallel-active.tsv" ] && echo 1 || echo 0)" "clears the registry"
assert_eq 0 "$(gh_calls | grep -c 'workflow run')" "integrate dispatches nothing itself"
assert_not_contains "$(cat "$SCRIPTS/integrate-parallel.sh")" "dispatch_deploy" "integrate-parallel.sh has no dispatch_deploy"
assert_not_contains "$(grep -v '^#' "$SCRIPTS/integrate-parallel.sh")" "deploy.sh\"" "integrate-parallel.sh runs no deploy.sh"
# Updates main by fetch + merge --ff-only (never pull) and tolerates a worktree/branch already removed.
git clone --quiet "$TMP/remote.git" "$TMP/other"
git -C "$TMP/other" config user.email test@example.org
git -C "$TMP/other" config user.name test
git -C "$TMP/other" config commit.gpgsign false
echo more >"$TMP/other/more.txt"
git -C "$TMP/other" add more.txt
git -C "$TMP/other" commit --quiet -m "chore: advance main"
git -C "$TMP/other" push --quiet origin HEAD:main
real_git="$(command -v git)"
cat >"$TMP/bin/git" <<G
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = pull ] && { echo "fatal: Cannot fast-forward to multiple branches" >&2; exit 128; }; done
exec "$real_git" "\$@"
G
chmod +x "$TMP/bin/git"
printf '9\tfeat/issue-9-ja-removida\t%s\n' "$TMP/no-such-worktree" >"$repo/.worktrees/parallel-active.tsv"
assert_status 0 "integrate updates main with fetch + ff-only and tolerates removed worktree/branch" sh -c "cd '$repo' && scripts/integrate-parallel.sh --interval 0"
assert_eq "$("$real_git" -C "$TMP/other" rev-parse HEAD)" "$("$real_git" -C "$repo" rev-parse main)" "local main reached origin/main"
rm -f "$TMP/bin/git"

# A dirty or behind PR is not redone here: redo-phase.sh, called by the phase session
# (close-phase.sh --check), is the one owner of that path. integrate only waits.
git -C "$repo" switch --quiet main
git -C "$repo" pull --quiet --ff-only origin main
git -C "$repo" switch --quiet -c feat/issue-12-x
echo phase >"$repo/phase12.txt"
git -C "$repo" add phase12.txt
git -C "$repo" commit --quiet -m "feat: phase 12"
git -C "$repo" push --quiet origin feat/issue-12-x
git -C "$repo" switch --quiet main
echo ahead >"$TMP/other/ahead.txt"
git -C "$TMP/other" pull --quiet origin main
git -C "$TMP/other" add ahead.txt
git -C "$TMP/other" commit --quiet -m "chore: another phase merged"
git -C "$TMP/other" push --quiet origin HEAD:main
for ms in DIRTY BEHIND; do
  cat >"$TMP/handler2.sh" <<H
case "\$*" in
  "pr list"*"--state open"*) echo 77 ;;
  "pr list"*) echo OPEN ;;
  "pr view 77"*) echo "feat: phase 12" ;;
  "pr view feat/issue-12-x"*) echo $ms ;;
esac
H
  use_fake_gh "$TMP/handler2.sh"
  printf '12\tfeat/issue-12-x\t%s\n' "$repo" >"$repo/.worktrees/parallel-active.tsv"
  assert_status 3 "integrate only waits on a $ms PR" sh -c "cd '$repo' && scripts/integrate-parallel.sh --timeout 0 --interval 0"
  assert_not_contains "$(gh_calls)" "pr create" "integrate opens no PR for a $ms one"
  assert_not_contains "$(gh_calls)" "pr close" "integrate closes no PR for a $ms one"
  assert_eq "" "$(git -C "$repo" branch --list 'feat/issue-12-x-r*')" "integrate creates no branch for a $ms PR"
  assert_eq "12	feat/issue-12-x	$repo" "$(cat "$repo/.worktrees/parallel-active.tsv")" "integrate leaves the registry as it is ($ms)"
done
assert_not_contains "$(cat "$SCRIPTS/integrate-parallel.sh")" "cherry-pick" "integrate-parallel.sh has no cherry-pick of its own"
finish
