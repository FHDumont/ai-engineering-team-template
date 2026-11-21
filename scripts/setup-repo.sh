#!/usr/bin/env bash
#: setup-repo.sh: apply the method's standard to the GitHub repository (idempotent).
#:
#: Usage: setup-repo.sh [--dry-run | --check] [--only labels|settings|protection]
#:
#: 1. Labels: syncs with .github/labels.tsv (creates, updates color and
#:    description, renames from old names with `gh label edit --name`) and
#:    deletes GitHub's default labels.
#: 2. Settings (§10.1): auto-merge on, rebase only, delete branch on merge.
#: 3. Protection of main (§10.1): requires the `CI` check (from GitHub Actions)
#:    and the `review/independent` status, no "up to date" requirement;
#:    0 approvals; linear history; enforced for admins; no force-push, no deletion.
#:    It is read back after being applied. When the plan has no branch protection
#:    (a private repository on a free account) it records the "unprotected" mode in
#:    the repository variable PROCESS_BRANCH_MODE, warns and exits 0 (§10.3 of the
#:    design); --check then accepts it and the gate is kept by scripts.
#:
#: Usage: setup-repo.sh --offers | [--dry-run] --project | --decline project|runner|runner-trigger
#: Offers (asked once; the agent shows one choice board per offer):
#:    --offers   lists unanswered offers (`offer:project`, `offer:runner`);
#:    --project  idempotent: checks the `project` scope (includes read; if missing, prints
#:               the single `gh auth login` command with every scope of the method and exits 1), creates the board
#:               if none is stored (PROCESS_PROJECT_NUMBER), links the repo and reads it back,
#:               creates the default views that are missing (by name; what the API refuses
#:               becomes a `pending:` line for the browser) and reads the native workflows
#:               (declared on only with proof); open-issue, new-phase and close-phase move
#:               the item (Todo / In Progress / Done);
#:    --decline  records the "no" outside git, in the repository variable
#:               PROCESS_OFFER_PROJECT / PROCESS_OFFER_RUNNER / PROCESS_OFFER_RUNNER_TRIGGER.
#:    A runner declined at setup only returns through the triage trigger
#:    (triage.sh --runner-offer).
#: --check is the single conference of the mandatory setup (phase-start.sh,
#: open-issue.sh and the session hook call it): it only reads, each thing once
#: (labels, repository, protection, variables), and exits 0 when all three match and no offer
#: is unanswered. Otherwise it prints one `missing:` line per part and the
#: sentence to say ("configurar o repo") on stderr and exits 7 (a plan without branch
#: protection and no recorded mode is one of them). With --only it checks that part alone.
#: --dry-run only shows the difference (with --project too: it only reads and says
#: what it would create). A second run with no difference changes nothing. Pre-approved: the agent runs it; the owner never does.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"
ROOT="$(cd "$HERE/.." && pwd)"

dry=0 only="" mode=""
decline=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --dry-run) dry=1; shift ;;
    --check) mode=check; dry=1; shift ;;
    --only) only="$2"; shift 2 ;;
    --offers) mode=offers; shift ;;
    --project) mode=project; shift ;;
    --decline) mode=decline; decline="${2:-}"; shift 2 ;;
    *) die "unknown option: $1 (see --help)" 2 ;;
  esac
done
require_cmd gh jq
repo="$(repo_slug)"
branch="${SETUP_BRANCH:-main}"
changes=0

