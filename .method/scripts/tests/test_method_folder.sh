#!/usr/bin/env bash
# The method scripts live in .method/scripts; scripts is a versioned link to them (issue #269).
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

[ -x "$REPO/.method/scripts/validate.sh" ] && ok || bad ".method/scripts/validate.sh is missing or not executable"
[ -L "$REPO/scripts" ] && ok || bad "scripts is not a symbolic link"
assert_eq ".method/scripts" "$(readlink "$REPO/scripts" || true)" "scripts points to .method/scripts"
assert_eq "scripts" "$(git -C "$REPO" ls-files scripts)" "git tracks only the link under scripts"
"$REPO/.method/scripts/validate.sh" --help >/dev/null && ok || bad ".method/scripts/validate.sh --help fails"

# The method globs in code cover the new folder, also with an adopter's old one-class list.
old="$TMP/old-sensitive-paths"
printf 'db/migrations/**\n' >"$old"
sens() { printf '%s\n' "$2" | SENSITIVE_CLASS="$1" python3 "$SCRIPTS/lib/sensitive_paths.py" "$old"; }
assert_eq ".method/scripts/sessions.sh" "$(sens owner-ok .method/scripts/sessions.sh)" ".method/scripts/sessions.sh is owner-ok by code"
assert_eq ".method/scripts/close-phase.sh" "$(sens gate .method/scripts/close-phase.sh)" ".method/scripts/close-phase.sh is gate by code"
assert_eq ".method/scripts/lib/sensitive_paths.py" "$(sens gate .method/scripts/lib/sensitive_paths.py)" "sensitive_paths.py is gate by code in the new folder"

finish
