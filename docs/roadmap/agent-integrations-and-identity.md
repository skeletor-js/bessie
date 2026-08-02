# Agent integrations and identity

**Status:** Exploring  
**Roadmap horizon:** Post-V1  
**Product area:** Integrations  
**Implementation approval:** Not granted by this document

## Outcome

Explain how Herdr recognizes each agent, which features are trustworthy, and how to repair degraded integrations.

## Why this exists

The design distinguishes native integrations, hooks, manifests, process identity, and heuristics and exposes provenance and confidence.

## First useful slice

- List known agents with executable, version, and integration type.
- Show structured-state and action capabilities.
- Explain identity/state provenance when Herdr exposes it.
- Provide rescan and owner-specific setup/configuration handoffs.

## Possible later scope

- Confidence and degraded-heuristic explanations.
- Raw inference sample where safe.
- Per-agent notification rules.
- Misread reporting and correction loop.

## Sources of truth and dependencies

Herdr manifest and status provenance; some confidence and correction behavior needs upstream or companion support.

Bessie must preserve Herdr as the authority for sessions, panes, processes, agents, and durable session state. Any additional owner—filesystem, Git, agent integration, companion plugin, or provider—must be named explicitly in the eventual implementation plan.

## Principal risks

- Displaying a guessed identity as fact can route actions to the wrong process.
- Raw samples may expose sensitive terminal content.

## Open questions

- Which provenance fields are public today?
- Should Bessie ever display heuristic confidence numerically?

## Graduation criteria

Before this idea becomes **Proposed**, validate the first useful slice against the current Herdr contracts, identify local and remote behavior, define failure and empty states, and split any high-risk side effects into separately approved milestones.