# One-time offers of the Project and of the runner. The "no" stays in the repository variable.
# The variable names and the repository are read once per run, whatever asks for them.
var_names="" var_names_read=0
var_exists() { # var_exists <name>
  if [ "$var_names_read" = 0 ]; then
    var_names="$(gh variable list --repo "$repo" --json name --jq '.[].name' 2>/dev/null || true)"
    var_names_read=1
  fi
  printf '%s\n' "$var_names" | grep -qxF "$1"
}
repo_info=""
read_repo_info() {
  [ -n "$repo_info" ] || repo_info="$(gh api "repos/$repo")"
}
offers_pending=""
run_offers() {
  offers_pending=""
  var_exists PROCESS_OFFER_PROJECT || offers_pending="offer:project"
  if ! var_exists PROCESS_OFFER_RUNNER && ! var_exists CI_RUNS_ON; then
    read_repo_info 2>/dev/null || true
    if [ "$(printf '%s' "$repo_info" | jq -r .private 2>/dev/null)" = "true" ]; then
      offers_pending="${offers_pending:+$offers_pending }offer:runner"
    fi
  fi
}
case "$mode" in
  offers)
    run_offers
    # shellcheck disable=SC2086
    if [ -n "$offers_pending" ]; then printf '%s\n' $offers_pending; else echo "offers: none pending"; fi
    exit 0 ;;
  project)
    # shellcheck source=scripts/lib/project.sh
    source "$HERE/lib/project.sh"
    owner="${repo%%/*}"
    # 1. Scope: without it, returns the real step (the owner only logs in) and does not claim success.
    if ! project_require_scopes; then exit 1; fi
    # --dry-run: only reads, and says what a real run would create.
    if [ "$dry" = 1 ]; then
      num="$(project_number "$repo")"
      if [ -z "$num" ]; then
        echo "would: create the project board, store PROCESS_PROJECT_NUMBER, link it to $repo and create the default views"
        exit 0
      fi
      echo "ok: board #$num already exists (reused)"
      project_linked_numbers "$repo" | grep -qxF "$num" || echo "would: link board #$num to $repo"
      existing="$(project_list_views "$owner" "$num")"
      while IFS='|' read -r name _; do
        printf '%s\n' "$existing" | cut -f1 | grep -qxF "$name" || echo "would: create view: $name"
      done < <(project_default_views)
      exit 0
    fi
    # 2. Board: reuses the stored one (idempotent); creates only if there is none.
    num="$(project_number "$repo")"
    created=0
    if [ -z "$num" ]; then
      num="$(gh project create --owner "$owner" --title "${repo#*/}" --format json --jq .number)"
      [ -n "$num" ] || die "could not create the project board (is the project scope granted?)" 1
      created=1
      echo "ok: board #$num created"
    else
      echo "ok: board #$num already exists (reused)"
    fi
    gh variable set PROCESS_PROJECT_NUMBER --repo "$repo" --body "$num"
    gh variable set PROCESS_OFFER_PROJECT --repo "$repo" --body created
    # 3. Link: without it the board does not show in the repository Projects tab; reads it back.
    project_ensure_link "$repo" "$num" || exit 1
    # Open issues go to Todo only on a new board (an existing board keeps its statuses).
    if [ "$created" = 1 ]; then
      for i in $(gh issue list --repo "$repo" --state open --limit 200 --json number --jq '.[].number'); do
        project_set_status "$i" "Todo" || exit 1
      done
    fi
    # 4. Default views and 5. native workflows (read only).
    project_ensure_views "$owner" "$num"
    project_check_workflows "$owner" "$num"
    if [ "$PROJECT_PENDING" -gt 0 ]; then
      echo "partial: project board #$num linked; $PROJECT_PENDING item(s) pending in the browser (see 'pending:' lines)"
    else
      echo "done: project board #$num ready (linked, views and workflows read back)"
    fi
    exit 0 ;;
  decline)
    case "$decline" in
      project) name=PROCESS_OFFER_PROJECT ;;
      runner) name=PROCESS_OFFER_RUNNER ;;
      runner-trigger) name=PROCESS_OFFER_RUNNER_TRIGGER ;;
      *) die "--decline takes project, runner or runner-trigger" 2 ;;
    esac
    gh variable set "$name" --repo "$repo" --body declined
    echo "done: $name=declined"; exit 0 ;;
esac

# Runs (or only shows, with --dry-run) one change.
apply() { # apply <description> <command...>
  local what="$1"; shift
  changes=$((changes + 1))
  if [ "$dry" = 1 ]; then
    echo "would: $what"
  else
    "$@" >/dev/null
    echo "done: $what"
  fi
}

# Default labels GitHub creates in every new repository.
DEFAULT_LABELS="bug
documentation
duplicate
enhancement
good first issue
help wanted
invalid
question
wontfix
accessibility"

