#!/usr/bin/env bash
#: open-parallel.sh: open the worktrees of all parallel phases and register them.
#:
#: Usage: open-parallel.sh <issue> <issue> [...] [--no-check] [--dry-run]
#:
#: Runs new-phase.sh for each issue and writes .worktrees/parallel-active.tsv
#: (issue, branch, path), read later by integrate-parallel.sh. Opens nothing
#: unless every issue is open and has a spec (see new-phase.sh).
#: Refuses (exit 1) a registry with leftovers: a line whose worktree is gone, or
#: a line of one of the issues asked for. Never leaves half a group: when one
#: phase fails to open, the ones already opened are undone (close-phase.sh
#: --abort --discard), which takes their lines out of the registry.
#: Needs one machine-wide "fase" slot per issue (new-phase.sh): without enough free
#: slots it exits 75 before creating anything and says who holds them.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"

issues=() pass=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --no-check|--dry-run) pass+=("$1"); shift ;;
    *[!0-9]*) die "unknown argument: $1 (see --help)" 2 ;;
    *) issues+=("$1"); shift ;;
  esac
done
[ ${#issues[@]} -ge 2 ] || die "a parallel group needs at least 2 issues" 2

main_root="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
registry="$main_root/.worktrees/parallel-active.tsv"
dry=0
for p in ${pass[@]+"${pass[@]}"}; do [ "$p" = --dry-run ] && dry=1; done
[ "$dry" = 1 ] || mkdir -p "$main_root/.worktrees"

# A registry with leftovers is refused: the lines must be the phases really open.
if [ -s "$registry" ]; then
  left=""
  while IFS="$(printf '\t')" read -r n branch path; do
    [ -d "$path" ] || left="$left #$n"
    for i in "${issues[@]}"; do [ "$i" != "$n" ] || left="$left #$n"; done
  done <"$registry"
  [ -z "$left" ] ||
    die "$registry has leftover lines ($(echo $left)): run scripts/close-phase.sh --cleanup in the main checkout, or close-phase.sh --abort in the phase worktree"
fi

# Enough phase slots for the whole group, before anything is created.
if [ "$dry" = 0 ]; then
  "$HERE/machine-slots.sh" --check fase "${#issues[@]}" || exit $?
fi

# Every issue must pass the guards of new-phase.sh (open, with a spec) before any phase opens.
for n in "${issues[@]}"; do
  "$HERE/new-phase.sh" "$n" --dry-run >/dev/null
done
opened=()
# Half a group never stays: undo the phases already opened.
undo() {
  local p
  for p in ${opened[@]+"${opened[@]}"}; do
    echo "undoing the phase at $p"
    (cd "$p" && "$p/scripts/close-phase.sh" --abort --discard) || echo "warn: could not undo $p" >&2
  done
}
for n in "${issues[@]}"; do
  if ! out="$("$HERE/new-phase.sh" "$n" ${pass[@]+"${pass[@]}"})"; then
    [ -z "$out" ] || echo "$out"
    undo
    die "phase #$n did not open: the group was not opened and nothing was registered"
  fi
  echo "$out"
  if [ "$dry" = 0 ]; then
    path="$(echo "$out" | tail -1)"
    opened+=("$path")
    # Registered as it opens (the "Fase atual" filter reads the registry); undo takes the line out.
    printf '%s\t%s\t%s\n' "$n" "$(git -C "$path" branch --show-current)" "$path" >>"$registry"
  fi
done
[ "$dry" = 1 ] || echo "registered ${#issues[@]} parallel phases in $registry"
