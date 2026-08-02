# Layout presets and workspace navigation

**Status:** Deferred
**Roadmap horizon:** Deferred (2026-08-02)
**Product area:** Workspace
**Implementation approval:** Not granted
**Deferred reason:** Jordan occam-loop — Projects already capture layouts; presets are convenience.

## Outcome

Make common pane arrangements and cross-workspace movement faster without introducing a shadow layout model.

## Why this exists

The design adds Even, Main + stack, pane-number badges, shortcut hints, richer pane headers, and navigation to agents elsewhere.

## First useful slice

- Add Even and Main + stack presets by issuing ordinary Herdr resize actions.
- Add pane-number badges and direct selection affordances.
- Add a held-shortcut hint overlay.
- Add clearer tab-level state rollups.

## Possible later scope

- Rich pane headers with process, agent, dimensions, state, and host.
- Agents-elsewhere quick navigation.
- Recipe access after recipes exist.

## Sources of truth and dependencies

Current pane topology, resize, focus, and agent projections.

Bessie must preserve Herdr as the authority for sessions, panes, processes, agents, and durable session state. Any additional owner—filesystem, Git, agent integration, companion plugin, or provider—must be named explicitly in the eventual implementation plan.

## Principal risks

- Presets must converge through Herdr rather than persist private split ratios.
- Extra pane chrome can reduce terminal space.

## Open questions

- Should presets affect one tab or an entire workspace?
- How should presets behave when another client changes layout concurrently?

## Graduation criteria

Before this idea becomes **Proposed**, validate the first useful slice against the current Herdr contracts, identify local and remote behavior, define failure and empty states, and split any high-risk side effects into separately approved milestones.
