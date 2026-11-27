#!/usr/bin/env bash
#: close-phase.sh: close the phase of the current branch (design §6.1), in steps.
#:
#: Usage:
#:   close-phase.sh --prepare --title "chore: ..." --body-file F [--issue N]
#:   close-phase.sh --save-review AGENT_ID [--gate]
#:   close-phase.sh --publish-review F [--verdict success|failure] [--gate] [--round N]
#:   close-phase.sh --pre-review --verdict clean|findings [--round N]
#:   close-phase.sh --check
#:   close-phase.sh --merge [--owner-ok SHA] [--wait]
#:   close-phase.sh --pr N --publish-review F [--verdict success|failure]
#:   close-phase.sh --pr N --merge --owner-ok SHA
#:
#: Do not pipe --check or --merge (the pipe hides the exit code and the cleanup
#: can stop the reader). Write the output to a file and read its last line:
#:   .method/scripts/close-phase.sh --merge --wait >file 2>&1
#:   close-phase.sh --cleanup
#:   close-phase.sh --abort [--discard]
#:
#: --prepare: refuses, before anything else, when origin/main changed a gate-class path after
#:   the base of the branch (rebase first); runs validate.sh (not again when the trace holds a green run of this
#:   branch on the same HEAD, or on a later commit that changes nothing the suite
#:   reads, with no change in the tree) and check-docs.sh and pushes ONCE per round; opens
#:   the PR, or edits it only if the title or body changed; copies the issue
#:   labels to the PR. It does not regenerate CHANGELOG.md or ROADMAP.md (the
#:   main session generates them once at the end, with gen-docs.sh) and does not
#:   require a change in docs/STATE.md. Deletes, in a phase commit, every spec
#:   that cites the phase issue and cites no other open issue (issues the PR
#:   closes do not count); the file name does not matter. The text of every spec
#:   that cites the phase issue, deleted or kept, goes at the end of the PR body,
#:   in a <details>; a deleted spec that does not cite it stays out.
#:   Writes the "## Modelo e esforço" section of the PR body from the trace
#:   (requested x used table, .method/scripts/trace-view.py --pairs): what the body file
#:   has in that section is replaced.
#: --save-review: writes the close-reviewer opinion literally to .process/reviewer-<sha>.md of HEAD
#:   (--gate: reviewer-gate-<sha>.md), from the transcript of the subagent AGENT_ID (the agentId of
#:   the Agent result; foreground or background): the last text with a "Veredito:" line, the same
#:   filter the trace hook hashes. Refuses, writing nothing, when the agent has no close-reviewer
#:   stop in the trace or its sha256 is not the output_sha the hook recorded. The transcript is
#:   found under ~/.claude/projects/*/*/subagents/ (CLOSE_PHASE_SUBAGENTS_ROOT replaces ~/.claude/projects).
#:   Never write the opinion by hand.
#: --publish-review: posts the independent review (file, in Portuguese) as a PR
#:   comment and sets the review/independent status on the HEAD SHA. The file must
#:   be the saved close-reviewer output (.process/reviewer-<sha>.md), written whole
#:   and literally by --save-review (step 5 of the close-phase skill); the agent
#:   writes only that .md. The script reads its "Veredito:" line (aprovado = success,
#:   mudanças pedidas = failure; no line: refused), writes .process/reviewer-<sha>.verdict
#:   and refuses a --verdict that differs from it (--verdict is optional); a rewrite is
#:   refused, and so is an opinion whose sha256 differs from the one the trace hook recorded
#:   when the close-reviewer stopped (run the close-reviewer again; never edit the opinion). --gate publishes the second review of a PR that touches the gate
#:   (.process/reviewer-gate-<sha>.md): comment and gate_review in the trace, no
#:   review/independent status. Refuses an
#:   opinion without a reviewer round after the last push: the trace of the main
#:   checkout must hold the phase_push of the branch (recorded by --prepare and
#:   by redo-phase.sh) on the PR head SHA and, after it, a SubagentStart of the
#:   close-reviewer agent of this session. Records review_round in the trace
#:   (.process/events.jsonl).
#: --check: reads the PR's mergeable, mergeStateStatus and headRefOid. UNKNOWN
#:   retries (up to 5 reads, CLOSE_PHASE_MERGEABLE_PAUSE s apart, default 10;
#:   still UNKNOWN: exit 8). Dirty/CONFLICTING: calls redo-phase.sh without
#:   waiting for CI and without asking anyone; once redone, exits 0 with the new
#:   PR (under --merge exits 6: the new PR has no CI and no review yet); a real
#:   conflict in the cherry-pick exits 4. A PR with a commit that origin/main
#:   already has under another SHA (git cherry origin/main HEAD, e.g. the spec commit
#:   another phase of the group carried) is redone the same way. A PR that is only
#:   behind main (no conflict, no such commit) is not redone. Then requires a check on the HEAD SHA: none after
#:   CLOSE_PHASE_CI_TIMEOUT s (default 180, read every CLOSE_PHASE_CI_POLL,
#:   default 15) exits 7 as CI missing; a check on an older SHA does not count.
#:   Run it before and while waiting for CI; --merge runs it too.
#: --prepare, --check and --merge --wait record their steps in
#:   ~/.cache/ai-method/progress/ (.method/scripts/progress.sh), never in the output.
#: --pre-review: records pre_review (sha of HEAD, verdict, round) in the trace after the
#:   cheap review of the close-reviewer (only the issue and the diff; no tests, no push,
#:   no status). --prepare warns, without refusing, when the trace holds no pre_review
#:   of the HEAD it starts from.
#: --merge: first refuses (exit 12) while the issue holds a comment headed "Para: fase #n"
#:   (.method/scripts/lib/author.sh) after the last comment of the phase itself; then refuses with needs-owner-ok, a sensitive area label or a diff in
#:   .github/sensitive-paths in the class owner-ok (union of the base's list and the PR's;
#:   no readable list on the base: refused; a list with no `# class:` line is all owner-ok),
#:   unless --owner-ok SHA (only after the owner's ok in a
#:   choice question, bound to that SHA of HEAD). --owner-ok only counts with needs-owner-ok already on the
#:   PR: without it the refusal puts the label (read back) and exits 5, with or
#:   without the flag. A diff in the class gate (or needs-gate-review on the PR) needs, instead
#:   of the owner, a second close-reviewer opinion about "does it weaken the gate?",
#:   published with --publish-review F --gate on that HEAD with verdict success;
#:   without it the refusal puts needs-gate-review (read back) and exits 5. Requires review/independent = success on HEAD and, in the
#:   trace, the close-reviewer round of this session after the push of that HEAD
#:   (a status posted by hand does not count); requires the protection of the
#:   base branch with CI and review/independent (no protection, no merge), except in
#:   the unprotected mode (repository variable PROCESS_BRANCH_MODE, set by
#:   setup-repo.sh on a plan with no branch protection): there it reads through the
#:   API that the CI check run and review/independent are success on HEAD (exit 11
#:   when not); runs
#:   check-attribution.sh --pr N (final body and commits); then
#:   gh pr merge --auto --rebase --delete-branch. Before that, requires the phase
#:   to have run in a child session (phase_session event of the issue, from a session
#:   other than the one that opened the phase, in .process/events.jsonl); an issue with the test
#:   label goes through the same gate. The gate fails closed: the trace is
#:   .process/events.jsonl of the main checkout (PROCESS_EVENTS_FILE does not
#:   redirect it) and must hold a phase_opened of the branch's issue; the session
#:   that runs --merge (CLAUDE_CODE_SESSION_ID) must be another one, with its own
#:   phase_session (check-env.sh) and an event recorded by the hooks; --issue
#:   different from the branch's issue is refused (exit 2). --wait waits for the merge and
#:   runs --cleanup; each round it reads CI and review/independent on HEAD and leaves at once
#:   (exit 13) when either turned failure or cancelled, naming the failed run, the fix in a
#:   new commit or .method/scripts/rerun-ci.sh, and that the owner's ok holds only for the old SHA;
#:   it leaves at once (exit 1) when a check on HEAD was cancelled,
#:   naming .method/scripts/rerun-ci.sh <run>. Never dispatches a deploy: .method/scripts/deploy.sh does, run by
#:   the main session after the last merge of the group.
#: --pr N: a pull request whose head is not a phase branch. A phase branch is
#:   <type>/issue-<n>-* with type feat, fix, docs or chore (new-phase.sh),
#:   including fix/issue-*. --pr does not use the phase gate and it does not
#:   change --merge for a phase branch. --publish-review posts review/independent
#:   on that pull request's head SHA from the saved review of that SHA
#:   (.process/reviewer-<sha>.md; the .verdict is read from its Veredito line). --merge is refused
#:   unless --owner-ok is that same SHA, the CI check run on it is success, and
#:   the saved independent review of that SHA has verdict success. A wrong SHA,
#:   missing CI and a phase head are refused. The phase path stays --merge.
#: --prepare, --publish-review, --check and --merge exit 9 in the session that
#:   opened the phase (phase_opened): it forwards the request to the child
#:   session and stops.
#: --cleanup: after the merge, stops the processes whose directory is in the worktree
#:   and the headless child of the trace (with its MCPs; never a child of the
#:   Claude.app). It does not scan the machine and does not stop an orphan outside
#:   that worktree. Then, like the rest below, records phase_closed in the trace, sets the issue
#:   to Done and resets the "Fase atual" view filter (or leaves the group of
#:   another active phase), takes out of .worktrees/parallel-active.tsv the line
#:   of the phase and every line whose worktree is gone, removes the local
#:   worktree and branch and the remote branch (read back) and updates main. On
#:   main it only cleans the registry and updates main. An untracked file of the
#:   main checkout identical to one main now adds is removed before the update.
#: --abort: gives up the phase without a merge. Before touching anything, lists
#:   what would be lost (uncommitted change, untracked file, commit not pushed,
#:   pushed commit that no PR keeps) and exits 10. With nothing to lose, or with
#:   --discard, closes the PR, deletes the remote branch (read back), sets the
#:   issue back to Todo, takes the group out of the filter and the line out of
#:   .worktrees/parallel-active.tsv and deletes the local worktree and branch.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=.method/scripts/lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=.method/scripts/lib/slots.sh
source "$HERE/lib/slots.sh"
# shellcheck source=.method/scripts/lib/progress.sh
source "$HERE/lib/progress.sh"
# shellcheck source=.method/scripts/lib/notes.sh
source "$HERE/lib/notes.sh"
# shellcheck source=.method/scripts/lib/role.sh
source "$HERE/lib/role.sh"
# shellcheck source=.method/scripts/lib/refs.sh
source "$HERE/lib/refs.sh"
ROOT="$(cd "$HERE/../.." && pwd)"

