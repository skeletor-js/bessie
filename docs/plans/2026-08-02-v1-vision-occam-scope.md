# Bessie V1 vision and Occam scope

**Date:** 2026-08-02
**Status:** Locked with Jordan after vision-quest + occam-loop
**Governs:** remaining V1 work in docs/plans and docs/roadmap

## Governing vision

Bessie makes a live Herdr session easier to see, shape, and leave running.

- Herdr owns live work; Bessie owns desktop presentation and honest affordances.
- Terminal stays primary for action; GUI is supervision and navigation.
- Honesty over completeness: no fake approve, no fake remote files, no IDE pretension.
- Local and remote agents may share one Herd, with clear connection ownership.
- Mac-native trust (quit, window) is product, not polish.

**Promise:** Open Bessie, get real Herdr work, know who needs you, see what the agent made, jump around, use normal Mac quit, leave work running.

**Refuses:** generic IDE, chat shell, phone remote, task manager, plugin host, shadow session DB, Search the Herd in V1.

## Locked remaining V1 features

### Keep

1. Production UI/UX cleanup — Cmd-Q/Quit, titlebar double-click zoom, shortcut ownership, chrome cull.
2. Richer Herd (bar B) — fix Needs-you/urgency/open pane; clearer cards (state, location, connection); simple filters; local+remote labels in one list.
3. Attention — Needs-you list + Open pane only. No snooze, no resolved-local history, no keyboard triage pack.
4. Follow files — touch list, follow latest, one baseline, pin, local-only honesty. Read-only supervision.
5. Workspace media and markdown viewer — images/video preview; markdown preview+edit+save; rename/move/delete with confirm. NOT a general code editor.
6. Notification polish — exact-pane deep links; shared urgency with Herd/Attention. Menu-bar status item DEFERRED.
7. Appearance — Dark/Light cowprint, density, cowprint texture on/off. No token playground.
8. Connection UX — unified Herd local+remote; connection labels on panes/agents; better settings and onboarding for connections; harden SSH. No multi-host fleet console product.
9. Integrated hardening and notarization gate.

### Deferred out of V1 (this pass)

- Search the Herd
- Menu-bar Herd status item (notifications stay)
- Layout presets
- Entity-aware command palette
- Agent detail + prompt composer
- New Agent launch flow
- Zen mode
- Broadcast
- Worktrees
- In-app browser (Proposed)
- Shepherd (Proposed)
- General code editing beyond markdown

## Build order

D Production polish -> E Herd B + Attention thin -> F Follow files + media/markdown viewer -> G Notification polish -> I Appearance -> J Connection UX / remote labels -> K Notarized gate

## Already complete

- Bundled runtime, onboarding, Trouble (implementation)
- Native Bessie Projects (V1 scope)
