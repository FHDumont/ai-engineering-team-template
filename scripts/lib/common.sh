#!/usr/bin/env bash
# Common functions of the method scripts. Load with:
#   source "$(dirname "$0")/lib/common.sh"
# Compatible with bash 3.2 (macOS) and bash 5 (CI).

# Consume all of stdin while testing a match. Under pipefail, `cmd | grep -q`
# closes the pipe on the first hit (SIGPIPE / 141), so a match looks like a miss.
stdin_grep() {
  local r=0
  grep "$@" >/dev/null || r=$?
  cat >/dev/null || true
  return "$r"
}

# Root of the repository (of the current worktree).
repo_root() {
  git rev-parse --show-toplevel 2>/dev/null
}

# Short error and exit with code 1 (or the given code).
die() {
  echo "error: $1" >&2
  exit "${2:-1}"
}

# A performance deadline warns and does not change the exit code. A hang is a
# separate, wider limit that still fails. CI gets a warning annotation.
warn_over_expected() { # warn_over_expected <what> <measured> <expected>
  [ "${2:-0}" -gt "${3:-0}" ] 2>/dev/null || return 0
  local line="warn: over-expected $1 $2 $3"
  printf '%s\n' "$line"
  [ -z "${CI:-}" ] || printf '::warning::%s\n' "$line"
  if [ -n "${AI_METHOD_OVER_EXPECTED:-}" ]; then
    printf '%s\n' "$line" >>"$AI_METHOD_OVER_EXPECTED" 2>/dev/null || true
  fi
  return 0
}

info() {
  echo "$*"
}

# Requires the commands to exist in PATH.
require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "missing command: $c"
  done
}

# GitHub owner/repo; GH_REPO has priority (tests and CI).
repo_slug() {
  if [ -n "${GH_REPO:-}" ]; then
    echo "$GH_REPO"
    return
  fi
  gh repo view --json nameWithOwner --jq .nameWithOwner
}

# Current branch (empty on a detached HEAD).
# shellcheck disable=SC2120  # other files pass a directory
current_branch() {
  git -C "${1:-.}" branch --show-current 2>/dev/null
}

# True when the branch is the main one.
is_main_branch() {
  case "$1" in
    main|master) return 0 ;;
    *) return 1 ;;
  esac
}

# Format of ask_id (YYYYMMDDHHMMSS-pid); it goes into jq and sed regexes, so it is validated.
valid_ask_id() {
  case "$1" in
    *[!0-9-]*|-*|*-|*-*-*|"") return 1 ;;
  esac
  printf '%s' "$1" | stdin_grep -qE '^[0-9]{14}-[0-9]+$'
}

# Issue number from the branch name (e.g. feat/issue-12-login -> 12).
issue_from_branch() {
  echo "$1" | sed -n -E 's/.*issue-([0-9]+).*/\1/p'
}

# The bots of this repository are data, not code: .github/bots.tsv of the checkout
# these scripts run from (BOTS_FILE overrides the path), one bot per line:
# slug, name, webhook reference (tab-separated; "#" starts a comment line).
bots_file() {
  printf '%s\n' "${BOTS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.github/bots.tsv}"
}

# Slugs of the bots, one per line. Empty when the repository has no bots file.
bot_slugs() {
  local f
  f="$(bots_file)"
  [ -f "$f" ] || return 0
  awk -F '\t' '!/^#/ && $1 != "" { print $1 }' "$f"
}

