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
assert_status 1 "check-env fails on main" sh -c "cd '$repo' && scripts/check-env.sh"
assert_contains "$(last_output)" "never run on main" "explains"
assert_status 0 "check-env passes on the phase branch" sh -c "cd '$path' && scripts/check-env.sh"
assert_eq ".githooks" "$(git -C "$path" config core.hooksPath)" "installs core.hooksPath"

# check-env never runs the suite, and names what the environment lacks with the command.
printf '#!/usr/bin/env bash\necho "validate was called" >>"%s"\nexit 1\n' "$TMP/validate.log" >"$path/scripts/validate.sh"
assert_status 0 "check-env passes without running the suite (a failing validate.sh does not matter)" sh -c "cd '$path' && scripts/check-env.sh"
assert_eq "" "$(cat "$TMP/validate.log" 2>/dev/null || true)" "check-env never calls validate.sh"
assert_status 2 "check-env has no option anymore" sh -c "cd '$path' && scripts/check-env.sh --no-tests"
git -C "$path" checkout --quiet -- scripts/validate.sh
# A PATH with every system tool but shellcheck (and the ones the script needs).
mkdir -p "$TMP/nosc"
for d in /usr/bin /bin /usr/local/bin /opt/homebrew/bin; do
  [ -d "$d" ] || continue
  for t in "$d"/*; do [ "${t##*/}" = shellcheck ] || ln -sf "$t" "$TMP/nosc/${t##*/}" 2>/dev/null || true; done
done
ln -sf "$TMP/bin/gh" "$TMP/nosc/gh"
assert_status 1 "check-env names a missing shellcheck" env PATH="$TMP/nosc" sh -c "cd '$path' && scripts/check-env.sh"
assert_contains "$(last_output)" "missing tool of the method: shellcheck" "says which tool is missing"
assert_contains "$(last_output)" "brew install shellcheck" "gives the install command"
rm -rf "$TMP/nosc"
# Declared dependencies of the product: folder and command, nothing is run.
mkdir -p "$path/app"
printf 'no-such-package-xyz==1.0\n' >"$path/app/requirements.txt"
git -C "$path" add app/requirements.txt
assert_status 1 "check-env names a missing python package" sh -c "cd '$path' && scripts/check-env.sh"
assert_contains "$(last_output)" "missing dependency: no-such-package-xyz (folder app): pip install -r app/requirements.txt" "names package, folder and command"
git -C "$path" rm --quiet -f app/requirements.txt
mkdir -p "$path/app"
printf '{"dependencies":{"left-pad":"1.0.0"}}\n' >"$path/app/package.json"
git -C "$path" add app/package.json
assert_status 1 "check-env names an absent node_modules" sh -c "cd '$path' && scripts/check-env.sh"
assert_contains "$(last_output)" "folder app): cd app && npm install" "names the folder and the npm command"
mkdir -p "$path/app/node_modules"
assert_status 0 "check-env passes once node_modules exists" sh -c "cd '$path' && scripts/check-env.sh"
git -C "$path" rm --quiet -f app/package.json
rm -rf "$path/app"

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
assert_status 0 "check-env skips the provider when the spec has no bots" sh -c "cd '$path' && scripts/check-env.sh"
printf '# Spec\n\nFase da issue #7.\n\nPergunta ao bot `bot-b` com ask-bot.sh.\n' >"$path/docs/specs/a.md"
assert_status 0 "check-env passes with an env provider" env BOT_WEBHOOK_BOT_B_URL=https://h.example sh -c "cd '$path' && scripts/check-env.sh"
assert_contains "$(last_output)" "bot secret provider configured" "reports the provider ok"
assert_not_contains "$(last_output)" "h.example" "does not print the secret"
assert_status 1 "check-env fails when the spec cites bots and there is no provider" sh -c "cd '$path' && scripts/check-env.sh"
assert_contains "$(last_output)" "no secret provider configured" "explains the missing provider"
assert_eq "" "$(cat "$FAKE_OP_LOG" 2>/dev/null || true)" "check-env never calls op"
printf '# Spec\n\nFase da issue #8, `bot-b`.\n' >"$path/docs/specs/a.md"
assert_status 0 "check-env ignores specs of other issues" sh -c "cd '$path' && scripts/check-env.sh"
# Only the header and the phase's own section count; a skill path is not a bot call.
printf '# Spec\n\n## Fase #7\n\nSem bots.\n\n## Fase #8\n\nPergunta ao bot `bot-b`.\n\n## Fase #9\n\nVer .claude/skills/ask-bot/SKILL.md\n' >"$path/docs/specs/a.md"
assert_status 0 "check-env ignores bots cited in another phase's section" sh -c "cd '$path' && scripts/check-env.sh"
printf '# Spec\n\nFase #7: ver .claude/skills/ask-bot/SKILL.md\n' >"$path/docs/specs/a.md"
assert_status 0 "check-env ignores an ask-bot/ file path" sh -c "cd '$path' && scripts/check-env.sh"
printf '# Spec\n\n## Fase #7\n\nPergunta ao bot `bot-b`.\n' >"$path/docs/specs/a.md"
assert_status 1 "check-env still fails when the phase's own section cites a bot" sh -c "cd '$path' && scripts/check-env.sh"
rm -f "$path/docs/specs/a.md"

out="$(cd "$repo" && scripts/open-parallel.sh 8 9 --dry-run 2>&1 || true)"
assert_contains "$out" "fix/issue-8" "parallel dry-run lists the phases"
assert_status 2 "parallel needs 2 issues" sh -c "cd '$repo' && scripts/open-parallel.sh 8"

# Phase slots: the phase of #7 holds one; with a limit of 1 nothing else opens and nothing is created.
assert_eq "1" "$(ls "$AI_METHOD_CACHE/slots/fase" | wc -l | tr -d ' ')" "the open phase holds a slot"
assert_status 75 "new-phase.sh exits 75 without a free slot" env AI_METHOD_SLOTS_FASE=1 sh -c "cd '$repo' && scripts/new-phase.sh 8 --no-check"
assert_contains "$(last_output)" "no free phase slot" "new-phase.sh says why"
assert_contains "$(last_output)" "#7" "new-phase.sh says who holds the slot"
assert_eq "" "$(git -C "$repo" branch --list 'fix/issue-8-*')" "no branch is created without a slot"
assert_status 75 "open-parallel.sh exits 75 without enough slots" env AI_METHOD_SLOTS_FASE=2 sh -c "cd '$repo' && scripts/open-parallel.sh 8 9 --no-check"
assert_eq "" "$(git -C "$repo" branch --list 'fix/issue-*')" "open-parallel.sh creates nothing without slots"
assert_eq "no" "$([ -e "$repo/.worktrees/issue-8" ] && echo yes || echo no)" "no worktree without a slot"

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
