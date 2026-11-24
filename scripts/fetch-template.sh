#!/usr/bin/env bash
#: fetch-template.sh: brings a template commit into .process/template of the current worktree.
#:
#: Usage: fetch-template.sh <sha> [--url <template>] [--apply]
#:
#: Fetches <sha> (and the commit of .github/method-origin, when there is one) from
#: the template into a small git directory at .process/template, with the files of
#: <sha> extracted, so method-diff.sh --template .process/template --to <sha> works.
#: No worktree is registered and nothing is cloned: .process/ is outside git, and the
#: phase is listed once. --url defaults to https://github.com/FHDumont/ai-engineering-team-template
#: (a local path works). --apply then copies the method paths of <sha> (its
#: .github/method-files.txt, plus files of the method folders the worktree lacks or has outdated: equal to the origin, different at <sha>) over this
#: worktree; files only of the repository stay. The copy is a headless-safe step:
#: this script is in the allow list, `git checkout <sha> -- <paths>` is not.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"
require_cmd git

sha="" url="https://github.com/FHDumont/ai-engineering-team-template" apply=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --url) [ $# -ge 2 ] || die "--url needs a value" 2; url="$2"; shift 2 ;;
    --apply) apply=1; shift ;;
    -*) die "unknown option: $1 (see --help)" 2 ;;
    *) [ -z "$sha" ] || die "one sha only" 2; sha="$1"; shift ;;
  esac
done
[ -n "$sha" ] || die "usage: fetch-template.sh <sha> [--url <template>] [--apply]" 2

root="$(repo_root)" || die "not in a git repository" 2
dir="$root/.process/template"
mkdir -p "$dir"
[ -d "$dir/.git" ] || git -C "$dir" init --quiet
fetch_rev() { git -C "$dir" fetch --quiet --no-tags "$url" "$1" 2>/dev/null; }
fetch_rev "$sha" || die "cannot fetch $sha from $url" 1
dest="$(git -C "$dir" rev-parse --verify --quiet "FETCH_HEAD^{commit}")" || die "no commit $sha at $url" 1
git -C "$dir" update-ref refs/heads/destination "$dest"
if [ -f "$root/.github/method-origin" ]; then
  origin="$(tr -d '[:space:]' <"$root/.github/method-origin")"
  case "$origin" in
    ""|template) ;;
    *) if fetch_rev "$origin"; then git -C "$dir" update-ref refs/heads/origin "$(git -C "$dir" rev-parse FETCH_HEAD)"; else info "origin $origin not fetched; method-diff needs --from"; fi ;;
  esac
fi
git -C "$dir" checkout --quiet --force --detach "$dest"
info "template $dest extracted in .process/template"
[ "$apply" = 1 ] || exit 0

paths="$(git -C "$dir" show "$dest:.github/method-files.txt" 2>/dev/null | grep -vE '^[[:space:]]*(#|$)' || true)"
[ -n "$paths" ] || die "$dest has no .github/method-files.txt" 1
dirs="$(printf '%s\n' "$paths" | awk -F/ 'NF>1 { print $1 }' | sort -u)"
origin_ref=""
git -C "$dir" rev-parse --verify --quiet refs/heads/origin >/dev/null && origin_ref=refs/heads/origin
while read -r f; do
  [ -n "$f" ] || continue
  case "$f" in scripts/tests/template/*|docs/specs/*) continue ;; esac
  printf '%s\n' "$dirs" | stdin_grep -qx "${f%%/*}" || continue
  if [ -e "$root/$f" ]; then
    # Present: only an outdated file (repository = origin, destination differs); adapted stays.
    [ -n "$origin_ref" ] || continue
    ob="$(git -C "$dir" rev-parse --verify --quiet "$origin_ref:$f" 2>/dev/null)" || continue
    [ "$(git -C "$root" hash-object "$root/$f")" = "$ob" ] || continue
  fi
  paths="$paths
$f"
done < <(git -C "$dir" ls-tree -r --name-only "$dest")
n=0
while read -r f; do
  [ -n "$f" ] || continue
  [ -f "$dir/$f" ] || continue
  mkdir -p "$root/$(dirname "$f")"
  cp -p "$dir/$f" "$root/$f"
  n=$((n + 1))
done < <(printf '%s\n' "$paths" | awk 'NF && !seen[$0]++')
info "applied $n method files from $dest"
