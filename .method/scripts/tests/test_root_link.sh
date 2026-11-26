#!/usr/bin/env bash
# Scripts run through the scripts link read files from the repo root, not from .method (issue #290).
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

repo="$(make_repo)"
mkdir -p "$repo/.method" "$repo/docs/specs" "$repo/.github"
copy_scripts "$repo"
mv "$repo/scripts" "$repo/.method/scripts"
ln -s .method/scripts "$repo/scripts"
printf '# Spec\n\n## Fase #77 — x\n\nmodelo: sonnet · esforço: medium\n' >"$repo/docs/specs/2026-01-01-x.md"
printf 'k\tv\n' >"$repo/.github/time-targets.tsv"
git -C "$repo" checkout --quiet -b fix/issue-77-x

# check-env.sh finds the spec of the phase through the link.
out="$(cd "$repo" && scripts/check-env.sh 2>&1 || true)"
assert_contains "$out" "ok: spec cites #77" "check-env.sh finds the spec through the scripts link"

# machine-slots.sh --report reads .github/time-targets.tsv of the root.
printf 'validate\t50\ts\n' >"$repo/.github/time-targets.tsv"
slots="$TMP/slots-home"
mkdir -p "$slots"
printf 'ts\tclass\trepo\twait_s\tduration_s\twall_s\n%s\tvalidate\t%s\t0\t100\t100\n' "$(date +%s)" "$(basename "$repo")" >"$slots/history.tsv"
out="$(cd "$repo" && AI_METHOD_CACHE="$slots" scripts/machine-slots.sh --report 2>&1 || true)"
assert_contains "$out" "target 50 s" "machine-slots.sh --report reads time-targets.tsv through the scripts link"

finish
