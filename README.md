# claude-parallel-sessions

Fan a batch of independent tasks into N cold Claude Code processes, each in its own WezTerm pane. The skill (`skills/spawn-parallel-sessions/SKILL.md`) tells the controlling Claude session how to write self-contained prompts and pipe a JSON batch to `bin/claude-parallel-spawn.sh`. The script handles tab/pane layout in WezTerm and spawns the cold Claude CLIs.

Use this when you have N independent units of the same kind of work (e.g. 10 code reviews) and don't need the spawned sessions' output back in the controlling conversation. Spawned sessions run independently; the user owns them after launch.

**Requires:** WezTerm, Claude Code, bash. Cleanup: `bin/claude-parallel-cleanup.sh`.

See `setup.md` to install.
