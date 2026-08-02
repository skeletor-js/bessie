# Broadcast

**Status:** Deferred
**Roadmap horizon:** Deferred (2026-08-02)
**Product area:** Multi-agent operations
**Implementation approval:** Not granted by this document
**Deferred reason:** Jordan — not needed for current product direction; do not sequence.

## Outcome

Send one reviewed prompt or key operation to a deliberate set of real Herdr panes.

## Why this exists

The design treated broadcast as a second-wave orchestration tool with filters, exclusions, variables, and a dry run. That need is not current; park the plan.

## First useful slice

- Select explicit target panes or agents.
- Preview the exact per-pane operation and destination.
- Exclude blocked or incompatible targets.
- Send one prompt only after confirmation and report partial failures.

## Possible later scope

- State/workspace filters.
- Saved templates and per-target variables.
- Raw keys or commands.
- Interrupt-before-send orchestration.

## Sources of truth and dependencies

Current pane input actions make a narrow version possible; safe interruption and capability-aware prompts may need typed contracts.

Bessie must preserve Herdr as the authority for sessions, panes, processes, agents, and durable session state. Any additional owner—filesystem, Git, agent integration, companion plugin, or provider—must be named explicitly in the eventual implementation plan.

## Principal risks

- A small targeting error can disrupt many agents at once.
- Variables and raw keys increase destructive ambiguity.

## Open questions

- Is explicit target selection the only acceptable first release?
- Which operation types should never be broadcast?

## Graduation criteria

Before this idea becomes **Proposed**, validate the first useful slice against the current Herdr contracts, identify local and remote behavior, define failure and empty states, and split any high-risk side effects into separately approved milestones.
