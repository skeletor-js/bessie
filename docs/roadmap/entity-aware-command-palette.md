# Entity-aware command palette

**Status:** Exploring  
**Roadmap horizon:** Post-V1  
**Product area:** Command palette  
**Implementation approval:** Not granted by this document

## Outcome

Turn the existing palette into a universal navigator for live Bessie and Herdr entities.

## Why this exists

The current palette searches commands; the mockup also searches agents, panes, workspaces, attention items, scrollback, and future workflow entities.

## First useful slice

- Index current agents, panes, tabs, workspaces, and attention items.
- Show destination, state, and ownership metadata.
- Focus or open an entity directly.
- Offer context-safe actions such as prompt or interrupt when typed.

## Possible later scope

- Current-session scrollback snippets.
- Fill versus run command in a new pane.
- Worktree, recipe, plugin, plan, and file results as those features ship.

## Sources of truth and dependencies

Current Bessie projections for the first slice; scrollback and historical search require Herdr or companion support.

Bessie must preserve Herdr as the authority for sessions, panes, processes, agents, and durable session state. Any additional owner—filesystem, Git, agent integration, companion plugin, or provider—must be named explicitly in the eventual implementation plan.

## Principal risks

- A universal palette can become noisy without ranking and scope.
- Action results must not bypass confirmation rules.

## Open questions

- Should navigation and actions share one result list?
- What ranking favors urgent live entities without hiding exact command matches?

## Graduation criteria

Before this idea becomes **Proposed**, validate the first useful slice against the current Herdr contracts, identify local and remote behavior, define failure and empty states, and split any high-risk side effects into separately approved milestones.
