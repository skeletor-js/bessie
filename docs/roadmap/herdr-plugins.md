# Herdr plugins

**Status:** Exploring  
**Roadmap horizon:** Post-V1  
**Product area:** Plugins  
**Implementation approval:** Not granted by this document

## Outcome

Show which Herdr plugins are installed and how their capabilities map into Bessie without hosting a second plugin system.

## Why this exists

The exploration includes plugin inventory, capability mapping, handoff to Herdr configuration, and a Bessie companion-plugin status surface.

## First useful slice

- Define or consume a public plugin capability manifest.
- List installed plugins, versions, state, and descriptions.
- Map known capabilities to Bessie surfaces or disclose no surface.
- Open configuration in the owning Herdr flow.

## Possible later scope

- Companion-plugin setup and health checks.
- Enable/disable handoffs.
- Optional discovery catalog if Herdr eventually owns one.

## Sources of truth and dependencies

A Herdr plugin manifest and owner-specific configuration actions.

Bessie must preserve Herdr as the authority for sessions, panes, processes, agents, and durable session state. Any additional owner—filesystem, Git, agent integration, companion plugin, or provider—must be named explicitly in the eventual implementation plan.

## Principal risks

- Bessie must not become an alternate plugin host or registry.
- Enable/disable actions can affect all clients and require clear ownership.

## Open questions

- What companion capabilities justify a first plugin surface?
- Is a catalog useful without a Herdr-owned registry?

## Graduation criteria

Before this idea becomes **Proposed**, validate the first useful slice against the current Herdr contracts, identify local and remote behavior, define failure and empty states, and split any high-risk side effects into separately approved milestones.
