# claude-parallel-sessions — setup

**Requires:** WezTerm, Claude Code, bash

## Per-machine values

None — paths are user-relative (`~/bin/`, `~/.claude/skills/`).

## Files

| Source | Destination |
|---|---|
| `bin/claude-parallel-spawn.sh` | `~/bin/claude-parallel-spawn.sh` (chmod +x) |
| `bin/claude-parallel-cleanup.sh` | `~/bin/claude-parallel-cleanup.sh` (chmod +x) |
| `skills/spawn-parallel-sessions/` | `~/.claude/skills/spawn-parallel-sessions/` (symlink the folder) |

## Install

```bash
# Replace <REPO_PATH> with this machine's clone path, e.g. /mnt/d/labs/claude-parallel-sessions
mkdir -p ~/bin
ln -sf <REPO_PATH>/bin/claude-parallel-spawn.sh ~/bin/claude-parallel-spawn.sh
ln -sf <REPO_PATH>/bin/claude-parallel-cleanup.sh ~/bin/claude-parallel-cleanup.sh
ln -sf <REPO_PATH>/skills/spawn-parallel-sessions ~/.claude/skills/spawn-parallel-sessions  # <-- edit per machine: repo clone path
```

Confirm `~/bin` is on `$PATH` (most distros include it for login shells; if not, add `export PATH="$HOME/bin:$PATH"` to `~/.bashrc`).

## Verify

In a Claude Code session, ask: *"do these three things in parallel sessions: (a) … (b) … (c) …"*. The agent should invoke the `spawn-parallel-sessions` skill and run `claude-parallel-spawn.sh`. Three new WezTerm panes appear, each running an independent `claude` process.

`bin/claude-parallel-cleanup.sh` tears down panes spawned by the originator pane (uses a `/tmp/claude-parallel-spawn-<pane>.json` registry).

## Uninstall

```bash
rm ~/bin/claude-parallel-spawn.sh ~/bin/claude-parallel-cleanup.sh
rm ~/.claude/skills/spawn-parallel-sessions
```