# gh prints "hint:" lines (for example "gh event listen") that drown the result
# and, once captured, corrupt a value read from the command. Drop them. The last
# line of this script is the result.
# Comments of the method agent: the app token when the owner configured it,
# the owner's gh otherwise. ROLE_APP_REQUIRE=1 refuses until the app exists.
gh_role() {
  if [ "${ROLE_APP_REQUIRE:-}" = 1 ]; then
    role_require method || exit $?
  fi
  role_exec method -- gh "$@"
}

gh() {
  local out err rc=0
  out="$(mktemp)"
  err="$(mktemp)"
  command gh "$@" >"$out" 2>"$err" || rc=$?
  grep -vE '^[[:space:]]*hint:' "$out" || true
  grep -vE '^[[:space:]]*hint:' "$err" >&2 || true
  rm -f "$out" "$err"
  return "$rc"
}

mode="" title="" body_file="" issue="" review_file="" verdict="" round="" owner_ok=0 owner_ok_sha="" wait=0 discard=0 pr="" gate_review=0 agent_id=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --prepare) mode=prepare; shift ;;
    --pre-review) mode=prereview; shift ;;
    --save-review) mode=save; agent_id="${2:-}"; [ -n "$agent_id" ] || die "--save-review needs the agentId of the close-reviewer" 2; shift 2 ;;
    --publish-review) mode=review; review_file="$2"; shift 2 ;;
    --verdict) verdict="$2"; shift 2 ;;
    --gate) gate_review=1; shift ;;
    --round) round="$2"; shift 2 ;;
    --check) mode=check; shift ;;
    --merge) mode=merge; shift ;;
    --cleanup) mode=cleanup; shift ;;
    --abort) mode=abort; shift ;;
    --discard) discard=1; shift ;;
    --owner-ok)
      owner_ok=1
      case "${2:-}" in
        ''|--*) die "--owner-ok needs the SHA of the approved HEAD" 2 ;;
        *) owner_ok_sha="$2"; shift 2 ;;
      esac ;;
    --wait) wait=1; shift ;;
    --pr)
      case "${2:-}" in
        ''|--*) die "--pr needs the number of the pull request" 2 ;;
        *[!0-9]*) die "--pr needs the number of the pull request" 2 ;;
        *) pr="$2"; shift 2 ;;
      esac ;;
    --title) title="$2"; shift 2 ;;
    --body-file) body_file="$2"; shift 2 ;;
    --issue) issue="$2"; shift 2 ;;
    *) die "unknown option: $1 (see --help)" 2 ;;
  esac
done
[ -n "$mode" ] || { print_help "$0"; exit 2; }
if [ -n "$pr" ]; then
  case "$mode" in
    review|merge) ;;
    *) die "--pr is only valid with --publish-review or --merge" 2 ;;
  esac
fi
require_cmd gh jq git python3
cd "$ROOT"

branch="$(current_branch)"
if [ "$mode" != cleanup ] && [ -z "$pr" ] && is_main_branch "$branch"; then
  die "on $branch: close-phase runs on the phase branch"
fi
repo="$(repo_slug)"
# The phase is the one of the branch: --issue only names it when the branch has no number.
branch_issue="$(issue_from_branch "$branch")"
if [ -n "$issue" ] && [ -n "$branch_issue" ] && [ "$issue" != "$branch_issue" ]; then
  die "--issue $issue differs from the phase of branch $branch (#$branch_issue)" 2
fi
[ -n "$issue" ] || issue="$branch_issue"
# The session that opened the phase (the manager) never closes it: the child session does.
case "$mode" in
  prepare|prereview|save|review|check|merge)
    if [ -z "$pr" ] && [ "$(phase_opener_state "$issue" "${CLAUDE_CODE_SESSION_ID:-}" "$ROOT")" = opener ]; then
      die "this session opened phase #$issue: forward the request to the child session (send_message) and stop" 9
    fi ;;
esac

pr_number() {
  gh pr list --repo "$repo" --head "$branch" --state open --json number --jq '.[0].number // empty'
}

SENSITIVE_AREAS='area:billing area:auth area:migration area:credentials'

# SHA of the last green validate.sh this branch recorded, or empty.
last_validate_sha() {
  local events
  events="$(events_file "$ROOT")" || return 1
  [ -f "$events" ] || return 1
  jq -rs --arg b "$branch" '[.[] | select(type == "object" and .event == "phase_validate" and .branch == $b)] | last | .sha // ""' "$events" 2>/dev/null
}

# True when the diff from $1 to $2 changes a path the suite reads. The inert set is
# the one in ci.yml (needs_tests): docs/ and a root .md, except the design, AGENTS.md
# and CLAUDE.md. CHANGELOG.md and ROADMAP.md are inert. A diff that cannot be read counts as read.
suite_reads_diff() { # suite_reads_diff <from> <to>
  local files
  files="$(git diff --name-only --no-renames -z "$1" "$2" 2>/dev/null | tr '\0' '\n' || echo "?")"
  [ "$files" != "?" ] || return 0
  if printf '%s\n' "$files" | grep -vE '^$' | grep -vE '^(docs/|[^/]+\.md$)' | stdin_grep -q .; then
    return 0
  fi
  if printf '%s\n' "$files" | grep -E '^(docs/process-design\.md|AGENTS\.md|CLAUDE\.md)$' | stdin_grep -q .; then
    return 0
  fi
  return 1
}

# True when a green validate.sh of this branch already covers HEAD: the same commit,
# or a later commit that changes nothing the suite reads, and the tree is clean.
validated_head() {
  local head prev
  git diff --quiet && git diff --cached --quiet || return 1
  head="$(git rev-parse HEAD)"
  prev="$(last_validate_sha)" || return 1
  [ -n "$prev" ] || return 1
  [ "$prev" = "$head" ] && return 0
  suite_reads_diff "$prev" "$head" && return 1
  return 0
}

# The commit created after the green run (the spec removal) inherits it when the
# suite would read none of the new bytes. Records phase_validate on that HEAD.
inherit_validation() {
  local head prev
  git diff --quiet && git diff --cached --quiet || return 0
  head="$(git rev-parse HEAD)"
  prev="$(last_validate_sha)" || return 0
  [ -n "$prev" ] && [ "$prev" != "$head" ] || return 0
  suite_reads_diff "$prev" "$head" && return 0
  trace_event phase_validate sha="$head" inherited=1
  echo "skipped validate.sh: no-new-fact: nothing the suite reads ($(git rev-parse --short HEAD) since ${prev:0:12})"
}

# validate.sh once per HEAD: a second --prepare on the same commit (a retry after a
# failed push or PR edit) does not run the suite again; a green run is recorded.
# The long modes record their steps for the owner and the dashboard (process-design §6.4).
case "$mode" in
  prepare|check|merge) progress_start close-phase.sh "$issue"; trap 'progress_end $?' EXIT ;;
esac

run_validate() {
  if validated_head; then
    if [ "$(last_validate_sha)" = "$(git rev-parse HEAD)" ]; then
      echo "skipped validate.sh: HEAD $(git rev-parse --short HEAD) already validated green in this phase"
    else
      inherit_validation
    fi
    return 0
  fi
  local t0 secs sha
  sha="$(git rev-parse HEAD)"
  t0="$(date +%s)"
  "$HERE/validate.sh" || die "validate.sh failed"
  secs=$(( $(date +%s) - t0 ))
  [ "$(git rev-parse HEAD)" = "$sha" ] || return 0
  git diff --quiet && git diff --cached --quiet || return 0
  # validate.sh records a full green run itself; do not write the same SHA twice.
  [ "$(last_validate_sha)" = "$sha" ] && return 0
  trace_event phase_validate sha="$sha" secs="$secs"
}

# True when the trace holds a pre_review of this branch on exactly HEAD.
pre_reviewed_head() {
  local events
  events="$(events_file "$ROOT")" && [ -f "$events" ] || return 1
  jq -e -s --arg b "$branch" --arg s "$(git rev-parse HEAD)" \
    'any(.[]; .event == "pre_review" and .branch == $b and .sha == $s)' "$events" >/dev/null 2>&1
}

pre_review() {
  case "$verdict" in clean|findings) ;; *) die "--verdict must be clean or findings" 2 ;; esac
  git diff --quiet && git diff --cached --quiet || die "uncommitted changes: the pre-review reads the committed diff"
  trace_event pre_review sha="$(git rev-parse HEAD)" verdict="$verdict" round="${round:-1}"
  pre_reviewed_head || die "pre_review was not recorded in the trace"
  echo "recorded pre_review=$verdict on $(git rev-parse --short HEAD) (read back)"
}

# A gate-class path that origin/main changed after the base of this branch: the review would be of a
# tree that is not the one that merges, and the gate review would be asked twice. Dies with the paths.
stale_gate_base() {
  local base globs changed hit
  git fetch --quiet origin main 2>/dev/null || return 0
  base="$(git merge-base HEAD origin/main 2>/dev/null)" || return 0
  [ "$base" != "$(git rev-parse origin/main)" ] || return 0
  [ -f "$ROOT/.github/sensitive-paths" ] || return 0
  globs="$(mktemp)"
  cat "$ROOT/.github/sensitive-paths" >"$globs"
  changed="$(mktemp)"
  git diff --name-only --no-renames -z "$base" origin/main >"$changed" 2>/dev/null || true
  hit="$(SENSITIVE_CLASS=gate python3 "$HERE/lib/sensitive_paths.py" "$globs" <"$changed" || true)"
  rm -f "$globs" "$changed"
  [ -z "$hit" ] ||
    die "origin/main changed gate path(s) after the base of this branch ($(echo "$hit" | paste -sd, -)): rebase on origin/main (git rebase origin/main), run --prepare again, then ask for the review"
}

