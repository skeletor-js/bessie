# GitHub Copilot instructions

Read and follow [`AGENTS.md`](../AGENTS.md) before changing code. It is the repository-wide contributor contract and source of truth for agent behavior.

In particular:

- Keep Bessie a graphical client for Herdr; never create a replacement runtime or shadow live-session database.
- Keep Herdr authoritative for workspaces, tabs, panes, terminals, processes, agents, and durable session state.
- Use `GhosttyTerminal` for every visible terminal and only Herdr's public JSON API, CLI, and terminal-session bridge.
- Keep changes focused, add relevant tests, and run `./scripts/check.sh`.
- Do not commit credentials, generated release material, personal paths, or private-workstream references.
- Do not publish, sign, notarize, deploy, or change distribution settings as part of an ordinary pull request.
