#!/usr/bin/env bash
# The method scripts live in .method/scripts; scripts is a versioned link to them (issue #269).
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

[ -x "$REPO/.method/scripts/validate.sh" ] && ok || bad ".method/scripts/validate.sh is missing or not executable"
[ -L "$REPO/scripts" ] && ok || bad "scripts is not a symbolic link"
assert_eq ".method/scripts" "$(readlink "$REPO/scripts" || true)" "scripts points to .method/scripts"
assert_eq "scripts" "$(git -C "$REPO" ls-files scripts)" "git tracks only the link under scripts"
"$REPO/.method/scripts/validate.sh" --help >/dev/null && ok || bad ".method/scripts/validate.sh --help fails"

finish
