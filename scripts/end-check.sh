#!/usr/bin/env bash
#: end-check.sh: check that the end is clean; exit 1 listing every leftover.
#:
#: Usage: end-check.sh [--issue N] [--offline]
#:
#: Read-only: it never fixes anything. Looks at the main checkout, wherever it
#: is called from. scripts/status.sh --state pronto runs it and refuses the
#: state when it fails.
#:
#: Without --issue (the end of the group, by the main session), fails with:
#:   - a local branch other than main, or main behind or ahead of origin/main;
#:   - a worktree other than the main checkout;
#:   - a line in .worktrees/parallel-active.tsv;
#:   - an untracked file or an uncommitted change in the main checkout;
#:   - a remote branch with no open PR;
#:   - a spec in docs/specs that cites no open issue;
#:   - ROADMAP.md different from the generated one (scripts/gen-roadmap.py);
#:   - a deploy that was not checked (scripts/deploy.sh --check).
#:
#: With --issue N (the end of one phase, by its session), fails with a worktree,
#: a local branch, a registry line, a remote branch or an open PR of phase N.
#: Online, also fails when the check CI of origin/main is red (names the run) or
#: still running (says to wait); absent follows the same rule as phase-start.sh.
#:
#: In the unprotected mode (repository variable PROCESS_BRANCH_MODE, a plan with no
#: branch protection) nothing here changes; the ok line names the mode.
#:
#: --offline runs only the checks that do not call GitHub.
#: Exit: 0 clean; 1 at least one "fail:" line.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"

issue="" offline=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --issue) issue="$2"; shift 2 ;;
    --offline) offline=1; shift ;;
    *) die "unknown option: $1 (see --help)" 2 ;;
  esac
done
case "$issue" in *[!0-9]*) die "--issue takes the issue number" 2 ;; esac
require_cmd git jq

main_root="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
[ -n "$main_root" ] || die "not a git checkout"
registry="$main_root/.worktrees/parallel-active.tsv"
TAB="$(printf '\t')"

fails=0
fail() { echo "fail: $*"; fails=$((fails + 1)); }
list() { paste -sd, - | sed 's/,/, /g'; }

worktrees="$(git -C "$main_root" worktree list --porcelain | sed -n 's/^worktree //p' | sed 1d)"
branches="$(git -C "$main_root" for-each-ref --format='%(refname:short)' refs/heads)"
repo=""
if [ "$offline" = 0 ]; then
  require_cmd gh python3
  repo="$(repo_slug)"
  remote="$(git -C "$main_root" ls-remote --heads origin | sed -n 's#^.*refs/heads/##p')" ||
    die "remote branches not read back"
  open_prs="$(gh pr list --repo "$repo" --state open --limit 200 --json number,headRefName \
    --jq '.[] | "\(.headRefName)\t#\(.number)"')" || die "open PRs not read back"
fi

if [ -n "$issue" ]; then
  # The end of one phase: nothing of phase <issue> is left.
  of_phase() { grep -E "(^|/)issue-$issue(-|\$)" || true; }
  left="$(printf '%s\n' "$worktrees" | of_phase | list)"
  [ -z "$left" ] || fail "worktree of phase #$issue still exists ($left): the phase closes with scripts/close-phase.sh --merge --wait"
  left="$(printf '%s\n' "$branches" | of_phase | list)"
  [ -z "$left" ] || fail "local branch of phase #$issue still exists ($left)"
  if [ -f "$registry" ] && grep -q "^$issue$TAB" "$registry"; then
    fail "phase #$issue is still in $registry"
  fi
  if [ "$offline" = 0 ]; then
    left="$(printf '%s\n' "$remote" | of_phase | list)"
    [ -z "$left" ] || fail "remote branch of phase #$issue still exists ($left)"
    left="$(printf '%s\n' "$open_prs" | grep -E "(^|/)issue-$issue(-[^$TAB]*)?$TAB" | cut -f2 | list || true)"
    [ -z "$left" ] || fail "PR of phase #$issue is still open ($left): the phase is not merged"
  fi
