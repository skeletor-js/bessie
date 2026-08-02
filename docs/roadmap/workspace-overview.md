# Richer workspace overview

**Status:** Exploring  
**Roadmap horizon:** Post-V1  
**Product area:** Workspaces  
**Implementation approval:** Not granted by this document

## Outcome

Make workspaces legible as live Herdr environments rather than only names and topology counts.

## Why this exists

The designs distinguish attached, detached, observed, recent, and remote workspaces and expose runtime and agent health at a glance.

## First useful slice

- Group attached, detached, and locally recent workspaces.
- Expose attach, detach, observe, open, and Open in Herdr actions where supported.
- Add last-output and agent-state rollups.
- Show runtime version, health, and latency.

## Possible later scope

- Concurrent-client visibility.
- Remote groups.
- Save-current-layout entry point.
- Copy attach commands.

## Sources of truth and dependencies

Herdr session and client metadata; remote grouping follows the connection manager.

Bessie must preserve Herdr as the authority for sessions, panes, processes, agents, and durable session state. Any additional owner—filesystem, Git, agent integration, companion plugin, or provider—must be named explicitly in the eventual implementation plan.

## Principal risks

- Client-local recents must not look like durable Herdr workspaces.
- Detach semantics must not terminate processes.

## Open questions

- What does detached mean in the public Herdr model?
- Which workspace facts belong in cards versus the session manager?

## Graduation criteria

Before this idea becomes **Proposed**, validate the first useful slice against the current Herdr contracts, identify local and remote behavior, define failure and empty states, and split any high-risk side effects into separately approved milestones.
