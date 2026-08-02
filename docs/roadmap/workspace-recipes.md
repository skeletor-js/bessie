# Workspace recipes

**Status:** Superseded  
**Superseded on:** 2026-08-01  
**Replaced by:** [Native Bessie Projects](../plans/2026-07-31-native-bessie-projects.md)

## Decision history

This exploration proposed capturing and recreating Herdr workspace shapes, potentially through a Bessie companion plugin and portable TOML.

The product decision changed materially:

- Projects are now a native Bessie feature.
- Bessie owns versioned project recipe files, catalog CRUD, editing, previews, and materialization orchestration.
- Herdr still owns every resulting live workspace, tab, pane, terminal, process, and durable runtime fact.
- Native Projects use Bessie's versioned JSON model rather than Herdr Plus TOML.
- Herdr Plus is optional migration prior art, not a runtime, plugin, storage, or synchronization dependency.

Retain this document only as decision history. Do not implement it independently or use its companion-plugin ownership recommendation.
