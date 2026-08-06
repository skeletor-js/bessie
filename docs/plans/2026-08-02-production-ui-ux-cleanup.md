# Production UI/UX cleanup — execution plan (ce-plan)

**Date:** 2026-08-02
**Status:** Implementation-ready
**V1 slice:** D
**Goal-loop ready:** Yes — **macOS agent required** for M1–M5 live verification
**Branch:** `feat/v1-d-production-polish`
**Roadmap:** [`../roadmap/production-ui-ux-cleanup.md`](../roadmap/production-ui-ux-cleanup.md)
**Substrate:** [`2026-08-02-v1-shared-substrate.md`](2026-08-02-v1-shared-substrate.md)
**Vision lock:** [`2026-08-02-v1-vision-occam-scope.md`](2026-08-02-v1-vision-occam-scope.md)
**Research:** [`../research/2026-08-02-v1-feature-codebase-inventory.md`](../research/2026-08-02-v1-feature-codebase-inventory.md) §1

---

## 1. Outcome

Bessie quits and windows like a normal Mac app while keeping the Herdr survival rule:

1. **⌘Q** and **Bessie → Quit Bessie** always quit the application, including when a libghostty terminal is first responder.
2. Quit **never** stops Herdr or pane processes.
3. **Double-click** the custom top chrome / title drag region performs standard window **zoom** (`NSWindow.performZoom`).
4. Standard Mac chords that are not Bessie product commands (**⌘H** hide, **⌘M** minimize, **⌘Q** quit) are never consumed by the local key monitor.
5. Obvious prototype-only / dead chrome on primary destinations is removed or hidden.

## 2. Current behavior (evidence)

| Fact | Evidence |
| --- | --- |
| Local key monitor swallows matched commands | `KeyboardShortcutCoordinator.handle` returns `nil` on `.command` |
| Router only handles strokes with `command: true` | `BessieKeyboardShortcutRouter.handle` |
| **No** quit command in router | `BessieShortcutCommand` has no quit case; ⌘Q falls through as passthrough from router |
| Residual ⌘Q risk | Terminal first responder + `BessieTerminalView.performKeyEquivalent` / libghostty may still eat ⌘Q before menu |
| No NSApplicationDelegate / explicit terminate hook | `BessieApp` is pure SwiftUI `@main` App |
| Hidden title bar, no zoom wiring | `.windowStyle(.hiddenTitleBar)`; custom `BessieTopBar` / `titlebarHeight` |
| Cleanup on disappear | `ConnectView.onDisappear` releases controllers — **not identical** to app terminate |

## 3. Product decisions (locked)

1. Quit = terminate **Bessie only**.
2. Double-click = **zoom** (not fullscreen toggle) unless system fullscreen is already user-controlled via traffic lights — do not fight green-button fullscreen; double-click uses `performZoom`.
3. Do **not** add quit as a Bessie router "command" that returns `nil` from the monitor — quit must reach AppKit.
4. Prefer **explicit passthrough allowlist** for system chords + ensure main menu Quit exists with `q` + command.
5. Chrome cull is **safe removal only** — no Herd/Workspace feature deletion. The later slice M product decision explicitly removes standalone Attention and supersedes this older D boundary for that surface only.

## 4. Architecture approach

### 4.1 System key policy in Core (testable)

Extend `BessieKeyboardShortcutRouter` (or sibling pure helper) with:

```swift
public enum BessieKeyPolicy: Equatable, Sendable {
    case passthrough          // deliver to AppKit/terminal
    case appCommand(BessieShortcutCommand) // consume + handle in Bessie
}

public static func policy(for stroke: BessieShortcutStroke) -> BessieKeyPolicy
```

