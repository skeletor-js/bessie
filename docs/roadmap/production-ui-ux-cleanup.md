# Production UI/UX cleanup

**Status:** Approved (Mac polish integrated; **brand chrome remainder → slice L**)
**Roadmap horizon:** V1
**Product area:** App shell, windowing, menus, chrome hygiene
**Implementation approval:** Granted by Jordan on 2026-08-02 as part of the expanded V1 release contract
**Execution:** Mac quit/zoom/keys — [`../plans/2026-08-02-production-ui-ux-cleanup.md`](../plans/2026-08-02-production-ui-ux-cleanup.md) (D).
**Brand/visual chrome** — [`../plans/2026-08-03-brand-shell-and-chrome-hygiene.md`](../plans/2026-08-03-brand-shell-and-chrome-hygiene.md) (L).

## Outcome

Make Bessie behave like a normal production Mac app **and** look like finished cowprint Bessie: standard window/quit, predictable shortcuts, no prototype chrome, and identity-correct light/dark surfaces.

## Why this exists

Foundation preview had desktop-polish gaps (⌘Q, title-bar zoom). Separate live-app review found brand drift (cream light, grey top bar, badge shout, full-bleed Trouble). D owns Mac behavior; L owns visual hygiene.

## Product boundary (V1)

### In scope (D)

- Quit paths; title-bar zoom; shortcut ownership; dead prototype cull.

### In scope (L)

- Achromatic light; cowprint on light; continuous top bar; gaps; case/badges/controls; empties; onboarding/Trouble restyle; workspace pane chrome.

### Out of scope

- Full design-token playground.
- Deferred product surfaces (menu bar item, entity palette, graphical approve, etc.). Bounded Zen is owned by slice M rather than this cleanup card.
- Changing Herdr lifecycle on quit.

## Acceptance

D: quit/zoom/keys evidenced.
L: brand checklist on 14-surface re-capture.
Together: primary paths feel production-ready before K.
