#!/usr/bin/env bash
# Tests of close-phase.sh --prepare: specs that leave with the phase.
# shellcheck source=.method/scripts/tests/close_phase_common.sh
source "$(dirname "$0")/close_phase_common.sh"

printf 'Resumo\n\nCloses #1\n' >"$TMP/body.md"
# Specs leave by the issue they cite, never by the file name: a spec that cites the
# phase issue and no other open issue is deleted in a phase commit and goes to the PR body.
spec_round() { # spec_round <open issues, JSON> <spec file name> <spec text>
  git -C "$repo" switch --quiet -c "chore/issue-1-spec-$RANDOM" origin/main
  mkdir -p "$repo/docs/specs"
  printf '# Spec\n\n%s\n' "$3" >"$repo/docs/specs/$2"
  git -C "$repo" add docs
  git -C "$repo" commit --quiet -m "docs: spec and state"
  cat >"$TMP/handler.sh" <<H
case "\$*" in
  "pr list"*"--state open"*) echo 12 ;;
  "issue view 1"*) printf 'type:chore\ngroup:g\n' ;;
  "issue list"*"--state open"*) echo '$1' | jq -r "\$(printf '%s' "\$*" | sed -n 's/.*--jq //p')" ;;
  "pr view 12"*) echo '{"number":12,"title":"chore: x","body":"","labels":[],"url":"u"}' ;;
  "pr list"*"merged"*) echo '[]' ;;
  "issue list"*) echo '[]' ;;
esac
H
  use_fake_gh "$TMP/handler.sh"
  assert_status 0 "prepare with a spec ($2, open $1)" sh -c "cd '$repo' && .method/scripts/close-phase.sh --prepare --title 'chore: x' --body-file '$TMP/body.md'"
}
# The file name has nothing of the group: it leaves because it cites #1 and no other open issue.
spec_round '[{"number":1},{"number":40}]' 2026-01-18-plano.md 'Texto da spec da fase #1.'
assert_contains "$(last_output)" "removed docs/specs/2026-01-18-plano.md" "says the spec was removed"
[ ! -e "$repo/docs/specs/2026-01-18-plano.md" ] && ok || bad "spec file is gone"
assert_eq "docs(specs): remove the spec whose last open issue is #1" "$(git -C "$repo" log -1 --format=%s)" "the spec removal is the last commit of the phase"
body_arg="$(gh_calls | sed -n 's/.*pr edit 12 --repo owner\/repo --title chore: x --body-file \([^ ]*\).*/\1/p' | head -1)"
assert_contains "$(cat "$body_arg")" "<summary>Spec (docs/specs/2026-01-18-plano.md)</summary>" "PR body carries the spec"
assert_contains "$(cat "$body_arg")" "Texto da spec da fase #1." "PR body has the spec text"
assert_contains "$(cat "$body_arg")" "Closes #1" "PR body keeps the original text"

# Another open issue cited: the spec stays, whatever the group label says.
spec_round '[{"number":1},{"number":2}]' 2026-01-18-g.md 'Fases #1 e #2.'
assert_contains "$(last_output)" "kept docs/specs/2026-01-18-g.md: it still cites open issue(s) #2" "keeps the spec while another cited issue is open"
[ -e "$repo/docs/specs/2026-01-18-g.md" ] && ok || bad "spec file stays"

# The body carries the spec of the phase even when it stays: the kept spec is
# attached, and a spec the branch deleted that does not cite the phase issue is not.
body_arg="$(gh_calls | sed -n 's/.*pr edit 12 --repo owner\/repo --title chore: x --body-file \([^ ]*\).*/\1/p' | head -1)"
assert_contains "$(cat "$body_arg")" "<summary>Spec (docs/specs/2026-01-18-g.md)</summary>" "PR body carries the spec that stays for another open issue"
git -C "$repo" switch --quiet -c chore/old-specs origin/main
mkdir -p "$repo/docs/specs"
printf '# Spec\n\nFase #50, antiga.\n' >"$repo/docs/specs/2026-01-17-old.md"
git -C "$repo" add docs/specs/2026-01-17-old.md
git -C "$repo" commit --quiet -m "docs: old spec"
git -C "$repo" push --quiet origin chore/old-specs:main
git -C "$repo" fetch --quiet origin
git -C "$repo" switch --quiet -c chore/issue-1-drops-old origin/main
git -C "$repo" rm --quiet docs/specs/2026-01-17-old.md
git -C "$repo" commit --quiet -m "docs: drop the old spec"
assert_status 0 "prepare of a phase that deletes a spec of another issue" sh -c "cd '$repo' && .method/scripts/close-phase.sh --prepare --title 'chore: x' --body-file '$TMP/body.md'"
body_arg="$(gh_calls | sed -n 's/.*pr edit 12 --repo owner\/repo --title chore: x --body-file \([^ ]*\).*/\1/p' | tail -1)"
assert_not_contains "$(cat "${body_arg:-$TMP/body.md}")" "2026-01-17-old.md" "PR body leaves out a deleted spec that does not cite the phase issue"

# A spec named after the group that does not cite the phase issue is not the phase's to delete.
spec_round '[{"number":1}]' 2026-01-18-g.md 'Fase #15 apenas.'
[ -e "$repo/docs/specs/2026-01-18-g.md" ] && ok || bad "a spec that does not cite the issue stays"
assert_not_contains "$(last_output)" "removed" "nothing is removed by the file name"

