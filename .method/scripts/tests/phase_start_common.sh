#!/usr/bin/env bash
# Shared preparation of the test_phase_start_*.sh files (not a test itself): a repository with
# the scripts, the git hooks, the labels, a bare remote, the fake gh and the spec helper.
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

repo="$(make_repo)"
copy_scripts "$repo"
# phase-start.sh checks the setup against the labels file of the repository.
mkdir -p "$repo/.github" && cp "$REPO/.github/labels.tsv" "$repo/.github/labels.tsv"
# The git hooks are active and the trace is the one the phase locks read: the
# session that opens the phase (phase_opened) cannot commit in the worktree.
cp -R "$REPO/.githooks" "$repo/.githooks"
printf '.worktrees/\n.process/\n' >"$repo/.gitignore"
git -C "$repo" add .method .githooks .gitignore .github
git -C "$repo" commit --quiet -m "chore: scripts"
git -C "$repo" config core.hooksPath .githooks
export PROCESS_EVENTS_FILE="$repo/.process/events.jsonl"
git clone --quiet --bare "$repo" "$TMP/remote.git"
git -C "$repo" remote add origin "$TMP/remote.git"

# Issues 7, 8, 11 and 12 are open; 9 is closed; 10 is a test issue.
cat >"$TMP/handler.sh" <<'H'
case "$*" in
  "issue view 9 "*) echo '{"state":"CLOSED","title":"Fechada","labels":[{"name":"type:bug"}]}' ;;
  "issue view 10 "*) echo '{"state":"OPEN","title":"Teste de fluxo","labels":[{"name":"test"}]}' ;;
  "issue view "*"--json state,title,labels"*) echo '{"state":"OPEN","title":"Listar issues","labels":[{"name":"type:feature"}]}' ;;
  "api repos/"*"--jq .private") echo "${FAKE_PRIVATE:-false}" ;;
  "issue list"*"--state open"*) printf '%s\n' ${FAKE_OPEN:-} ;;
esac
H
use_fake_gh "$TMP/handler.sh"
fake_setup ok
events() { cat "$PROCESS_EVENTS_FILE" 2>/dev/null || true; }
spec() { # spec <file> <issue> [pair line]
  mkdir -p "$repo/docs/specs"
  printf '# Spec\n\n## Fase #%s — x\n\n1. Etapa. %s\n' "$2" "${3-modelo: sonnet · esforço: low · motivo: leve}" >"$repo/docs/specs/$1"
}

