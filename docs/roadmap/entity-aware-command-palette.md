# Entity-aware command palette

**Status:** First entity and Project-launch slice implemented under the 2026-08-04 UI redesign amendment
**Roadmap horizon:** Pre-v1
**Product area:** Command palette
**Implementation approval:** Granted by [`../plans/2026-08-04-001-feat-pre-v1-ui-redesign-plan.md`](../plans/2026-08-04-001-feat-pre-v1-ui-redesign-plan.md) U6/U12.

## Outcome

Turn the existing palette into a universal navigator for live Bessie and Herdr entities.

## Why this exists

The current palette searches commands; the mockup also searches agents, panes, workspaces, attention items, scrollback, and future workflow entities.

## Shipped entity slice

- Index panes, workspaces, Projects, herds, and commands from fresh authoritative projections.
- Show typed state, provider, health, freshness, and location metadata with deterministic ranking.
- Focus or open live entities directly. Project results use the canonical Project launch flow, including launch review when commands require it.
- Keep Project management explicit: only the **Manage projects** command opens the Projects catalog.
- Preserve explicit confirmation and command-dispatch paths for actions.

Typed prompt and interrupt actions remain parked. They require capability-gated action IDs,
labels, payloads, and scope, and the roadmap requires high-risk side effects to land as a
separately approved milestone rather than being inferred by the navigation palette.

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
