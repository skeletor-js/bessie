# Richer Herd dashboard

**Status:** Approved
**Roadmap horizon:** V1 (Occam bar B)
**Product area:** The Herd
**Implementation approval:** Granted (Occam-locked 2026-08-02)

## Outcome

Make the Herd the fastest place to understand every agent and take the next safe action.

## Why this exists

The current Herd has blocked-first ordering and state filters, but the design exploration treats it as a live operational dashboard rather than a directory of agents.

## First useful slice

- Add counts to the existing state filters.
- Add workspace/runtime filters and selectable sorting.
- Show bounded recent-output or last-event snippets.
- Expose safe state-specific actions: focus, prompt idle agent, interrupt where typed, and confirmed close.

## Possible later scope

- Seen/unseen completion presentation state.
- Branch, worktree, host, and runtime badges when authoritative.
- Compact and live-output density modes.

## Sources of truth and dependencies

Herdr snapshot and pane actions for core state; companion/upstream metadata for reliable branch, host, and richer event facts.

Bessie must preserve Herdr as the authority for sessions, panes, processes, agents, and durable session state. Any additional owner—filesystem, Git, agent integration, companion plugin, or provider—must be named explicitly in the eventual implementation plan.

## Principal risks

- Terminal snippets can leak sensitive output or become stale.
- Card actions must preserve the same confirmations and ownership rules as pane actions.

## Open questions

- Which actions belong directly on cards versus in an overflow menu?
- Should seen/unseen state remain client-local or wait for durable event IDs?

## Graduation criteria

Before this idea becomes **Proposed**, validate the first useful slice against the current Herdr contracts, identify local and remote behavior, define failure and empty states, and split any high-risk side effects into separately approved milestones.
