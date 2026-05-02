#!/usr/bin/env bash
# ~/bin/claude-parallel-spawn.sh
#
# Spawn N independent claude sessions across one or more WezTerm tabs in the
# current window. Tab 1 holds the originating (dashboard) pane plus up to 5
# spawned sessions; each subsequent tab holds up to 5 more spawned sessions
# (anchor + 4 splits). Cap: 15 spawned sessions total.
#
# Input (stdin, JSON):
#   { "sessions": [{"label","cwd","prompt_file"}, ...] }
#
# Output (stdout):
#   <label>  pane=<wezterm-pane-id>     (one line per spawned session)
#
# Exit codes:
#   0 success
#   1 precondition failed (not in WezTerm, missing deps, bad input, > cap)
#   2 layout build failed mid-flight (window may be partially constructed)

set -euo pipefail

# --- preconditions --------------------------------------------------------

WT=wezterm.exe
CAP=15
PER_TAB=5

err() { printf 'claude-parallel-spawn: %s\n' "$*" >&2; }

command -v "$WT" >/dev/null 2>&1 \
  || { err "wezterm.exe not on PATH (are you in WSL with WezTerm host?)"; exit 1; }
command -v jq >/dev/null 2>&1 \
  || { err "jq required (apt install jq)"; exit 1; }
[[ -n "${WEZTERM_PANE:-}" ]] \
  || { err "WEZTERM_PANE not set; must run from inside a WezTerm pane"; exit 1; }

# --- parse input ----------------------------------------------------------

JSON=$(cat)
if ! jq -e . >/dev/null 2>&1 <<<"$JSON"; then
  err "stdin is not valid JSON"; exit 1
fi

N=$(jq '.sessions | length' <<<"$JSON")
if ! [[ "$N" =~ ^[0-9]+$ ]] || (( N < 1 )); then
  err "input must contain a non-empty 'sessions' array"; exit 1
fi
if (( N > CAP )); then
  err "max $CAP spawned sessions per invocation (got $N); split into multiple invocations"
  exit 1
fi

for i in $(seq 0 $((N-1))); do
  pf=$(jq -r ".sessions[$i].prompt_file // empty" <<<"$JSON")
  cwd=$(jq -r ".sessions[$i].cwd // empty" <<<"$JSON")
  label=$(jq -r ".sessions[$i].label // empty" <<<"$JSON")
  [[ -n "$pf" && -n "$cwd" && -n "$label" ]] \
    || { err "sessions[$i] missing label/cwd/prompt_file"; exit 1; }
  [[ -r "$pf" ]] \
    || { err "sessions[$i] prompt_file not readable: $pf"; exit 1; }
  [[ -d "$cwd" ]] \
    || { err "sessions[$i] cwd is not a directory: $cwd"; exit 1; }
done

# --- helpers --------------------------------------------------------------

DASH="$WEZTERM_PANE"

# The bash command run inside each spawned pane: cd into target cwd, then
# exec claude with the prompt file's contents as the prompt argv. $(< "$pf")
# is evaluated inside the spawned shell so prompt text never crosses any
# intermediate argv.
session_cmd() {
  local idx=$1 cwd pf
  cwd=$(jq -r ".sessions[$idx].cwd"         <<<"$JSON")
  pf=$( jq -r ".sessions[$idx].prompt_file" <<<"$JSON")
  printf 'cd %q && exec claude "$(< %q)"' "$cwd" "$pf"
}

# split_spawn <target_pane> <right|bottom> <percent> <session_idx>
# Splits target_pane and runs claude for sessions[idx]. Echoes new pane id.
split_spawn() {
  local target=$1 dir=$2 pct=$3 idx=$4 cmd new_pane
  cmd=$(session_cmd "$idx")
  new_pane=$("$WT" cli split-pane \
                --pane-id "$target" "--$dir" --percent "$pct" \
                -- bash -lc "$cmd") \
    || { err "split-pane failed at session $idx"; exit 2; }
  printf '%s' "$new_pane" | tr -d '[:space:]'
}

# spawn_in_new_tab <session_idx>
# Creates a new tab in the dashboard's window and runs claude for sessions[idx].
# Echoes the anchor pane id.
spawn_in_new_tab() {
  local idx=$1 cmd new_pane
  cmd=$(session_cmd "$idx")
  new_pane=$("$WT" cli spawn --window-id "$WINID" -- bash -lc "$cmd") \
    || { err "spawn (new tab) failed at session $idx"; exit 2; }
  printf '%s' "$new_pane" | tr -d '[:space:]'
}

