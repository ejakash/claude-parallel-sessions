#!/usr/bin/env bash
# ~/bin/claude-parallel-cleanup.sh
#
# Kill all claude sessions previously spawned from this pane via
# claude-parallel-spawn.sh and clear the per-originator registry.
#
# Reads /tmp/claude-parallel-spawn-<originator>.json (built up by spawn
# script across one or more invocations) and kills each recorded pane.
# Failures to kill individual panes are logged but non-fatal — a pane
# may already be closed by the user or by a previous cleanup attempt.
#
# Output (stdout):
#   killed <label>  pane=<id>
#   missing <label> pane=<id>     (kill-pane reported pane gone)
#
# Exit codes:
#   0  cleanup ran (some kills may have failed; check stdout)
#   1  precondition failed (missing deps, no registry, no WEZTERM_PANE)

set -euo pipefail

WT=wezterm.exe
err() { printf 'claude-parallel-cleanup: %s\n' "$*" >&2; }

command -v "$WT" >/dev/null 2>&1 \
  || { err "wezterm.exe not on PATH"; exit 1; }
command -v jq >/dev/null 2>&1 \
  || { err "jq required"; exit 1; }
[[ -n "${WEZTERM_PANE:-}" ]] \
  || { err "WEZTERM_PANE not set; run from inside a WezTerm pane"; exit 1; }

REGISTRY="/tmp/claude-parallel-spawn-${WEZTERM_PANE}.json"
if [[ ! -f "$REGISTRY" ]]; then
  err "no registry at $REGISTRY — nothing to clean up"
  exit 1
fi

N=$(jq '.spawned | length' "$REGISTRY")
if (( N == 0 )); then
  rm -f "$REGISTRY"
  echo "registry empty; removed"
  exit 0
fi

for i in $(seq 0 $((N-1))); do
  label=$( jq -r ".spawned[$i].label"   "$REGISTRY")
  pane=$(  jq -r ".spawned[$i].pane_id" "$REGISTRY")

  # kill-pane returns non-zero if the pane is already gone; treat that as ok.
  if "$WT" cli kill-pane --pane-id "$pane" >/dev/null 2>&1; then
    printf 'killed  %s  pane=%s\n' "$label" "$pane"
  else
    printf 'missing %s  pane=%s\n' "$label" "$pane"
  fi
done

rm -f "$REGISTRY"
