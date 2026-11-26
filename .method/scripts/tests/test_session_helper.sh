#!/usr/bin/env bash
# The Claude.app helper is not a second session line (issue #146).
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

repo="$(make_repo)"
bin="$TMP/bin146"
mkdir -p "$bin"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "9201" "1" "00:10" "0.0" "100" "/Applications/Claude.app/Contents/Helpers/disclaimer -- /usr/bin/claude" \
  "9202" "9201" "00:10" "1.2" "495616" "/usr/bin/claude" >"$TMP/ps146.tab"
printf '%s\t%s\n' "9201" "$repo" "9202" "$repo" >"$TMP/lsof146.tab"
export FAKE_PS_TAB="$TMP/ps146.tab" FAKE_LSOF_TAB="$TMP/lsof146.tab"
cat >"$bin/ps" <<'PS'
#!/bin/sh
tab="${FAKE_PS_TAB:?}"
spec="" pid=""
while [ $# -gt 0 ]; do
  case "$1" in
    -p) pid="$2"; shift 2 ;;
    -o|-axo) spec="$2"; shift 2 ;;
    *) shift ;;
  esac
done
emit() {
  fpid=$(printf '%s' "$1" | awk -F '\t' '{ print $1 }')
  fppid=$(printf '%s' "$1" | awk -F '\t' '{ print $2 }')
  fet=$(printf '%s' "$1" | awk -F '\t' '{ print $3 }')
  fcpu=$(printf '%s' "$1" | awk -F '\t' '{ print $4 }')
  frss=$(printf '%s' "$1" | awk -F '\t' '{ print $5 }')
  fcmd=$(printf '%s' "$1" | awk -F '\t' '{ print $6 }')
  case "$spec" in
    ppid=) printf '%s\n' "$fppid" ;;
    rss=) printf '%s\n' "$frss" ;;
    command=) printf '%s\n' "$fcmd" ;;
    "pid=,ppid=") printf '%s %s\n' "$fpid" "$fppid" ;;
    "pid=,etime=,pcpu=,rss=,command=") printf '%s %s %s %s %s\n' "$fpid" "$fet" "$fcpu" "$frss" "$fcmd" ;;
    *) printf '%s\n' "$fpid $fppid $fet $fcpu $frss $fcmd" ;;
  esac
}
if [ -n "$pid" ]; then
  row=$(awk -F '\t' -v p="$pid" '$1 == p { print; exit }' "$tab")
  [ -n "$row" ] || exit 0
  emit "$row"
  exit 0
fi
while IFS= read -r row; do
  [ -n "$row" ] || continue
  emit "$row"
done <"$tab"
PS
cat >"$bin/lsof" <<'LSOF'
#!/bin/sh
tab="${FAKE_LSOF_TAB:?}"
want=""
while [ $# -gt 0 ]; do
  case "$1" in
    -p) want="$2"; shift 2 ;;
    *) shift ;;
  esac
done
awk -F '\t' -v want="$want" '$1 == want { printf "p%s\nn%s\n", $1, $2 }' "$tab"
LSOF
chmod +x "$bin/ps" "$bin/lsof"
out="$(PATH="$bin:$PATH" "$SCRIPTS/sessions.sh" --list)"
assert_contains "$out" "9202" "the claude child is a session line"
assert_not_contains "$out" "9201" "the app helper is not a session line"
assert_eq 1 "$(printf '%s\n' "$out" | grep -c '9202')" "one line for the app session"

finish
