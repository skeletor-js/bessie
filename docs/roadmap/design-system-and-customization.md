# Design-system capabilities and customization

**Status:** Approved
**Roadmap horizon:** V1 (Dark/Light, density, cowprint on/off)
**Product area:** Appearance, interaction, and settings
**Implementation approval:** Granted (Occam-locked 2026-08-02)

## Outcome

Expose the useful parts of Bessie's design system as coherent native preferences without turning Settings into a token playground.

## Why this exists

The design system demonstrates density, shape, elevation, state indicators, pane borders/gaps, motion, key maps, notification policy, and owner-aware settings.

## First useful slice

- Add density and pane border/gap modes where they improve readability.
- Complete Reduce Motion behavior across cowprint and transitions.
- Provide a coherent remappable shortcut/key-map editor with conflict detection.
- Show whether a setting is Bessie-owned or Herdr-owned.

## Possible later scope

- Key-map export/import and reset.
- Notification matrix and quiet hours.
- Window and workspace defaults.
- Shape, elevation, and state-indicator alternatives only after user evidence.

## Sources of truth and dependencies

Native preferences and keyboard routing; Herdr-owned bindings require read-only capability/configuration contracts.

Bessie must preserve Herdr as the authority for sessions, panes, processes, agents, and durable session state. Any additional owner—filesystem, Git, agent integration, companion plugin, or provider—must be named explicitly in the eventual implementation plan.

## Principal risks

- Preference sprawl increases testing combinations and visual inconsistency.
- Shortcut remapping must not steal terminal input or create inaccessible conflicts.

## Open questions

- Which axes solve real accessibility or density needs?
- Should arbitrary shape/elevation controls remain internal design tools rather than product settings?

## Graduation criteria

Before this idea becomes **Proposed**, validate the first useful slice against the current Herdr contracts, identify local and remote behavior, define failure and empty states, and split any high-risk side effects into separately approved milestones.
