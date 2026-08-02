# Cost and usage

**Status:** Exploring  
**Roadmap horizon:** Post-V1  
**Product area:** Usage telemetry  
**Implementation approval:** Not granted by this document

## Outcome

Show trustworthy agent and provider usage context without pretending Bessie is the billing authority.

## Why this exists

The mockup contains token, cost, elapsed-time, provider, ceiling, forecast, and export views.

## First useful slice

- Define trusted per-agent/backend usage ingestion.
- Show today/week/month input and output totals.
- Break down by agent and workspace.
- Label provider-reported, estimated, and unavailable values distinctly.

## Possible later scope

- Tool-call and active/blocked/idle context.
- User-defined ceiling and forecast.
- CSV export.
- Carefully framed anomaly or repeated-read hints.

## Sources of truth and dependencies

Typed provider or agent telemetry through Herdr/companion contracts.

Bessie must preserve Herdr as the authority for sessions, panes, processes, agents, and durable session state. Any additional owner—filesystem, Git, agent integration, companion plugin, or provider—must be named explicitly in the eventual implementation plan.

## Principal risks

- Estimated costs can be wrong or omit discounts and cached tokens.
- Usage telemetry may expose sensitive project or model information.

## Open questions

- Which providers expose sufficiently reliable data?
- Should ceilings be advisory only, or ever affect agent behavior?

## Graduation criteria

Before this idea becomes **Proposed**, validate the first useful slice against the current Herdr contracts, identify local and remote behavior, define failure and empty states, and split any high-risk side effects into separately approved milestones.
