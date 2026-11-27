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
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

cd "$TESTS_DIR"
files=(test_*.sh test_*.py phase_start_common.sh close_phase_common.sh)
hits=""
for f in "${files[@]}"; do
  [ "$f" != "test_load_patterns.sh" ] || continue
  uses_home=no
  grep -qE '^[[:space:]]*export HOME=' "$f" && uses_home=yes
  while IFS= read -r row; do
    n="${row%%:*}"; text="${row#*:}"
    case "$text" in *"# load-ok: "?*) continue ;; esac
    case "$text" in "#"*|[[:space:]]*"#"*) continue ;; esac
    why=""
    if printf '%s\n' "$text" | grep -qE '\| *grep -[a-zA-Z]*q'; then why="pipe into grep -q"
    elif printf '%s\n' "$text" | grep -qE '"\$i" -lt [0-9]{1,3} \]'; then why="polling loop with a tight bound (use 1200 or more)"
    elif printf '%s\n' "$text" | grep -qE '[A-Z_]*TIMEOUT[A-Z_]*=([1-9]|[1-5][0-9])([^0-9]|$)'; then why="time limit under 60s"
    elif printf '%s\n' "$text" | grep -qE '(>>?|touch|mkdir( -p)?|rm( -[a-zA-Z]+)?|cp|mv) +"?/tmp/[A-Za-z]'; then why="write to a fixed /tmp path"
    elif [ "$uses_home" = no ] && printf '%s\n' "$text" | grep -qE '(>>?|touch|mkdir( -p)?|rm( -[a-zA-Z]+)?) +"?(\$HOME|~)/'; then why="write under the real HOME"
    fi
    [ -z "$why" ] || hits="$hits$f:$n: $why: $text"$'\n'
  done < <(grep -nE '.' "$f")
done
assert_eq "" "$hits" "no test uses a load-sensitive pattern (add '# load-ok: <reason>' when one must stay)"
finish
