#!/usr/bin/env bash
#: deploy.sh: the one deploy of a close: dispatch each deploy-*.yml on main, wait for the run, read it back.
#:
#: Usage: deploy.sh [--timeout seconds] [--interval seconds]
#:        deploy.sh --check
#:
#: The only way to dispatch a deploy. Run by the main session, from the main
#: checkout, after the last phase of the group is merged and after
#: scripts/gen-docs.sh, in the end step of the group (the same for a solo and a
#: parallel group). The workflow itself runs scripts/validate.sh on main before
#: the build.
#:
#: Refuses (exit 1), dispatching nothing, when:
#:   - it does not run from the main checkout;
#:   - there is no session id, or this session has in the trace a phase_session
#:     of an issue it did not open (a phase session never deploys; a
#:     phase_session of an issue the same session opened, phase_opened, is the
#:     main session running check-env.sh and does not count; a phase_session
#:     with an empty issue, from check-env.sh outside a phase, does not count);
#:   - .worktrees/parallel-active.tsv is not empty;
#:   - a phase is open (a .worktrees/issue-<n> worktree) or a phase PR is open.
#:
#: For each .github/workflows/deploy-*.yml of origin/main (its "# deploy-paths:"
#: line lists the paths of the app it deploys):
#:   - a successful run on the same SHA: no dispatch (never twice on one SHA);
#:   - a run still going on the same SHA: no dispatch, waits for that run;
#:   - no change in the deploy paths since the last successful deploy: no dispatch.
#:     A path in the line that starts with ! is excluded (an inert doc can be
#:     left out). A change only in excluded paths is "no deploy:";
#:   - otherwise dispatches once (workflow_dispatch on main), prints the run URL
#:     and waits for the run (default 1800 s, read every 15 s).
#:
#: --check only reads (scripts/end-check.sh calls it): no refusal above applies,
#: nothing is dispatched and nothing is waited for. Exits 5 when a workflow
#: still has a deploy to do or a run still going on the SHA of main.
#:
#: Exit: 0 deployed or nothing to deploy; 1 refused; 3 the run did not finish
#: in time; 4 a run finished without success; 5 (--check) deploy not done.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"

usage_error() { # usage_error <message>: the message and the usage, exit 2
  {
    echo "error: $1"
    echo "Usage: deploy.sh [--timeout seconds] [--interval seconds]"
    echo "       deploy.sh --check"
  } >&2
  exit 2
}
# Prints the value of option <name>: a whole number of seconds, zero or more.
seconds_of() { # seconds_of <name> <number of arguments left> [value]
  [ "$2" -ge 2 ] || usage_error "$1 needs a value: a whole number of seconds"
  case "$3" in
    ''|*[!0-9]*) usage_error "$1 needs a whole number of seconds, zero or more: got '$3'" ;;
  esac
  echo "$3"
}

timeout=1800 interval=15 check=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --timeout) timeout="$(seconds_of "$1" $# "${2-}")" || exit 2; shift 2 ;;
    --interval) interval="$(seconds_of "$1" $# "${2-}")" || exit 2; shift 2 ;;
    --check) check=1; shift ;;
    *) die "unknown option: $1 (see --help)" 2 ;;
  esac
done
require_cmd gh jq git

