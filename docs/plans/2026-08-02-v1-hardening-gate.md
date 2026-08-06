# V1 integrated hardening and notarization gate — execution plan (ce-plan)

**Date:** 2026-08-02
**Status:** Release gate (last), expanded by slice M acceptance/performance requirements
**V1 slice:** K
**Branch:** release branch / main RC only after features merge
**Goal-loop ready:** Yes as checklist-driven Mac loop — not feature invent

## 1. Outcome

Public V1 candidate is installable and trustworthy:

1. `./scripts/check.sh` green
2. `./scripts/mac-verify.sh` green
3. Signed + notarized app (Jordan credentials)
4. Clean-machine style path: install → first terminal → Project open → Herd/Needs you → Follow/files local → notification click → quit survive → relaunch
5. Controlled Trouble failure still understandable
6. No Deferred features required

## 2. Pre-req

All slices D–J plus L/M accepted or explicitly waived by Jordan. Slice M's performance budgets, public-protocol mouse support, 24-item evidence checklist, and stability soak are mandatory inputs to this gate.

## 3. Clean-machine checklist

1. Install Bessie.app from packaged artifact
2. No system Herdr required (bundled runtime)
3. Onboarding → real terminal
4. Create/open Project
5. Launch agent; see Herd card; Needs you filter works when blocked
6. No Attention destination exists; Herd Needs you shows connected blocked agents only and Open pane resolves the exact target
7. Follow files shows touch on local edit
8. Markdown save + image preview
9. Notification click routes
10. Appearance light/dark + density + cowprint toggle
11. SSH connection if available; labels show
12. ⌘Q quit; processes survive; relaunch attaches
13. Ordinary `herdr` CLI attach still works
14. Notarization staple + Gatekeeper open
15. Slice M feedback checklist: all 24 Pass/Waived with linked evidence
16. Startup and terminal latency report meets plan budgets or records explicit waivers
17. Mouse-aware TUI clicks work through negotiated public Herdr input
18. Multi-folder Project migration/launch and ordinary-Herdr attach work
19. Zen entry/exit preserves focus, reconnect behavior, and Herdr topology
20. Single-window enforcement: second launch/New Window activates the existing window
21. Preferences/connection/Project migration, interrupted migration, downgrade/rollback, and corruption recovery
22. SSH host-key, notification privacy, diagnostic redaction, and support-bundle preview checks
23. Terminal conformance matrix across modifiers, IME/Unicode, paste, selection/mouse, alternate screen, resize, cursor, focus, and representative TUIs
24. Live/stale/disconnected status cannot falsely count or display stale Needs you state
25. Destructive actions state exact process/topology impact and pass cascade/race tests
26. VoiceOver, keyboard navigation, Increase Contrast, Reduce Motion, and non-color status cues
27. CPU/memory/energy/scale budgets and overnight soak
28. Crash/relaunch reattach, stale-ID recovery, corrupted-config recovery, and partial Project materialization

## 4. Evidence

Fill release report under `docs/reports/YYYY-MM-DD-v1-rc.md` with versions, checksums, notarization id, checklist Pass/Fail.

## 5. Pause

Notary account, signing identity, or Herdr redistribution rights → Jordan only.

## 6. Non-goals

Feature development; menu bar item; search.
