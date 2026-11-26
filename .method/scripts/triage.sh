#!/usr/bin/env bash
#: triage.sh: open issues as short JSON (number, title, labels) for triage.
#:
#: Usage: triage.sh [--include-test] [--issue N]... [--limit N]
#:        triage.sh --runner-offer
#:
#: Each item: {"n": 12, "t": "title", "l": ["type:bug"], "unlabeled": false,
#: "needs": [...]}; "needs" lists what is still unclassified (type, priority,
#: area). Issues labeled `test` are left out unless --include-test.
#: --issue N (repeatable): only the issues asked for by number, `test` ones included.
#: An issue asked for that is not open is left out, with a warning on stderr.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=.method/scripts/lib/common.sh
source "$HERE/lib/common.sh"

include_test=0 limit=200 runner_offer=0 only="[]"
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --include-test) include_test=1; shift ;;
    --runner-offer) runner_offer=1; shift ;;
    --issue)
      case "${2:-}" in ''|*[!0-9]*) die "--issue needs an issue number" 2 ;; esac
      only="$(jq -cn --argjson o "$only" --argjson n "$2" '$o + [$n]')"; shift 2 ;;
    --limit) limit="$2"; shift 2 ;;
    *) die "unknown option: $1 (see --help)" 2 ;;
  esac
done
require_cmd gh jq
# shellcheck source=.method/scripts/lib/runner_offer.sh
source "$HERE/lib/runner_offer.sh"

if [ "$runner_offer" = 1 ]; then
  repo="$(repo_slug)"
  vars="$(gh variable list --repo "$repo" --json name --jq '.[].name' 2>/dev/null || true)"
  if echo "$vars" | stdin_grep -qxF PROCESS_OFFER_RUNNER_TRIGGER; then
    echo "skip trigger offer already declined"; exit 0
  fi
  has_runs_on=0
  echo "$vars" | stdin_grep -qxF CI_RUNS_ON && has_runs_on=1
  private="$(gh api "repos/$repo" --jq .private 2>/dev/null || true)"
  # Average (s) of the last completed CI runs; empty if the API fails.
  avg="$(gh api "repos/$repo/actions/runs?per_page=20&status=completed" --jq \
    '[.workflow_runs[] | select(.name == "CI") | ((.updated_at | fromdate) - (.run_started_at | fromdate))]
     | if length == 0 then empty else (add / length | floor) end' 2>/dev/null || true)"
  # Monthly quota used (%); empty if the API fails or there is no quota.
  quota="$(gh api "users/${repo%%/*}/settings/billing/actions" --jq \
    'if (.included_minutes // 0) > 0 then (.total_minutes_used * 100 / .included_minutes | floor) else empty end' 2>/dev/null || true)"
  runner_offer_decision "$private" "$has_runs_on" "$avg" "$quota"
  exit 0
fi
list="$(gh issue list --repo "$(repo_slug)" --state open --limit "$limit" --json number,title,labels)"
# An issue asked for by number that is not in the open list (closed, or no such
# issue) is said on stderr: the JSON on stdout stays the list of the open ones.
for n in $(jq -r --argjson l "$list" '. - [$l[].number] | .[]' <<<"$only"); do
  echo "warn: issue #$n is not open (closed or not found): left out" >&2
done
printf '%s\n' "$list" |
  jq -c --argjson it "$include_test" --argjson only "$only" '
    [ .[]
      | {n: .number, t: .title, l: [.labels[].name]}
      | select(if ($only | length) > 0 then (.n as $n | $only | index($n)) != null
               else $it == 1 or (.l | index("test") | not) end)
      | .unlabeled = (.l | length == 0)
      | .needs = ([
          (if any(.l[]; startswith("type:") or . == "debt" or . == "finding") then empty else "type" end),
          (if any(.l[]; startswith("priority:")) then empty else "priority" end),
          (if any(.l[]; startswith("area:")) then empty else "area" end)
        ])
    ] | sort_by(.n)'