sync_labels() {
  local current name color desc olds old found
  current="$(gh label list --repo "$repo" --limit 500 --json name,color,description)"
  while IFS="$(printf '\t')" read -r name color desc olds; do
    case "$name" in ''|'#'*) continue ;; esac
    found="$(echo "$current" | jq -c --arg n "$name" '.[] | select(.name == $n)')"
    if [ -n "$found" ]; then
      if [ "$(echo "$found" | jq -r '.color | ascii_downcase')" != "$color" ] ||
         [ "$(echo "$found" | jq -r .description)" != "$desc" ]; then
        apply "update label $name" gh label edit "$name" --repo "$repo" --color "$color" --description "$desc"
      fi
      continue
    fi
    # Renames from an old name, if it exists (keeps the issues labeled).
    old=""
    if [ -n "$olds" ]; then
      for o in $(echo "$olds" | tr ',' ' '); do
        if echo "$current" | jq -e --arg n "$o" 'any(.[]; .name == $n)' >/dev/null; then old="$o"; break; fi
      done
    fi
    if [ -n "$old" ]; then
      apply "rename label $old -> $name" gh label edit "$old" --repo "$repo" --name "$name" --color "$color" --description "$desc"
      current="$(echo "$current" | jq -c --arg o "$old" 'map(select(.name != $o))')"
    else
      apply "create label $name" gh label create "$name" --repo "$repo" --color "$color" --description "$desc"
    fi
  done <<<"$(label_rows "$ROOT/.github/labels.tsv")"

  local wanted
  wanted="$(label_rows "$ROOT/.github/labels.tsv" | cut -f1)"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    echo "$wanted" | grep -qxF "$name" && continue
    if echo "$current" | jq -e --arg n "$name" 'any(.[]; .name == $n)' >/dev/null; then
      apply "delete default label $name" gh label delete "$name" --repo "$repo" --yes
    fi
  done <<<"$DEFAULT_LABELS"
}

sync_settings() {
  local want have
  want='{"allow_auto_merge":true,"allow_merge_commit":false,"allow_squash_merge":false,"allow_rebase_merge":true,"delete_branch_on_merge":true}'
  read_repo_info
  have="$(printf '%s' "$repo_info" | jq '{allow_auto_merge, allow_merge_commit, allow_squash_merge, allow_rebase_merge, delete_branch_on_merge}')"
  if [ "$(echo "$have" | jq -S -c .)" != "$(echo "$want" | jq -S -c .)" ]; then
    echo "settings: have $(echo "$have" | jq -S -c .)"
    apply "repo settings (rebase only, auto-merge, delete branch on merge)" \
      gh api -X PATCH "repos/$repo" --input - <<<"$want"
  fi
}

