# Cost and usage

**Status:** Permanently deferred  
**Roadmap horizon:** Not planned  
**Product area:** Usage telemetry  
**Implementation approval:** Permanently withheld by product decision (2026-08-04)  
**Plan:** [`docs/plans/2026-08-04-003-feat-cost-and-usage-screen-plan.md`](../plans/2026-08-04-003-feat-cost-and-usage-screen-plan.md)  
**Research:** [`docs/research/2026-08-04-cost-and-usage-codexbar-scope.md`](../research/2026-08-04-cost-and-usage-codexbar-scope.md)

## Decision

Cost and usage is not part of Bessie's planned product roadmap. Do not schedule, prototype, feature-flag, or implement the local-estimate precursor or the fuller telemetry concept. This document, its plan, and its research remain only as retained rationale; re-entry requires Jordan to explicitly reverse this decision.

## Outcome

Show trustworthy agent and provider usage context without pretending Bessie is the billing authority.

## Why this exists

The mockup contains token, cost, elapsed-time, provider, ceiling, forecast, and export views.

## Retained concept (not planned)

The previously proposed precursor was:

- Feature-flagged Cost & usage / local-estimates screen with honest empty, partial, and stale states.
- Codex + Claude **local session** token totals on **this Mac only**, with source + confidence + pricing-coverage labels.
- API list-rate **estimated** cost only — never invoice or quota claims.
- Borrow CodexBar scanner/confidence ideas under MIT; do **not** vendor CodexBar or lead with OAuth quota scraping.

**Previously envisioned full slice (not planned; would have required U01):**

- Trusted per-agent/backend usage ingestion (Herdr/companion correlation IDs).
- Today/week/month totals joined to agents and workspaces (including remote).
- Provider-reported quota windows only after defensible per-provider contracts.
- Label provider-reported, estimated, and unavailable values distinctly.

## Previously considered later scope

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

## Re-entry criteria

There is no ordinary graduation path. Only an explicit product decision from Jordan can return cost and usage to exploration.
