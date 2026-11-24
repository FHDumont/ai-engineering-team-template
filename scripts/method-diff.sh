#!/usr/bin/env bash
#: method-diff.sh: compare this repository with a template checkout.
#:
#: Usage: method-diff.sh --template <dir> [--from <rev>] [--to <rev>] [--remove]
#:        method-diff.sh --find-base --template <dir>
#:
#: Reads the template commit this repository came from (.github/method-origin,
#: written by setup-repo.sh --record-origin) and lists method files by blob
#: hash: identical, adapted, missing, removed, kept, repo-owned (a repository
#: file with a template default) or repo-only. template-only marks a test of
#: scripts/tests/template/ that a repository must not have (--remove deletes
#: it); missing-label names a method label absent from .github/labels.tsv. --remove
#: deletes a file the template dropped since that commit when this repository
#: did not change it. A repository-only file is never deleted. --find-base
#: prints the template commit whose blobs match the commit that introduced
#: .github/method-origin (or the first commit), for a repository that does
#: not have the file yet.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"

template="" from="" to="" remove=0 find=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --template) template="$2"; shift 2 ;;
    --from) from="$2"; shift 2 ;;
    --to) to="$2"; shift 2 ;;
    --remove) remove=1; shift ;;
    --find-base) find=1; shift ;;
    *) die "unknown option: $1 (see --help)" 2 ;;
  esac
done
[ -n "$template" ] || die "--template is required" 2
[ -d "$template" ] || die "--template is not a directory: $template" 2
root="${REPO_ROOT:-$PWD}"
# rev-parse prints the spec itself when the path is absent. Only a real blob counts.
blob_at() { # blob_at <repo> <rev> <path>
  git -C "$1" rev-parse --verify --quiet "$2:$3" 2>/dev/null || true
}

if [ "$find" = 1 ]; then
  git -C "$template" rev-parse --verify --quiet HEAD >/dev/null 2>&1 || die "no template commit to compare: $template"
  git -C "$root" rev-parse --verify --quiet HEAD >/dev/null 2>&1 || die "this repository has no commit"
  first="$(git -C "$root" rev-list --reverse HEAD | while read -r c; do
    # An if, not an && list: a missing file must not leak the 128 of cat-file as the loop status.
    if git -C "$root" cat-file -e "$c:.github/method-origin" 2>/dev/null; then echo "$c"; break; fi
  done)"
  [ -n "$first" ] || first="$(git -C "$root" rev-list --max-parents=0 HEAD | tail -1)"
  best="" bestn=-1
  # One ls-tree per side and one awk per template commit: a git call per file and commit took minutes.
  firsttree="$(mktemp)"
  git -C "$root" ls-tree -r "$first" | awk -F'\t' '{ split($1, m, " "); print m[3] "\t" $2 }' >"$firsttree"
  while read -r rev; do
    [ -n "$rev" ] || continue
    n="$(git -C "$template" ls-tree -r "$rev" | awk -F'\t' -v ft="$firsttree" '
      BEGIN { while ((getline l < ft) > 0) seen[l] = 1 }
      { split($1, m, " "); if ((m[3] "\t" $2) in seen) n++ }
      END { print n + 0 }')"
    if [ "$n" -gt "$bestn" ]; then bestn=$n; best=$rev; fi
  done < <(git -C "$template" rev-list --reverse HEAD)
  rm -f "$firsttree"
  [ -n "$best" ] || die "no template commit to compare"
  echo "$best"
  exit 0
fi
to="${to:-$(git -C "$template" rev-parse HEAD)}"

if [ -z "$from" ]; then
  [ -f "$root/.github/method-origin" ] || die "no .github/method-origin: record it with setup-repo.sh --record-origin <sha>, or pass --from" 2
  from="$(tr -d '[:space:]' <"$root/.github/method-origin")"
  [ "$from" = template ] && from="$to"
fi

list_manifest() { # list_manifest <rev>
  git -C "$template" show "$1:.github/method-files.txt" 2>/dev/null | grep -vE '^[[:space:]]*(#|$)' || true
}
from_list="$(list_manifest "$from")"
to_list="$(list_manifest "$to")"
# Directories the method owns, so a file of the repository there is repo-only.
dirs="$(printf '%s\n%s\n' "$from_list" "$to_list" | awk -F/ 'NF>1 { print $1 }' | sort -u)"

paths="$(printf '%s\n%s\n' "$from_list" "$to_list")"
while read -r f; do
  [ -n "$f" ] || continue
  top="${f%%/*}"
  printf '%s\n' "$dirs" | stdin_grep -qx "$top" || continue
  paths="$paths
$f"
done < <(git -C "$root" ls-files)
# Repository files that start from a template default: brought when missing, never overwritten.
seeded=".github/required-checks .github/headless .github/update-notice.md .github/label-areas.tsv .github/ci-extra-jobs"
paths="$paths
$(printf '%s\n' $seeded)"
paths="$(printf '%s\n' "$paths" | awk 'NF && !seen[$0]++')"

while read -r path; do
  [ -n "$path" ] || continue
  fb="$(blob_at "$template" "$from" "$path")"
  tb="$(blob_at "$template" "$to" "$path")"
  if [ -f "$root/$path" ]; then
    rb="$(git -C "$root" hash-object "$path")"
  else
    rb=""
  fi
  if [ "${path#scripts/tests/template/}" != "$path" ]; then
    # Tests that only hold in the template: never part of a repository.
    if [ -n "$rb" ]; then
      echo "template-only $path"
      if [ "$remove" = 1 ]; then rm -f "$root/$path"; fi
    fi
  elif printf '%s\n' $seeded | stdin_grep -qx "$path"; then
    if [ -n "$rb" ]; then echo "repo-owned $path"; elif [ -n "$tb" ]; then echo "missing $path"; fi
  elif [ -n "$rb" ] && [ -z "$fb" ] && [ -z "$tb" ]; then
    echo "repo-only $path"
  elif [ -n "$tb" ] && [ -z "$rb" ]; then
    echo "missing $path"
  elif [ -n "$fb" ] && [ -z "$tb" ] && [ -n "$rb" ]; then
    if [ "$rb" = "$fb" ]; then
      echo "removed $path"
      if [ "$remove" = 1 ]; then
        rm -f "$root/$path"
      fi
    else
      echo "kept $path"
    fi
  elif [ -n "$rb" ] && [ "$rb" = "$tb" ]; then
    echo "identical $path"
  elif [ -n "$rb" ] && [ -n "$tb" ]; then
    echo "adapted $path"
  fi
done <<<"$paths"

# Method labels the repository lacks: its labels.tsv is its own, so a row is added by hand (FHDumont/ai-engineering-team-template#207).
if git -C "$template" cat-file -e "$to:.github/labels.tsv" 2>/dev/null; then
  have=""
  [ -f "$root/.github/labels.tsv" ] && have="$(cut -f1 "$root/.github/labels.tsv")"
  while IFS=$'\t' read -r name _; do
    case "$name" in ""|\#*|*"<"*|area:*|group:*|name) continue ;; esac
    printf '%s\n' "$have" | stdin_grep -qxF "$name" || echo "missing-label $name"
  done < <(git -C "$template" show "$to:.github/labels.tsv")
fi