else
  # The end of the group: only an updated main is left, here and on GitHub.
  left="$(printf '%s\n' "$branches" | grep -vxE 'main|master' | list || true)"
  [ -z "$left" ] || fail "extra local branch ($left): at the end git branch shows only main"
  left="$(printf '%s\n' "$worktrees" | grep . | list || true)"
  [ -z "$left" ] || fail "extra worktree ($left)"
  if [ -s "$registry" ]; then
    fail "$registry is not empty (#$(cut -f1 "$registry" | paste -sd' ' - | sed 's/ / #/g')): scripts/close-phase.sh --cleanup takes the lines out"
  fi
  dirty="$(git -C "$main_root" status --porcelain --untracked-files=all)"
  left="$(printf '%s\n' "$dirty" | sed -n 's/^?? //p' | list)"
  [ -z "$left" ] || fail "untracked file in the main checkout ($left)"
  left="$(printf '%s\n' "$dirty" | grep -v '^??' | cut -c4- | list || true)"
  [ -z "$left" ] || fail "uncommitted change in the main checkout ($left)"
  if [ "$offline" = 0 ]; then
    git -C "$main_root" fetch --quiet origin main
    [ "$(git -C "$main_root" rev-parse refs/heads/main)" = "$(git -C "$main_root" rev-parse refs/remotes/origin/main)" ] ||
      fail "local main is not at origin/main"
    left="$(printf '%s\n' "$remote" | while read -r b; do
      if [ -z "$b" ] || is_main_branch "$b"; then continue; fi
      printf '%s\n' "$open_prs" | stdin_grep -q "^$b$TAB" || echo "$b"
    done | list)"
    [ -z "$left" ] || fail "remote branch with no open PR ($left)"
    open="$(gh issue list --repo "$repo" --state open --limit 1000 --json number --jq '.[].number')" ||
      die "open issues not read back"
    for f in "$main_root"/docs/specs/*.md; do
      [ -f "$f" ] || continue
      [ -n "$(spec_open_issues "$f" "$open")" ] ||
        fail "spec of closed issues (docs/specs/$(basename "$f") cites no open issue): it leaves with its last phase"
    done
    generated="$(cd "$main_root" && python3 "$HERE/gen-roadmap.py" --output -)" || die "ROADMAP.md not generated"
    [ -f "$main_root/ROADMAP.md" ] && [ "$generated" = "$(cat "$main_root/ROADMAP.md")" ] ||
      fail "ROADMAP.md differs from the generated one: the main session runs scripts/gen-docs.sh"
    deploy="$("$HERE/deploy.sh" --check 2>&1)" ||
      fail "deploy not checked ($(printf '%s' "$deploy" | tail -1)): the main session runs scripts/deploy.sh"
  fi
fi

# The CI of origin/main: a red or unfinished base is not "pronto" (phase-start.sh would refuse).
if [ "$offline" = 0 ]; then
  git -C "$main_root" fetch --quiet origin main || fail "cannot fetch origin/main to read its CI"
  base="$(git -C "$main_root" rev-parse origin/main)"
  ci_json="$(gh api "repos/$repo/commits/$base/check-runs?per_page=100" 2>&1)" || {
    fail "could not read the check 'CI' of origin/main ${base:0:9} (gh api failed)"
    ci_json=""
  }
  ci=""
  if [ -n "$ci_json" ]; then
    ci="$(printf '%s' "$ci_json" | jq -r '[.check_runs[]? | select(.name == "CI")] | sort_by(.started_at // "") | last
      | if . == null then "absent" else "\(.status)/\(.conclusion // "none") \(.html_url // "")" end' 2>/dev/null || true)"
    if [ "$ci" = absent ]; then
      runs_json="$(gh api "repos/$repo/actions/runs?head_sha=$base&per_page=100" 2>/dev/null || true)"
      ci="$(printf '%s' "$runs_json" | jq -r '[.workflow_runs[]? | select(.status != "completed")] | last
        | if . == null then "absent" else "in_progress/none \(.html_url // "")" end' 2>/dev/null || echo absent)"
    fi
  fi
  case "$ci" in
    completed/success*) ;;
    queued/*|in_progress/*|waiting/*|pending/*|requested/*)
      fail "CI of origin/main ${base:0:9} is still running (${ci#* }): wait for it" ;;
    ""|absent)
      prs="$(gh api "repos/$repo/commits/$base/pulls" 2>/dev/null | jq -r '.[]? | select(.merged_at != null) | .number' 2>/dev/null || true)"
      if [ -z "$prs" ]; then
        fail "no check 'CI' on origin/main ${base:0:9} and no merged PR vouches for it"
      fi
      ;;
    *)
      fail "CI of origin/main ${base:0:9} is ${ci%% *} (${ci#* })" ;;
  esac
fi

if [ "$fails" -gt 0 ]; then
  echo "end-check: $fails problem(s)${issue:+ in phase #$issue}"
  exit 1
fi
note=""
[ "$offline" = 0 ] || note=" (offline: GitHub not read)"
# The unprotected mode (no branch protection on the plan) is not an error: the gate is
# kept by scripts, so it is only named here.
if [ "$offline" = 0 ] && gh variable list --repo "$repo" --json name --jq '.[].name' 2>/dev/null | stdin_grep -qxF PROCESS_BRANCH_MODE; then
  note="$note (mode: unprotected, the gate is kept by scripts)"
fi
echo "ok: end-check${issue:+ of phase #$issue}: nothing left$note"
