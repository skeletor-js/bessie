# Attention queue and resolution

**Status:** Exploring  
**Roadmap horizon:** Post-V1  
**Product area:** Attention  
**Implementation approval:** Not granted by this document

## Outcome

Make attention items triageable and resolvable while preserving the real terminal as the universal fallback.

## Why this exists

The current surface safely opens blocked and completed panes, but the designs include history, snoozing, structured questions, failures, and typed resolution.

## First useful slice

- Add Open, Resolved, and All presentation views for locally observed items.
- Add age, count, seen/dismiss, and snooze presentation state.
- Add keyboard navigation and next-attention routing.
- Add a zoomed attention mode around the exact real terminal.

## Possible later scope

- Structured questions and suggested answers.
- Failure classification and retry actions.
- Completion review cards.
- Typed allow-once, allow-for-session, and deny actions.

## Sources of truth and dependencies

Native presentation work can ship first; durable history and graphical resolution require typed upstream event and action contracts.

Bessie must preserve Herdr as the authority for sessions, panes, processes, agents, and durable session state. Any additional owner—filesystem, Git, agent integration, companion plugin, or provider—must be named explicitly in the eventual implementation plan.

## Principal risks

- Screen scraping approvals would be unsafe.
- Client-local resolved state can disagree with another client unless clearly labeled.

## Open questions

- Which presentation state is useful before durable event IDs exist?
- What exact provenance must accompany every graphical action?

## Graduation criteria

Before this idea becomes **Proposed**, validate the first useful slice against the current Herdr contracts, identify local and remote behavior, define failure and empty states, and split any high-risk side effects into separately approved milestones.
