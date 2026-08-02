# Search the Herd

**Status:** Exploring  
**Roadmap horizon:** Post-V1  
**Product area:** Cross-agent search  
**Implementation approval:** Not granted by this document

## Outcome

Find relevant terminal, file, plan, and prompt context across the current Herdr session and jump to the exact source.

## Why this exists

The exploration proposes one scoped, filterable search across all agent panes rather than command-only search.

## First useful slice

- Establish a versioned current-session scrollback search source.
- Search by text with agent/workspace scope, regex, and case controls.
- Group results by agent and show timestamps and snippets.
- Jump to the exact pane and location when supported.

## Possible later scope

- Saved searches and time ranges.
- File, prompt, plan, and tool result types.
- Historical search after durable event/storage contracts exist.

## Sources of truth and dependencies

Herdr-side search/index or a companion index; Bessie must not silently become a durable shadow session archive.

Bessie must preserve Herdr as the authority for sessions, panes, processes, agents, and durable session state. Any additional owner—filesystem, Git, agent integration, companion plugin, or provider—must be named explicitly in the eventual implementation plan.

## Principal risks

- Search indexes can persist secrets and large amounts of terminal output.
- Approximate jumps erode trust if presented as exact.

## Open questions

- What data may be indexed and for how long?
- Should saved searches store only queries or also result snapshots?

## Graduation criteria

Before this idea becomes **Proposed**, validate the first useful slice against the current Herdr contracts, identify local and remote behavior, define failure and empty states, and split any high-risk side effects into separately approved milestones.
