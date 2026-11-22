#!/usr/bin/env bash
#: open-issue.sh: open an issue whose body is built from the issue template.
#:
#: Usage:
#:   open-issue.sh --type feature|bug|debt|finding --title "Title" \
#:     --section "Objetivo" "text" [--section "<template heading>" "text" ...] \
#:     [--priority high|medium|low] [--size small|medium|large] \
#:     [--end lab-test|auto-close] [--group name] [--area name] [--label x] [--dry-run]
#:
#: --section titles are the `##` headings of .github/ISSUE_TEMPLATE/<type>.md.
#: A missing required section is an error and nothing is created. Labels come
#: from the template, the auto-label.py rules on the body and the options.
#: --dry-run prints the body and labels without calling GitHub.
#: When gh refuses the issue and the labels of the method are missing, the error
#: is the one of setup-repo.sh --check (exit 7, "configurar o repo").
#: Prints the URL of the new issue after reading the issue and its labels back.
#: With a board configured, the item goes to Todo; a board write that fails
#: exits != 0 with the cause and the fix (lib/project.sh).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"
ROOT="$(cd "$HERE/.." && pwd)"

type="" title="" dry=0
values='{}'
extra=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --type) type="$2"; shift 2 ;;
    --title) title="$2"; shift 2 ;;
    --section)
      [ $# -ge 3 ] || die "--section needs a title and a text"
      values="$(jq -c --arg k "$2" --arg v "$3" '. + {($k): $v}' <<<"$values")"
      shift 3 ;;
    --priority) extra+=("priority:$2"); shift 2 ;;
    --size) extra+=("size:$2"); shift 2 ;;
    --end) extra+=("end:$2"); shift 2 ;;
    --group) extra+=("group:$2"); shift 2 ;;
    --area) extra+=("area:$2"); shift 2 ;;
    --label) extra+=("$2"); shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) die "unknown option: $1 (see --help)" 2 ;;
  esac
done
[ -n "$type" ] || die "--type is required" 2
[ -n "$title" ] || die "--title is required" 2

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf '%s' "$values" >"$tmp/values.json"
# The body comes from the template itself; a missing required section stops here.
REPO_ROOT="$ROOT" python3 "$HERE/lib/issue_template.py" render "$type" "$tmp/values.json" >"$tmp/body.md" \
  || die "issue not created"

# Template labels + auto-label rules + options, without repeats.
tpl_labels="$(REPO_ROOT="$ROOT" python3 "$HERE/lib/issue_template.py" sections "$type" | jq -r '.labels[]')"
auto_labels="$(python3 "$HERE/auto-label.py" --body-file "$tmp/body.md" --labels "$(echo "$tpl_labels" | paste -sd, -)" | jq -r '.add[]')"
labels="$( { echo "$tpl_labels"; echo "$auto_labels"; if [ ${#extra[@]} -gt 0 ]; then printf '%s\n' "${extra[@]}"; fi; } | sed '/^$/d' | awk '!seen[$0]++')"

# An explicit priority/end/size option beats the body rule.
for prefix in priority end size; do
  explicit="$( [ ${#extra[@]} -gt 0 ] && printf '%s\n' "${extra[@]}" | grep "^$prefix:" | tail -1 || true)"
  if [ -n "$explicit" ]; then
    labels="$(echo "$labels" | grep -v "^$prefix:" || true)"
    labels="$(printf '%s\n%s\n' "$labels" "$explicit" | sed '/^$/d')"
  fi
done

if [ "$dry" = 1 ]; then
  echo "title: $title"
  echo "labels: $(echo "$labels" | paste -sd, -)"
  echo "---"
  cat "$tmp/body.md"
  exit 0
fi

require_cmd gh
repo="$(repo_slug)"
# Groups are dynamic: creates the label only if it is in neither labels.tsv nor the
# repository (without --force, so the canonical description is never overwritten).
known="$(grep -v '^#' "$ROOT/.github/labels.tsv" | cut -f1)"
for l in $labels; do
  case "$l" in
    group:*)
      echo "$known" | stdin_grep -qxF "$l" && continue
      gh label create "$l" --repo "$repo" --color d4c5f9 --description "Grupo de afinidade" >/dev/null 2>&1 || true ;;
  esac
done
args=(issue create --repo "$repo" --title "$title" --body-file "$tmp/body.md")
for l in $labels; do args+=(--label "$l"); done
if ! url="$(gh "${args[@]}")"; then
  # Labels of the method missing: the repository was never set up; same message as phase-start.sh.
  "$HERE/setup-repo.sh" --check --only labels >/dev/null
  die "issue not created: gh issue create failed"
fi
# Exit 0 does not prove the issue exists: the URL must be one, and the issue is read back.
num="$(printf '%s\n' "$url" | sed -n -E 's#^https://.*/issues/([0-9]+)$#\1#p' | tail -1)"
[ -n "$num" ] || die "issue not created: gh issue create returned no issue URL (got '${url:-nothing}')"
have="$(gh issue view "$num" --repo "$repo" --json labels --jq '.labels[].name')" ||
  die "issue #$num not confirmed on read back (gh issue view failed)"
for l in $labels; do
  printf '%s\n' "$have" | stdin_grep -qxF "$l" || die "issue #$num was created without the label $l (read back); fix: scripts/label-issue.sh $num --add $l"
done
echo "$url"
# shellcheck source=scripts/lib/project.sh
source "$HERE/lib/project.sh"
project_set_status "$num" "Todo" || die "issue #$num was created, but it is not on the board (cause and fix above)"
