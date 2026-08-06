# Zen mode

**Status:** Approved for bounded V1 remediation
**Roadmap horizon:** V1 (promoted by Jordan 2026-08-02)
**Product area:** Workspace focus
**Implementation approval:** Granted as part of hands-on acceptance remediation
**Execution:** [`../plans/2026-08-03-v1-acceptance-remediation.md`](../plans/2026-08-03-v1-acceptance-remediation.md) §8.3

## Outcome

Offer a nearly chrome-free real terminal while preserving awareness of the rest of the herd.

## Why this exists

Pane zoom exists, but the design proposes a distinct focus presentation with a tiny herd spine and cross-agent cues.

## Bounded V1 slice

- Hide nonessential chrome around the selected real libghostty pane.
- Show a minimal connection/herd spine and blocked cue.
- Add exit, previous/next-agent, and next-attention commands.
- Route completion/blocked cues without stealing terminal focus.
- Preserve connection-loss and ownership-conflict recovery.

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

## V1 acceptance

Zen is presentation only: it creates no Herdr objects, changes no durable topology, never substitutes a terminal, and exits predictably through visible and keyboard paths. Live tests must cover focus, reconnect, blocked cues, shortcuts, and ordinary Herdr state before/after entry.
