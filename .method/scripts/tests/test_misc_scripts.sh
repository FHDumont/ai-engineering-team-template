#!/usr/bin/env bash
# Tests for search-history, measure-session and the --help of every script.
# shellcheck source=.method/scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

# A script that is not part of the method must not be executed (issue #92).
# The sentinel lives in a copy: the real .method/scripts/ is never written (#281).
copy="$(make_repo)"
copy_scripts "$copy"
CSCRIPTS="$copy/.method/scripts"
# copy_scripts stubs these two; their --help is read from the real ones.
cp "$SCRIPTS/validate.sh" "$SCRIPTS/check-docs.sh" "$CSCRIPTS/"
sentinel="$CSCRIPTS/zz-not-a-method-script.sh"
marker="$TMP/sentinel-ran"
rm -f "$sentinel" "$marker"
cat >"$sentinel" <<EOF
#!/bin/sh
echo ran >"$marker"
echo "usage: not a method script"
exit 0
EOF
chmod +x "$sentinel"

# Closed list of the method's scripts. Never a glob of .method/scripts/: an adopted
# repository keeps the application's scripts in that directory (issue #92).
for name in \
  archive-adr.sh ask-bot.sh auto-label.py check-attribution.sh check-docs.sh \
  check-env.sh check-workflows.py ci-gate.sh close-phase.sh deploy.sh \
  end-check.sh gen-changelog.py gen-docs.sh gen-roadmap.py init-env.sh \
  integrate-parallel.sh label-issue.sh machine-slots.sh measure-session.py method-diff.sh \
  new-phase.sh notify-bot.sh open-issue.sh open-parallel.sh phase-start.sh \
  progress.sh redo-phase.sh search-history.sh sessions.sh setup-repo.sh \
  setup-runner.sh start-headless.sh status.sh summarize-thread.sh \
  trace-view.py triage.sh validate.sh wait-reply.sh weights.sh
do
  s="$CSCRIPTS/$name"
  out="$("$s" --help 2>&1)" && rc=0 || rc=$?
  assert_eq 0 "$rc" "$(basename "$s") --help exits 0"
  [ -n "$out" ] && ok || bad "$(basename "$s") --help prints usage"
  # --help is part of the code: in English.
  assert_contains "$(printf '%s' "$out" | tr '[:upper:]' '[:lower:]')" "usage" "$(basename "$s") --help shows usage in English"
  assert_not_contains "$out" "Uso:" "$(basename "$s") --help has no Portuguese usage"
done
[ ! -f "$marker" ] && ok || bad "a sentinel script in .method/scripts/ was executed"
rm -f "$sentinel"

repo="$(make_repo)"
mkdir -p "$repo/docs/adr/archive"
echo "Estado: usamos rebase" >"$repo/docs/STATE.md"
echo "| [ADR-001](ADR-001-x.md) | Rebase | vigente |" >"$repo/docs/adr/INDEX.md"
echo "Decidimos usar rebase" >"$repo/docs/adr/archive/ADR-000-old.md"
git -C "$repo" add docs; git -C "$repo" commit --quiet -m "docs: decide rebase only"
out="$(REPO_ROOT="$repo" "$SCRIPTS/search-history.sh" rebase --local)"
assert_contains "$out" "docs/STATE.md:1" "finds in STATE first"
assert_contains "$out" "archive/ADR-000-old.md" "searches archived ADRs"
assert_contains "$out" "docs: decide rebase only" "searches git log"
assert_eq "== state + adr index" "$(echo "$out" | head -1)" "cheapest source first"

cat >"$TMP/session.jsonl" <<'J'
{"type":"user","message":{"role":"user","content":"executar a issue"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash"},{"type":"tool_use","name":"AskUserQuestion"}],"usage":{"input_tokens":100,"output_tokens":20}}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"um dois três"}]}}
J
out="$("$SCRIPTS/measure-session.py" "$TMP/session.jsonl" --json)"
assert_eq '1 2 1 3 100' "$(echo "$out" | jq -r '.[0] | [.user_messages, .tool_calls, .choice_questions, .words_read, .input_tokens] | map(tostring) | join(" ")')" "counts touches, tools, choices, words, tokens"
finish
