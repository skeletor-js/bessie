# Trouble and diagnostics

**Status:** Approved  
**Roadmap horizon:** V1  
**Product area:** Diagnostics  
**Implementation approval:** Granted by Jordan on 2026-08-01 through the V1 release decision  
**Release train:** [`../plans/2026-08-01-bundled-herdr-runtime-setup.md`](../plans/2026-08-01-bundled-herdr-runtime-setup.md)

## Outcome

Give users one trustworthy place to understand connection, runtime, controller, and pane failures.

## Why this exists

Recovery exists today, but it is distributed across banners, logs, and controller behavior rather than assembled into an explainable diagnostic surface.

## First useful slice

- Add a dedicated Trouble destination.
- Show connection state, retry progress, and manual retry.
- Expose copy/open actions for Bessie and Herdr logs.
- Show stale/read-only state and authoritative capability facts.

## Possible later scope

- Per-pane controller and process health.
- Resume, reattach, restart, nudge, or interrupt where typed.
- Causal incident narratives assembled only from known facts.
- Self-checks with actionable repairs.

## Sources of truth and dependencies

Current connection lifecycle and diagnostics for the first slice; richer process/controller facts may need Herdr changes.

Bessie must preserve Herdr as the authority for sessions, panes, processes, agents, and durable session state. Any additional owner—filesystem, Git, agent integration, companion plugin, or provider—must be named explicitly in the eventual implementation plan.

## Principal risks

- Overconfident diagnosis is worse than an honest unknown.
- Logs may contain paths or sensitive terminal context.

## Open questions

- Which health facts are authoritative in Herdr 0.7.5?
- What diagnostic bundle is safe to copy or export by default?

## Graduation criteria

Before this idea becomes **Proposed**, validate the first useful slice against the current Herdr contracts, identify local and remote behavior, define failure and empty states, and split any high-risk side effects into separately approved milestones.
