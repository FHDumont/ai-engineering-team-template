#!/usr/bin/env bash
#: label-issue.sh: apply type, area, priority, group, size and end labels.
#:
#: Usage:
#:   label-issue.sh <number> [--type feature|bug|docs|chore] [--area name]...
#:     [--priority high|medium|low] [--group name] [--size small|medium|large]
#:     [--end lab-test|auto-close] [--add label]... [--remove label]... [--dry-run]
#:
#: Priority, size and end are single-choice: the previous one is removed.
#: Labels missing from .github/labels.tsv are refused, except `group:*`, which
#: is created on the fly. Works for issues and PRs. Reads the labels back and
#: exits 1 when the request is not there.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"
ROOT="$(cd "$HERE/.." && pwd)"

[ $# -gt 0 ] || { print_help "$0"; exit 2; }
case "$1" in -h|--help) print_help "$0"; exit 0 ;; esac
num="$1"; shift
case "$num" in ''|*[!0-9]*) die "first argument must be the issue number" 2 ;; esac

add=() remove=() single=() dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --type) add+=("type:$2"); shift 2 ;;
    --area) add+=("area:$2"); shift 2 ;;
    --group) add+=("group:$2"); shift 2 ;;
    --priority) add+=("priority:$2"); single+=(priority); shift 2 ;;
    --size) add+=("size:$2"); single+=(size); shift 2 ;;
    --end) add+=("end:$2"); single+=(end); shift 2 ;;
    --add) add+=("$2"); shift 2 ;;
    --remove) remove+=("$2"); shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) die "unknown option: $1 (see --help)" 2 ;;
  esac
done

known="$(label_rows "$ROOT/.github/labels.tsv" | cut -f1)"
if [ ${#add[@]} -gt 0 ]; then
  for l in "${add[@]}"; do
    case "$l" in group:*) continue ;; esac
    echo "$known" | grep -qxF "$l" || die "unknown label: $l (add it to .github/labels.tsv)"
  done
fi

repo="${GH_REPO:-}"
[ "$dry" = 1 ] || { require_cmd gh; repo="$(repo_slug)"; }

# Current labels, to remove the previous one from the single-choice categories.
if [ ${#single[@]} -gt 0 ] && [ "$dry" = 0 ]; then
  current="$(gh issue view "$num" --repo "$repo" --json labels --jq '.labels[].name')"
  for prefix in "${single[@]}"; do
    for l in $(echo "$current" | grep "^$prefix:" || true); do
      printf '%s\n' "${add[@]}" | grep -qxF "$l" || remove+=("$l")
    done
  done
fi

args=(issue edit "$num" --repo "$repo")
if [ ${#add[@]} -gt 0 ]; then for l in "${add[@]}"; do args+=(--add-label "$l"); done; fi
if [ ${#remove[@]} -gt 0 ]; then for l in "${remove[@]}"; do args+=(--remove-label "$l"); done; fi
[ ${#args[@]} -gt 4 ] || die "nothing to change" 2

if [ "$dry" = 1 ]; then
  echo "gh ${args[*]}"
  exit 0
fi
if [ ${#add[@]} -gt 0 ]; then
  for l in "${add[@]}"; do
    case "$l" in
      group:*) echo "$known" | grep -qxF "$l" || gh label create "$l" --repo "$repo" --color d4c5f9 --description "Grupo de afinidade" >/dev/null 2>&1 || true ;;
    esac
  done
fi
gh "${args[@]}" >/dev/null || die "could not label #$num: gh issue edit failed"
# Read back: every label asked for is on the issue and every removed one is gone.
have="$(gh issue view "$num" --repo "$repo" --json labels --jq '.labels[].name')" ||
  die "labels of #$num not confirmed on read back (gh issue view failed)"
if [ ${#add[@]} -gt 0 ]; then
  for l in "${add[@]}"; do
    printf '%s\n' "$have" | grep -qxF "$l" || die "label $l is not on #$num after the edit (read back)"
  done
fi
if [ ${#remove[@]} -gt 0 ]; then
  for l in "${remove[@]}"; do
    ! printf '%s\n' "$have" | grep -qxF "$l" || die "label $l is still on #$num after the edit (read back)"
  done
fi
echo "labeled #$num: +${add[*]:-} -${remove[*]:-} (read back)"