prepare() {
  pre_reviewed_head ||
    echo "warning: no pre_review of HEAD $(git rev-parse --short HEAD) in the trace: run the close-reviewer pre-review (issue and diff only) before --prepare"
  [ -n "$body_file" ] && [ -f "$body_file" ] || die "--body-file is required (fill .github/pull_request_template.md)"
  "$HERE/check-attribution.sh" --text-file "$body_file" >/dev/null || die "PR body has AI attribution"
  stale_gate_base
  progress_step "validate.sh"
  run_validate
  progress_step "check-docs.sh"
  "$HERE/check-docs.sh" || die "check-docs.sh failed"
  git fetch --quiet origin main
  git diff --quiet && git diff --cached --quiet || die "uncommitted changes: commit each step first"

  # Issues the PR closes (Closes/Fixes/Resolves #n); the first one serves as the phase issue.
  local closing
  closing="$(grep -oiE '(close[sd]?|fix(e[sd])?|resolve[sd]?) +#[0-9]+' "$body_file" | grep -oE '[0-9]+' | paste -sd, - || true)"
  [ -n "$issue" ] || issue="${closing%%,*}"
  local labels=""
  if [ -n "$issue" ]; then
    labels="$(gh issue view "$issue" --repo "$repo" --json labels --jq '.labels[].name' | grep -vxE 'approved|needs-context' || true)"
  fi

  # The spec's ok: the phase issue is approved and its spec declares the sensitive area.
  local spec_declared=""
  if [ -n "$issue" ] && echo "$(gh issue view "$issue" --repo "$repo" --json labels --jq '.labels[].name' 2>/dev/null || true)" | stdin_grep -qxF approved; then
    spec_declared="$(spec_declared_areas "$issue")"
  fi

  # Spec with no other open issue: leaves in a phase commit and its text goes into the body.
  remove_done_specs "$closing"
  inherit_validation
  body_file="$(body_with_pairs "$body_file")"
  body_file="$(body_with_spec "$body_file")"
  [ -n "$issue" ] || issue="$(issue_from_branch "$branch")"
  if [ -n "$issue" ] && issue_kept_open "$issue" "$ROOT"; then
    body_keep_open "$body_file" "$issue" "$ROOT"
  fi

  # One push per round = one CI run. Generated files are not the phase's: gen-docs.sh.
  local n remote_sha=""
  n="$(pr_number)"
  [ -n "$n" ] || [ -n "$title" ] || die "--title is required to open the PR"
  # A prepare that only edits the PR sends nothing: recording phase_push again
  # would demand a new review of the same SHA.
  if git rev-parse --verify --quiet "refs/remotes/origin/${branch}" >/dev/null; then
    remote_sha="$(git rev-parse "refs/remotes/origin/${branch}")"
  fi
  if [ "$remote_sha" = "$(git rev-parse HEAD)" ]; then
    echo "no-new-fact: already on origin: $branch was not pushed again"
  else
    progress_step "pushing the branch"
    git push --quiet -u origin "$branch"
    trace_event phase_push sha="$(git rev-parse HEAD)"
    echo "pushed $branch (one push for this round)"
  fi
  if [ -n "$spec_declared" ]; then
    trace_event spec_ok issue="$issue" sha="$(git rev-parse HEAD)" declared="$spec_declared"
    echo "spec ok recorded for $(git rev-parse --short HEAD): declared $spec_declared"
  fi

  progress_step "opening or updating the PR"
  if [ -z "$n" ]; then
    gh pr create --repo "$repo" --base main --head "$branch" --title "$title" --body-file "$body_file" >/dev/null ||
      die "gh pr create failed (body $(wc -c <"$body_file") characters; the GitHub limit is 65536): read the gh error above"
    n="$(pr_number)"
    echo "opened PR #$n"
  else
    # Edit only if the title or body changed (editing does not trigger CI, but avoids noise).
    local current want_title
    current="$(gh pr view "$n" --repo "$repo" --json title,body)"
    want_title="${title:-$(echo "$current" | jq -r .title)}"
    if [ "$(echo "$current" | jq -r .title)" != "$want_title" ] ||
       [ "$(echo "$current" | jq -r .body)" != "$(cat "$body_file")" ]; then
      gh pr edit "$n" --repo "$repo" --title "$want_title" --body-file "$body_file" >/dev/null
      echo "updated PR #$n (title or body changed)"
    else
      echo "PR #$n title and body unchanged"
    fi
  fi

  # The issue labels go to the PR (type:* feeds the changelog).
  if [ -n "$labels" ]; then
    local args
    args=(pr edit "$n" --repo "$repo")
    while IFS= read -r l; do args+=(--add-label "$l"); done <<<"$labels"
    gh "${args[@]}" >/dev/null
    echo "copied labels from #$issue: $(echo "$labels" | paste -sd, -)"
  fi
  echo "PR #$n ready for the independent review at $(git rev-parse --short HEAD)"
  echo "next: run the close-reviewer agent, then close-phase.sh --publish-review <file> --verdict success|failure"
}

# Deletes each spec that cites the phase issue and no other open issue (the
# issues this PR closes do not count). The spec leaves by the issue it cites,
# never by its file name.
remove_done_specs() { # remove_done_specs <issues the PR closes, comma-separated>
  local specs open f others gone=""
  [ -n "$issue" ] || return 0
  specs="$(specs_citing "$issue" "$ROOT" | while read -r f; do git ls-files -- "$f"; done)"
  [ -n "$specs" ] || return 0
  open="$(gh issue list --repo "$repo" --state open --limit 1000 --json number --jq '.[].number')" ||
    die "open issues not read back: the spec of #$issue stays"
  open="$(printf '%s\n' "$open" | grep -vxE "$(printf '%s' "$issue${1:+,$1}" | tr ',' '|')" || true)"
  for f in $specs; do
    others="$(spec_open_issues "$f" "$open" | sed 's/^/#/' | paste -sd' ' -)"
    if [ -n "$others" ]; then
      echo "kept $f: it still cites open issue(s) $others"
    else
      gone="$gone $f"
    fi
  done
  [ -n "$gone" ] || return 0
  # shellcheck disable=SC2086  # names under docs/specs/ have no spaces
  git rm --quiet -- $gone
  # shellcheck disable=SC2086
  git commit --quiet -m "docs(specs): remove the spec whose last open issue is #$issue" -- $gone
  echo "removed$gone (no other open issue cited)"
}

# PR body with the "## Modelo e esforço" section written from the trace (requested x
# used, .method/scripts/trace-view.py --pairs): whatever the body had there is replaced; a body
# without the section gets it at the end. Prints the file to use.
body_with_pairs() { # body_with_pairs <body file>
  local out table
  [ -n "$issue" ] || { echo "$1"; return 0; }
  table="$(mktemp)" out="$(mktemp)"
  "$HERE/trace-view.py" --events "$(events_file)" --pairs "$issue" >"$table" 2>/dev/null ||
    "$HERE/trace-view.py" --events /dev/null --pairs "$issue" >"$table"
  awk -v table="$table" '
    function put(  l) { print "## Modelo e esforço\n"; while ((getline l < table) > 0) print l; print ""; done = 1 }
    /^## / { skip = 0 }
    /^## Modelo e esforço[[:space:]]*$/ { put(); skip = 1; next }
    !skip { print }
    END { if (!done) { print ""; put() } }' "$1" >"$out"
  rm -f "$table"
  echo "$out"
}

# PR body + the text of the specs of the phase, each in a <details>: the specs that
# cite the phase issue, whether this branch deleted them or they stay for another
# open issue. A spec the branch deleted that does not cite the issue is not the
# phase's and stays out. Prints the file to use.
body_with_spec() { # body_with_spec <body file>
  local out c f text
  out="$(mktemp)" text="$(mktemp)"
  cat "$1" >"$out"
  for c in $(git log --diff-filter=D --format=%H origin/main..HEAD -- 'docs/specs/*.md'); do
    for f in $(git show --diff-filter=D --name-only --format= "$c" -- 'docs/specs/*.md'); do
      git show "$c^:$f" >"$text"
      [ -z "$issue" ] || spec_cites "$text" "$issue" || continue
      spec_details "$out" "$f" "$text" "$c^"
    done
  done
  if [ -n "$issue" ]; then
    for f in $(specs_citing "$issue" "$ROOT"); do
      [ -n "$(git ls-files -- "$f")" ] || continue
      spec_details "$out" "$f" "$ROOT/$f" "$(git rev-parse HEAD)"
    done
  fi
  rm -f "$text"
  # No spec of the phase: the original file goes on.
  if cmp -s "$1" "$out"; then rm -f "$out"; echo "$1"; else echo "$out"; fi
}
# The body limit of GitHub is 65536 characters; the text of a spec goes in only while
# the body stays under CLOSE_PHASE_BODY_LIMIT, then the spec is a link to its blob.
spec_details() { # spec_details <body file> <spec path> <file with the spec text> <commit with the blob>
  local limit="${CLOSE_PHASE_BODY_LIMIT:-60000}" size
  grep -qF "<summary>Spec ($2)</summary>" "$1" && return 0
  size="$(( $(wc -c <"$1") + $(wc -c <"$3") ))"
  if [ "$size" -gt "$limit" ]; then
    printf '\n<details>\n<summary>Spec (%s)</summary>\n\nText left out (body limit): https://github.com/%s/blob/%s/%s\n\n</details>\n' "$2" "$repo" "$4" "$2" >>"$1"
    return 0
  fi
  printf '\n<details>\n<summary>Spec (%s)</summary>\n\n%s\n\n</details>\n' "$2" "$(cat "$3")" >>"$1"
}

