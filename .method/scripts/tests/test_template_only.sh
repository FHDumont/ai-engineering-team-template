#!/usr/bin/env bash
# Runs the checks that exist only in this template. An adopted repository does not
# copy .method/scripts/tests/template, so this file finds nothing there and passes.
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

dir="$REPO/.method/scripts/tests/template"
if [ -d "$dir" ]; then
  for t in "$dir"/test_*.sh "$dir"/test_*.py; do
    [ -e "$t" ] || continue
    case "$t" in
      *.py) assert_status 0 "$(basename "$t")" python3 "$t" ;;
      *) assert_status 0 "$(basename "$t")" bash "$t" ;;
    esac
  done
fi
finish