# An issue the same PR closes does not count as another open issue.
printf 'Resumo\n\nCloses #1\nCloses #3\n' >"$TMP/body.md"
spec_round '[{"number":1},{"number":3}]' 2026-01-18-g.md 'Fases #1 e #3.'
assert_contains "$(last_output)" "removed docs/specs/2026-01-18-g.md" "issues closed by the PR do not keep the spec"
printf 'Resumo\n\nCloses #1\n' >"$TMP/body.md"

# Specs that add up to more than the GitHub body limit (65536): the text that does not
# fit becomes a link to the blob, and every spec is still cited.
big_round() {
  git -C "$repo" switch --quiet -c "chore/issue-1-big-$RANDOM" origin/main
  mkdir -p "$repo/docs/specs"
  for n in a b c; do
    { printf '# Spec\n\nFase #1 e #2.\n\n'; head -c 30000 /dev/zero | tr '\0' 'x'; echo; } >"$repo/docs/specs/2026-01-19-big-$n.md"
  done
  git -C "$repo" add docs
  git -C "$repo" commit --quiet -m "docs: big specs"
  cat >"$TMP/handler.sh" <<'H'
case "$*" in
  "pr list"*"--state open"*) echo 12 ;;
  "issue view 1"*) printf 'type:chore\ngroup:g\n' ;;
  "issue list"*"--state open"*) echo 1 ;;
  "pr view 12"*) echo '{"number":12,"title":"chore: x","body":"","labels":[],"url":"u"}' ;;
  "pr list"*"merged"*) echo '[]' ;;
  "issue list"*) echo '[]' ;;
esac
H
  use_fake_gh "$TMP/handler.sh"
  assert_status 0 "prepare with specs that add up to more than the body limit" sh -c "cd '$repo' && .method/scripts/close-phase.sh --prepare --title 'chore: x' --body-file '$TMP/body.md'"
}
big_round
body_arg="$(gh_calls | sed -n 's/.*pr edit 12 --repo owner\/repo --title chore: x --body-file \([^ ]*\).*/\1/p' | tail -1)"
[ "$(wc -c <"$body_arg")" -lt 65536 ] && ok || bad "body stays under 65536 characters ($(wc -c <"$body_arg"))"
for n in a b c; do
  assert_contains "$(cat "$body_arg")" "docs/specs/2026-01-19-big-$n.md" "body cites big spec $n"
done
assert_contains "$(cat "$body_arg")" "/blob/" "the spec that does not fit is a blob link"

# The spec's ok: approved issue + a spec that declares the sensitive area = spec_ok in the trace.
git -C "$repo" switch --quiet -c chore/issue-1-specok origin/main
mkdir -p "$repo/docs/specs"
printf '# Spec\n\n## Fase #1 — x\n\nÁrea sensível: `scripts/gate.sh` (classe `owner-ok`).\n\n## Fase #9 — y\n\nÁrea sensível: `outro.sh`.\n' >"$repo/docs/specs/2026-01-20-ok.md"
git -C "$repo" add docs
git -C "$repo" commit --quiet -m "docs: spec ok"
# The approved text is the one on origin/main.
git -C "$repo" push --quiet origin HEAD:main
git -C "$repo" fetch --quiet origin
cat >"$TMP/handler.sh" <<'H'
case "$*" in
  "pr list"*"--state open"*) echo 12 ;;
  "issue view 1"*) printf 'type:chore\napproved\n' ;;
  "issue list"*"--state open"*) echo 1 ;;
  "pr view 12"*) echo '{"number":12,"title":"chore: x","body":"","labels":[],"url":"u"}' ;;
  "pr list"*"merged"*) echo '[]' ;;
  "issue list"*) echo '[]' ;;
esac
H
use_fake_gh "$TMP/handler.sh"
export PROCESS_EVENTS_FILE="$TMP/spec-ok-events.jsonl"
assert_status 0 "prepare of an approved issue whose spec declares the area" sh -c "cd '$repo' && .method/scripts/close-phase.sh --prepare --title 'chore: x' --body-file '$TMP/body.md'"
assert_eq "owner-ok,scripts/gate.sh" "$(jq -r 'select(.event == "spec_ok") | .declared' "$PROCESS_EVENTS_FILE" | tail -1)" "records spec_ok with the declared words of the phase section only"
assert_eq "$(git -C "$repo" rev-parse HEAD)" "$(jq -r 'select(.event == "spec_ok") | .sha' "$PROCESS_EVENTS_FILE" | tail -1)" "spec_ok is bound to the pushed HEAD"
# A spec only on the branch (never approved on main) declares nothing.
git -C "$repo" switch --quiet -c chore/issue-1-specok2 origin/main
printf '# Spec\n\n## Fase #1 — x\n\nArea: x\n' >"$repo/docs/specs/2026-01-21-ok2.md"
sed -i.bak 's/^Área sensível:.*/Área sensível: `tudo.sh`./' "$repo/docs/specs/2026-01-20-ok.md"; rm -f "$repo/docs/specs/2026-01-20-ok.md.bak"
git -C "$repo" add docs
git -C "$repo" commit --quiet -m "docs: edited declaration"
: >"$PROCESS_EVENTS_FILE"
assert_status 0 "prepare after the branch edited the declaration" sh -c "cd '$repo' && .method/scripts/close-phase.sh --prepare --title 'chore: x' --body-file '$TMP/body.md'"
assert_not_contains "$(cat "$PROCESS_EVENTS_FILE")" "tudo.sh" "an edit of the declaration on the branch is not recorded"
unset PROCESS_EVENTS_FILE

git -C "$repo" switch --quiet main
assert_status 1 "refuses to run on main" sh -c "cd '$repo' && '$CLOSE' --merge"
finish