main_root="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
[ -n "$main_root" ] || die "not a git checkout"
repo="$(repo_slug)"
# --check only reads: the refusals are for the session that dispatches.
if [ "$check" = 0 ]; then
  [ "$(cd "$HERE/.." && pwd -P)" = "$(cd "$main_root" && pwd -P)" ] ||
    die "deploy refused: deploy.sh runs from the main checkout ($main_root), by the main session"

  # A phase session never deploys. Fails closed: no session id, or a trace line
  # that is not JSON, refuses.
  sid="${CLAUDE_CODE_SESSION_ID:-}"
  [ -n "$sid" ] || die "deploy refused: no session id (CLAUDE_CODE_SESSION_ID): the main session deploys"
  trace="$(phase_trace_file "$main_root")" || die "deploy refused: cannot locate the trace"
  if [ -f "$trace" ]; then
    # A phase_session of an issue this same session opened (phase_opened) is not a
    # phase session: the old new-phase.sh ran check-env.sh in the session that opened it.
    phases="$(jq -rs --arg s "$sid" '
      [.[] | select(type == "object" and .session_id == $s)] as $e
      | [$e[] | select(.event == "phase_opened") | (.issue | tostring)] as $opened
      | [$e[] | select(.event == "phase_session") | (.issue | tostring) | select(test("^[0-9]+$")) | select(. as $i | $opened | index($i) | not) | "#\(.)"]
      | unique | join(", ")' "$trace" 2>/dev/null)" ||
      die "deploy refused: a line of $trace is not JSON"
    [ -z "$phases" ] || die "deploy refused: this session is a phase session (phase_session of $phases in the trace): the main session deploys"
  fi

  registry="$main_root/.worktrees/parallel-active.tsv"
  [ ! -s "$registry" ] || die "deploy refused: parallel phases are still registered ($registry): deploy after all of them merge (close-phase.sh --cleanup takes each line out)"

  open_phases="$(git -C "$main_root" worktree list --porcelain | sed -n 's/^worktree //p' | while read -r wt; do
    p="$(phase_of_path "$wt")"
    [ -z "$p" ] || printf '#%s ' "${p%%	*}"
  done)"
  [ -z "$open_phases" ] || die "deploy refused: phase still open (worktree of ${open_phases% }): deploy after the last phase is merged"

  open_prs="$(gh pr list --repo "$repo" --state open --limit 200 --json number,headRefName |
    jq -r '[.[] | select(.headRefName | test("(^|/)issue-[0-9]+")) | "#\(.number) (\(.headRefName))"] | join(", ")')" ||
    die "deploy refused: open PRs not read back"
  [ -z "$open_prs" ] || die "deploy refused: phase PR still open ($open_prs): deploy after the last phase is merged"

fi

git -C "$main_root" fetch --quiet origin main
sha="$(git -C "$main_root" rev-parse origin/main)"

# Waits for run <id> of <workflow>; prints the result. Returns 0 success, 3 timeout, 4 failed.
wait_run() { # wait_run <workflow> <run id>
  local wf="$1" id="$2" waited=0 info status conclusion url
  while :; do
    info="$(gh run view "$id" --repo "$repo" --json status,conclusion,url,headSha)"
    status="$(echo "$info" | jq -r .status)"
    url="$(echo "$info" | jq -r .url)"
    [ "$status" != completed ] || break
    if [ "$waited" -ge "$timeout" ]; then
      echo "deploy not finished: $wf run $id is $status after ${timeout}s: $url"
      return 3
    fi
    sleep "$interval"; waited=$((waited + (interval > 0 ? interval : 1)))
  done
  conclusion="$(echo "$info" | jq -r .conclusion)"
  trace_event deploy "workflow=$wf" "sha=$(echo "$info" | jq -r .headSha)" "run=$id" "conclusion=$conclusion"
  if [ "$conclusion" != success ]; then
    echo "deploy failed: $wf run $id ended as $conclusion: $url"
    return 4
  fi
  echo "deployed: $wf on main at ${sha:0:12}: $url"
}

