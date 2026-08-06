# Bessie V1 vision and Occam scope

**Date:** 2026-08-02
**Status:** Locked with Jordan after vision-quest + occam-loop
**Governs:** remaining V1 work in docs/plans and docs/roadmap

> **2026-08-04 amendment:** The Pre-v1 UI redesign plan supersedes this document's shell/onboarding visual direction and explicitly unparks the native menu-bar companion and entity-aware palette. Needs you / Working / Settled / Unknown is the canonical visible model; elapsed-age UI is intentionally absent.

## Governing vision

Bessie makes a live Herdr session easier to see, shape, and leave running.

- Herdr owns live work; Bessie owns desktop presentation and honest affordances.
- Terminal stays primary for action; GUI is supervision and navigation.
- Honesty over completeness: no fake approve / no graphical Allow without typed RPC, no fake remote files, no IDE pretension.
- Local and remote agents may share one Herd, with clear connection ownership.
- Mac-native trust (quit, window) is product, not polish.

**Promise:** Open Bessie, get real Herdr work, know who needs you, see what the agent made, jump around, use normal Mac quit, leave work running.

**Refuses (Mac V1):** generic IDE, chat shell, task manager, plugin host, shadow session DB, Search the Herd in V1.  
**Not Mac V1:** phone/iOS client — queued as **first post-V1 ship** (`2026-08-03-bessie-ios-control-plane.md`), not a Mac V1 surface.

## Locked remaining V1 features

### Keep

1. Production UI/UX cleanup — Cmd-Q/Quit, titlebar double-click zoom, shortcut ownership, chrome cull.
2. Richer Herd (bar B) — fix Needs-you/urgency/open pane; clearer cards (state, location, connection); simple filters; local+remote labels in one list.
3. Herd Needs you — blocked-only filter, count, blocked-first ordering, Open pane, and next-needs-you routing. No standalone Attention destination or history model.
4. Follow files — touch list, follow latest, one baseline, pin, local-only honesty. Read-only supervision.
5. Workspace media and markdown viewer — images/video preview; markdown preview+edit+save; rename/move/delete with confirm. NOT a general code editor.
6. Notification polish — exact-pane deep links; shared state language with Herd. Menu-bar status item DEFERRED.
7. Appearance — Dark/Light cowprint, density, cowprint texture on/off. No token playground. Light is pure achromatic cowprint (2026-08-03).
8. Connection UX — unified Herd local+remote; connection labels on panes/agents; better settings and onboarding for connections; harden SSH. No multi-host fleet console product.
9. Brand shell and chrome hygiene (slice L) — achromatic light finish, continuous top bar, gaps, case/badges/control quieting, zero-state copy, onboarding+Trouble restyle, workspace pane chrome. No new product surfaces. Plan: 2026-08-03-brand-shell-and-chrome-hygiene.md.
10. Bounded Zen — one real terminal with minimal Herd/connection cues and obvious exit.
11. Integrated hardening and notarization gate.

### Deferred out of V1 (this pass)

- Search the Herd
- Menu-bar Herd status item (notifications stay)
- Layout presets
- Entity-aware command palette
- Agent detail + prompt composer
- New Agent launch flow
- Worktrees
- In-app browser (Proposed)
- Shepherd (Proposed; owns any later reviewed broadcast capability)
- General code editing beyond markdown
- **Bessie iOS** (remote control plane) — **first post-V1 ship**, not Mac V1. Plan: `2026-08-03-bessie-ios-control-plane.md`

## Build order

D Production polish -> E Herd baseline -> F Follow files + media/markdown viewer -> G Notification polish -> I Appearance -> J Connection UX / remote labels -> L Brand shell / chrome hygiene -> M acceptance remediation including Herd consolidation + Zen -> K Notarized gate

## Already complete

- Bundled runtime, onboarding, Trouble (implementation)
- Native Bessie Projects (V1 scope)
