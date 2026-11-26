#!/usr/bin/env bash
# Scripts in .method/scripts read files from the repo root, two levels up (issues #290, #288).
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

repo="$(make_repo)"
mkdir -p "$repo/docs/specs" "$repo/.github"
copy_scripts "$repo"
printf '# Spec\n\n## Fase #77 — x\n\nmodelo: sonnet · esforço: medium\n' >"$repo/docs/specs/2026-01-01-x.md"
printf 'k\tv\n' >"$repo/.github/time-targets.tsv"
git -C "$repo" checkout --quiet -b fix/issue-77-x

# check-env.sh finds the spec of the phase.
out="$(cd "$repo" && .method/scripts/check-env.sh 2>&1 || true)"
assert_contains "$out" "ok: spec cites #77" "check-env.sh finds the spec from .method/scripts"

# machine-slots.sh --report reads .github/time-targets.tsv of the root.
printf 'validate\t50\ts\n' >"$repo/.github/time-targets.tsv"
slots="$TMP/slots-home"
mkdir -p "$slots"
printf 'ts\tclass\trepo\twait_s\tduration_s\twall_s\n%s\tvalidate\t%s\t0\t100\t100\n' "$(date +%s)" "$(basename "$repo")" >"$slots/history.tsv"
out="$(cd "$repo" && AI_METHOD_CACHE="$slots" .method/scripts/machine-slots.sh --report 2>&1 || true)"
assert_contains "$out" "target 50 s" "machine-slots.sh --report reads time-targets.tsv from .method/scripts"

finish
