# Bessie 0.1.0 release-candidate Mac verification

Date: 2026-07-31

Candidate: `v0.1.0-rc.1`

## Result

The Mac-testable V1 stop condition is met. The packaged app is at:

`/Users/jordanstella/GitHub/bessie/dist/Bessie.app`

The final verifier run launched that app against an isolated repository-local Herdr 0.7.5 server, exercised the live terminal and topology paths, captured the native window, and cleaned up only the processes it started.

## Commands and results

Run from `/home/hermes/code/bessie`:

```bash
./scripts/check.sh
./scripts/mac-verify.sh
git diff --check
```

Final results:

- `check.sh`: exit 0; shell/static contract checks passed. Swift is intentionally unavailable on the VPS.
- `BESSIE_AGENT_KIND=codex ./scripts/mac-verify.sh`: exit 0 on `jordan-macbook` using Apple Swift 6.3.3.
- Swift tests: 50 executed, 0 failures.
- Debug build and production `BessieApp` build: passed without reported warnings.
- Packaging: `dist/Bessie.app` produced; plist validation and strict ad-hoc signature verification passed.
- Packaged executable: 12,937,200 bytes in the final checked artifact; SHA-256 `21ed77d17750ad85547ae11260d707fe965ac06a8a9a4be195d8a79415ee00f9`.
- `git diff --check`: passed.
- Final process check: no packaged Bessie process, repository-local Herdr server, or Bessie terminal-controller process remained.

The verifier downloaded official Herdr 0.7.5 only to the Mac mirror's `.local/herdr/herdr` when needed and required SHA-256 `37350546b0012555943b92eaf962665de4e264395baeb44227b8015e8ff5b0d6`. It used unique repository-local config/state directories and never reused or stopped another Herdr server.

## Exercised acceptance criteria

- Runtime discovery, Herdr 0.7.5/protocol-17 compatibility, public socket ping, subscribe-before-snapshot bootstrap, event invalidation, snapshot reconciliation, bounded retry, isolated server restart, and reconnect.
- The retained Bessie rail and high-fidelity product surfaces: The herd, Attention, Workspaces, active workspace, Agent Detail, Settings, Connect, and New pane. Herd and Agent Detail consume real Herdr pane/state metadata; the detail terminal and prompt composer use the same live libghostty/controller path rather than mock content.
- Model decoding, NDJSON framing, response correlation/errors, recursive layouts, focus fallback, close confirmation, presentation persistence, and every V1 public action envelope.
- Live workspace create, rename, move, focus, and close; tab create, rename, move, focus, and close; pane split, rename, focus, resize, explicit split ratio, swap, zoom, move, and close. Client-originated actions reconciled from Herdr snapshots; public CLI mutations converged into the already-running app.
- Two distinct visible Herdr panes, each rendered by `GhosttyTerminal` through `InMemoryTerminalSession`, with explicit control and observe modes and no implicit takeover. Read-only observe rejects input; takeover is a separate confirmed action.
- Full-frame gating, contiguous deltas, Unicode raw input, intercepted Enter, paste, scroll, resize, controller ownership conflict, bounded reconnect, forced controller recovery, and observable public `herdr pane read` markers.
- App-driven shell creation through New pane, followed by a live libghostty controller and public pane-read proof.
- Quitting Bessie released its controllers while both Herdr panes and their output survived. Reopening reacquired fresh controllers. Closing the test workspace released them without terminating unrelated processes.
- Public `server.agent_manifests` discovery, PATH-backed availability reasons, semantic names, exact `agent.start` request construction, and shell retention after fixture-driven agent-start failure. The app also started the installed `codex` executable through real Herdr 0.7.5, observed its `idle` semantic state without sending a model prompt, quit, and reopened onto the surviving agent pane.
- Pane movement choices derive from authoritative topology. Workspace cards and tabs expose native drag reorder, and split dividers provide live resize previews that commit public `workspace.move`, `tab.move`, and `layout.set_split_ratio` actions. Pure mapping and clamping behavior is covered by focused tests; the native controls compiled in the packaged app and the divider was visually reviewed in the live split grid.
- Notification planning covers needs-you/done transitions, initial-snapshot suppression, deduplication, active-pane suppression, and exact workspace/tab/pane routing. Permission is requested only by the explicit Settings action.
- Native 1180 x 740 app-owned PNG captures at `/Users/jordanstella/GitHub/bessie/dist/Bessie-window.png` and `Bessie-settings.png`. Visual inspection confirmed the retained dark Bessie shell, supplied cow logo, visible ASCII cowprint field, clean draggable split divider, two distinct terminal viewports, readable notification controls, and no clipping or overlapping content.
- A native AppKit screenshot guard rejected light/warm regressions, missing cowprint, and undersized system thumbnails. The final Workspace capture measured rail luminance `11.34`, dark-pixel cowprint standard deviation `3.35`, and mean chroma `0.00`; Settings measured `13.41`, `4.08`, and `0.00` respectively.

