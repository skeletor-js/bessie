# Design-system capabilities and customization

**Status:** Approved  
**Roadmap horizon:** V1 (Dark/Light, density, cowprint on/off; **achromatic light** locked 2026-08-03)  
**Product area:** Appearance, interaction, and settings  
**Implementation approval:** Granted (Occam-locked 2026-08-02)  
**Execution:** [`../plans/2026-08-02-design-system-customization.md`](../plans/2026-08-02-design-system-customization.md) (I) · brand/chrome finish [`../plans/2026-08-03-brand-shell-and-chrome-hygiene.md`](../plans/2026-08-03-brand-shell-and-chrome-hygiene.md) (L)

## Outcome

Expose the useful parts of Bessie's design system as coherent native preferences without turning Settings into a token playground. Shipped light is **pure achromatic cowprint**, not warm paper.

## Why this exists

The design system demonstrates density, shape, elevation, state indicators, pane borders/gaps, motion, key maps, notification policy, and owner-aware settings. Live review showed light cream drift and chrome noise — L finishes identity; I owns theme prefs.

## First useful slice

- Dark/Light cowprint (achromatic light ladder).
- Density and pane gap modes where they improve readability.
- Cowprint texture on/off; Reduce Motion across cowprint and transitions.
- Continuous top bar with main plate (no grey slab).

## Possible later scope

- Advanced custom Bessie themes: user-authored semantic app and terminal token
  values, accessibility and syntax validation, live preview, reset, and
  import/export. Define the file format only when this work is approved.
- Key-map export/import and reset (not V1 required).
- Notification matrix and quiet hours.
- Window and workspace defaults.
- Shape, elevation, and state-indicator alternatives only after user evidence.

## Sources of truth and dependencies

Native preferences and keyboard routing; Herdr-owned bindings require read-only capability/configuration contracts. Brand prose: workstream `source-material/design-system/readme.md`. Jordan decisions 17–20 in workstream `DECISIONS.md`.

Bessie must preserve Herdr as the authority for sessions, panes, processes, agents, and durable session state.

## Principal risks

- Preference sprawl increases testing combinations and visual inconsistency.
- Shortcut remapping must not steal terminal input or create inaccessible conflicts.
- Light shell vs dark terminal contrast — keep terminal plate independent if needed.

## Open questions

- Compact density floor for gaps (see L: cardGap ≥ 6, paneGap ≥ 5).

## Graduation criteria

I: theme switch + density + cowprint toggle. L: brand checklist on re-capture.
