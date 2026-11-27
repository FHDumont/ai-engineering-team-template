#!/usr/bin/env bash
#: fetch-template.sh: brings a template commit into .process/template of the current worktree.
#:
#: Usage: fetch-template.sh [<sha>|<tag>] [--url <template>] [--apply]
#:
#: Without a destination it uses the last method tag of the template (vYYYY.MM.DD-N,
#: made by tag-release.sh at the end of a group), never the tip of main; no tag is an
#: error. A sha or a tag given explicitly is used as it is.
#:
#: Fetches the destination (and the commit of .github/method-origin, when there is one) from
#: the template into a small git directory at .process/template, with the files of
#: <sha> extracted, so method-diff.sh --template .process/template --to <sha> works.
#: No worktree is registered and nothing is cloned: .process/ is outside git, and the
#: phase is listed once. --url defaults to https://github.com/FHDumont/ai-engineering-team-template
#: (a local path works). --apply then copies the method paths of <sha> (its
#: .github/method-files.txt, plus method docs (AGENTS.md, CLAUDE.md, docs/process-design.md, docs/adr/*, .cursor/rules/*) and files of the method folders the worktree lacks or has outdated: equal to the origin, different at <sha>) over this
#: worktree; files only of the repository stay. The copy is a headless-safe step:
#: this script is in the allow list, `git checkout <sha> -- <paths>` is not.
set -euo pipefail
# The whole body lives in a function bash reads in full before running it, and the call and the
# exit share one line: --apply may overwrite this very file, and bash must not read the new bytes (#322).
main() {
  HERE="$(cd "$(dirname "$0")" && pwd)"
  # shellcheck source=.method/scripts/lib/common.sh
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
  tag=""
  if [ -z "$sha" ]; then
    tag="$(git ls-remote --tags --refs "$url" 'v*' 2>/dev/null |
      sed -nE 's#^.*refs/tags/(v([0-9]{4})\.([0-9]{2})\.([0-9]{2})-([0-9]+))$#\2\3\4 \5 \1#p' |
      sort -k1,1n -k2,2n | tail -1 | cut -d' ' -f3)"
    [ -n "$tag" ] || die "no method tag at $url; pass a sha or a tag" 1
    sha="$tag"
  fi

  root="$(repo_root)" || die "not in a git repository" 2
  dir="$root/.process/template"
  mkdir -p "$dir"
  [ -d "$dir/.git" ] || git -C "$dir" init --quiet
  fetch_rev() { git -C "$dir" fetch --quiet --no-tags "$url" "$1" 2>/dev/null; }
  # A short sha is not fetchable: resolve it against the branches of the template first.
  case "$sha" in
    *[!0-9a-f]*|"") ;;
    *) if [ "${#sha}" -lt 40 ]; then
         git -C "$dir" fetch --quiet --no-tags "$url" '+refs/heads/*:refs/remotes/template/*' 2>/dev/null || true
         full="$(git -C "$dir" rev-parse --verify --quiet "$sha^{commit}")" || die "cannot resolve $sha at $url" 1
         sha="$full"
       fi ;;
  esac
  fetch_rev "$sha" || die "cannot fetch $sha from $url" 1
  dest="$(git -C "$dir" rev-parse --verify --quiet "FETCH_HEAD^{commit}")" || die "no commit $sha at $url" 1
  git -C "$dir" update-ref refs/heads/destination "$dest"
  # The tag of the destination (explicit or last) stays in the extracted template, so the notice can cite it.
  case "$sha" in v[0-9][0-9][0-9][0-9].*-*) git -C "$dir" update-ref "refs/tags/$sha" "$dest" ;; esac
  if [ -f "$root/.github/method-origin" ]; then
    origin="$(tr -d '[:space:]' <"$root/.github/method-origin")"
    case "$origin" in
      ""|template) ;;
      *) if fetch_rev "$origin"; then git -C "$dir" update-ref refs/heads/origin "$(git -C "$dir" rev-parse FETCH_HEAD)"; else info "origin $origin not fetched; method-diff needs --from"; fi ;;
    esac
  fi
  git -C "$dir" checkout --quiet --force --detach "$dest"
  info "template $dest${tag:+ ($tag)} extracted in .process/template"
  [ "$apply" = 1 ] || exit 0

  origin_ref=""
  git -C "$dir" rev-parse --verify --quiet refs/heads/origin >/dev/null && origin_ref=refs/heads/origin
  md="$dir/.method/scripts/method-diff.sh"
  [ -f "$md" ] || md="$dir/scripts/method-diff.sh"
  [ -f "$md" ] || die "$dest has no .method/scripts/method-diff.sh nor scripts/method-diff.sh" 1
  # The method-diff.sh and the lib of the destination decide, not the ones of this repository (which may be old).
  run_diff() { (cd "$root" && REPO_ROOT="$root" bash "$md" --template "$dir" --to "$dest" "$@"); }
  diff_args=()
  [ -n "$origin_ref" ] || diff_args=(--from "$dest")
  report="$(run_diff ${diff_args[@]+"${diff_args[@]}"})"
  n=0
  while read -r class f; do
    case "$class" in outdated|missing) ;; *) continue ;; esac
    [ -f "$dir/$f" ] || continue
    mkdir -p "$root/$(dirname "$f")"
    cp -p "$dir/$f" "$root/$f"
    n=$((n + 1))
  done <<<"$report"
  # A method label the repository lacks goes to the end of its labels.tsv, with the destination row.
  while read -r class name; do
    [ "$class" = missing-label ] || continue
    row="$(git -C "$dir" show "$dest:.github/labels.tsv" | awk -F'\t' -v n="$name" '$1 == n { print; exit }')"
    [ -n "$row" ] || continue
    mkdir -p "$root/.github"
    [ -f "$root/.github/labels.tsv" ] && [ -n "$(tail -c1 "$root/.github/labels.tsv")" ] && echo >>"$root/.github/labels.tsv"
    printf '%s\n' "$row" >>"$root/.github/labels.tsv"
  done <<<"$report"
  run_diff ${diff_args[@]+"${diff_args[@]}"} --remove >/dev/null
  info "applied $n method files from $dest"
  run_diff ${diff_args[@]+"${diff_args[@]}"} --notice
}
main "$@"; exit $?