# Rows of a labels file, without the comment lines. A row with <slug> is repeated
# once per bot, with <slug> and <name> replaced by the columns of the bots file.
label_rows() { # label_rows <labels.tsv>
  local f
  f="$(bots_file)"
  [ -f "$f" ] || f=/dev/null
  awk -F '\t' '
    FILENAME == ARGV[1] && ARGV[1] != ARGV[2] { if ($0 !~ /^#/ && $1 != "") { n++; slug[n] = $1; name[n] = $2 } next }
    /^#/ || $0 == "" { next }
    /<slug>/ {
      for (i = 1; i <= n; i++) { row = $0; gsub(/<slug>/, slug[i], row); gsub(/<name>/, name[i], row); print row }
      next
    }
    { print }' "$f" "$1"
}

# True when a spec cites an issue. A mention in passing does not count: #<n> only
# inside the section ("## ...") of another phase, one whose heading names other
# issues and not this one. The title, the text before the first section, a section
# heading and a section whose heading names no issue all count.
spec_cites() { # spec_cites <spec file> <issue>
  awk -v re="#$2([^0-9]|\$)" '
    /^## / { other = ($0 !~ re && $0 ~ /#[0-9]/) }
    !other && $0 ~ re { found = 1; exit }
    END { exit !found }' "$1"
}

# Specs that cite an issue (spec_cites): paths (relative to the checkout root) of
# the docs/specs/*.md files, one per line. Empty when none does.
specs_citing() { # specs_citing <issue> [checkout root]
  local root="${2:-.}" f
  for f in "$root"/docs/specs/*.md; do
    [ -f "$f" ] || continue
    spec_cites "$f" "$1" && echo "docs/specs/$(basename "$f")"
  done
  return 0
}

# Open issues a spec still cites (spec_cites): the numbers of <open issues> (one
# per line), one per line. Empty: the spec has no open issue.
spec_open_issues() { # spec_open_issues <spec file> <open issue numbers>
  local n
  for n in $2; do
    spec_cites "$1" "$n" && echo "$n"
  done
  return 0
}

# Open issues that have their own "## Fase #<n>" section in a spec (the phases the
# spec still has to open), one per line. An issue cited only in the text (solved
# inside another phase, or roadmap) is not a phase and does not count.
spec_open_phases() { # spec_open_phases <spec file> <open issue numbers>
  local n
  for n in $2; do
    grep -Eq "^## Fase #$n([^0-9]|\$)" "$1" && echo "$n"
  done
  return 0
}

# Pairs a spec asks for an issue, one "model effort" per line, without repeats:
# every "modelo: X · esforço: Y" of the issue's sections ("## ... #<n> ..."); when
# they have none, the first one of a spec that cites the issue. The first line is
# the pair of the phase session. Exits 1 when there is no pair.
spec_pairs() { # spec_pairs <issue> <spec>...
  python3 -I - "$@" <<'PY'
import re, sys

issue, files = sys.argv[1], sys.argv[2:]
pair = re.compile(r"modelo:\s*`?([\w.-]+)`?\s*·\s*esforço:\s*`?([\w+-]+)")
cite = re.compile(r"#%s(?!\d)" % issue)
texts = [open(f, encoding="utf-8").read() for f in files]
sections = "".join(p for t in texts for p in re.split(r"(?m)^(?=## )", t)
                   if p.startswith("## ") and cite.search(p.split("\n", 1)[0]))
found = pair.findall(sections) or [m.groups() for m in (pair.search(t) for t in texts) if m][:1]
if not found:
    sys.exit(1)
for model, effort in dict.fromkeys(found):
    print(model, effort)
PY
}

# Family of a model name, to compare what was asked with what ran:
# "claude-sonnet-5-5" and "sonnet" are both "sonnet". A name without a plain word
# is printed as it came.
model_family() { # model_family <name>
  local fam
  fam="$(printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/\[.*$//' | tr '-' '\n' | grep -E '^[a-z]+$' | grep -vx claude | head -1 || true)"
  printf '%s\n' "${fam:-$1}"
}

# Model of a transcript file (JSONL of the harness): the model of its last assistant
# message. "main" skips the messages of subagents. Prints nothing when it cannot tell.
transcript_model() { # transcript_model <file> [main]
  [ -f "$1" ] || return 0
  tail -n 200 "$1" 2>/dev/null | jq -Rr --arg main "${2:-}" 'fromjson?
    | select(.type == "assistant" and ($main == "" or (.isSidechain | not)))
    | .message.model // empty' 2>/dev/null | grep -v '^<' | tail -1 || true
}

# Real pair of the session that runs the script, "model effort": the model of the
# session's own transcript and the effort the harness exports. "unknown" stands for
# what cannot be read.
session_pair() {
  local sid="${CLAUDE_CODE_SESSION_ID:-}" model="" f
  if [ -n "$sid" ]; then
    for f in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$sid".jsonl; do
      model="$(transcript_model "$f" main)"
      [ -z "$model" ] || break
    done
  fi
  echo "${model:-unknown} ${CLAUDE_EFFORT:-unknown}"
}

# Trace read by the phase locks (git hooks, Claude hooks, close-phase.sh): always
# .process/events.jsonl of the main checkout. PROCESS_EVENTS_FILE is ignored
# here, so a redirected trace opens nothing.
phase_trace_file() { # phase_trace_file [directory]
  local common
  common="$(git -C "${1:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  echo "$(dirname "$common")/.process/events.jsonl"
}

# Who opened phase <issue>, seen from <session id>. Prints one word:
#   other    some session recorded phase_opened of the issue, and it was not this one
#   opener   this session recorded phase_opened of the issue
#   unknown  cannot tell: no session id, not a git checkout, no trace, a trace
#            line that is not JSON, or no phase_opened of the issue
phase_opener_state() { # phase_opener_state <issue> <session id> [directory]
  local trace
  if [ -z "$1" ] || [ -z "$2" ] || ! trace="$(phase_trace_file "${3:-.}")" || [ ! -f "$trace" ]; then
    echo unknown
    return 0
  fi
  jq -rs --arg i "$1" --arg s "$2" '
    [.[] | select(type == "object" and .event == "phase_opened" and (.issue | tostring) == $i) | (.session_id // "")]
    | if length == 0 then "unknown" elif index($s) then "opener" else "other" end' "$trace" 2>/dev/null || echo unknown
}

# Phase of a path: prints "<issue><TAB><main checkout>" when the path is inside
# .worktrees/issue-<n>[-r<k>] (or its git dir, .git/worktrees/issue-<n>[-r<k>]).
phase_of_path() { # phase_of_path <absolute path>
  printf '%s\n' "$1" | sed -n -E 's#^(.*)/(\.worktrees|\.git/worktrees)/issue-([0-9]+)(-r[0-9]+)?(/.*)?$#\3	\1#p'
}

# Prints the script --help: the "#:" lines of the header, in English.
# The rest of the header ("# ") is a maintainer comment.
print_help() {
  sed -n 's/^#: \{0,1\}//p' "$1"
}

# Trace file: .process/events.jsonl at the root of the main checkout
# (found through --git-common-dir), so every worktree writes to the same place.
# PROCESS_EVENTS_FILE has priority (tests).
events_file() {
  if [ -n "${PROCESS_EVENTS_FILE:-}" ]; then
    echo "$PROCESS_EVENTS_FILE"
    return
  fi
  local common
  common="$(git -C "${1:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  echo "$(dirname "$common")/.process/events.jsonl"
}

# Appends one JSON line to the trace. Never fails: the trace must not stop the flow.
append_event() { # append_event <json-line> [directory]
  local f
  f="$(events_file "${2:-.}")" || return 0
  mkdir -p "$(dirname "$f")" 2>/dev/null || return 0
  printf '%s\n' "$1" >>"$f" 2>/dev/null || true
}

# Event recorded by a script (bot_ask, bot_reply, review_round, phase_closed).
# Extra fields as key=value.
trace_event() { # trace_event <event> [key=value...]
  local ev="$1" branch line
  shift
  command -v jq >/dev/null 2>&1 || return 0
  branch="$(current_branch)"
  line="$(jq -cn --arg ev "$ev" --arg branch "$branch" --arg issue "$(issue_from_branch "$branch")" \
    --arg cwd "$PWD" --arg sid "${CLAUDE_CODE_SESSION_ID:-}" \
    '{ts: (now | todate), event: $ev, session_id: $sid, cwd: $cwd, branch: $branch, issue: $issue}
     + ($ARGS.positional | map(capture("^(?<k>[^=]+)=(?<v>.*)$") | {(.k): .v}) | add // {})' \
    --args "$@" 2>/dev/null)" || return 0
  append_event "$line"
}