# Stuck PR: dirty (conflict) or CI missing on HEAD. Never force-pushes.
# A conflicting PR is redone by redo-phase.sh, the one owner of that path.
check_pr() { # check_pr [PR number]
  local n info m s sha reads=0 tries="${CLOSE_PHASE_MERGEABLE_TRIES:-5}"
  n="${1:-$(pr_number)}"; [ -n "$n" ] || die "no open PR for $branch"
  progress_step "reading the PR state"
  while :; do
    reads=$((reads + 1))
    info="$(gh pr view "$n" --repo "$repo" --json mergeable,mergeStateStatus,headRefOid)"
    m="$(echo "$info" | jq -r '.mergeable // "UNKNOWN"')"
    s="$(echo "$info" | jq -r '.mergeStateStatus // "UNKNOWN"')"
    sha="$(echo "$info" | jq -r '.headRefOid // empty')"
    [ "$m" = UNKNOWN ] || break
    [ "$reads" -lt "$tries" ] || die "PR #$n mergeable is still UNKNOWN after $reads reads: check the PR on GitHub" 8
    sleep "${CLOSE_PHASE_MERGEABLE_PAUSE:-10}"
  done
  local why=""
  if [ "$m" = CONFLICTING ] || [ "$s" = DIRTY ]; then
    why="conflicts with main (mergeable=$m, mergeStateStatus=$s)"
  elif git fetch --quiet origin main 2>/dev/null && [ -n "$(git cherry origin/main HEAD 2>/dev/null | grep '^-' || true)" ]; then
    # A commit of the branch that main has under another SHA (another phase carried it):
    # GitHub's rebase merge refuses with "Base branch was modified" until the PR is redone.
    why="has a commit that origin/main already has under another SHA"
  fi
  if [ -n "$why" ]; then
    echo "PR #$n $why: redoing the phase with redo-phase.sh"
    local redo=0
    "$HERE/redo-phase.sh" || redo=$?
    [ "$redo" = 0 ] || exit "$redo"
    [ "$mode" != merge ] || { echo "not merged: run the independent review on the new PR, publish it and run --merge again"; exit 6; }
    exit 0
  fi
  # CI on the HEAD SHA; a check on an older SHA does not count.
  local count waited=0 timeout="${CLOSE_PHASE_CI_TIMEOUT:-180}" poll="${CLOSE_PHASE_CI_POLL:-15}"
  progress_step "waiting for CI on HEAD" 0 "$timeout"
  while :; do
    count="$(gh api "repos/$repo/commits/$sha/check-runs" --jq '.total_count')"
    [ "${count:-0}" -gt 0 ] && break
    if [ "$waited" -ge "$timeout" ]; then
      echo "CI missing: no check on HEAD ${sha:0:12} after ${timeout}s (PR #$n, mergeStateStatus=$s)"
      echo "investigate: workflow skipped, refs/pull/$n/merge missing or runner offline; report it in the status block"
      exit 7
    fi
    sleep "$poll"; waited=$((waited + poll))
    progress_step "waiting for CI on HEAD" "$waited" "$timeout"
    [ "$poll" -gt 0 ] || waited="$timeout"
  done
  echo "ok: PR #$n mergeable ($s), $count check(s) on HEAD ${sha:0:12}"
}

# Pair of the close-reviewer from the trace (model and effort of its last stop).
# Empty when the trace does not hold it: the script must not invent one.
reviewer_trace_pair() { # reviewer_trace_pair <events file>
  [ -f "$1" ] || return 0
  jq -rs '
    [ .[] | select(type == "object" and .event == "SubagentStop" and .agent_type == "close-reviewer" and (.model // "") != "") ] | last
    | if . == null then "" else "Modelo do revisor: \(.model) · esforço: \(.effort // "?")" end
  ' "$1" 2>/dev/null || true
}

# Path of the body to post. A self-reported "Modelo do revisor" line is replaced
# by the trace pair, or dropped when the trace has none. A review without that
# line is posted unchanged.
reviewer_body() { # reviewer_body <review file> <events file>
  local line posted
  line="$(reviewer_trace_pair "$2")"
  if [ -z "$line" ] && ! grep -q '^Modelo do revisor:' "$1"; then
    printf '%s\n' "$1"
    return 0
  fi
  posted="$(mktemp)"
  python3 - "$1" "$posted" "$line" <<'PY'
import sys
src, dst, line = sys.argv[1:]
text = open(src, encoding="utf-8").read().splitlines(True)
out, seen = [], False
for row in text:
    if row.startswith("Modelo do revisor:"):
        if line and not seen:
            out.append(line + "\n")
            seen = True
        continue
    out.append(row)
if line and not seen:
    if out and not out[-1].endswith("\n"):
        out[-1] += "\n"
    out.append(line + "\n")
open(dst, "w", encoding="utf-8").write("".join(out))
PY
  printf '%s\n' "$posted"
}

# The verdict of a saved close-reviewer opinion, read from its "Veredito:" line.
opinion_verdict() { # opinion_verdict <saved opinion>
  local line v
  line="$(grep -m1 -E '^Veredito:' "$1" || true)"
  [ -n "$line" ] || die "no Veredito line in the saved opinion $1: save the whole close-reviewer output, which has the line 'Veredito: aprovado | mudanças pedidas'"
  v="$(printf '%s' "${line#Veredito:}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr 'A-Z' 'a-z')"
  case "$v" in
    aprovado) echo success ;;
    "mudanças pedidas") echo failure ;;
    *) die "the Veredito line of $1 is neither 'aprovado' nor 'mudanças pedidas': $line: run the close-reviewer again; never edit the opinion" ;;
  esac
}

# Reads the verdict of the saved opinion, refuses a --verdict that differs and records
# it in the .verdict file next to it (the agent writes only the .md).
save_opinion_verdict() { # save_opinion_verdict <saved .md> <.verdict file> [<given verdict>]
  local got
  got="$(opinion_verdict "$1")" || exit $?
  [ -z "${3:-}" ] || [ "$3" = "$got" ] || die "review --verdict $3 does not match the Veredito of the saved opinion ($got)"
  printf '%s\n' "$got" >"$2"
  printf '%s' "$got"
}

# An opinion saved after the close-reviewer stopped must be its output as the trace hook hashed it:
# a text edited after it was saved is refused. A trace without the hash (an older hook) is not checked.
require_unedited_opinion() { # require_unedited_opinion <saved .md> <events file>
  local want got agent="" sid="${CLAUDE_CODE_SESSION_ID:-}"
  [ -f "$2" ] || return 0
  # The stop of this opinion's own reviewer: its agent id (written by --save-review next to the
  # opinion) or, without it, the phase session; the last stop of the shared trace is another phase's.
  [ ! -f "${1%.md}.agent" ] || agent="$(tr -d '[:space:]' <"${1%.md}.agent")"
  local sel='[.[] | select(type == "object" and .event == "SubagentStop" and .agent_type == "close-reviewer")]'
  if [ -n "$agent" ]; then
    # An agent id with no stop in the trace is refused: a forged or stale .agent file must not skip the check.
    want="$(jq -rs --arg a "$agent" "$sel | map(select(.agent_id == \$a)) | if length == 0 then \"missing\" else last | .output_sha // \"\" end" "$2" 2>/dev/null || true)"
    [ "$want" != missing ] || die "the trace has no close-reviewer stop for agent $agent of the saved opinion $1: run the close-reviewer again; never edit the opinion"
  else
    # Own session's stops; with none of them, the last stop of the trace (the former behavior).
    want="$(jq -rs --arg s "$sid" "$sel | (if \$s == \"\" then . else (map(select(.session_id == \$s)) as \$m | if (\$m | length) == 0 then . else \$m end) end) | last | .output_sha // \"\"" "$2" 2>/dev/null || true)"
  fi
  [ -n "$want" ] || return 0
  got="$(opinion_sha <"$1")"
  [ "$got" = "$want" ] ||
    die "the saved opinion $1 does not match the close-reviewer output recorded in the trace: run the close-reviewer again; never edit the opinion"
}

# Where the phase session saved the close-reviewer output <name> (.md): the .process/ of the main
# checkout (where the trace is) or the one of this phase worktree, whichever holds the file; with
# neither, the main one (the path the refusal names).
opinion_dir() { # opinion_dir <name without extension>
  local main
  main="$(dirname "$(phase_trace_file "$ROOT" 2>/dev/null || echo "$ROOT/.process/x")")"
  if [ ! -f "$main/$1.md" ] && [ -f "$ROOT/.process/$1.md" ]; then
    echo "$ROOT/.process"
  else
    echo "$main"
  fi
}

missing_opinion_msg() { # missing_opinion_msg <sha> <path>
  echo "no saved reviewer output for ${1:0:12}: the phase session writes the whole close-reviewer output, literally and unchanged, to $2 (step 5 of the close-phase skill); save it with close-phase.sh --save-review <agentId>, and the verdict is read from its Veredito line"
}

# Saves the close-reviewer opinion of subagent <agent id> from its transcript, after checking its hash
# against the output_sha the trace hook recorded when that agent stopped.
save_review() {
  local events want got tr text prefix=reviewer sha dir out
  [ "$gate_review" = 0 ] || prefix=reviewer-gate
  events="$(phase_trace_file "$ROOT")" || die "cannot locate the trace: save refused"
  [ -f "$events" ] || die "no trace at $events: save refused"
  want="$(jq -rs --arg a "$agent_id" '[.[] | select(type == "object" and .event == "SubagentStop" and .agent_type == "close-reviewer" and .agent_id == $a)] | last | .output_sha // ""' "$events" 2>/dev/null || true)"
  [ -n "$want" ] || die "the trace has no close-reviewer stop with an output_sha for agent $agent_id: wait for it to finish, or run the close-reviewer again"
  tr=""
  if [ -n "${CLOSE_PHASE_SUBAGENTS_ROOT:-}" ]; then
    set -- "$CLOSE_PHASE_SUBAGENTS_ROOT"/*/subagents/agent-"$agent_id".jsonl
  else
    set -- "$HOME"/.claude/projects/*/*/subagents/agent-"$agent_id".jsonl
  fi
  [ ! -f "$1" ] || tr="$1"
  [ -n "$tr" ] || die "no transcript subagents/agent-$agent_id.jsonl found"
  text="$(opinion_from_transcript "$tr")"
  [ -n "$text" ] || die "the transcript of agent $agent_id has no text with a Veredito line"
  got="$(printf '%s' "$text" | opinion_sha)"
  [ "$got" = "$want" ] || die "the opinion in the transcript of agent $agent_id does not match the output_sha recorded in the trace: run the close-reviewer again; never edit the opinion"
  sha="$(git rev-parse HEAD)"
  dir="$(dirname "$events")"
  out="$dir/$prefix-$sha.md"
  mkdir -p "$dir"
  printf '%s\n' "$text" >"$out"
  printf '%s\n' "$agent_id" >"${out%.md}.agent"
  echo "saved the opinion of agent $agent_id to $out"
}

