#!/usr/bin/env bash
# Tests for search-history, measure-session and the --help of every script.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

# A script that is not part of the method must not be executed (issue #92).
sentinel="$SCRIPTS/zz-not-a-method-script.sh"
marker="$TMP/sentinel-ran"
rm -f "$sentinel" "$marker"
cat >"$sentinel" <<EOF
#!/bin/sh
echo ran >"$marker"
echo "usage: not a method script"
exit 0
EOF
chmod +x "$sentinel"
trap 'rm -f "$sentinel"; test_sweep; rm -rf "$TMP"' EXIT

# Closed list of the method's scripts. Never a glob of scripts/: an adopted
# repository keeps the application's scripts in that directory (issue #92).
for name in \
  archive-adr.sh ask-bot.sh auto-label.py check-attribution.sh check-docs.sh \
  check-env.sh check-workflows.py ci-gate.sh close-phase.sh deploy.sh \
  end-check.sh gen-changelog.py gen-docs.sh gen-roadmap.py init-env.sh \
  integrate-parallel.sh label-issue.sh machine-slots.sh measure-session.py \
  new-phase.sh notify-bot.sh open-issue.sh open-parallel.sh phase-start.sh \
  progress.sh redo-phase.sh search-history.sh sessions.sh setup-repo.sh \
  setup-runner.sh start-headless.sh status.sh summarize-thread.sh \
  trace-view.py triage.sh validate.sh wait-reply.sh weights.sh
do
  s="$SCRIPTS/$name"
  out="$("$s" --help 2>&1)" && rc=0 || rc=$?
  assert_eq 0 "$rc" "$(basename "$s") --help exits 0"
  [ -n "$out" ] && ok || bad "$(basename "$s") --help prints usage"
  # --help is part of the code: in English.
  assert_contains "$(printf '%s' "$out" | tr '[:upper:]' '[:lower:]')" "usage" "$(basename "$s") --help shows usage in English"
  assert_not_contains "$out" "Uso:" "$(basename "$s") --help has no Portuguese usage"
done
[ ! -f "$marker" ] && ok || bad "a sentinel script in scripts/ was executed"
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

# A script dropped into scripts/ is not part of the method (issue #92). The walk below
# is the same glob the loop at the top uses, so this fails until that walk is a closed list.
# case-92-start
sentinel92="$SCRIPTS/zz-not-a-method-script.sh"
marker92="$TMP/sentinel92.ran"
rm -f "$marker92"
printf '#!/bin/sh\nprintf ran >"%s"\nexit 0\n' "$marker92" >"$sentinel92"
chmod +x "$sentinel92"
for s92 in "$SCRIPTS"/*.sh "$SCRIPTS"/*.py; do
  [ -f "$s92" ] || continue
  "$s92" --help >/dev/null 2>&1 || true
done
got92="$(cat "$marker92" 2>/dev/null || true)"
rm -f "$sentinel92" "$marker92"
assert_eq "" "$got92" "a sentinel script in scripts/ is not executed"
# case-92-end
finish
