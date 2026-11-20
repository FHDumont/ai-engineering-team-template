#!/usr/bin/env bash
#: new-phase.sh: create the branch and worktree of a solo phase, never on main.
#:
#: Usage: new-phase.sh <issue> [--type feat|fix|docs|chore] [--slug text] [--no-check] [--dry-run]
#:
#: Branch: <type>/issue-<n>-<slug>, from an updated origin/main.
#: Worktree: .worktrees/issue-<n> (ignored by git). Without --type, the type
#: comes from the issue's type:* label; without --slug, from its title. Then runs
#: check-env.sh inside the worktree. Sets the issue to In Progress and the
#: Project's "Fase atual" view filter to the group (group:* label) of the active
#: phases. Prints the worktree path on the last line.
#: Refuses an issue that is not open and an issue without a spec: some
#: docs/specs/*.md of the main checkout must cite #<n>. A spec that is not on the
#: branch yet is committed here, on the phase branch. The entry point of the
#: method is phase-start.sh, which calls this script.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"

[ $# -gt 0 ] || { print_help "$0"; exit 2; }
case "$1" in -h|--help) print_help "$0"; exit 0 ;; esac
issue="$1"; shift
case "$issue" in ''|*[!0-9]*) die "first argument must be the issue number" 2 ;; esac
type="" slug="" check=1 dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --type) type="$2"; shift 2 ;;
    --slug) slug="$2"; shift 2 ;;
    --no-check) check=0; shift ;;
    --dry-run) dry=1; shift ;;
    *) die "unknown option: $1 (see --help)" 2 ;;
  esac
done

# Always from the main checkout, not from inside another worktree.
main_root="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
cd "$main_root"

info_json="$(gh issue view "$issue" --json state,title,labels)" || die "cannot read issue #$issue"
# No phase on a closed issue, and no phase without a spec in docs/specs citing #<n>.
state="$(echo "$info_json" | jq -r '.state // empty')"
[ "$state" = OPEN ] || die "issue #$issue is not open (state: ${state:-unknown}): no phase opens on it"
specs="$(specs_citing "$issue" "$main_root")"
[ -n "$specs" ] || die "no spec in docs/specs cites #$issue: write and approve it with the plan skill first"
if [ -z "$type" ]; then
  case "$(echo "$info_json" | jq -r '[.labels[].name] | join(",")')" in
    *type:bug*) type=fix ;;
    *type:docs*) type=docs ;;
    *type:chore*|*debt*) type=chore ;;
    *) type=feat ;;
  esac
fi
if [ -z "$slug" ]; then
  slug="$(echo "$info_json" | jq -r .title)"
fi
# Slug in lowercase ASCII with hyphens, up to 40 characters.
slug="$(python3 -c '
import re, sys, unicodedata
s = unicodedata.normalize("NFKD", sys.argv[1]).encode("ascii", "ignore").decode().lower()
print(re.sub(r"[^a-z0-9]+", "-", s).strip("-")[:40].rstrip("-"))' "$slug")"
branch="$type/issue-$issue-$slug"
path="$main_root/.worktrees/issue-$issue"

# A configured board must accept writes before anything opens (--dry-run included).
# shellcheck source=scripts/lib/project.sh
source "$HERE/lib/project.sh"
project_preflight || die "phase #$issue not opened: the board cannot be written (cause and fix above)"
if [ "$dry" = 1 ]; then
  echo "branch: $branch"
  echo "worktree: $path"
  exit 0
fi
[ ! -e "$path" ] || die "worktree already exists: $path"
git fetch --quiet origin main
# Marks the session that opened the phase (planning): the close-phase.sh gate only
# accepts as the child session a session different from this one.
# Recorded before the worktree exists, so the opening session is known from its first second.
# The pair of the session that opens the phase goes along: check-env.sh accepts the
# child session in the pair of the spec or in this one.
opener_pair="$(session_pair)"
trace_event phase_opened "issue=$issue" "model=${opener_pair% *}" "effort=${opener_pair#* }"
# The spec enters git here, as the commit the branch is created on: the session that
# opens the phase never commits in the worktree (the git hooks refuse it).
base="$(git rev-parse origin/main)"
start="$base"
index="$(mktemp -d)/index"
GIT_INDEX_FILE="$index" git read-tree "$base"
added=()
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  if [ "$(git rev-parse --quiet --verify "$base:$rel" 2>/dev/null || true)" != "$(git hash-object "$main_root/$rel")" ]; then
    GIT_INDEX_FILE="$index" git update-index --add --cacheinfo "100644,$(git hash-object -w "$main_root/$rel"),$rel"
    added+=("$rel")
  fi
done <<<"$specs"
if [ ${#added[@]} -gt 0 ]; then
  start="$(git commit-tree "$(GIT_INDEX_FILE="$index" git write-tree)" -p "$base" -m "docs(specs): add the spec of issue #$issue")"
fi
rm -rf "$(dirname "$index")"
git worktree add --quiet -b "$branch" "$path" "$start"
git -C "$path" branch --quiet --unset-upstream 2>/dev/null || true
if [ ${#added[@]} -gt 0 ]; then
  # Read back: the branch holds exactly the spec that was approved.
  for rel in "${added[@]}"; do
    [ "$(git -C "$path" rev-parse --quiet --verify "HEAD:$rel" 2>/dev/null || true)" = "$(git hash-object "$main_root/$rel")" ] ||
      die "spec $rel was not committed on $branch"
  done
  echo "spec committed on $branch: ${added[*]}"
fi
if [ "$check" = 1 ]; then
  (cd "$path" && "$path/scripts/check-env.sh")
fi
board=0
project_set_status "$issue" "In Progress" || board=1
# Filter of the "Fase atual" view: the group of this phase plus the one of the parallel phases already active.
project_refresh_phase_filter "$main_root" "$issue" "" || board=1
[ "$board" = 0 ] || die "phase #$issue is open at $path, but the board was not updated (cause and fix above)"
echo "$path"
