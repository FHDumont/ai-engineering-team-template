#!/usr/bin/env bash
#: machine-slots.sh: machine-wide slots (validations and phases), load and history.
#:
#: Usage: machine-slots.sh --status | --check <class> [n] | --report [--days N]
#:
#: --status: the slots of each class (validate, fase) with who holds them, and the
#:           load, free memory and swap against the thresholds. Warns, never blocks.
#: --check <class> [n]: exits 0 when n slots (default 1) of the class are free; exits
#:           75 and says who holds them otherwise. Takes nothing.
#: --report [--days N]: median and p90 of wait and duration per class and per
#:           repository from ~/.cache/ai-method/history.tsv (default 7 days), to
#:           compare before and after a change.
#: Limits live in ~/.config/ai-method/machine-limits.env (created from
#: scripts/lib/machine-limits.env.example on the first run); see process-design §6.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=scripts/lib/slots.sh
source "$HERE/lib/slots.sh"

[ $# -gt 0 ] || { print_help "$0"; exit 2; }
slots_load_limits
free_count() { # free_count <class>
  local limit used=0 d
  limit="$(slots_limit "$1")"
  slots_reap "$1"
  for d in "$(slots_home)/slots/$1"/*/; do [ -d "${d%/}" ] && used=$((used + 1)); done
  echo $((limit - used))
}
case "$1" in
  -h|--help) print_help "$0" ;;
  --status)
    for c in validate fase; do
      free="$(free_count "$c")"
      echo "$c: $(( $(slots_limit "$c") - free ))/$(slots_limit "$c") in use"
      slots_holders "$c"
    done
    slots_load_report ;;
  --check)
    c="${2:-}"; n="${3:-1}"
    case "$c" in validate|fase) ;; *) die "class must be validate or fase" 2 ;; esac
    free="$(free_count "$c")"
    if [ "$free" -ge "$n" ]; then exit 0; fi
    echo "error: $c slots: $free free, $n needed (limit $(slots_limit "$c")); held by:" >&2
    slots_holders "$c" >&2
    exit 75 ;;
  --report)
    days=7
    [ "${2:-}" != --days ] || days="${3:?--days needs a number}"
    case "$days" in ''|*[!0-9]*) die "--days needs a number" 2 ;; esac
    f="$(slots_home)/history.tsv"
    [ -f "$f" ] || { echo "no history yet: $f"; exit 0; }
    python3 -I - "$f" "$days" <<'PY'
import csv, sys, time

path, days = sys.argv[1], int(sys.argv[2])
since = time.time() - days * 86400

def pct(vals, p):
    vals = sorted(vals)
    return vals[min(len(vals) - 1, int(round(p * (len(vals) - 1))))]

def med(vals):
    vals = sorted(vals)
    n = len(vals)
    return vals[n // 2] if n % 2 else (vals[n // 2 - 1] + vals[n // 2]) / 2

rows = []
with open(path, encoding="utf-8") as fh:
    for r in csv.DictReader(fh, delimiter="\t"):
        try:
            if float(r["ts"]) >= since:
                rows.append((r["class"], r["repo"], float(r["wait_s"]), float(r["duration_s"])))
        except (ValueError, KeyError, TypeError):
            continue
print(f"history of the last {days} days: {len(rows)} runs")
if not rows:
    sys.exit(0)
print(f"{'class':<10}{'repo':<28}{'runs':>5}  {'wait med':>9}{'wait p90':>9}  {'dur med':>9}{'dur p90':>9}   (seconds)")
groups = {}
for c, repo, w, d in rows:
    groups.setdefault((c, "(all)"), []).append((w, d))
    groups.setdefault((c, repo), []).append((w, d))
for (c, repo), v in sorted(groups.items()):
    ws, ds = [x[0] for x in v], [x[1] for x in v]
    print(f"{c:<10}{repo:<28}{len(v):>5}  {med(ws):>9.0f}{pct(ws, .9):>9.0f}  {med(ds):>9.0f}{pct(ds, .9):>9.0f}")
PY
    ;;
  *) die "unknown option: $1 (see --help)" 2 ;;
esac
