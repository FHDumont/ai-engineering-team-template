#!/usr/bin/env bash
# The method scripts live in .method/scripts; the old scripts link is gone (issues #269, #288).
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

[ -x "$REPO/.method/scripts/validate.sh" ] && ok || bad ".method/scripts/validate.sh is missing or not executable"
[ ! -e "$REPO/scripts" ] && [ ! -L "$REPO/scripts" ] && ok || bad "the scripts link is back at the repo root"
assert_eq "" "$(git -C "$REPO" ls-files scripts)" "git tracks nothing at scripts"
"$REPO/.method/scripts/validate.sh" --help >/dev/null && ok || bad ".method/scripts/validate.sh --help fails"

# The method globs in code cover the new folder, also with an adopter's old one-class list.
old="$TMP/old-sensitive-paths"
printf 'db/migrations/**\n' >"$old"
sens() { printf '%s\n' "$2" | SENSITIVE_CLASS="$1" python3 "$SCRIPTS/lib/sensitive_paths.py" "$old"; }
assert_eq ".method/scripts/sessions.sh" "$(sens owner-ok .method/scripts/sessions.sh)" ".method/scripts/sessions.sh is owner-ok by code"
assert_eq ".method/scripts/close-phase.sh" "$(sens gate .method/scripts/close-phase.sh)" ".method/scripts/close-phase.sh is gate by code"
assert_eq ".method/scripts/lib/sensitive_paths.py" "$(sens gate .method/scripts/lib/sensitive_paths.py)" "sensitive_paths.py is gate by code in the new folder"

finish
