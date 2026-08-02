# Zen mode

**Status:** Exploring  
**Roadmap horizon:** Post-V1  
**Product area:** Workspace focus  
**Implementation approval:** Not granted by this document

## Outcome

Offer a nearly chrome-free real terminal while preserving awareness of the rest of the herd.

## Why this exists

Pane zoom exists, but the design proposes a distinct focus presentation with a tiny herd spine and cross-agent cues.

## First useful slice

- Hide nonessential chrome around the selected libghostty pane.
- Show a minimal status line and herd-state dots.
- Add exit, next-agent, and next-attention shortcuts.
- Route completion cues without stealing terminal focus.

## Possible later scope

- Blocked-state cues that remain answerable in the terminal.
- Per-user persistence of Zen presentation preference.

## Sources of truth and dependencies

Existing pane zoom, notifications, agent projection, and keyboard routing.

Bessie must preserve Herdr as the authority for sessions, panes, processes, agents, and durable session state. Any additional owner—filesystem, Git, agent integration, companion plugin, or provider—must be named explicitly in the eventual implementation plan.

## Principal risks

- Hidden chrome can make ownership and observe mode unclear.
- Global shortcuts must not steal ordinary terminal input.

## Open questions

- Is Zen a stronger zoom state or an independent workspace mode?
- Which status facts are essential enough to remain visible?

## Graduation criteria

Before this idea becomes **Proposed**, validate the first useful slice against the current Herdr contracts, identify local and remote behavior, define failure and empty states, and split any high-risk side effects into separately approved milestones.
