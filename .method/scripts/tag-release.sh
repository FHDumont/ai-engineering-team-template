#!/usr/bin/env bash
#: tag-release.sh: tags the tip of main as a method version, only when its CI is green.
#:
#: Usage: tag-release.sh [--remote <name>]
#:
#: Fetches <remote>/main (default origin), and, when the check CI of that commit is
#: completed/success, creates the annotated tag vYYYY.MM.DD-N (UTC date; N counts the
#: tags of that day, from 1) and pushes it. Exit 0 with "tagged: <tag>"; a commit that
#: already has a version tag prints "already tagged: <tag>" and creates nothing.
#: A CI skipped for a tree a merged PR already proved green counts as green.
#: Exit 3 when the CI is red, running or absent (nothing is created). Exit 1 on a git
#: or gh failure. Adopters update to the last tag (fetch-template.sh); the template
#: tags at the end of a group (skill integrate), never an adopter repository.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=.method/scripts/lib/common.sh
source "$HERE/lib/common.sh"
require_cmd git gh jq

remote=origin
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --remote) [ $# -ge 2 ] || die "--remote needs a value" 2; remote="$2"; shift 2 ;;
    *) die "unknown option: $1 (see --help)" 2 ;;
  esac
done

git fetch --quiet --tags "$remote" main || die "cannot fetch $remote main" 1
sha="$(git rev-parse --verify --quiet "refs/remotes/$remote/main^{commit}")" || die "no $remote/main" 1

existing="$(git tag --points-at "$sha" | grep -E '^v[0-9]{4}\.[0-9]{2}\.[0-9]{2}-[0-9]+$' | tail -1 || true)"
if [ -n "$existing" ]; then
  echo "already tagged: $existing"
  exit 0
fi

slug="$(repo_slug)"
json="$(gh api "repos/$slug/commits/$sha/check-runs?per_page=100")" || die "cannot read the checks of $sha" 1
ci="$(printf '%s' "$json" | jq -r '[.check_runs[]? | select(.name == "CI")] | sort_by(.started_at // "") | last
  | if . == null then "absent" else "\(.status)/\(.conclusion // "none")" end')"
# A push to main whose tree a merged PR already proved has no CI run of its own (skipped or absent):
# ci-already-green.sh accepts it only with a green CI on the same tree.
if [ "$ci" != "completed/success" ] && [ "$("$HERE/ci-already-green.sh" "$sha")" = "skip=true" ]; then
  ci="completed/success"
fi
if [ "$ci" != "completed/success" ]; then
  echo "error: CI of $sha is $ci; no tag created (a version needs a green CI)" >&2
  exit 3
fi

day="$(date -u +%Y.%m.%d)"
n=$(( $(git tag -l "v$day-*" | wc -l | tr -d ' ') + 1 ))
tag="v$day-$n"
git tag -a "$tag" -m "method version $tag" "$sha"
if ! git push --quiet "$remote" "refs/tags/$tag"; then
  git tag -d "$tag" >/dev/null
  die "cannot push $tag to $remote" 1
fi
echo "tagged: $tag ($sha)"
