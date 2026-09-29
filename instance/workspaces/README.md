# Agent workspaces

One directory per agent, named after the agent id in
`site/configure.d/`. The files are the agent's instruction files
(`AGENTS.md`, `SOUL.md`, `IDENTITY.md`, `USER.md`, optional `MEMORY.md`
seed); OpenClaw injects them into every new session.

`bin/claw sync-workspaces` (part of every deploy) copies each directory into
the agent's workspace on the host. Files here **replace** their copies; what
the agent wrote itself is left alone. Changing an agent is a PR here and a
deploy — never an edit on the host.

This README is not synced (only subdirectories are).