# True when nothing that this workflow publishes changed. A ! token is excluded.
deploy_unchanged() { # deploy_unchanged <repo> <from> <to> <path list>
  local repo="$1" from="$2" to="$3" list="$4" f p base skip hit
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    skip=0
    for p in $list; do
      case "$p" in
        !*)
          base="${p#!}"; base="${base%/}"
          # shellcheck disable=SC2254  # the exclusion token is a glob on purpose
          case "$f" in $base|$base/*) skip=1 ;; esac ;;
      esac
    done
    [ "$skip" = 1 ] && continue
    hit=0
    for p in $list; do
      case "$p" in
        !*) ;;
        *)
          base="${p%/}"
          # shellcheck disable=SC2254  # the path token is a glob on purpose
          case "$f" in $base|$base/*) hit=1 ;; esac ;;
      esac
    done
    [ "$hit" = 1 ] && return 1
  done < <(git -C "$repo" diff --name-only "$from" "$to")
  return 0
}

workflows="$(git -C "$main_root" ls-tree -r --name-only "$sha" -- .github/workflows | grep -E '/deploy-[^/]+\.yml$' || true)"
if [ -z "$workflows" ]; then
  echo "no deploy: no deploy-*.yml workflow on main"
  exit 0
fi

rc=0
for path in $workflows; do
  wf="$(basename "$path")"
  paths="$(git -C "$main_root" show "$sha:$path" | sed -n 's/^# deploy-paths:[[:space:]]*//p' | head -1)"
  [ -n "$paths" ] || die "$wf has no '# deploy-paths:' line: cannot tell what it deploys"
  runs="$(gh run list --repo "$repo" --workflow "$wf" --branch main --event workflow_dispatch --limit 50 \
    --json databaseId,headSha,status,conclusion,url)"
  [ -n "$runs" ] || runs='[]'

  same="$(echo "$runs" | jq -r --arg s "$sha" '[.[] | select(.headSha == $s and (.status != "completed" or .conclusion == "success"))][0] | select(. != null) | "\(.databaseId)\t\(.status)\t\(.url)"')"
  if [ -n "$same" ]; then
    IFS="$(printf '\t')" read -r id status url <<<"$same"
    if [ "$status" = completed ]; then
      echo "no deploy: $wf already deployed main at ${sha:0:12}: $url"
      continue
    fi
    if [ "$check" = 1 ]; then
      echo "deploy not done: $wf run $id is still $status on ${sha:0:12}: $url"
      rc=5
      continue
    fi
    echo "no dispatch: $wf run $id is already $status on ${sha:0:12}: $url"
    wait_run "$wf" "$id" || { r=$?; [ "$rc" -ge "$r" ] || rc="$r"; }
    continue
  fi

  last="$(echo "$runs" | jq -r '[.[] | select(.conclusion == "success")][0] | select(. != null) | "\(.headSha)\t\(.url)"')"
  if [ -n "$last" ]; then
    IFS="$(printf '\t')" read -r last_sha last_url <<<"$last"
    # A token that starts with ! is a shell pattern of paths to leave out
    # (!app/*.md). What remains of the other tokens is the deploy.
    if git -C "$main_root" cat-file -e "$last_sha^{commit}" 2>/dev/null &&
       deploy_unchanged "$main_root" "$last_sha" "$sha" "$paths"; then
      echo "no deploy: $wf has no change in ($paths) since the last deploy at ${last_sha:0:12}: $last_url"
      continue
    fi
  fi

  if [ "$check" = 1 ]; then
    echo "deploy not done: $wf has not deployed main at ${sha:0:12}"
    rc=5
    continue
  fi
  known="$(echo "$runs" | jq -c '[.[].databaseId]')"
  gh workflow run "$wf" --repo "$repo" --ref main >/dev/null
  echo "deploy dispatched: $wf on main at ${sha:0:12}"
  id="" waited=0
  while :; do
    id="$(gh run list --repo "$repo" --workflow "$wf" --branch main --event workflow_dispatch --limit 50 \
      --json databaseId,headSha,status,conclusion,url |
      jq -r --argjson known "$known" '[.[] | select(.databaseId as $i | $known | index($i) | not)][0] | select(. != null) | "\(.databaseId)\t\(.url)"')"
    [ -z "$id" ] || break
    if [ "$waited" -ge "$timeout" ]; then
      echo "deploy not read back: no new $wf run after ${timeout}s"
      [ "$rc" -ge 3 ] || rc=3
      continue 2
    fi
    sleep "$interval"; waited=$((waited + (interval > 0 ? interval : 1)))
  done
  IFS="$(printf '\t')" read -r id url <<<"$id"
  echo "deploy run: $url"
  wait_run "$wf" "$id" || { r=$?; [ "$rc" -ge "$r" ] || rc="$r"; }
done
exit "$rc"