# apply_splits <anchor_pane> <base_idx> <K>
# Performs K splits from anchor_pane to lay out K spawned sessions, populating
# P[base_idx .. base_idx+K-1]. Layout patterns mirror the original
# dashboard-anchored layouts for N=1..5.
apply_splits() {
  local anchor=$1 base=$2 K=$3
  case "$K" in
    0)
      ;;
    1)
      P[$base]=$(split_spawn "$anchor" right 50 $base)
      ;;
    2)
      P[$base]=$(split_spawn "$anchor"           right 67 $base)
      P[$((base+1))]=$(split_spawn "${P[$base]}" right 50 $((base+1)))
      ;;
    3)
      P[$((base+1))]=$(split_spawn "$anchor"             right  50 $((base+1)))
      P[$base]=$(split_spawn "$anchor"                   bottom 50 $base)
      P[$((base+2))]=$(split_spawn "${P[$((base+1))]}"   bottom 50 $((base+2)))
      ;;
    4)
      P[$((base+1))]=$(split_spawn "$anchor"             right  67 $((base+1)))
      P[$((base+2))]=$(split_spawn "${P[$((base+1))]}"   right  50 $((base+2)))
      P[$base]=$(split_spawn "$anchor"                   bottom 50 $base)
      P[$((base+3))]=$(split_spawn "${P[$((base+2))]}"   bottom 50 $((base+3)))
      ;;
    5)
      P[$((base+1))]=$(split_spawn "$anchor"             right  67 $((base+1)))
      P[$((base+2))]=$(split_spawn "${P[$((base+1))]}"   right  50 $((base+2)))
      P[$base]=$(split_spawn "$anchor"                   bottom 50 $base)
      P[$((base+3))]=$(split_spawn "${P[$((base+1))]}"   bottom 50 $((base+3)))
      P[$((base+4))]=$(split_spawn "${P[$((base+2))]}"   bottom 50 $((base+4)))
      ;;
    *)
      err "internal: apply_splits called with K=$K (expected 0..5)"; exit 2
      ;;
  esac
}

# --- build layout ---------------------------------------------------------

# Move dashboard to a fresh tab in the same window.
"$WT" cli move-pane-to-new-tab --pane-id "$DASH" >/dev/null \
  || { err "failed to move dashboard pane to new tab"; exit 2; }

# Capture the dashboard's window id so subsequent tabs spawn into it.
WINID=$("$WT" cli list 2>/dev/null | awk -v p="$DASH" '$3==p {print $1; exit}')
[[ -n "$WINID" ]] \
  || { err "couldn't determine window id for dashboard pane $DASH"; exit 2; }

declare -A P
i=0
tab=0
while (( i < N )); do
  remaining=$(( N - i ))
  chunk=$(( remaining < PER_TAB ? remaining : PER_TAB ))

  if (( tab == 0 )); then
    # Tab 1: dashboard already present; chunk panes are all splits.
    apply_splits "$DASH" "$i" "$chunk"
  else
    # Tab 2+: spawn anchor (which IS sessions[i]), then chunk-1 splits.
    anchor=$(spawn_in_new_tab "$i")
    P[$i]=$anchor
    apply_splits "$anchor" "$((i+1))" "$((chunk - 1))"
  fi

  i=$(( i + chunk ))
  tab=$(( tab + 1 ))
done

# Return focus to the dashboard pane (and its tab).
"$WT" cli activate-pane --pane-id "$DASH" >/dev/null 2>&1 || true

# --- registry (for cleanup) -----------------------------------------------

REGISTRY="/tmp/claude-parallel-spawn-${DASH}.json"
[[ -f "$REGISTRY" ]] || printf '{"spawned":[]}\n' > "$REGISTRY"

for i in $(seq 0 $((N-1))); do
  label=$(jq -r ".sessions[$i].label" <<<"$JSON")
  pane_id="${P[$i]}"
  tmp=$(mktemp)
  jq --arg label "$label" --arg pane "$pane_id" \
     '.spawned += [{"label":$label,"pane_id":$pane}]' \
     "$REGISTRY" > "$tmp" && mv "$tmp" "$REGISTRY"
done

# --- report ---------------------------------------------------------------

for i in $(seq 0 $((N-1))); do
  label=$(jq -r ".sessions[$i].label" <<<"$JSON")
  printf '%s  pane=%s\n' "$label" "${P[$i]}"
done