## Design-system fidelity

The packaged application—not a separate HTML mock—uses native SwiftUI/AppKit primitives derived from the retained Bessie desktop kit. It ships the supplied `BessieLogo.svg` and `CowprintTile.png` inside `Bessie_BessieApp.bundle`; both resources were loaded by the running app during capture. The shell uses the retained 244pt rail, 46pt topbar, 36pt tabs, thin pane headers, 9pt card gaps, monochrome state vocabulary, flat charcoal surfaces, compact monospaced metadata, and 26pt status line. Connect, The herd, Workspaces, active workspace, Attention, Agent Detail, Settings, and New pane share those primitives and screen-specific cowprint crops.

`scripts/check.sh` guards the required resources and structural design tokens. `scripts/verify-design-snapshot.swift`, called by `mac-verify.sh`, checks the actual packaged-window PNG for the dark monochrome palette and measurable ASCII cowprint variance so a return to the earlier generic warm shell fails verification.

## UI copy acceptance

- Inventoried 387 Swift string literals in `Sources/BessieApp`; 295 were mechanically flagged as likely UI-facing and manually reviewed in context. Three independent read-only audits covered reachable app copy, the retained UI kit's product voice, and senior UX-writing concerns.
- Removed visible planning and implementation residue, including alpha framing, public-protocol narration, shadow-model explanations, mock shortcuts, unavailable-layout copy, empty Trace/History/Provenance panels, and deferred-notification placeholder copy.
- Reworked connection, recovery, navigation, The herd, Workspaces, active workspace, Agent Detail, Attention, New pane, Settings, errors, close confirmations, empty states, and accessibility labels around current state, consequence, or next action.
- The primary rail now shows The herd, Attention, Workspaces, and Settings. Active workspaces live under `OPEN`; the duplicate static `Workspace` item was removed. Attention uses a rendered bell symbol.
- The empty herd hides meaningless counts and filters, says `No agents running`, and offers one `New agent` action. The New pane shell sheet contracts to 760 x 360 while agent mode retains the taller catalog layout.
- `scripts/check-ui-copy.sh`, called by `scripts/check.sh`, rejects known planning/explanatory residue and requires the accepted product vocabulary. The final humanizer scan reported 0 findings.
- Captured and visually inspected Connect, active workspace, Workspaces, Attention, Settings, New pane, The herd, and Agent Detail. The seven full-window captures were 1180 x 740; New pane was 760 x 360. No clipped copy, missing symbol, light-system artifact, redundant static Workspace navigation item, or blocking layout defect remained.

## Known limitations

- The verifier does not grant macOS notification permission or manufacture system delivery. A user must choose **Allow notifications** in Settings; delivery then remains subject to macOS authorization and notification settings.
- V1 intentionally excludes remote/multiple runtime endpoints, graphical approval inference, inner-application mouse reporting, focus reporting, Kitty keyboard protocol support, worktrees, plugins, generic IDE surfaces, Rust FFI, notarization, and publishing.

## Reproduce, inspect, and clean up

The supported one-path run is documented in `README.md` and is:

```bash
cd /home/hermes/code/bessie
./scripts/check.sh
./scripts/mac-verify.sh
```

The verifier syncs to the intentional Mac mirror without `rsync --delete`, packages and launches the app, performs live checks, writes the screenshot, then stops only the exact Bessie and isolated Herdr PIDs it started. It does not leave a test session running.

To inspect the packaged artifact after verification:

```bash
ssh jordan-macbook 'open -na /Users/jordanstella/GitHub/bessie/dist/Bessie.app'
```

Without a compatible local Herdr server, the reopened app correctly shows Connect/setup state. Rerun `mac-verify.sh` for the complete connected live exercise.

If a failed run ever leaves a process, inspect before stopping anything:

```bash
ssh jordan-macbook 'pgrep -af "/Users/jordanstella/GitHub/bessie/(dist/Bessie.app/Contents/MacOS/BessieApp|.local/herdr/herdr)"'
```

Only stop a PID after its full command points inside `/Users/jordanstella/GitHub/bessie`. Do not use broad `pkill herdr` commands because they could affect unrelated sessions.