Rules:
- If stroke is system-reserved → `.passthrough` **before** product mappings:
  - ⌘Q, ⌘H, ⌘M
  - ⌘` (optional cycle windows — passthrough)
  - ⌘Tab is not delivered as keyDown to app usually — ignore
- Else existing product mappings → `.appCommand`
- Else → `.passthrough`

**Do not** implement quit by consuming ⌘Q and calling `NSApp.terminate` from the monitor unless live Mac proof shows menu path cannot work with terminal focus. Prefer menu/AppKit path first.

### 4.2 AppKit application + window glue (App target)

Add a small `@MainActor` `BessieAppDelegate: NSObject, NSApplicationDelegate` installed via:

```swift
@NSApplicationDelegateAdaptor(BessieAppDelegate.self) private var appDelegate
```

Responsibilities:
- Ensure main menu includes standard Quit (SwiftUI usually does; verify and fix if missing).
- Optional: `applicationShouldTerminate` → allow; teardown is best-effort synchronous release if needed.
- Do **not** send Herdr stop/close server APIs on quit.

Window zoom:
- Prefer `NSWindow` subclass or `Window` accessor via `Background`/`NSViewRepresentable` installer on the main shell that:
  - Sets `titlebarAppearsTransparent` / keeps traffic lights layout consistent with current design
  - Installs double-click on the drag region **or** uses `NSWindow` standard behavior if we partially restore titlebar interaction
- Minimal approach: transparent titlebar still receives double-click zoom if `titleVisibility` and toolbar configured correctly — **spike in M0/M2**.
- Fallback: attach `NSClickGestureRecognizer` (double-click) on the custom top bar hosting view calling `view.window?.performZoom(nil)`.

### 4.3 Termination cleanup

On terminate (delegate or `NSApplication.willTerminateNotification`):
- Release terminal controllers for all connections (same as disappear).
- Cancel connection runners / SSH bridges without Herdr server stop.
- Idempotent: safe if already released.

Extract shared `ConnectionFleetViewModel.shutdownForAppExit()` (name flexible) callable from disappear + terminate.

### 4.4 Chrome cull

Manual audit of primary destinations in `ProductSurfaces.swift` + settings:
- Remove buttons with empty actions, "coming soon" placeholders on primary paths, debug-only probes if visible in production builds.
- Keep `BessieWindowSnapshotProbe` if used by verify scripts — hide from user-facing layout if visible.
- Do not restyle the whole app (slice I owns appearance).

## 5. Files to touch

| File | Change |
| --- | --- |
| `Sources/BessieCore/KeyboardShortcuts.swift` | System passthrough policy; tests |
| `Tests/BessieCoreTests/KeyboardShortcutTests.swift` | ⌘Q/H/M passthrough; existing mappings unchanged |
| `Sources/BessieApp/KeyboardShortcutCoordinator.swift` | Use policy API; never consume system passthrough |
| `Sources/BessieApp/BessieApp.swift` | App delegate adaptor; optional willTerminate hook |
| `Sources/BessieApp/BessieAppDelegate.swift` (**new**) | Quit menu verify; terminate cleanup entry |
| `Sources/BessieApp/WindowChromeSupport.swift` (**new**, optional) | Zoom double-click installer / window configurator |
| `Sources/BessieApp/ProductSurfaces.swift` | Top bar double-click; chrome cull; start/stop monitor single-flight if needed |
| `Sources/BessieApp/TerminalPaneController.swift` | Only if live proof shows terminal eats ⌘Q — passthrough `performKeyEquivalent` for quit |
| `Sources/BessieApp/BessieApp.swift` `ConnectionViewModel` / fleet | `shutdownForAppExit()` |
| `scripts/check.sh` | Optional grep anchors for AppDelegate / policy symbols |
| `docs/plans/2026-08-02-production-ui-ux-cleanup.md` | Append verification evidence when done |

Avoid drive-by refactors of Herd beyond chrome cull. Slice M separately owns Attention removal and Herd consolidation.

## 6. Milestones

### M0 — Reproduce and pin (half day, Mac)

**Work:**
1. Build/run installed or dev app with a live terminal focused.
2. Matrix:

| Focus | Action | Expected now | Notes |
| --- | --- | --- | --- |
| Terminal | ⌘Q | ??? | Capture actual |
| SwiftUI control | ⌘Q | ??? | |
| Either | Menu Quit | ??? | |
| Either | Double-click top chrome | ??? | |
| Terminal | ⌘H / ⌘M | ??? | |

3. If needed, temporary log in coordinator when stroke is ⌘Q.

**DoD:**
- [ ] Written matrix filled in plan appendix (this file §11) with Pass/Fail before code changes.
- [ ] Decision recorded: menu-only vs terminal `performKeyEquivalent` fix needed.

**Tests:** none required beyond notes.

### M1 — System key policy + quit path

**Work:**
1. Implement Core `policy(for:)` with system passthrough.
2. Coordinator uses policy; app commands still consume.
3. AppDelegate ensures Quit menu item.
4. If M0 proved terminal eats ⌘Q, fix `BessieTerminalView.performKeyEquivalent` to return `false` for ⌘Q (and ⌘H/⌘M) so AppKit handles it.
5. `shutdownForAppExit` on willTerminate.

**DoD:**
- [ ] Unit tests: ⌘Q/H/M → passthrough; ⌘B still command; ⌘W still close tab command.
- [ ] `./scripts/check.sh` green.
- [ ] Mac: terminal focused ⌘Q quits Bessie.
- [ ] Mac: `pgrep`/herdr status shows session still running after quit.
- [ ] Relaunch attaches without restarting killed work.

**Pause if:** libghostty requires upstream change to deliver ⌘Q — document and ping Jordan.

### M2 — Titlebar double-click zoom

**Work:**
1. Spike which view owns the top drag strip (`BessieTopBar` / shell header).
2. Implement double-click → `performZoom`.
3. Verify traffic lights still work; drag-to-move still works.

**DoD:**
- [ ] Double-click toggles zoom on main window.
- [ ] Does not toggle zoom when double-clicking interactive controls (buttons) — only non-control drag region or standard titlebar area.
- [ ] check.sh green.

### M3 — Shortcut ownership audit

**Work:**
1. Document reserved product shortcuts in a short comment block on `BessieKeyboardShortcutRouter` or `docs/plans` appendix.
2. Confirm ⌘H/⌘M/⌘Q passthrough under terminal focus.
3. No new product shortcuts in this slice.

**DoD:**
- [ ] Tests cover system passthrough set.
- [ ] Manual: hide/minimize work with terminal focused.

### M4 — Chrome cull

**Work:**
1. Walk Herd, Workspace, Attention, Projects, Settings, Onboarding, Trouble.
2. Remove dead controls / prototype-only labels that imply unfinished fake features.
3. Keep honest empty states.

**DoD:**
- [ ] Short before/after list in §11.
- [ ] No removal of live Open pane / Projects / Trouble actions.
- [ ] UI copy check still passes if applicable (`scripts/check-ui-copy.sh`).

### M5 — Integration verify

**Work:**
1. `./scripts/check.sh`
2. `./scripts/mac-verify.sh` (or project equivalent path used for RC)
3. Hands-on checklist §7

**DoD:** all acceptance criteria §7 checked with evidence notes.

## 7. Acceptance criteria

1. Terminal focused: ⌘Q quits Bessie in one chord.
2. Menu **Quit Bessie** quits Bessie.
3. After quit, Herdr `bessie` (or active) session still running; pane processes alive.
4. Relaunch reconnects; work visible.
5. Double-click top chrome zooms window.
6. ⌘H / ⌘M work with terminal focused.
7. Primary destinations free of obvious dead prototype controls.
8. `./scripts/check.sh` passes.
9. No change to Deferred V1 items; no Herdr stop-on-quit.

## 8. Test plan

### Unit (VPS or Mac)

| Test | Location |
| --- | --- |
| ⌘Q/H/M passthrough | `KeyboardShortcutTests` |
| Existing ⌘B/⌘W/⌥⌘N mappings unchanged | same |
| Optional: policy table-driven tests | same |

### Live Mac

| Check | How |
| --- | --- |
| Quit survival | start agent/shell; ⌘Q; `herdr status` / process list |
| Zoom | double-click chrome twice |
| Monitor single instance | open one window; ensure one local monitor |

### Non-goals for tests

- Full XCUITest suite not required if manual matrix + unit policy tests exist.
- Do not automate notarization here.

## 9. Implementation order (agent)

```text
1. Branch feat/v1-d-production-polish
2. M0 manual matrix on Mac → write §11
3. Core policy + unit tests
4. Coordinator wiring
5. Terminal performKeyEquivalent fix only if M0 requires
6. AppDelegate + shutdownForAppExit
7. M2 zoom
8. M3 audit
9. M4 chrome cull
10. check.sh + mac-verify + §11 evidence
11. Stop — do not start slice E in this branch unless asked
```

## 10. Parallelism / dependencies

- **Blocks:** nothing (first remaining slice).
- **Blocked by:** Mac access for live DoD.
- **Unblocks:** E/I can start after D merges; I can theoretically parallel after M1 if separate files — prefer merge D first to avoid App.swift conflicts.
- **Worktree:** solo; do not pair with F file work.

## 11. Evidence log (fill during execution)

### M0 matrix

| Focus | Action | Result | Date |
| --- | --- | --- | --- |
| Terminal | ⌘Q | | |
| SwiftUI | ⌘Q | | |
| Either | Menu Quit | | |
| Either | Double-click chrome | | |
| Terminal | ⌘H | | |
| Terminal | ⌘M | | |

### Decisions

- Terminal ⌘Q fix needed? _TBD_
- Zoom approach: _TBD_

### Chrome cull list

- Removed: _TBD_
- Kept intentionally: _TBD_

### Final verify

- check.sh: _TBD_
- mac-verify: _TBD_
- Herdr survived quit: _TBD_

## 12. Pause conditions

Stop and ask Jordan if:
1. libghostty cannot deliver or yield ⌘Q without forking Ghostty.
2. hiddenTitleBar makes zoom impossible without full window rewrite (>1 day rabbit hole) — propose restoring standard titlebar hybrid.
3. Quit cleanup would require Herdr APIs that stop sessions.
4. Scope pressure to add menu-bar item or entity palette into this branch.

## 13. Out of scope

- Menu-bar status item (Deferred)
- Entity-aware palette (Deferred)
- Appearance Dark/Light tokens (slice I)
- Brand shell / case / badges / onboarding·Trouble restyle (slice L — [`2026-08-03-brand-shell-and-chrome-hygiene.md`](2026-08-03-brand-shell-and-chrome-hygiene.md))
- Herd filter bug (slice E) — unless a one-line fix is needed for compile; prefer E
- Shortcut customization UI

## 14. Done means

Slice D is done only when §7 acceptance is evidenced in §11 and the branch is ready for Jordan review — not when code merely compiles.
