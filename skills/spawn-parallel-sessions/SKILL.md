---
name: spawn-parallel-sessions
description: Use when the user has a batch of independent tasks to fan out into separate cold Claude CLI sessions, each running in its own WezTerm pane. Triggers on shapes like "do these N tasks in parallel", "run X across each of these inputs", "one session per Y", and on explicit phrases "in parallel sessions", "fan this out", "split across sessions", "spawn N claude sessions".
---

# Spawn Parallel Sessions

## Overview

Fan a batch of **independent tasks** into N cold Claude CLI processes, each in its own WezTerm pane. Spawned sessions run independently — separate context, no message-passing, no shared state. The user interacts with each spawned session directly; this skill is for **pure fan-out without coordination**.

**Use this when** you don't care about the spawned sessions' output landing back in this conversation — the user will own them after launch.

**Use something else when:**
- You need the result back here to act on it → sub-agent (a sub-agent makes sense even for a single independent task if you'll consume its output)
- The sessions need to coordinate or share state → agent-teams
- The user wants the work done inline in this conversation → just do it sequentially
- Single task with no fan-out shape → just do it

## Trigger Behavior

Two paths:

1. **Explicit phrases** ("do these in parallel", "fan this out", "spawn N sessions", "one session per X") → spawn directly.
2. **Implicit fan-out shape** (a request that's clearly N independent units of the same kind of work) → **confirm first** with one line: *"This is N independent tasks — fan them out into parallel sessions?"* Wait for yes.

When in doubt, ask. A wrong autonomous spawn (panes the user has to triage) costs more than one round-trip.

## Self-Contained Prompts (Critical)

Each spawned session starts **cold**. It has none of: this conversation, your memory, other spawned sessions, or any files/tools/skills referenced earlier in this turn.

**Every prompt must contain everything the new session needs to do its task with no prior context.** That means:

- Inline every constraint the user mentioned in this conversation that applies to this task ("ignore styling nits", "Sarah owns this — flag, don't demand", "watch for the regression we discussed earlier")
- Replace every reference to "the X we discussed" / "the file we just saw" / "as agreed" with the actual content
- If the spawned session is meant to invoke a skill, give it everything that skill needs as input — same standard

**Forbidden in prompts:** "as we discussed", "as agreed", "from the conversation", "the X you mentioned", "earlier", "above", bare item identifiers without enough context to disambiguate. If you reach for a pronoun or phrase pointing outside the prompt, expand it inline.

## Invocation

Two-step: write each prompt to a file in `/tmp/`, then pipe a JSON batch to `~/bin/claude-parallel-spawn.sh`. The script handles tab creation, layout, and pane spawn — don't write `wezterm cli` calls yourself.

```bash
# 1. write prompts to files (self-clear on reboot; useful for debugging)
cat > /tmp/claude-spawn-alpha.md <<'EOF'
<full self-contained prompt for session alpha>
EOF

cat > /tmp/claude-spawn-beta.md <<'EOF'
<full self-contained prompt for session beta>
EOF

# 2. pipe the batch
cat <<EOF | ~/bin/claude-parallel-spawn.sh
{
  "sessions": [
    {"label": "alpha", "cwd": "$HOME/projects/foo", "prompt_file": "/tmp/claude-spawn-alpha.md"},
    {"label": "beta",  "cwd": "$HOME/projects/bar", "prompt_file": "/tmp/claude-spawn-beta.md"}
  ]
}
EOF
```

Each session entry needs:
- **`label`**: short human-readable name; used in the script's stdout mapping
- **`cwd`**: absolute working directory the session starts in
- **`prompt_file`**: absolute path to the prompt file you wrote in step 1

Use random or descriptive suffixes for prompt files to avoid collisions across batches.

Pass all the user's tasks in a single invocation — the script handles capacity, layout, and tab/window organization. If the script rejects the batch (e.g., too many sessions), it will say so; relay the error to the user.

## After Spawning

The script prints `<label>  pane=<id>` lines for each spawned session. Tell the user briefly what was launched (e.g., "Spawned alpha, beta, gamma") and then **proceed with any remaining work in this conversation, or wait for the user's next message**. Spawned sessions are independent — they don't report back, don't share state, and aren't your responsibility after launch. Don't poll, narrate, or speculate about their progress.

## Cleanup

Each spawn appends the new panes to `/tmp/claude-parallel-spawn-<originator-pane-id>.json`. When the user is done with the spawned sessions and wants to tear them down — phrases like "clean up", "kill the spawned sessions", "tear down the panes", "revert this" — invoke:

```bash
~/bin/claude-parallel-cleanup.sh
```

It kills every pane registered across all spawns from this originator, then deletes the registry. The originator pane stays where it is (WezTerm CLI doesn't support moving panes back to a previous tab; the user navigates manually if needed).

Cleanup uses `kill-pane` (SIGHUP) rather than `/exit`, so spawned sessions' history isn't flushed for `--resume`. Fine for ephemeral fan-out work. If a particular spawned session has work the user wants to keep, they should `/exit` it manually first.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Prompt references "the file we just saw" | Inline the actual path or content |
| Prompt says "as we discussed" / "as agreed" | Replace with the actual decision |
| Bare item identifier without context | Add whatever the spawned session needs to find/identify it |
| Forgetting a per-task constraint the user mentioned | Re-read the user's message; bake every named constraint into its session's prompt |
| Trying to manage panes/tabs/layout yourself | The script owns layout; pass all sessions in one call |
| Autonomous spawn on implicit trigger | Confirm with one-line question first |
| Polling/narrating spawned sessions | Stop after launch — they're independent |
| Hand-rolling `wezterm cli` calls or shell loops | Use the JSON contract; the script does mechanics |
| Embedding prompt text in argv | Always use `prompt_file`; never serialize prompt text into the JSON or argv |

## Red Flags — Stop

- About to spawn without explicit request or confirmation
- Prompt contains "we", "us", "earlier", "above", "the X" pointing outside the prompt body
- Bare ID without enough context to disambiguate
- Reaching for `wezterm cli`, `tmux`, or shell loops directly
- Putting prompt text in the JSON instead of in a file
- Thinking about pane placement, tab boundaries, or batch sizing — the script owns all of that

All mean: stop, fix the prompt or the JSON, or ask first.