publish_review() {
  [ -f "$review_file" ] || die "review file not found: $review_file"
  case "$verdict" in ''|success|failure) ;; *) die "--verdict must be success or failure" 2 ;; esac
  "$HERE/check-attribution.sh" --text-file "$review_file" >/dev/null || die "review has AI attribution"
  local n sha events saved savedv got prefix=reviewer
  [ "$gate_review" = 0 ] || prefix=reviewer-gate
  n="$(pr_number)"; [ -n "$n" ] || die "no open PR for $branch"
  sha="$(gh pr view "$n" --repo "$repo" --json headRefOid --jq .headRefOid)"
  [ "$sha" = "$(git rev-parse HEAD)" ] || die "local HEAD differs from PR head $sha: push or pull first"
  review_after_push "$sha"
  events="$(phase_trace_file "$ROOT")" || die "cannot locate the trace: review refused"
  saved="$(opinion_dir "$prefix-$sha")/$prefix-$sha.md"
  savedv="$(dirname "$saved")/$prefix-$sha.verdict"
  [ -f "$saved" ] || die "$(missing_opinion_msg "$sha" "$saved")"
  cmp -s "$saved" "$review_file" || die "review file differs from the saved close-reviewer output"
  require_unedited_opinion "$saved" "$events"
  got="$(save_opinion_verdict "$saved" "$savedv" "$verdict")" || exit $?
  verdict="$got"
  local body
  body="$(reviewer_body "$review_file" "$events")"
  gh_role pr comment "$n" --repo "$repo" --body-file "$body" >/dev/null
  if [ "$gate_review" = 1 ]; then
    trace_event gate_review pr="$n" round="${round:-1}" verdict="$verdict" sha="$sha"
    echo "published the gate review=$verdict on ${sha:0:12} (PR #$n)"
    return 0
  fi
  local desc="Revisão independente aprovada"
  [ "$verdict" = success ] || desc="Revisão independente pediu mudanças"
  gh api -X POST "repos/$repo/statuses/$sha" -f state="$verdict" -f context=review/independent \
    -f description="$desc" >/dev/null
  trace_event review_round pr="$n" round="$round" verdict="$verdict" sha="$sha"
  echo "published review/independent=$verdict on ${sha:0:12} (PR #$n)"
}

# True when this branch's last phase_push is <sha> and a clean pre_review of that
# SHA is already in the trace. Used only when CLAUDE_CODE_SESSION_ID is unset.
clean_prereview_of_head() { # clean_prereview_of_head <events file> <sha>
  jq -e -rs --arg b "$branch" --arg sha "$2" '
    [ .[] | select(type == "object") ] as $e
    | ([$e[] | select(.event == "phase_push" and .branch == $b)] | last) as $p
    | $p != null and $p.sha == $sha
      and (([$e[] | select(.event == "pre_review" and .sha == $sha and .verdict == "clean")] | length) > 0)
  ' "$1" >/dev/null 2>&1
}

# An opinion is published only when a reviewer round started after the last push of
# the branch: in the trace of the main checkout, the last phase_push of the branch is
# on the PR head SHA and a SubagentStart of close-reviewer of this session follows it.
# With no session id, the same push plus a clean pre_review of that SHA is enough.
# A set session id with no harness proof is still refused.
review_after_push() { # review_after_push <PR head SHA> [what is refused]
  local events sid="${CLAUDE_CODE_SESSION_ID:-}" why what="${2:-review refused}"
  events="$(phase_trace_file "$ROOT")" || die "cannot locate the trace: $what"
  [ -f "$events" ] || die "$what: no trace at $events: push with --prepare and run the close-reviewer agent first"
  if [ -z "$sid" ]; then
    clean_prereview_of_head "$events" "$1" || die "$what: no session id (CLAUDE_CODE_SESSION_ID): the phase session publishes the review and merges"
    return 0
  fi
  why="$(jq -rs --arg b "$branch" --arg s "$sid" --arg sha "$1" '
      [to_entries[] | select(.value | type == "object")] as $e
      | ([$e[] | select(.value.event == "phase_push" and .value.branch == $b)] | last) as $p
      | if $p == null then "no phase_push of \($b) in the trace: push with close-phase.sh --prepare"
        elif $p.value.sha != $sha then "the last push recorded (\($p.value.sha[0:12])) is not the PR head (\($sha[0:12])): push with close-phase.sh --prepare"
        elif ([$e[] | select(.key > $p.key and .value.event == "SubagentStart" and .value.agent_type == "close-reviewer" and .value.session_id == $s)] | length) == 0
          then "no close-reviewer round after the last push (\($sha[0:12])): run the close-reviewer agent on this HEAD and publish its opinion"
        else "" end' "$events" 2>/dev/null)" ||
    die "a line of $events is not JSON: $what"
  [ -z "$why" ] || die "$what: $why"
}

