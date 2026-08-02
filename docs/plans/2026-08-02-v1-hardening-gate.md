# V1 integrated hardening and notarization gate — execution plan (ce-plan)

**Date:** 2026-08-02
**Status:** Implementation-ready as **release gate** (last)
**V1 slice:** K
**Branch:** release branch / main RC only after features merge
**Goal-loop ready:** Yes as checklist-driven Mac loop — not feature invent

## 1. Outcome

Public V1 candidate is installable and trustworthy:

1. `./scripts/check.sh` green
2. `./scripts/mac-verify.sh` green
3. Signed + notarized app (Jordan credentials)
4. Clean-machine style path: install → first terminal → Project open → Herd/Attention → Follow/files local → notification click → quit survive → relaunch
5. Controlled Trouble failure still understandable
6. No Deferred features required

## 2. Pre-req

All slices D–J accepted or explicitly waived by Jordan.

## 3. Clean-machine checklist

1. Install Bessie.app from packaged artifact
2. No system Herdr required (bundled runtime)
3. Onboarding → real terminal
4. Create/open Project
5. Launch agent; see Herd card; Needs you filter works when blocked
6. Attention Open pane works
7. Follow files shows touch on local edit
8. Markdown save + image preview
9. Notification click routes
10. Appearance light/dark + density + cowprint toggle
11. SSH connection if available; labels show
12. ⌘Q quit; processes survive; relaunch attaches
13. Ordinary `herdr` CLI attach still works
14. Notarization staple + Gatekeeper open

## 4. Evidence

Fill release report under `docs/reports/YYYY-MM-DD-v1-rc.md` with versions, checksums, notarization id, checklist Pass/Fail.

## 5. Pause

Notary account, signing identity, or Herdr redistribution rights → Jordan only.

## 6. Non-goals

Feature development; menu bar item; search.
