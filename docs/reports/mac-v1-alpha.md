# Bessie 0.1.0 release-candidate Mac verification

Date: 2026-07-31

Candidate: `v0.1.0-rc.2`

## Result

The Mac-testable V1 stop condition is met. The packaged app is at:

`/Users/jordanstella/GitHub/bessie/dist/Bessie.app`

The final verifier run launched that app against an isolated repository-local Herdr 0.7.5 server, proved automatic detached startup of the named `bessie` session without touching `default`, exercised the live terminal and topology paths, captured the native windows, and cleaned up only the processes it started.

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
- Swift tests: 54 executed, 0 failures.
- Debug build and production `BessieApp` build: passed without reported warnings.
- Packaging: `dist/Bessie.app` produced as version `0.1.0` build `2` with dark and light icon resources; plist validation and strict ad-hoc signature verification passed.
- Packaged executable: 13,026,320 bytes; SHA-256 `faec204ea555946f6e8b8162b990e2d1f53808ceecde17f53d5fbd47eb401666`.
- Candidate archive: `dist/Bessie-0.1.0-rc.2.zip`, 7,752,137 bytes; SHA-256 `799efbd84a0622194e8c136ae98f12af2ee46261987e169216a050ddac5ff9f3`. Archive integrity, extraction, strict signature verification, default-icon metadata, and alternate-icon presence passed.
- `git diff --check`: passed.
- Verifier cleanup left no packaged test app, repository-local Herdr server, or test terminal controller running. The separately installed RC2 app and its user-owned named `bessie` session were then intentionally left running for hands-on acceptance.

The verifier downloaded official Herdr 0.7.5 only to the Mac mirror's `.local/herdr/herdr` when needed and required SHA-256 `37350546b0012555943b92eaf962665de4e264395baeb44227b8015e8ff5b0d6`. It used unique repository-local config/state directories and never reused or stopped another Herdr server.

## Exercised acceptance criteria

- Runtime discovery, Herdr 0.7.5/protocol-17 compatibility, automatic detached startup of an isolated named `bessie` session, healthy-server reuse, ownership-safe cleanup, readiness polling, public socket ping, subscribe-before-snapshot bootstrap, event invalidation, snapshot reconciliation, bounded retry, isolated server restart, and reconnect. The verifier also proved that the isolated `default` session remained stopped.
- The retained Bessie rail and high-fidelity product surfaces: The herd, Attention, Workspaces, active workspace, Agent Detail, Settings, Connect, and New pane. Herd and Agent Detail consume real Herdr pane/state metadata; the detail terminal and prompt composer use the same live libghostty/controller path rather than mock content.
- Model decoding, NDJSON framing, response correlation/errors, recursive layouts, focus fallback, close confirmation, presentation persistence, and every V1 public action envelope.
- Live workspace create, rename, move, focus, and close; tab create, rename, move, focus, and close; pane split, rename, focus, resize, explicit split ratio, swap, zoom, move, and close. Client-originated actions reconciled from Herdr snapshots; public CLI mutations converged into the already-running app.
- Two distinct visible Herdr panes, each rendered by `GhosttyTerminal` through `InMemoryTerminalSession`, with explicit control and observe modes and no implicit takeover. Read-only observe rejects input; takeover is a separate confirmed action.
- Full-frame gating, contiguous deltas, Unicode raw input, intercepted Enter, paste, scroll, resize, controller ownership conflict, bounded reconnect, forced controller recovery, and observable public `herdr pane read` markers.
- App-driven shell creation through New pane, followed by a live libghostty controller and public pane-read proof.
- Quitting Bessie released its controllers while both Herdr panes and their output survived. Reopening reacquired fresh controllers. Closing the test workspace released them without terminating unrelated processes.
- Public `server.agent_manifests` discovery, PATH-backed availability reasons, semantic names, exact `agent.start` request construction, bounded retry while a fresh pane reaches its interactive shell, and shell retention after non-transient agent-start failure. A controlled slow-shell reproduction returned `agent_pane_busy` immediately and succeeded after readiness; the repaired app then started installed `codex` through real Herdr 0.7.5, observed its `idle` semantic state without sending a model prompt, quit, and reopened onto the surviving agent pane.
- Pane movement choices derive from authoritative topology. Workspace cards and tabs expose native drag reorder, and split dividers provide live resize previews that commit public `workspace.move`, `tab.move`, and `layout.set_split_ratio` actions. Pure mapping and clamping behavior is covered by focused tests; the native controls compiled in the packaged app and the divider was visually reviewed in the live split grid.
- Notification planning covers needs-you/done transitions, initial-snapshot suppression, deduplication, active-pane suppression, and exact workspace/tab/pane routing. Permission is requested only by the explicit Settings action.
- The supplied dark desktop icon is the signed bundle default. A retained light-polarity alternate is selectable in Settings, persisted with presentation preferences, loaded from the packaged resource bundle, and reapplied to the Dock and app switcher on launch. Legacy preference files default to dark.
- Native 1180 x 740 app-owned PNG captures at `/Users/jordanstella/GitHub/bessie/dist/Bessie-window.png` and `Bessie-settings.png`. Visual inspection confirmed the retained dark Bessie shell, supplied cow logo, visible ASCII cowprint field, clean draggable split divider, two distinct terminal viewports, readable notification controls, and no clipping or overlapping content.
- A native AppKit screenshot guard rejected light/warm regressions, missing cowprint, and undersized system thumbnails. The final RC2 Workspace capture measured rail luminance `11.21`, dark-pixel cowprint standard deviation `3.19`, and mean chroma `0.00`; Settings measured `13.35`, `4.03`, and `0.00` respectively. The Settings review found the Appearance control legible, aligned, and unclipped.

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

