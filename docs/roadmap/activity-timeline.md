# Activity timeline

**Status:** Exploring  
**Roadmap horizon:** Post-V1  
**Product area:** History  
**Implementation approval:** Not granted by this document

## Outcome

Explain what happened across the herd while the user was away and route them to the next useful action.

## Why this exists

The design includes a durable event timeline, summaries, filters, seen state, and links to review or recovery.

## First useful slice

- Define the durable Herdr event contract required by the UI.
- Show a since-last-open summary and chronological event list.
- Filter completions, blocks, failures, and commits.
- Open the exact live or historical context when supported.

## Possible later scope

- Wait-time and change metrics.
- Mark all seen.
- Replay or historical pane-state navigation.
- Review, restart, inspect-rule, and Trouble actions.

## Sources of truth and dependencies

Durable ordered event IDs and history from Herdr or a versioned companion source.

Bessie must preserve Herdr as the authority for sessions, panes, processes, agents, and durable session state. Any additional owner—filesystem, Git, agent integration, companion plugin, or provider—must be named explicitly in the eventual implementation plan.

## Principal risks

- Bessie-only attachment history would provide an incomplete and misleading record.
- Historical terminal content has privacy and storage costs.

## Open questions

- Which events deserve durable retention?
- What does since last open mean across multiple Bessie clients?

## Graduation criteria

Before this idea becomes **Proposed**, validate the first useful slice against the current Herdr contracts, identify local and remote behavior, define failure and empty states, and split any high-risk side effects into separately approved milestones.
