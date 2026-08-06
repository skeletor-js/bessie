# Broadcast

**Status:** Absorbed into Shepherd (2026-08-04)
**Roadmap horizon:** No independent feature; later Shepherd milestone
**Product area:** Shepherd multi-agent operations
**Implementation approval:** Not granted; governed by [`shepherd.md`](shepherd.md)

## Decision

Broadcast is no longer a standalone Bessie feature or surface. Its deliberate multi-target send capability belongs inside Shepherd's later targeting and routing milestone. This file is retained as source material; Shepherd owns sequencing, product boundaries, and eventual approval.

## Retained outcome

Through Shepherd, send one reviewed prompt to a deliberate set of real Herdr agent panes.

## Why this exists

The design treated broadcast as a second-wave orchestration tool with filters, exclusions, variables, and a dry run. A separate Broadcast destination would duplicate Shepherd's dispatch responsibility, so the safe core is retained under Shepherd instead.

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

## Re-entry criteria

This item does not graduate independently. Any implementation requires the corresponding Shepherd milestone to be separately approved and must preserve explicit target review, confirmation, and partial-failure reporting.
