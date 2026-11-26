# Notes to a phase on its issue: comments headed "Para: fase #n" (author.sh)
# after the last comment the phase itself wrote ("De: fase #n").
# phase_pending_notes <issue> [repo]: prints the url of each unanswered note.
# A failed read prints nothing and returns 1 (fails closed). Empty: return 0.

phase_pending_notes() {
  local issue="$1" repo="${2:-}" json
  [ -n "$issue" ] || return 0
  if [ -n "$repo" ]; then
    json="$(gh issue view "$issue" --repo "$repo" --json comments)" || return 1
  else
    json="$(gh issue view "$issue" --json comments)" || return 1
  fi
  [ -n "$json" ] || return 0
  printf '%s' "$json" | jq -r --arg n "$issue" '
    (.comments // []) as $c
    | ($c | map(.body | test("(^|\n)\\*\\*De:\\*\\* fase #" + $n + " ·")) | rindex(true) // -1) as $last
    | $c | to_entries[]
    | select(.key > $last and (.value.body | test("(^|\n)\\*\\*De:\\*\\* [^\n]+ · \\*\\*Para:\\*\\* fase #" + $n + " ·")))
    | .value.url // "(comment without url)"' || return 1
}