# Normalized form of the protection, to compare what exists with what is wanted.
NORMALIZE='{
  strict: (.required_status_checks | if . == null then null else .strict end),
  checks: ([.required_status_checks.checks[]? | .context + "@" + ((.app_id // "any") | tostring)] | sort),
  enforce_admins: (.enforce_admins.enabled // false),
  reviews: (.required_pull_request_reviews.required_approving_review_count // null),
  linear: (.required_linear_history.enabled // false),
  force_pushes: (.allow_force_pushes.enabled // false),
  deletions: (.allow_deletions.enabled // false)
}'

# The plan of the account has no branch protection for this repository (a private
# repository on a free plan): GitHub answers 403 with an upgrade message. The method
# then runs in the "unprotected" mode: the gate is kept by scripts (close-phase.sh
# --merge reads CI and review/independent through the API; the reference-transaction
# hook refuses a push to main), and the mode is recorded in the repository variable
# PROCESS_BRANCH_MODE. Returns 0 when it handled the case (the caller leaves the
# protection alone), 1 when the output is not that answer.
unprotected_mode() { # unprotected_mode <gh output>
  printf '%s' "$1" | grep -qiE 'Upgrade to GitHub|make this repository public' || return 1
  if var_exists PROCESS_BRANCH_MODE; then
    echo "mode: unprotected ($repo has no branch protection on this plan; the gate is kept by scripts)" >&2
    return 0
  fi
  changes=$((changes + 1))
  local what="record the unprotected branch mode (PROCESS_BRANCH_MODE=unprotected)"
  if [ "$dry" = 1 ]; then echo "would: $what"; return 0; fi
  gh variable set PROCESS_BRANCH_MODE --repo "$repo" --body unprotected >/dev/null
  var_names_read=0
  var_exists PROCESS_BRANCH_MODE || die "PROCESS_BRANCH_MODE not confirmed on read back"
  echo "done: $what (read back)"
  echo "warning: $repo has no branch protection on this plan (a private repository on a free plan): the server does not enforce CI and review/independent, so close-phase.sh --merge checks them through the API and the git hook refuses a push to $branch; a merge done by hand on GitHub is not blocked" >&2
  return 0
}

sync_protection() {
  local body want have raw
  body='{
    "required_status_checks": {"strict": false, "checks": [{"context": "CI", "app_id": 15368}, {"context": "review/independent"}]},
    "enforce_admins": true,
    "required_pull_request_reviews": {"required_approving_review_count": 0, "dismiss_stale_reviews": false, "require_code_owner_reviews": false},
    "restrictions": null,
    "required_linear_history": true,
    "allow_force_pushes": false,
    "allow_deletions": false
  }'
  want='{"strict":false,"checks":["CI@15368","review/independent@any"],"enforce_admins":true,"reviews":0,"linear":true,"force_pushes":false,"deletions":false}'
  # With no protection the API answers 404: compares with "none".
  if raw="$(gh api "repos/$repo/branches/$branch/protection" 2>&1)"; then
    have="$(echo "$raw" | jq -S -c "$NORMALIZE")"
  else
    unprotected_mode "$raw" && return 0
    have=none
  fi
  want="$(echo "$want" | jq -S -c .)"
  [ "$have" != "$want" ] || return 0
  echo "protection: have $have"
  local what="protect $branch (CI + review/independent, 0 approvals, linear, admins included)"
  changes=$((changes + 1))
  if [ "$dry" = 1 ]; then echo "would: $what"; return 0; fi
  if ! raw="$(gh api -X PUT "repos/$repo/branches/$branch/protection" --input - <<<"$body" 2>&1)"; then
    unprotected_mode "$raw" && return 0
    die "could not $what: $(printf '%s' "$raw" | tail -1)"
  fi
  # Exit 0 of the PUT is not the proof: the protection is read back and compared.
  if raw="$(gh api "repos/$repo/branches/$branch/protection" 2>&1)"; then
    have="$(echo "$raw" | jq -S -c "$NORMALIZE")"
  else
    unprotected_mode "$raw" && return 0
    have=none
  fi
  [ "$have" = "$want" ] || die "protection of $branch not confirmed on read back (have $have)"
  echo "done: $what (read back)"
}

case "$only" in
  ""|labels|settings|protection) ;;
  *) die "--only must be labels, settings or protection" 2 ;;
esac

# --check: the same reads as --dry-run and --offers, in one run; says only what is missing.
if [ "$mode" = check ]; then
  check_part() { # check_part <name> <function>
    local before="$changes"
    "$2" >/dev/null
    [ "$changes" = "$before" ] || echo "missing: $1 ($((changes - before)) change(s) pending)" >&2
  }
  case "$only" in ""|labels) check_part "labels of the method" sync_labels ;; esac
  case "$only" in ""|settings) check_part "repository settings" sync_settings ;; esac
  case "$only" in ""|protection) check_part "protection of $branch" sync_protection ;; esac
  if [ -z "$only" ]; then
    run_offers
    for o in $offers_pending; do
      echo "missing: answer to $o (asked once, by the setup skill)" >&2
      changes=$((changes + 1))
    done
  fi
  if [ "$changes" = 0 ]; then
    echo "ok: $repo is configured for the method"
    exit 0
  fi
  echo "error: $repo is not configured for the method: no phase opens and no issue is created before the setup" >&2
  echo "fix: say \"configurar o repo\" to the agent (setup skill, which runs the pre-approved scripts/setup-repo.sh)" >&2
  exit 7
fi

case "$only" in
  ""|labels) sync_labels ;;
esac
case "$only" in
  ""|settings) sync_settings ;;
esac
case "$only" in
  ""|protection) sync_protection ;;
esac

if [ "$changes" = 0 ]; then
  echo "ok: $repo already matches the method (no changes)"
elif [ "$dry" = 1 ]; then
  echo "dry-run: $changes changes pending"
else
  echo "ok: applied $changes changes to $repo"
fi