# Child-session gate: the phase runs in a child session (phase_session of the phase,
# from a session other than the one that opened it, in the trace).
# Fails closed. The phase is the one of the branch; the trace is the one of the main
# checkout (PROCESS_EVENTS_FILE never redirects it) and every line of it must be JSON.
# It must hold a phase_opened of the issue, and the session that merges
# (CLAUDE_CODE_SESSION_ID) must be another one, with a phase_session of the issue
# (check-env.sh) and an event recorded by the harness hooks (trace-event.sh), which
# a session id set by hand does not have. With no session id, the last phase_push
# of this branch must be HEAD and a clean pre_review of that SHA must already
# be in the trace; a set id with no harness proof is still refused.
phase_gate() {
  local events sid="${CLAUDE_CODE_SESSION_ID:-}" why
  [ -n "$branch_issue" ] || die "cannot tell the phase issue from branch $branch: the phase branch is the one phase-start.sh creates"
  events="$(phase_trace_file "$ROOT")" || die "cannot locate the trace: merge blocked"
  [ -f "$events" ] || die "no trace at $events: phase #$branch_issue has no phase_opened; open the phase with .method/scripts/phase-start.sh"
  if [ -z "$sid" ]; then
    clean_prereview_of_head "$events" "$(git rev-parse HEAD)" || die "no session id (CLAUDE_CODE_SESSION_ID): the child session of phase #$branch_issue runs --merge"
    return 0
  fi
  why="$(jq -rs --arg i "$branch_issue" --arg s "$sid" '
      def of($e): [.[] | select(type == "object" and .event == $e and (.issue | tostring) == $i) | (.session_id // "")];
      if (of("phase_opened") | length) == 0 then "no phase_opened of the issue in the trace: the phase opens only through .method/scripts/phase-start.sh"
      elif (of("phase_opened") | index($s)) then "this session opened the phase: forward the request to the child session and stop"
      elif (of("phase_session") | index($s) | not) then "this session has no phase_session of the issue: run .method/scripts/check-env.sh in the phase worktree, in the child session"
      elif ([.[] | select(type == "object" and .session_id == $s and (.event | IN("SessionStart", "SessionEnd", "Stop", "SubagentStart", "SubagentStop", "PreToolUse", "PostToolUse")))] | length) == 0
        then "no hook event of this session in the trace: the session id was not recorded by the harness"
      else "" end' "$events" 2>/dev/null)" ||
    die "a line of $events is not JSON: merge blocked"
  [ -z "$why" ] || die "phase #$branch_issue: $why"
}

# Unprotected mode: GitHub does not require the checks, so the merge reads them here.
# CI must be a completed check run with conclusion success on HEAD and
# review/independent a success status on HEAD; anything else exits 11.
unprotected_gate() { # unprotected_gate <sha>
  local sha="$1" ci rv
  ci="$(gh api "repos/$repo/commits/$sha/check-runs" --jq '[.check_runs[] | select(.name == "CI")] | sort_by(.started_at) | last | if . == null then "missing" elif .status != "completed" then .status else .conclusion end')" ||
    die "cannot read the check runs of ${sha:0:12}: merge blocked" 11
  [ "$ci" = success ] || die "unprotected mode: CI is $ci on ${sha:0:12}: no merge until it is success" 11
  rv="$(gh api "repos/$repo/commits/$sha/status" --jq '[.statuses[] | select(.context == "review/independent")][0].state // "missing"')" ||
    die "cannot read the statuses of ${sha:0:12}: merge blocked" 11
  [ "$rv" = success ] || die "unprotected mode: review/independent is $rv on ${sha:0:12}: no merge until it is success" 11
  echo "unprotected mode: CI and review/independent are success on ${sha:0:12} (read through the API)"
}

# Notes to the phase left unanswered on its issue (.method/scripts/lib/notes.sh). A read
# that fails is an error (fails closed).
pending_notes() {
  local notes
  notes="$(phase_pending_notes "$issue" "$repo")" ||
    die "cannot read the comments of issue #$issue: merge blocked"
  printf '%s' "$notes"
}

refuse_pending_notes() {
  local notes
  notes="$(pending_notes)"
  if [ -n "$notes" ]; then
    echo "refused: issue #$issue has a note to phase #$issue with no answer:"
    echo "$notes"
    echo "read it, follow it, and answer with a comment headed by .method/scripts/lib/author.sh (De: fase #$issue); then run --merge again"
    exit 12
  fi
}

# Creates a label the repository lacks (a repo updated from before the class) from its row in
# .github/labels.tsv of the PR HEAD, so putting it on the PR does not stop the merge.
ensure_repo_label() { # ensure_repo_label <label> <sha>
  local name="$1" sha="$2" row color desc
  gh label list --repo "$repo" --limit 500 --json name --jq '.[].name' 2>/dev/null | stdin_grep -qxF "$name" && return 0
  row="$(git show "$sha:.github/labels.tsv" 2>/dev/null | awk -F '\t' -v n="$name" '$1 == n { print; exit }')"
  [ -n "$row" ] || row="$(awk -F '\t' -v n="$name" '$1 == n { print; exit }' "$ROOT/.github/labels.tsv" 2>/dev/null)"
  [ -n "$row" ] || return 0
  color="$(printf '%s' "$row" | cut -f2)"; desc="$(printf '%s' "$row" | cut -f3)"
  gh label create "$name" --repo "$repo" --color "$color" --description "$desc" >/dev/null 2>&1 || true
}

# A PR that touches the gate needs a published second review (--publish-review --gate)
# of this HEAD with verdict success: the saved opinion and its gate_review event.
gate_review_required() { # gate_review_required <pr> <sha> <labels> <gate paths>
  local n="$1" sha="$2" labels="$3" paths="$4" events saved ok=0 got=""
  if ! echo "$labels" | stdin_grep -qxF needs-gate-review; then
    ensure_repo_label needs-gate-review "$sha"
    "$HERE/label-issue.sh" "$n" --add needs-gate-review >/dev/null ||
      die "PR #$n needs a gate review, but needs-gate-review could not be put on it"
    echo "needs-gate-review is now on PR #$n (read back)"
  fi
  events="$(phase_trace_file "$ROOT" 2>/dev/null || true)"
  if [ -n "$events" ] && [ -f "$events" ]; then
    saved="$(opinion_dir "reviewer-gate-$sha")/reviewer-gate-$sha.md"
    if [ -f "$saved" ]; then
      got="$(opinion_verdict "$saved" 2>/dev/null || true)"
      if [ "$got" = success ] && jq -e -s --arg sha "$sha" \
        '[.[] | select(type == "object" and .event == "gate_review" and .sha == $sha and .verdict == "success")] | length > 0' \
        "$events" >/dev/null 2>&1; then ok=1; fi
    fi
  fi
  [ "$ok" = 1 ] && return 0
  echo "refused: PR #$n touches the gate and needs a second review (needs-gate-review)${paths:+: $(echo "$paths" | paste -sd, -)}"
  echo "run the close-reviewer agent on HEAD $sha with the question 'does this PR weaken the gate?', save it with --save-review <agentId> --gate (.process/reviewer-gate-$sha.md), publish it with --publish-review <file> --gate, then rerun --merge; the owner is not asked"
  exit 5
}

# The sensitive area the spec of the phase declares: the backticked words of the line
# "Área sensível:" in its "## Fase #<n>" section, comma-separated (empty: none declared).
# Read from origin/main, the text the owner approved: a spec only on the branch, or an
# edit of that line made on the branch, declares nothing.
spec_declared_areas() { # spec_declared_areas <issue>
  local f
  git fetch --quiet origin main 2>/dev/null || true
  for f in $(specs_citing "$1" "$ROOT"); do
    git cat-file -e "origin/main:$f" 2>/dev/null || continue
    git show "origin/main:$f" |
      awk -v h="## Fase #$1 " 'index($0, h) == 1 {on=1; next} /^## / {on=0} on && /^Área sensível:/ {print}' |
      grep -o '`[^`]*`' | tr -d '`' || true
  done | sort -u | paste -sd, -
}
# 0 when every reason to ask the owner is declared by the spec recorded (spec_ok) for this
# SHA (at least one path or area label must be there): each touched owner-ok path and each sensitive area label must be one of the declared
# words. A path or area the spec did not declare is not covered.
spec_ok_covers() { # spec_ok_covers <PR head SHA> <labels> <touched paths>
  local events declared a p w hit
  events="$(phase_trace_file "$ROOT" 2>/dev/null || true)"
  [ -n "$events" ] && [ -f "$events" ] || return 1
  declared="$(jq -rs --arg sha "$1" --arg b "$branch" \
    '[.[] | select(type == "object" and .event == "spec_ok" and .sha == $sha and .branch == $b)] | last | .declared // empty' \
    "$events" 2>/dev/null || true)"
  [ -n "$declared" ] || return 1
  # needs-owner-ok alone (no owner-ok path, no area label) is not something a spec declares.
  local any=0
  [ -z "$3" ] || any=1
  for a in $SENSITIVE_AREAS; do
    if echo "$2" | stdin_grep -qxF "$a"; then
      any=1
      printf ',%s,' "$declared" | grep -qF ",$a," || return 1
    fi
  done
  [ "$any" = 1 ] || return 1
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    hit=0
    for w in $(printf '%s' "$declared" | tr ',' ' '); do
      case "$p" in "$w"|*/"$w") hit=1 ;; esac
    done
    [ "$hit" = 1 ] || return 1
  done <<EOF
$3
EOF
  return 0
}

merge() {
  local n info labels sha state
  n="$(pr_number)"; [ -n "$n" ] || die "no open PR for $branch"
  refuse_pending_notes
  info="$(gh pr view "$n" --repo "$repo" --json labels,headRefOid,baseRefName)"
  labels="$(echo "$info" | jq -r '.labels[].name')"
  sha="$(echo "$info" | jq -r .headRefOid)"

  # Never merges on its own: owner label, sensitive area or sensitive path.
  local reasons=""
  echo "$labels" | stdin_grep -qxF needs-owner-ok && reasons="$reasons needs-owner-ok"
  for a in $SENSITIVE_AREAS; do
    echo "$labels" | stdin_grep -qxF "$a" && reasons="$reasons $a"
  done
  local base touched globs
  base="$(echo "$info" | jq -r .baseRefName)"
  git fetch --quiet origin "$base"
  # The list is the union of the base's and the PR's: a PR cannot take itself out of
  # the rule by dropping an entry, and an entry it adds already counts. Fails closed:
  # no readable list on the base, no merge.
  globs="$(mktemp)"
  git show "origin/$base:.github/sensitive-paths" >"$globs" 2>/dev/null ||
    { rm -f "$globs"; die "cannot read .github/sensitive-paths of origin/$base: merge blocked"; }
  # The class line before the PR's list keeps its globs owner-ok whatever the base ended with.
  [ ! -f "$ROOT/.github/sensitive-paths" ] || { echo; echo "# class: owner-ok"; cat "$ROOT/.github/sensitive-paths"; } >>"$globs"
  local diffed touched_gate
  diffed="$(mktemp)"
  git diff --name-only --no-renames -z "origin/$base...$sha" >"$diffed" 2>/dev/null || true
  touched="$(SENSITIVE_CLASS=owner-ok python3 "$HERE/lib/sensitive_paths.py" "$globs" <"$diffed" || true)"
  touched_gate="$(SENSITIVE_CLASS=gate python3 "$HERE/lib/sensitive_paths.py" "$globs" <"$diffed" || true)"
  rm -f "$globs" "$diffed"
  [ -z "$touched" ] || reasons="$reasons sensitive-paths($(echo "$touched" | paste -sd, -))"
  # The ok of the approved spec that declares these areas counts as the owner's ok for
  # this HEAD, with no choice question. Anything the spec did not declare still asks.
  if [ -n "$reasons" ] && spec_ok_covers "$sha" "$labels" "$touched"; then
    echo "owner's ok given by the approved spec (declared areas cover:$reasons)"
    gh_role pr comment "$n" --repo "$repo" --body "<!-- spec-ok sha:$sha -->
Ok do dono dado pela spec aprovada, que declara a área sensível, para:$reasons." >/dev/null
    reasons=""
  fi
  if [ -n "$reasons" ]; then
    # --owner-ok only counts with needs-owner-ok already on the PR: the label is the
    # public record that the PR waited for the owner. A PR without it gets the label
    # now (read back by label-issue.sh) and this run is refused, with or without the flag.
    local labeled=1
    if ! echo "$labels" | stdin_grep -qxF needs-owner-ok; then
      labeled=0
      "$HERE/label-issue.sh" "$n" --add needs-owner-ok >/dev/null ||
        die "PR #$n needs the owner's ok ($reasons ), but needs-owner-ok could not be put on it"
      echo "needs-owner-ok is now on PR #$n (read back)"
    fi
    if [ "$owner_ok" = 0 ] || [ "$labeled" = 0 ]; then
      echo "refused: PR #$n needs the owner's ok:$reasons"
      [ "$owner_ok" = 0 ] || echo "--owner-ok does not count: needs-owner-ok was not on PR #$n before this run"
      echo "ask the repo owner with a choice question that names this SHA, then rerun with --merge --owner-ok $sha"
      unread="$(opinion_dir "reviewer-$sha")/reviewer-$sha.md"
      if [ -f "$unread" ]; then
        awk '/^### Não lido/{p=1} p && /^### / && !/^### Não lido/{exit} p' "$unread"
      fi
      exit 5
    fi
    if [ "$owner_ok_sha" != "$sha" ]; then
      echo "refused: --owner-ok $owner_ok_sha does not match HEAD $sha"
      echo "ask the repo owner with a choice question that names this SHA, then rerun with --merge --owner-ok $sha"
      exit 5
    fi
    gh_role pr comment "$n" --repo "$repo" --body "<!-- owner-ok sha:$sha -->
Ok do dono do repo registrado (quadro de escolha) para:$reasons." >/dev/null
  fi

  # The gate class: no owner, but a second close-reviewer opinion on this HEAD.
  if [ -n "$touched_gate" ] || echo "$labels" | stdin_grep -qxF needs-gate-review; then
    gate_review_required "$n" "$sha" "$labels" "$touched_gate"
  fi

  state="$(gh api "repos/$repo/commits/$sha/status" --jq '[.statuses[] | select(.context == "review/independent")][0].state // "missing"')"
  [ "$state" = success ] || die "review/independent is $state on ${sha:0:12}: run the independent review first"

  phase_gate

  # A green status is not the proof: the trace must hold the reviewer's round of this
  # session after the push of this HEAD (a status posted by hand opens nothing).
  review_after_push "$sha" "merge blocked"

  # The gate is the protection of the base branch: without it GitHub merges anything.
  # Exception: the unprotected mode (PROCESS_BRANCH_MODE, a plan with no branch
  # protection): there the gate is read through the API, below.
  local required c
  if required="$(gh api "repos/$repo/branches/$base/protection" --jq '.required_status_checks | ([.checks[]?.context] + (.contexts // [])) | unique | .[]' 2>/dev/null)"; then
    for c in CI review/independent; do
      printf '%s\n' "$required" | stdin_grep -qxF "$c" ||
        die "the protection of $base does not require $c: no merge without the gate; fix: .method/scripts/setup-repo.sh --only protection"
    done
  else
    gh variable list --repo "$repo" --json name --jq '.[].name' 2>/dev/null | stdin_grep -qxF PROCESS_BRANCH_MODE ||
      die "$base is not protected, or its protection cannot be read: no merge without the gate; fix: .method/scripts/setup-repo.sh --only protection"
    unprotected_gate "$sha"
  fi

  # Conflict or CI missing on HEAD: exits before requesting the merge.
  check_pr "$n"

  # CI does not run on a PR edit: check the final body and the commits here.
  "$HERE/check-attribution.sh" --pr "$n" || die "PR #$n has AI attribution: fix the body or commits first"

  # A note posted while this run was waiting still holds the merge (FHDumont/ai-engineering-team-template#122).
  refuse_pending_notes

  if ! gh pr merge "$n" --repo "$repo" --auto --rebase --delete-branch >/dev/null 2>&1; then
    # Already clean (green checks): auto-merge does not turn on, so merge directly.
    gh pr merge "$n" --repo "$repo" --rebase --delete-branch >/dev/null
  fi
  echo "merge requested for PR #$n (rebase, auto)"
  echo "no deploy from the phase: the main session runs .method/scripts/deploy.sh after the last merge of the group"

  if [ "$wait" = 1 ]; then
    local tries=0
    progress_step "waiting for the merge" 0 120
    until [ "$(gh pr view "$n" --repo "$repo" --json state --jq .state)" = MERGED ]; do
      tries=$((tries + 1))
      [ "$tries" -le 120 ] || die "PR #$n not merged after 60 minutes"
      # CI or review/independent turned red on HEAD while waiting: leave at once (exit 13).
      # Running or green: keep waiting. The gate is not weakened: the merge still needs both green.
      local wci wci_state wci_url wrv
      wci="$(gh api "repos/$repo/commits/$sha/check-runs" --jq '[.check_runs[] | select(.name == "CI")] | sort_by(.started_at) | last | [(if . == null then "missing" elif .status != "completed" then .status else .conclusion end), (.html_url // "")] | @tsv' 2>/dev/null || true)"
      wci_state="${wci%%$'\t'*}"
      wci_url="${wci#*$'\t'}"
      wrv="$(gh api "repos/$repo/commits/$sha/status" --jq '[.statuses[] | select(.context == "review/independent")][0].state // "missing"' 2>/dev/null || true)"
      local bad=""
      case "$wci_state" in failure | cancelled) bad="CI is $wci_state" ;; esac
      case "$wrv" in failure | error) bad="${bad:+$bad; }review/independent is $wrv" ;; esac
      if [ -n "$bad" ]; then
        local wrun
        wrun="$(printf '%s' "$wci_url" | sed -n 's#.*/actions/runs/\([0-9][0-9]*\).*#\1#p')"
        echo "PR #$n: $bad on HEAD ${sha:0:12}${wci_url:+ (failed run: $wci_url)}; the merge will not happen until it is green"
        echo "next: fix it in a new commit, then --prepare and --merge again; if it is a flake: .method/scripts/rerun-ci.sh ${wrun:-<run-id>}, then --merge --wait again"
        echo "the owner's ok (--owner-ok) holds only for the old SHA ${sha:0:12}: a new commit needs a new ok"
        exit 13
      fi
      # A cancelled check (network failure in Checkout) never recovers by itself: leave at once.
      local cancelled run_id
      cancelled="$(gh api "repos/$repo/commits/$sha/check-runs" --jq '[.check_runs[] | select(.conclusion == "cancelled")][0].html_url // empty' 2>/dev/null || true)"
      if [ -n "$cancelled" ]; then
        run_id="$(printf '%s' "$cancelled" | sed -n 's#.*/actions/runs/\([0-9][0-9]*\).*#\1#p')"
        echo "PR #$n: a check on HEAD ${sha:0:12} was cancelled ($cancelled); it will not recover by itself"
        echo "rerun: .method/scripts/rerun-ci.sh ${run_id:-<run-id>}, then --merge --wait again"
        exit 1
      fi
      sleep "${CLOSE_PHASE_MERGE_POLL:-30}"
      progress_step "waiting for the merge" "$tries" 120
    done
    echo "PR #$n merged"
    cleanup
  elif [ "$(gh pr view "$n" --repo "$repo" --json state --jq .state)" = MERGED ]; then
    echo "PR #$n merged"
  else
    echo "PR #$n is not merged yet (use --wait)"
  fi
}

