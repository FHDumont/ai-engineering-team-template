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
#: Needs one machine-wide "fase" slot per phase opened (new-phase.sh). With no free
#: slot it exits 75 before creating anything and says who holds them. With fewer
#: free slots than issues (and the group within the limit) it opens in waves: it
#: opens as many phases as there are free slots, registers the others as pending
#: (a line "<issue><TAB>pending", no branch, no worktree), exits 0 and prints
#: "pending: #n ..." with the command to open them. Calling it again with only
#: pending issues (one is enough) opens them in the same group, whatever the free
#: slots allow, and replaces their lines. A group over the limit still exits 76.
#: integrate-parallel.sh waits for the pending lines; the other readers of the
#: registry ignore a line with no worktree.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=scripts/lib/slots.sh
source "$HERE/lib/slots.sh"

issues=() pass=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --no-check|--dry-run) pass+=("$1"); shift ;;
    *[!0-9]*) die "unknown argument: $1 (see --help)" 2 ;;
    *) issues+=("$1"); shift ;;
  esac
done

main_root="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
registry="$main_root/.worktrees/parallel-active.tsv"
dry=0
# Issues of the call that are pending in the registry (an earlier wave of the same group).
pending_in() { # pending_in <issue>: 0 when the registry has "<issue>\tpending"
  [ -s "$registry" ] && awk -F '\t' -v n="$1" '$1 == n && $2 == "pending" { f = 1 } END { exit !f }' "$registry"
}
all_pending=1
for i in "${issues[@]}"; do pending_in "$i" || all_pending=0; done
[ ${#issues[@]} -ge 2 ] || [ "$all_pending" = 1 ] || die "a parallel group needs at least 2 issues" 2
for p in ${pass[@]+"${pass[@]}"}; do [ "$p" = --dry-run ] && dry=1; done
[ "$dry" = 1 ] || mkdir -p "$main_root/.worktrees"

# A registry with leftovers is refused: the lines must be the phases really open.
if [ -s "$registry" ]; then
  left=""
  while IFS="$(printf '\t')" read -r n branch path; do
    [ "$branch" != pending ] || continue
    [ -d "$path" ] || left="$left #$n"
    for i in "${issues[@]}"; do [ "$i" != "$n" ] || left="$left #$n"; done
  done <"$registry"
  [ -z "$left" ] ||
    die "$registry has leftover lines ($(echo $left)): run scripts/close-phase.sh --cleanup in the main checkout, or close-phase.sh --abort in the phase worktree"
fi

# Enough phase slots for the whole group, before anything is created.
free_now=${#issues[@]}
if [ "$dry" = 0 ]; then
  slots_load_limits
  fase_limit="$(slots_limit fase)"
  if [ "${#issues[@]}" -gt "$fase_limit" ]; then
    echo "error: ${#issues[@]} phases asked, the machine limit of fase slots is $fase_limit: nothing was created; split the group: open up to $fase_limit issues now and the rest when a slot is free" >&2
    exit 76
  fi
  # Open what fits: the largest k of the asked phases with k free slots; none free is exit 75.
  free_now=${#issues[@]}
  while [ "$free_now" -gt 0 ] && ! "$HERE/machine-slots.sh" --check fase "$free_now" >/dev/null 2>&1; do
    free_now=$((free_now - 1))
  done
  [ "$free_now" -gt 0 ] || { "$HERE/machine-slots.sh" --check fase 1 || exit $?; exit 75; }
fi

# Every issue must pass the guards of new-phase.sh (open, with a spec) before any phase opens.
# phase-start.sh already ran them (PHASE_START_CHECKED=1).
if [ "${PHASE_START_CHECKED:-}" != 1 ]; then
  for n in "${issues[@]}"; do
    "$HERE/new-phase.sh" "$n" --dry-run >/dev/null
  done
fi
opened=()
# Registry helpers: a line is replaced in place (a pending one) or appended; never duplicated.
registry_set() { # registry_set <issue> <branch> [path]
  local n="$1" b="$2" p="${3:-}" line
  line="$n	$b"; [ -z "$p" ] || line="$line	$p"
  if [ -f "$registry" ] && cut -f1 "$registry" | grep -qx "$n"; then
    awk -F '\t' -v n="$n" -v l="$line" '$1 == n { print l; next } { print }' "$registry" >"$registry.tmp"
    mv "$registry.tmp" "$registry"
  else
    printf '%s\n' "$line" >>"$registry"
  fi
}
# Half a group never stays: undo the phases already opened and put back what was pending.
undo() {
  local p
  for p in ${opened[@]+"${opened[@]}"}; do
    echo "undoing the phase at $p"
    (cd "$p" && "$p/scripts/close-phase.sh" --abort --discard) || echo "warn: could not undo $p" >&2
  done
  if [ "$dry" = 0 ] && [ "$all_pending" = 1 ]; then
    for n in "${issues[@]}"; do cut -f1 "$registry" 2>/dev/null | grep -qx "$n" || registry_set "$n" pending; done
  fi
}
# The groups that do not fit now: the rest is registered as pending before the first phase opens.
if [ "$dry" = 0 ] && [ "$free_now" -lt "${#issues[@]}" ]; then
  for n in "${issues[@]:$free_now}"; do
    cut -f1 "$registry" 2>/dev/null | grep -qx "$n" || registry_set "$n" pending
  done
fi
wave=("${issues[@]:0:$free_now}")
for n in "${wave[@]}"; do
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
    registry_set "$n" "$(git -C "$path" branch --show-current)" "$path"
  fi
done
if [ "$dry" = 0 ]; then
  echo "registered ${#issues[@]} parallel phases in $registry"
  if [ "$free_now" -lt "${#issues[@]}" ]; then
    left=""; for n in "${issues[@]:$free_now}"; do left="$left #$n"; done
    echo "pending:$left (no free phase slot for them now; scripts/phase-start.sh <issue> opens one when a slot is free)"
  fi
fi
