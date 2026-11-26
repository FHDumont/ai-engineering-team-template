#!/usr/bin/env bash
# Pure logic of the trigger that re-offers the self-hosted runner.
# Load with: source scripts/lib/runner_offer.sh
#
# runner_offer_decision <private_repo:true|false> <runs_on_set:0|1> <avg_sec> <quota_pct>
# Prints "offer <reason>" or "skip <reason>". Empty avg_sec and quota_pct = unknown criterion
# (the API failed) and are ignored. Never offers on a public repo nor
# when CI_RUNS_ON already exists; offers if the average passes 5 min or the quota 50%.
runner_offer_decision() {
  local private="$1" has_runs_on="$2" avg="${3:-}" quota="${4:-}"
  if [ "$private" != "true" ]; then echo "skip public repo"; return; fi
  if [ "$has_runs_on" = 1 ]; then echo "skip CI_RUNS_ON already set"; return; fi
  case "$avg" in ''|*[!0-9]*) avg="" ;; esac
  case "$quota" in ''|*[!0-9]*) quota="" ;; esac
  if [ -n "$avg" ] && [ "$avg" -gt 300 ]; then echo "offer average CI run is ${avg}s (over 5 min)"; return; fi
  if [ -n "$quota" ] && [ "$quota" -gt 50 ]; then echo "offer monthly minutes quota at ${quota}% (over 50%)"; return; fi
  echo "skip usage under the thresholds"
}