# Last words of the phase: what the owner archives (never deletes) in the app.
cleanup_message() { # cleanup_message <main checkout> <phase worktree>
  [ "$2" != "$1" ] || return 0
  echo "Archive this session in the Claude app (menu ... -> Archive) after the owner agreed once, with the spec or in one card at the end of the group. The manager then calls set_remote_control and archive_session; if the app returns a field, repeat once with that field, for both. Do not delete it: the history is gone for good. Closing the tab is not enough."
  local stale
  stale="$("$1/.method/scripts/sessions.sh" --stale 2>/dev/null || true)"
  [ -z "$stale" ] || printf 'Other sessions of this repository, not archived and idle (archive them too):\n%s\n' "$stale"
}

cleanup() {
  local main_root here n board=0
  main_root="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
  here="$ROOT"
  if [ -n "$branch" ] && ! is_main_branch "$branch"; then
    n="$(gh pr list --repo "$repo" --head "$branch" --state merged --json number --jq '.[0].number // empty')"
    [ -n "$n" ] || die "PR for $branch is not merged yet"
    trace_event phase_closed pr="$n"
    # shellcheck source=.method/scripts/lib/project.sh
    source "$HERE/lib/project.sh"
    # A board write that fails does not stop the cleanup: it fails the script at the end.
    project_set_done_if_closed "$(issue_from_branch "$branch")" || board=1
    # Filter of the "Fase atual" view: cleared, or left with only the group of the phases still active.
    project_refresh_phase_filter "$main_root" "" "$(issue_from_branch "$branch")" || board=1
    registry_drop "$main_root" "$(issue_from_branch "$branch")"
  else
    registry_drop "$main_root"
  fi
  git -C "$main_root" switch --quiet main
  # An untracked file of the main checkout equal to the one main now brings (the
  # spec the planning wrote there and the phase committed) would abort the
  # fast-forward: the copy leaves, the content comes back with the pull.
  git -C "$main_root" fetch --quiet origin main
  local f
  git -C "$main_root" diff --name-only --diff-filter=A HEAD FETCH_HEAD | while IFS= read -r f; do
    [ -f "$main_root/$f" ] && [ -z "$(git -C "$main_root" ls-files -- "$f")" ] || continue
    same=0
    [ "$(git -C "$main_root" hash-object "$main_root/$f")" = "$(git -C "$main_root" rev-parse "FETCH_HEAD:$f")" ] && same=1
    # A loose spec may be the copy from before an approved amendment. The merged
    # file wins so the fast-forward is not blocked. Any other different file stays.
    case "$f" in
      docs/specs/*) ;;
      *) [ "$same" = 1 ] || continue ;;
    esac
    rm -f "$main_root/$f"
    echo "removed the untracked copy of $f from the main checkout (main brings the same file)"
  done
  git -C "$main_root" pull --quiet --ff-only origin main
  # The phase slot ends with the phase. Recording it here, before the worktree
  # goes away, keeps the duration at the real end and out of the next opening.
  slots_end_phase "$here"
  if [ "$here" != "$main_root" ]; then
    # shellcheck source=.method/scripts/lib/procs.sh
    source "$HERE/lib/procs.sh"
    procs_cleanup_worktree "$here" "$(issue_from_branch "$branch")" "$(events_file "$here" 2>/dev/null || true)"
    git -C "$main_root" worktree remove --force "$here"
    echo "removed worktree $here"
  fi
  if [ -n "$branch" ] && ! is_main_branch "$branch"; then
    git -C "$main_root" branch -D "$branch" >/dev/null 2>&1 || true
    echo "deleted local branch $branch"
    delete_remote_branch "$main_root"
  fi
  git -C "$main_root" fetch --quiet --prune origin
  git -C "$main_root" branch
  cleanup_message "$main_root" "$here"
  [ "$board" = 0 ] || die "the phase is closed and cleaned up, but the board was not updated (cause and fix above)"
}

# What --abort would lose, one block per kind; empty when nothing is lost.
abort_losses() {
  local changed untracked unpushed orphan="" status
  status="$(git status --porcelain --untracked-files=all)"
  changed="$(printf '%s\n' "$status" | grep -v '^??' || true)"
  untracked="$(printf '%s\n' "$status" | sed -n 's/^?? //p')"
  git fetch --quiet --prune origin
  unpushed="$(git log --oneline HEAD --not --remotes=origin)"
  # Pushed commits survive the remote branch only inside a PR (refs/pull/<n>/head):
  # a PR of the branch, in any state, whose head is the head of the remote branch.
  local pushed
  pushed="$(git rev-parse --quiet --verify "refs/remotes/origin/$branch" || true)"
  if [ -n "$pushed" ] &&
     [ -z "$(gh pr list --repo "$repo" --head "$branch" --state all --json number,headRefOid \
       --jq "[.[] | select(.headRefOid == \"$pushed\")][0].number // empty")" ]; then
    orphan="$(git log --oneline "$pushed" --not refs/remotes/origin/main)"
  fi
  [ -z "$changed" ] || printf 'uncommitted changes:\n%s\n' "$(printf '%s\n' "$changed" | sed 's/^/  /')"
  [ -z "$untracked" ] || printf 'untracked files:\n%s\n' "$(printf '%s\n' "$untracked" | sed 's/^/  /')"
  [ -z "$unpushed" ] || printf 'commits not pushed:\n%s\n' "$(printf '%s\n' "$unpushed" | sed 's/^/  /')"
  [ -z "$orphan" ] || printf 'pushed commits with no PR (deleting the remote branch drops them):\n%s\n' "$(printf '%s\n' "$orphan" | sed 's/^/  /')"
}

# Deletes the remote branch, if it is still there, and reads the fact back.
delete_remote_branch() { # delete_remote_branch <checkout>
  [ -n "$(git -C "$1" ls-remote --heads origin "$branch")" ] || return 0
  git -C "$1" push --quiet origin --delete "$branch"
  [ -z "$(git -C "$1" ls-remote --heads origin "$branch")" ] || die "remote branch $branch was not deleted"
  echo "deleted remote branch $branch"
}

# Takes out of .worktrees/parallel-active.tsv the line of the phase and every
# line whose worktree is gone. A pending line (phase not opened yet, open-parallel.sh) has no
# worktree on purpose and stays, unless it is the line of the phase itself.
registry_drop() { # registry_drop <main checkout> [issue]
  local registry="$1/.worktrees/parallel-active.tsv" n b path
  [ -f "$registry" ] || return 0
  while IFS="$(printf '\t')" read -r n b path; do
    [ "$n" != "${2:-}" ] || continue
    if [ "$b" = pending ]; then printf '%s\tpending\n' "$n"
    elif [ -d "$path" ]; then printf '%s\t%s\t%s\n' "$n" "$b" "$path"; fi
  done <"$registry" >"$registry.tmp" || true
  mv "$registry.tmp" "$registry"
}

abort() {
  local main_root here n losses pr
  is_main_branch "$branch" && die "on $branch: --abort runs on the phase branch"
  main_root="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
  here="$ROOT"
  n="$(issue_from_branch "$branch")"
  # Nothing is touched before the losses are listed.
  losses="$(abort_losses)"
  if [ -n "$losses" ]; then
    if [ "$discard" = 0 ]; then
      echo "abort refused: phase #$n ($branch) would lose:"
      echo "$losses"
      echo "commit and push what must stay, or run --abort --discard to drop all of it"
      exit 10
    fi
    echo "discarded with phase #$n ($branch):"
    echo "$losses"
  fi
  # Same record as --cleanup: the slot is free at the end, not at the next opening.
  slots_end_phase "$here"
  pr="$(pr_number)"
  if [ -n "$pr" ]; then
    gh_role pr close "$pr" --repo "$repo" --comment "Fase #$n abortada (\`close-phase.sh --abort\`)." >/dev/null
    echo "closed PR #$pr"
  fi
  delete_remote_branch "$here"
  # shellcheck source=.method/scripts/lib/project.sh
  source "$HERE/lib/project.sh"
  local board=0
  project_set_status "$n" "Todo" || board=1
  registry_drop "$main_root" "$n"
  trace_event phase_aborted issue="$n"
  project_refresh_phase_filter "$main_root" "" "$n" || board=1
  if [ "$here" != "$main_root" ]; then
    git -C "$main_root" worktree remove --force "$here"
    echo "removed worktree $here"
  fi
  git -C "$main_root" branch -D "$branch" >/dev/null 2>&1 || true
  echo "deleted local branch $branch"
  [ "$board" = 0 ] || die "phase #$n is aborted and cleaned up, but the board was not updated (cause and fix above)"
}

# Head of a pull request that is not a phase. Prints "<sha>\t<base>".
# A fix/issue-* head is refused: that branch keeps --merge and the phase gate.
outside_refs() { # outside_refs <pull request number>
  local info branch sha base
  info="$(gh pr view "$1" --repo "$repo" --json headRefName,headRefOid,baseRefName)"
  branch="$(printf '%s' "$info" | jq -r '.headRefName // empty')"
  sha="$(printf '%s' "$info" | jq -r '.headRefOid // empty')"
  base="$(printf '%s' "$info" | jq -r '.baseRefName // "main"')"
  [ -n "$branch" ] && [ -n "$sha" ] || die "PR #$1 has no head"
  # new-phase.sh: <type>/issue-<n>-<slug>, type feat, fix, docs or chore.
  case "$branch" in
    feat/issue-*|fix/issue-*|docs/issue-*|chore/issue-*)
      die "refused: PR #$1 is on phase branch $branch: a phase branch keeps close-phase.sh --merge" 2 ;;
  esac
  printf '%s\t%s\n' "$sha" "$base"
}

# The saved independent review of a SHA, next to the trace. A review file, when
# this run has one, must be that saved output byte for byte.
require_saved_review() { # require_saved_review <sha> <verdict>
  local sha="$1" want="$2" events saved savedv got
  events="$(phase_trace_file "$ROOT")" || die "cannot locate the trace: review refused"
  saved="$(opinion_dir "reviewer-$sha")/reviewer-$sha.md"
  savedv="$(dirname "$saved")/reviewer-$sha.verdict"
  [ -f "$saved" ] || die "$(missing_opinion_msg "$sha" "$saved")"
  require_unedited_opinion "$saved" "$events"
  got="$(save_opinion_verdict "$saved" "$savedv")" || exit $?
  [ "$got" = "$want" ] || die "saved reviewer verdict $got is not $want for ${sha:0:12}"
  if [ -n "$review_file" ]; then
    cmp -s "$saved" "$review_file" || die "review file differs from the saved close-reviewer output"
  fi
}

# Conclusion of the CI check run on a SHA: "missing" when there is none.
ci_conclusion() { # ci_conclusion <sha>
  gh api "repos/$repo/commits/$1/check-runs" --jq '[.check_runs[] | select(.name == "CI")] | sort_by(.started_at) | last | if . == null then "missing" elif .status != "completed" then .status else .conclusion end'
}

# Same protection rule as a phase merge. Does not call the phase gate.
require_base_protection() { # require_base_protection <base> <sha>
  local base="$1" sha="$2" required c
  if required="$(gh api "repos/$repo/branches/$base/protection" --jq '.required_status_checks | ([.checks[]?.context] + (.contexts // [])) | unique | .[]' 2>/dev/null)"; then
    for c in CI review/independent; do
      printf '%s\n' "$required" | stdin_grep -qxF "$c" ||
        die "the protection of $base does not require $c: no merge without the gate; fix: .method/scripts/setup-repo.sh --only protection"
    done
  else
    gh variable list --repo "$repo" --json name --jq '.[].name' 2>/dev/null | stdin_grep -qxF PROCESS_BRANCH_MODE ||
      die "$base is not protected, or its protection cannot be read: no merge without the gate; fix: .method/scripts/setup-repo.sh --only protection"
    unprotected_gate "$sha"
  fi
}

outside_publish() {
  [ -f "$review_file" ] || die "review file not found: $review_file"
  case "$verdict" in ''|success|failure) ;; *) die "--verdict must be success or failure" 2 ;; esac
  "$HERE/check-attribution.sh" --text-file "$review_file" >/dev/null || die "review has AI attribution"
  local refs sha desc
  refs="$(outside_refs "$pr")" || exit $?
  sha="${refs%%$'\t'*}"
  if [ -z "$verdict" ]; then
    verdict="$(opinion_verdict "$(opinion_dir "reviewer-$sha")/reviewer-$sha.md")" || exit $?
  fi
  require_saved_review "$sha" "$verdict"
  local body events
  events="$(phase_trace_file "$ROOT" 2>/dev/null || true)"
  body="$(reviewer_body "$review_file" "$events")"
  gh_role pr comment "$pr" --repo "$repo" --body-file "$body" >/dev/null
  desc="Revisão independente aprovada"
  [ "$verdict" = success ] || desc="Revisão independente pediu mudanças"
  gh api -X POST "repos/$repo/statuses/$sha" -f state="$verdict" -f context=review/independent \
    -f description="$desc" >/dev/null
  echo "published review/independent=$verdict on ${sha:0:12} (PR #$pr)"
}

# Merge of a non-phase pull request. Always needs --owner-ok of its head, green
# CI and the saved review of that SHA. Never the phase gate.
outside_merge() {
  local refs sha base ci state
  refs="$(outside_refs "$pr")" || exit $?
  sha="${refs%%$'\t'*}"
  base="${refs#*$'\t'}"
  if [ "$owner_ok" = 0 ]; then
    echo "refused: PR #$pr needs --owner-ok equal to HEAD $sha"
    exit 5
  fi
  if [ "$owner_ok_sha" != "$sha" ]; then
    echo "refused: --owner-ok $owner_ok_sha does not match HEAD $sha"
    exit 5
  fi
  require_saved_review "$sha" success
  state="$(gh api "repos/$repo/commits/$sha/status" --jq '[.statuses[] | select(.context == "review/independent")][0].state // "missing"')"
  [ "$state" = success ] || die "review/independent is $state on ${sha:0:12}: publish the saved review of this SHA first"
  ci="$(ci_conclusion "$sha")" || die "cannot read the check runs of ${sha:0:12}: merge blocked" 11
  [ "$ci" = success ] || die "CI is $ci on ${sha:0:12}: no merge until it is success" 11
  require_base_protection "$base" "$sha"
  "$HERE/check-attribution.sh" --pr "$pr" || die "PR #$pr has AI attribution: fix the body or commits first"
  gh_role pr comment "$pr" --repo "$repo" --body "<!-- owner-ok sha:$sha -->
Ok do dono do repo registrado para o merge do PR #$pr fora de fase." >/dev/null
  if ! gh pr merge "$pr" --repo "$repo" --auto --rebase --delete-branch >/dev/null 2>&1; then
    gh pr merge "$pr" --repo "$repo" --rebase --delete-branch >/dev/null
  fi
  echo "merge requested for PR #$pr (rebase, auto)"
}

case "$mode" in
  abort) abort ;;
  prepare) prepare ;;
  prereview) pre_review ;;
  save) save_review ;;
  review) if [ -n "$pr" ]; then outside_publish; else publish_review; fi ;;
  check) check_pr ;;
  merge) if [ -n "$pr" ]; then outside_merge; else merge; fi ;;
  cleanup) cleanup ;;
esac