## Installed candidate

- Verified RC2 is installed at `/Applications/Bessie.app` on `jordan-macbook` as version `0.1.0` build `2`; strict signature verification passed after installation.
- A normal LaunchServices start supplied no Herdr path, socket, session, or `PATH` override. Bessie found `/Users/jordanstella/.local/bin/herdr`, started Herdr 0.7.5/protocol 17 as a detached server for the named `bessie` session, and reached `Connected`.
- The global `default` Herdr session remained stopped. Quitting the diagnostic app left the compatible `bessie` server running, proving shells and agents are not tied to Bessie's process lifetime.
- Bessie was reopened normally and intentionally left running for Jordan's hands-on acceptance test.

## Known limitations

- The verifier does not grant macOS notification permission or manufacture system delivery. A user must choose **Allow notifications** in Settings; delivery then remains subject to macOS authorization and notification settings.
- Runtime icon selection changes the Dock and app switcher icon. Finder continues to show the signed bundle's dark default.
- V1 intentionally excludes graphical remote/multiple runtime endpoints, graphical approval inference, inner-application mouse reporting, focus reporting, Kitty keyboard protocol support, worktrees, plugins, generic IDE surfaces, Rust FFI, notarization, and public publishing. Remote terminal access remains available through `herdr --remote <ssh-host> --session bessie`; Bessie should not ship remote UI until Herdr provides a headless bridge for both API and terminal-control sockets.

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

Without a compatible running `bessie` server, the reopened app locates Herdr, starts that named session in the background, waits for readiness, and connects automatically. Rerun `mac-verify.sh` for the complete isolated live exercise.

If a failed run ever leaves a process, inspect before stopping anything:

```bash
ssh jordan-macbook 'pgrep -af "/Users/jordanstella/GitHub/bessie/(dist/Bessie.app/Contents/MacOS/BessieApp|.local/herdr/herdr)"'
```

Only stop a PID after its full command points inside `/Users/jordanstella/GitHub/bessie`. Do not use broad `pkill herdr` commands because they could affect unrelated sessions.
