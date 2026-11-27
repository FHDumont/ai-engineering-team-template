#!/usr/bin/env bash
# No test depends on the machine being idle (#312, #305; before: #265, #272, #281): three patterns made
# tests fail only under load, each time in a different test.
#  1. `| grep -q` under pipefail: grep closes the pipe on the first match, the writer gets SIGPIPE
#     and the pipeline looks like a miss. Read the text into a variable and test it with case or grep <<<.
#  2. A fixed time limit: a polling loop that gives up after N*0.1s, or a *TIMEOUT*=N (seconds) under 60.
#     A loaded machine takes longer; poll up to a generous bound, never a tight one.
#  3. A write to a real shared path: a fixed /tmp/<name>, or $HOME/ in a test that does not set HOME to its
#     own folder. Parallel tests (or the owner's machine) then see each other's files.
# A line that must keep a pattern ends with `# load-ok: <reason>`; the reason is mandatory.
# The check is a heuristic grep over comment-free lines, like test_no_real_scripts_writes.sh.
# shellcheck disable=SC2016  # the patterns are regexes, not expansions
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

cd "$TESTS_DIR" || exit 1
files=(test_*.sh test_*.py phase_start_common.sh close_phase_common.sh)
unset_home=()
for f in "${files[@]}"; do
  [ "$f" = "test_load_patterns.sh" ] && continue
  grep -qE '^[[:space:]]*export HOME=' "$f" || unset_home+=("$f")
done
sweep() { # sweep <why> <regex> <file>...: lines matching, minus comments and load-ok lines
  grep -nE -e "$2" "${@:3}" 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -vF '# load-ok: ' | grep -v '^test_load_patterns.sh:' | awk -v why="$1" '{print why ": " $0}' || true
}
checked=()
for f in "${files[@]}"; do [ "$f" = "test_load_patterns.sh" ] || checked+=("$f"); done
hits="$(
  sweep "pipe into grep -q" '\| *grep -[a-zA-Z]*q' "${checked[@]}"
  sweep "polling loop with a tight bound (use 1200 or more)" '"\$i" -lt [0-9]{1,3} \]' "${checked[@]}"
  sweep "time limit under 60s" 'TIMEOUT[A-Z_]*=([1-9]|[1-5][0-9])([^0-9]|$)' "${checked[@]}"
  sweep "write to a fixed /tmp path" '(>>?|touch|mkdir( -p)?|rm( -[a-zA-Z]+)?|cp|mv) +"?/tmp/[A-Za-z]' "${checked[@]}"
  [ "${#unset_home[@]}" -eq 0 ] || sweep "write under the real HOME" '(>>?|touch|mkdir( -p)?|rm( -[a-zA-Z]+)?) +"?(\$HOME|~)/' "${unset_home[@]}"
)"
assert_eq "" "$hits" "no test uses a load-sensitive pattern (add '# load-ok: <reason>' when one must stay)"
finish
