# Native Bessie Projects

**Status:** Complete for V1 Projects scope (Milestones 0–6); notarization deferred  
**Roadmap horizon:** V1, immediately after bundled-runtime/onboarding/Trouble  
**Product area:** Reusable workspace launch  
**Implementation approval:** Final concept and staged-loop approval granted by Jordan on 2026-08-01  
**Implementation plan:** [`../plans/2026-07-31-native-bessie-projects.md`](../plans/2026-07-31-native-bessie-projects.md)

## Outcome

A person can define a reusable project—folder, tabs, pane layout, labels, and reviewed startup commands—and open it as ordinary Herdr-owned workspace state from Bessie.

## Why this exists

Projects create a repeat-use loop that neither a plain terminal launcher nor Bessie's current live-workspace browser provides:

> Open Bessie → choose a Project → get the complete working environment.

The recipe is Bessie-native product configuration. The resulting workspace is always ordinary Herdr.

## First useful release

- Native versioned project model and local storage.
- Searchable catalog with create, edit, preview, duplicate, archive, and confirmed delete.
- Local folder picker and graphical tab/pane layout editor.
- Exact startup-command review before launch.
- Materialization through public Herdr workspace, tab, pane, and input APIs.
- Exact returned-ID tracking, fresh-snapshot verification, and partial-workspace recovery.
- Save an authoritatively observable live workspace shape as a reviewed project draft.

## Product boundary

- Bessie owns recipes, catalog state, editor drafts, previews, and launch orchestration.
- Herdr owns every live workspace, tab, pane, terminal, process, agent, and durable session fact.
- Recipes never persist live Herdr IDs or terminal/process state.
- Herdr Plus is optional one-time migration prior art, not a runtime, plugin, format, storage, or synchronization dependency.
- Remote Projects, worktrees, secrets, shared repository recipes, and automatic live-workspace reconciliation are outside the first release.

## Dependency and risk

Projects follow the bundled-runtime/onboarding/Trouble release train so opening has one trustworthy local connection and recovery surface. Catalog and editing remain usable while disconnected.

Before implementation, Milestone 0 must prove exact creation-response IDs, authoritative cwd availability, and a headless public command-input readiness path. Bessie must not infer IDs from labels, parse shell prompts, or substitute arbitrary sleeps.

## Graduation criteria

Before implementation approval, complete the contract spike and explicitly approve local-only launch, reviewed command execution, deferred Herdr Plus import, and non-destructive partial-failure behavior.
