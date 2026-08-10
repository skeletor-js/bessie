# Bessie documentation

These documents describe the current public Mac application and how to build, operate, and contribute to it.

## Start here

1. [Project README](../README.md) — product overview, platform support, installation status, and development entry point.
2. [V1 features](v1/features.md) — shipping behavior, ownership boundaries, and explicit non-goals.
3. [Getting started](v1/getting-started.md) — first run, local and SSH setup, Projects, notifications, terminals, troubleshooting, and updates.
4. [CLI, MCP, and intent automation](v1/automation.md) — discovery, command contracts, concurrency, confirmation, and safety boundaries.
5. [Architecture](v1/architecture.md) — ownership, state, transport, terminal, persistence, and trust boundaries.
6. [Development](v1/development.md) — contributor setup, tests, packaging, signing, and validation.
7. [Release operations](releases/README.md) — signing, notarization, immutable artifacts, Sparkle, and publication boundaries.
8. [Contributing](../CONTRIBUTING.md), [security](../SECURITY.md), and [credits](../CREDITS.md).

For implementation work, [AGENTS.md](../AGENTS.md) is the repository-level invariant contract.

## Source-grounded references

Verify documentation claims against:

- [`Package.swift`](../Package.swift) for platform and package versions;
- [`scripts/herdr-runtime-lock.json`](../scripts/herdr-runtime-lock.json) for the bundled Herdr contract;
- `Sources/BessieCore/` for ownership, connection, Project, intent, and feature-flag models;
- `Sources/BessieApp/` for shipping UI behavior;
- `Tests/` and [`scripts/check.sh`](../scripts/check.sh) for enforced behavior;
- [`Sources/BessieApp/Resources/ATTRIBUTION.md`](../Sources/BessieApp/Resources/ATTRIBUTION.md) for packaged notices and asset provenance.
