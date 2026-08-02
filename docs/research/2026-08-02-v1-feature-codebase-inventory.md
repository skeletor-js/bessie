# Bessie V1 feature codebase inventory

**Date:** 2026-08-02
**Status:** Research inventory; no implementation performed
**Scope:** Current Swift/Rust implementation for the remaining V1 feature areas
**Branch inspected:** `main`

## Executive summary

The repository is a macOS 14+ Swift package with two Swift targets and no Rust code:

- `Sources/BessieApp/` owns the SwiftUI/AppKit product shell, libghostty hosting, settings UI, notification delivery, connection fleet view model, and feature surfaces.
- `Sources/BessieCore/` is a Swift library containing Herdr transport, projections, typed actions, terminal sequencing, connection definitions, remote SSH forwarding, persistence models, and Native Project logic.
- No `Cargo.toml` or `*.rs` files exist. The older shared architecture description of a Rust `BessieCore` does not describe the current repository. The controlling V1 decision is the narrow pure-Swift adapter already in use.

The strongest reusable substrate for the remaining V1 work is:

1. authoritative snapshot projection in `Sources/BessieCore/SessionProjection.swift` and `Sources/BessieCore/AgentProjection.swift`;
2. typed Herdr mutations in `Sources/BessieCore/HerdrActions.swift`;
3. multi-connection identity and aggregation in `Sources/BessieCore/BessieConnections.swift`, `Sources/BessieCore/RemoteHerdrBridge.swift`, and `ConnectionFleetViewModel` in `Sources/BessieApp/BessieApp.swift`;
4. attention and notification projection/planning in `Sources/BessieCore/SurfaceProjection.swift` and `Sources/BessieCore/NotificationPlanning.swift`;
5. app-owned shortcut routing in `Sources/BessieCore/KeyboardShortcuts.swift` plus AppKit interception in `Sources/BessieApp/KeyboardShortcutCoordinator.swift`.

The largest missing implementation areas are file/diff supervision, a menu-bar status item, and explicit AppKit window/application lifecycle control. Themes, attention triage, layout presets, entity-aware palette results, and a real session manager all have partial substrate but not their V1 product behavior.

| Area | Current state |
| --- | --- |
| App shell quit/window/shortcuts | Shortcut and terminal-focus infrastructure exists; explicit quit and standard window behavior do not |
| Herd dashboard | Working multi-connection agent grid with state ordering and basic filters; richer filtering/sorting/actions absent |
| Attention / notifications | Safe open-pane attention list and native blocked/done notifications exist; triage/history/snooze absent |
| Files/diff | No watcher, Git adapter, diff model, preview surface, or containment policy |
| Menu bar / status item | No menu-bar implementation; `UserNotifications` implementation exists |
| Layout actions | Herdr split/resize/focus/swap/move/zoom wrappers and manual UI exist; presets and hint overlay absent |
| Command palette | Static command search and execution exist; no live entity index or results |
| Themes / appearance | Persisted appearance model and several visual preferences exist; app is hard-forced dark and appearance is unused |
| Session connection + remote | SSH remote and concurrent connection fleet exist; session discovery/attach manager and polished selection lifecycle do not |

## Package and ownership structure

### Existing files and types

- `Package.swift`
  - Declares macOS 14+, Swift 6, library product `BessieCore`, executable product `BessieApp`, exact `libghostty-spm` 1.3.2, and `GhosttyTerminal` only in the app target.
  - `BessieCoreTests` depends only on `BessieCore`; `BessieAppModelTests` depends on both targets.
- `Sources/BessieApp/BessieApp.swift`
  - `BessieApp`, `ConnectionViewModel`, `ConnectionFleetViewModel`, and `ConnectView`.
  - Owns runtime-to-product orchestration, connection startup, remote bridge attachment, action execution, and the root scene.
- `Sources/BessieApp/ProductSurfaces.swift`
  - `BessieProductShell`, navigation, Herd, workspaces, workspace terminals, agent detail, attention, pane layout, and most action dispatch.
- `Sources/BessieApp/TerminalPaneController.swift`
  - AppKit/libghostty boundary: `TerminalControllerRegistry`, `PaneTerminalController`, `GhosttyPaneSurface`, and `BessieTerminalView`.
- `Sources/BessieCore/HerdrAPI.swift`, `ConnectionLifecycle.swift`, `SessionProjection.swift`, `HerdrActions.swift`, and `HerdrTerminalController.swift`
  - Current pure-Swift Herdr adapter and terminal control plane.

### What works

- `BessieCore` does not depend on SwiftUI or `GhosttyTerminal`; the renderer remains in `BessieApp`.
- Most wire and state logic is public, value-oriented, and covered by focused tests.
- The app target translates core projections and commands into native SwiftUI/AppKit surfaces.
- The exact terminal dependency is isolated to the app target as required.

### Gaps

- `BessieApp.swift` and especially `ProductSurfaces.swift` are broad ownership points. Remaining V1 surfaces would make `ProductSurfaces.swift` substantially larger unless coherent feature responsibilities move into focused files.
- Several testable product decisions remain in private SwiftUI types and closures inside `ProductSurfaces.swift`, limiting direct unit coverage.
- `BessieCore` is pure Swift, not fully platform-neutral: it uses Foundation process APIs, Darwin Unix sockets, local filesystem access, and macOS-oriented runtime assumptions. That is acceptable for the current Mac-first decision but should not be described as a cross-platform Rust core.
- There is no target for file/Git capabilities, menu-bar lifecycle, or app/window coordination yet.

### Risky seams

- `ConnectionViewModel` mixes runtime discovery, remote tunnel ownership, projection updates, actions, diagnostics, project handoff, and agent catalog loading. Session-manager expansion will increase lifecycle coupling here.
- `BessieProductShell` directly coordinates notifications, navigation, shortcuts, connection switching, settings persistence, terminal visibility, Projects, and all major surfaces. Notification cold-start, multi-session routing, and window lifecycle all converge on this one view.
- The historical `ARCHITECTURE.md` Rust recommendation and the actual Swift package can mislead implementation planning. Plans should use `Package.swift` and the V1 pure-Swift decision as the current source of truth.

## 1. App shell quit, window, shortcuts, and terminal focus

### Existing files and types

- `Sources/BessieApp/BessieApp.swift`
  - `BessieApp` uses a SwiftUI `WindowGroup`, `.windowStyle(.hiddenTitleBar)`, a minimum content size, and a separate `Settings` scene.
  - `ConnectView.onDisappear` releases terminal controllers and stops connection runners/SSH bridges.
- `Sources/BessieApp/KeyboardShortcutCoordinator.swift`
  - `BessieKeyboardShortcutCoordinator` installs an `NSEvent` local `.keyDown` monitor.
  - It converts AppKit events to `BessieShortcutStroke`, invokes `BessieKeyboardShortcutRouter`, consumes matched app commands, and passes unmatched events through.
- `Sources/BessieCore/KeyboardShortcuts.swift`
  - `BessieShortcutStroke`, `BessieShortcutCommand`, `BessieKeyboardShortcutRouter`, static `BessieCommandDefinition` entries, and geometry-based `BessiePaneNavigation`.
- `Sources/BessieApp/TerminalPaneController.swift`
  - `BessieTerminalView` subclasses the libghostty `TerminalView`.
  - It intercepts Page Up/Down, supported special keys, Command-V paste, wheel scroll, and shift-modified selection.
  - `mouseDown` explicitly makes the terminal first responder.
- `Sources/BessieCore/HerdrTerminalController.swift`
  - `release()` sends terminal release and terminates only the Bessie-owned controller subprocess, not the Herdr pane process or server.
- `Tests/BessieCoreTests/KeyboardShortcutTests.swift`
  - Covers passthrough, app command mappings, static palette search, and directional pane navigation.
- `Tests/BessieCoreTests/TerminalControllerTests.swift`
  - Covers terminal release/control/observe/takeover process behavior, but not application quit or AppKit first-responder behavior.

### What works

- App-owned Command shortcuts are intercepted before normal responder delivery when the router recognizes them.
- Non-Command input and unknown Command chords are deliberately passed through by the core router.
- Terminal focus is explicit on mouse click, and terminal-specific input is routed through the mode-correct Herdr input paths.
- Normal view teardown releases Bessie terminal controllers and connection resources without issuing Herdr workspace, pane, or server close actions.
- Standard SwiftUI app infrastructure should generate an application menu, but the code does not customize or verify its Quit behavior.

### Gaps

- There is no `NSApplicationDelegate`, explicit `NSApp.terminate`, app command for Quit, `CommandGroup` replacement, termination coordinator, or quit-specific cleanup hook.
- Command-Q is not represented in `BessieShortcutCommand` or `BessieKeyboardShortcutRouter`. It falls through the local monitor and relies on the downstream AppKit/libghostty responder and generated app menu to do the right thing. This is exactly the unverified seam called out by the V1 roadmap.
- There is no automated or live test for Command-Q with a `BessieTerminalView` as first responder, Quit from the app menu, Dock Quit, or Herdr process survival after quit.
- There is no explicit AppKit `NSWindow` owner, `NSWindowDelegate`, toolbar/titlebar configuration, standard-window proxy, or title-bar double-click handling.
- `.hiddenTitleBar` removes the ordinary title presentation, but no replacement title-bar hit region or standard zoom behavior is installed.
- No reserved-shortcut matrix exists in code or documentation. The local event monitor currently reserves every recognized Command chord even while a terminal is focused.
- `WindowGroup` permits multiple windows, while terminal control permits one writer per pane. The app has controller-conflict UI, but no window-level policy preventing two Bessie windows from independently trying to control the same pane.

### Risky seams

- `BessieTerminalView.performKeyEquivalent` handles Command-V and then delegates to the libghostty superclass. Whether Command-Q reaches the application menu while the terminal is first responder depends on external responder behavior rather than an explicit Bessie guarantee.
- Cleanup lives largely in SwiftUI `onDisappear`. App termination, window closure, scene replacement, and view disappearance are not identical lifecycle events.
- The local `NSEvent` monitor is process-wide but is started/stopped by each `BessieProductShell`. Multiple windows could install multiple monitors and command handlers.
- Window close and app quit semantics will interact with the planned menu-bar-only lifecycle. That decision must be made before treating last-window closure as teardown.

## 2. Herd dashboard UI and state

### Existing files and types

- `Sources/BessieCore/AgentProjection.swift`
  - `AgentProjection` decodes Herdr agent identity/state/revision.
  - `ConnectedAgentProjection` scopes raw Herdr IDs by connection to avoid collisions across sessions.
- `Sources/BessieCore/SessionProjection.swift`
  - `HerdrSessionProjection` merges authoritative snapshot agents with legacy pane agent data and exposes workspace/tab/pane topology.
- `Sources/BessieApp/BessieApp.swift`
  - `ConnectionFleetViewModel` keeps all configured connections live, aggregates `ConnectedAgentProjection` values, tracks connected count, and activates the owning model for a selected agent.
- `Sources/BessieApp/ProductSurfaces.swift`
  - `HerdFilter` and `HerdSurface` implement All / Needs you / Working / Done / Idle filtering, blocked-first ordering, a fixed three-column card grid, connection/workspace/tab location, basic activity copy, Open pane, and Details.
  - `AgentDetailSurface` hosts the real terminal, basic metadata, and a raw prompt/input field.
- `Tests/BessieAppModelTests/SurfaceProjectionTests.swift`
  - Covers authoritative agent roster projection and collision-safe connected-agent IDs.

### What works

- The Herd is already multi-connection: `ConnectionFleetViewModel.agents` is the union of every connected configured session.
- Agent identity is composite at the Bessie layer, so two sessions may safely reuse a pane ID such as `p1`.
- Cards are ordered blocked, working, done, idle, unknown.
- Each card shows authoritative state plus connection/workspace/tab/pane location and routes through the owning connection to the exact pane.
- The details path switches to the correct connection and opens a real libghostty terminal rather than a terminal imitation.

### Gaps

- Filter buttons have no per-state counts.
- There is no workspace filter, connection/runtime filter, search, density mode, or selectable sort.
- There are no typed state-specific actions such as interrupt or confirmed close on cards. Only Open pane and Details exist.
- No recent-output or last-event snippet is loaded. `activity(for:)` uses `AgentProjection.title` when present, otherwise generic copy for blocked/done.
- There is no seen/unseen completion presentation state or age/duration.
- The fixed three-column grid has no explicit narrow-window adaptation.
- Unknown agents appear only in All; there is no Unknown filter.
- Agent detail has no Follow files entry or richer workbench yet.

### Risky seams

- **Current filter bug:** `HerdFilter.blocked` has raw value `"Needs you"`, while `includes(_:)` compares the lowercased display label with `AgentSemanticState.blocked.rawValue` (`"blocked"`). The Needs you filter therefore excludes blocked agents. There is no UI-level test covering each filter.
- `AgentProjection.title` is displayed as activity text without a freshness or provenance label. It must not be expanded into “recent output” unless its Herdr semantics are verified.
- Fleet ordering is derived from a dictionary-backed set of models before state sorting. Agents with equal state rank have no stable secondary sort.
- `ConnectionFleetViewModel.refresh()` logs connection names and agent counts on every observed refresh. Richer frequent updates could create noisy diagnostics.
- Card actions must activate the owning connection before using raw Herdr IDs. Any future entity model that drops `connectionID` would reintroduce cross-session collisions.

## 3. Attention and notifications

### Existing files and types

- `Sources/BessieCore/SurfaceProjection.swift`
  - `AgentSemanticState`, `AttentionSurfaceItem`, `AttentionAction`, `PaneOpenTarget`, and `BessieSurfaceProjection`.
  - Attention consists of authoritative pane states `blocked` and `done`, sorted blocked first.
  - The only attention action is `.openPane`.
- `Sources/BessieApp/ProductSurfaces.swift`
  - `AttentionSurface` renders the current count, empty state, blocked/done cards, location, and Open pane.
  - Command `openNotificationTarget` opens the first current attention item or navigates to Attention.
- `Sources/BessieCore/NotificationPlanning.swift`
  - `BessieNotificationPane`, `BessieNotificationEvent`, `BessieNotificationPlanner`, and `BessieNotificationRoute`.
  - Planner seeds without retroactive delivery, emits only state transitions allowed by policy, suppresses the active pane, and builds exact-pane targets.
- `Sources/BessieApp/BessieNotifications.swift`
  - `BessieNotificationCoordinator` owns `UNUserNotificationCenter`, authorization, delivery, response routing, and app activation.
- `Sources/BessieApp/BessieSettings.swift`
  - Notification policy picker and authorization repair controls.
- `Tests/BessieAppModelTests/SurfaceProjectionTests.swift`
  - Covers attention truth, notification transition planning, policy changes, active-pane suppression, and stale-target re-resolution.

### What works

- Attention state comes from Herdr snapshot projections, not screen scraping.
- Open pane re-resolves the current workspace/tab/pane target before focusing, so stale stored topology is not blindly trusted.
- Native notifications support blocked-only or blocked-and-done policy, suppress the active pane, include connection/workspace/tab/pane IDs, and activate Bessie on click.
- Initial planner seeding prevents a launch-time burst of notifications for already-blocked/done panes.
- Foreground presentation is explicitly enabled with banner and sound.
- Settings handles not-determined, denied, and allowed authorization states.

### Gaps

- Attention is a current-state list, not a queue. There are no Open / Resolved / All views, local seen/dismiss state, history, age, snooze, clear, or resolved semantics.
- No keyboard list navigation, selection model, or zoomed attention mode exists.
- There is no durable or transient attention item ID beyond pane ID. Multiple attention transitions for one pane collapse into one current item.
- No explanation/reason is shown beyond state and location; `agent.explain` is not integrated.
- No typed approval or resolution actions exist, which is correct for the current Herdr contract but leaves the richer resolution scope unimplemented.
- Notification requests have no categories/actions, quiet timer, grouping/thread identifier, relevance/interruption policy, or delivered-notification cleanup.
- Authorization request and `center.add` errors are discarded.
- There is no cold-launch acceptance test proving a clicked notification activates the correct configured connection and pane.

### Risky seams

- `AttentionSurfaceItem.id` is `paneID`, which is only unique inside one Herdr session. The current in-window Attention surface is scoped to the active connection, but a future fleet-wide queue must use `connectionID + paneID`.
- `BessieNotificationCoordinator.pendingConnectionID` is optional. Notifications generated by current code include it, but a missing value routes against whichever connection is active.
- Notification planners are retained by connection ID even if a connection is removed. This is small in current use but becomes stale state if connections are frequently edited.
- The planner keys previous state only by pane ID inside each connection planner. That is safe while each planner remains strictly per connection.
- `routePendingNotification()` switches fleet activation and returns; completion depends on SwiftUI rebuilding around the newly active model. This warm/cold multi-connection path has no direct integration test.

## 4. Files and diff: watcher, Git, and path resolution

### Existing files and types

There is no feature implementation for Follow files, workspace browsing, Git status, or diff preview.

Nearby but insufficient primitives are:

- `Sources/BessieCore/SessionProjection.swift`
  - `PaneProjection.cwd` exposes Herdr-provided per-pane working directories.
- `Sources/BessieCore/BessieProjectCapture.swift`
  - `BessieProjectCapture.authoritativeWorkingDirectory` accepts a working directory only when every captured pane has the same absolute `cwd`.
- `Sources/BessieCore/BessieProjects.swift`
  - Native Project validation standardizes and resolves symlinks for a configured project working directory and verifies it is a directory.
- `Sources/BessieCore/BessieProjectStore.swift`
  - Canonicalizes the Bessie-owned Project recipe store root and constrains recipe files to that store.
- `Tests/BessieCoreTests/BessieProjectCaptureTests.swift` and `Tests/BessieCoreTests/BessieProjectTests.swift`
  - Cover Native Project cwd consensus and Project recipe path validation, not workspace file access.

### What works

- Herdr pane cwd is decoded and available to product code.
- Native Project capture has an honest rule for a workspace whose panes agree on one absolute cwd.
- Native Project persistence already demonstrates standardization/symlink resolution and atomic file writes for Bessie-owned recipe JSON.

### Gaps

- No filesystem watcher exists: no FSEvents, `DispatchSource`, watcher abstraction, coalescing, watch-stretch model, touch recency model, or invalidation scheduler.
- No Git process/API exists: no repository discovery, nested-repository policy, `status`, `diff`, baseline, rename detection, untracked-file handling, binary handling, or +/- counts.
- No workspace-root resolver exists for the Follow files contract. A pane cwd is not necessarily the repository/workspace root, and multiple panes may have different cwds.
- No path containment helper validates a requested file against a canonical workspace root after symlink resolution.
- No read-only file loader, size/binary guard, syntax-independent text model, diff parser, hunk model, or preview UI exists.
- No local/remote capability model exists for files. The current SSH bridge forwards Herdr sockets only; it does not provide a versioned remote filesystem transport.
- No Follow/pin state, touched list, watch lifecycle, agent binding, or honest attribution copy exists.
- No tests cover traversal, symlink escape, file replacement races, permission errors, large repositories, rapid writes, Git absence, non-repositories, or remote unsupported states.

### Risky seams

- Reusing Native Project path validation directly would be the wrong boundary. It validates launch recipes and a consensus cwd; it does not establish a safe file-browsing root or defend each requested descendant path.
- `PaneProjection.cwd` can change, can point below a repository root, and can differ across panes. Treating it as the workspace root would silently mis-scope files.
- Running Git or filesystem work on the main actor would compete with terminal rendering and snapshot reconciliation. No background/coalescing ownership exists yet.
- Files, Git output, and paths are untrusted data. Preview code must not execute files, interpret content as instructions, or log bodies by default.
- Remote sessions currently look almost identical to local sessions at the projection layer. File surfaces need an explicit connection capability check or they may accidentally attempt local reads of remote paths.

## 5. Menu bar, status item, and `UserNotifications`

### Existing files and types

- `Sources/BessieApp/BessieNotifications.swift`
  - Complete first native notification coordinator described in the Attention section.
- `Sources/BessieCore/NotificationPlanning.swift`
  - Shared blocked/done transition and routing plan.
- `Sources/BessieApp/BessieApp.swift`
  - Root `WindowGroup` and Settings scenes only.
- `Sources/BessieApp/BessieDesignSystem.swift`
  - `BessieStatusLine` is an in-window footer, not an `NSStatusItem`.
- Workstream design assets for menu-bar icons are outside this repository and are not packaged under `Sources/BessieApp/Resources/`.

### What works

- Native macOS notification authorization, delivery, foreground presentation, click routing, and Settings repair UI already exist.
- Notification events use the same authoritative pane targets as the main app.
- The fleet can already provide counts and urgent agents across connected sessions if the menu-bar product chooses fleet-wide scope.

### Gaps

- No `MenuBarExtra`, `NSStatusBar`, `NSStatusItem`, status-item controller, popover/panel, status-item menu, or menu-bar scene exists.
- No packaged monochrome template image or menu-bar-specific resource exists in `Sources/BessieApp/Resources/`.
- No last-window-close policy, accessory/regular activation-policy controller, reopen behavior, or windowless lifecycle exists.
- No Open Bessie, Open pane, Settings, Quiet, or Quit menu-bar actions exist.
- No shared urgency/count view model for a menu-bar panel exists.
- No quiet timer, done-unseen state, top-five ordering contract, overflow action, or disconnected panel state exists.
- No status-item accessibility or lifecycle tests exist.

### Risky seams

- The current connection fleet is owned by `ConnectView`. If the main window disappears, SwiftUI teardown releases controllers and stops the fleet. A menu-bar herd cannot simply reuse that view-owned lifetime without moving connection ownership above the window scene.
- `BessieNotificationCoordinator` is owned by `BessieApp`, which is suitable for window-independent delivery, but its pane routing is consumed inside `BessieProductShell`, which may not exist when no window is open.
- Menu-bar Quit must share the same explicit termination path as Command-Q and app-menu Quit while preserving Herdr processes.
- A windowless app may need to keep snapshot/event connections alive without keeping writable terminal controllers alive. Those lifetimes are currently coordinated together by `ConnectView` and `BessieProductShell`.

## 6. Layout actions: split, resize, and focus through Herdr

### Existing files and types

- `Sources/BessieCore/HerdrActions.swift`
  - `HerdrAction` wraps `pane.split`, `pane.focus`, `pane.resize`, `pane.swap`, `pane.move`, `pane.zoom`, and `layout.set_split_ratio`, plus workspace/tab actions.
  - `HerdrActionClient` performs mutations then fetches an authoritative snapshot.
- `Sources/BessieCore/SessionProjection.swift`
  - `RecursivePaneLayout`, `PaneLayoutBranch`, `PaneLayoutLeaf`, split paths, geometry, and zoom state.
- `Sources/BessieCore/KeyboardShortcuts.swift`
  - Directional focus, swap, split, resize, and zoom commands plus `BessiePaneNavigation` geometry selection.
- `Sources/BessieCore/DirectManipulation.swift`
  - `BessieSplitDrag` clamps ratios and drag payload helpers cover workspace/tab reorder.
- `Sources/BessieCore/SurfaceProjection.swift`
  - `BessiePaneActionTarget` prevents actions from escaping the visible tab; `PaneMoveChoices` derives valid destinations from current topology.
- `Sources/BessieApp/ProductSurfaces.swift`
  - Pane menus, shortcut dispatch, pane-number headers, split divider drag, move menus, and live recursive layout.
- `Tests/BessieCoreTests/ProjectionActionTests.swift`, `KeyboardShortcutTests.swift`, `Tests/BessieAppModelTests/SurfaceProjectionTests.swift`, and `Tests/BessieCoreTests/LiveHerdrTests.swift`
  - Cover exact API payloads, snapshot reconciliation, geometry navigation, target containment, drag ratios, and live topology mutations.

### What works

- All required low-level Herdr layout mutations are already typed and tested.
- UI supports split right/down, discrete resize, drag-to-set split ratio, directional focus, swap, move, zoom, and pane close.
- Dragged split ratios are only previews until one Herdr mutation is sent on drag end; authoritative projection updates clear the preview.
- Pane headers already show numeric badges based on visible pane order.
- Actions reconcile from a fresh snapshot rather than persisting a Bessie-owned layout model.
- The same API path works against a remotely forwarded Herdr socket.

### Gaps

- No Even or Main + stack preset model, planner, UI, command, or test exists.
- No held-shortcut pane-number hint overlay or direct number-to-pane shortcut exists. Existing Command-1…9 switches tabs, not panes.
- No explicit tab-level rolled-state model beyond `TabProjection.agentStatus` and the state glyph in the tab strip.
- No preset convergence/error presentation exists for partially applied multi-action layouts.
- No preset capability/degraded state exists for unsupported topology or concurrent remote changes.

### Risky seams

- `HerdrActionClient.perform([actions])` sends actions sequentially and snapshots only after all finish. A preset made of several resize actions is not atomic; failure can leave a partially changed Herdr layout.
- A preset should derive every step from a current authoritative topology and reconcile between steps when IDs or topology can change. Pane move operations are already documented as potentially changing public pane IDs across workspaces.
- `BessiePaneNavigation` uses projected rectangle centers and a simple weighted distance. It is adequate for current directional focus but may produce surprising selection in irregular nested layouts.
- Split-divider preview times out after one second if no matching projection arrives. There is no explicit request identity tying an update to that drag.
- Pane numbers are based on `projection.panes` order filtered by lookup, not an explicitly stable spatial numbering contract.

## 7. Command palette

### Existing files and types

- `Sources/BessieCore/KeyboardShortcuts.swift`
  - `BessieCommandDefinition`, static `BessieKeyboardShortcutRouter.commands`, tokenized substring matching, and command enum.
- `Sources/BessieApp/KeyboardShortcutCoordinator.swift`
  - `BessieCommandPalette` with search field, selected row, mouse hover, arrow navigation, Return execution, Escape close, and footer hints.
- `Sources/BessieApp/ProductSurfaces.swift`
  - Command-B toggles the overlay; `handleShortcut` executes commands against current workspace/tab/pane context and routes Projects/Settings/Attention.
- `Tests/BessieCoreTests/KeyboardShortcutTests.swift`
  - Covers command search against title/detail/keywords and shortcut routing.
- `Tests/BessieAppModelTests/ProjectsViewModelTests.swift`
  - Verifies Projects navigation is represented in the command definitions.

### What works

- The palette is a functional native overlay, not a mockup.
- It supports keyboard and pointer operation and closes before executing the selected command.
- Static command search requires every query token to appear somewhere in title/detail/keywords.
- Commands use the same action handlers and close confirmations as direct shortcuts rather than bypassing product safety.

### Gaps

- Results are static commands only. There is no agent, pane, tab, workspace, connection, or attention-item index.
- There is no result-kind model, stable result ID, connection-scoped target, ownership metadata, state badge, ranking, recency, or sectioning.
- No entity action routes directly to `PaneOpenTarget` or the owning `ConnectionViewModel` from the palette.
- No context-safe typed actions are exposed per entity.
- No fuzzy matching, exact-ID matching, aliases, ranking, or result limits exist.
- No search across terminal scrollback or files exists.
- The placeholder and empty state both describe commands rather than universal navigation.

### Risky seams

- Cross-session entities must carry `connectionID`; raw workspace/tab/pane IDs are not globally unique.
- Reusing `BessieShortcutCommand` as the only result payload will not represent live entities cleanly. A result can invoke existing command handlers, but entity identity needs its own typed target.
- The AppKit local event monitor consumes Command-B even with terminal focus. A remappable future key map needs conflict detection and a clear app-reserved policy.
- Static `commands` include actions that can become unavailable in current context, but the palette does not show disabled state or explain why an item cannot run.

## 8. Themes and appearance settings

### Existing files and types

- `Sources/BessieCore/PresentationPersistence.swift`
  - `BessieAppearance` (`system`, `dark`, `light`), `BessieAppIcon`, and `BessiePreferences` fields for appearance, cowprint intensity/motion, terminal font size, pane gap, notifications, and startup behavior.
- `Sources/BessieApp/BessieSettings.swift`
  - Persists preferences; exposes app icon, cowprint contrast/motion, terminal font size, pane spacing, notifications, startup, and runtime settings.
  - `BessieAppIconController` applies dark/light Dock icons.
- `Sources/BessieApp/BessieDesignSystem.swift`
  - Hard-coded dark monochrome `BessieDesign` tokens, cowprint texture/crops, controls, status line, and shared surface styles.
  - Cowprint animation respects Accessibility Reduce Motion and the Bessie motion preference.
- `Sources/BessieApp/BessieApp.swift` and `BessieSettings.swift`
  - Apply `.preferredColorScheme(.dark)` to primary and Settings surfaces.
- `Sources/BessieApp/TerminalPaneController.swift`
  - Applies terminal font size and background opacity to libghostty.
- `Tests/BessieAppModelTests/SurfaceProjectionTests.swift`
  - Covers preference round-trip and legacy defaults.

### What works

- Appearance is already represented in the persisted schema and decodes safely from older preference files.
- App icon, cowprint intensity/motion, terminal font size, and pane gap are user-facing and applied.
- Reduce Motion stops cowprint animation even if the Bessie motion preference is on.
- Shared visual tokens are centralized in `BessieDesign` rather than repeated as arbitrary colors across every view.

### Gaps

- The `appearance` preference is not exposed in Settings and is not applied anywhere.
- The app and Settings explicitly force dark color scheme. `BessieDesign` contains only one hard-coded dark palette, so `system` and `light` are currently dead persisted values.
- No theme abstraction, environment value, palette bundle, density preference, pane-border mode, chrome mode, shape/elevation option, or state-indicator style exists.
- No key-map editor, remapping persistence, conflict detection, import/export, or reset exists.
- No ownership labels distinguish Bessie-owned settings from Herdr-owned settings.
- Reduce Motion is only clearly implemented for cowprint animation; command-palette transitions and other animations do not consult it explicitly.
- Terminal colors/theme are not configured. Bessie controls terminal font size and opacity while rendered ANSI/libghostty state remains otherwise independent.
- No screenshot or UI test matrix covers preference combinations.

### Risky seams

- Simply honoring `.preferredColorScheme` would not create a light theme because all `BessieDesign` colors are fixed dark values.
- `ProductPalette` aliases `BessieDesign`, while some views refer directly to `BessieDesign`; a future theme must update one source of truth rather than layer local overrides.
- App icon choice and appearance choice are independent today. Product copy must avoid implying one automatically follows the other unless that behavior is intentionally added.
- Theme propagation must include SwiftUI windows, AppKit-hosted terminal surfaces, sheets, Settings, notification/menu-bar assets, and any future status-item panel.

## 9. Session connection and remote support

### Existing files and types

- `Sources/BessieCore/BessieConnections.swift`
  - `BessieConnectionKind`, `BessieConnectionDefinition`, `BessieConnectionState`, `BessieConnectionStore`, validation, and local canonical connection.
- `Sources/BessieCore/RemoteHerdrBridge.swift`
  - `RemoteHerdrBridgePlan` and `RemoteHerdrBridge`.
  - Uses noninteractive OpenSSH, validates host/session input, checks remote `herdr status --json`, and privately forwards both `herdr.sock` and `herdr-client.sock` to a protected local temporary directory.
- `Sources/BessieCore/ConnectionLifecycle.swift`
  - `HerdrBootstrapper`, bounded reconnect policy, `HerdrConnectionState`, and `HerdrConnectionRunner`.
- `Sources/BessieCore/HerdrAPI.swift`
  - Unix-socket JSON API, subscriptions, and snapshots.
- `Sources/BessieCore/HerdrTerminalController.swift`
  - Uses the endpoint socket through `HERDR_SOCKET_PATH`, so the ordinary terminal CLI path also works through the forwarded remote sockets.
- `Sources/BessieApp/BessieApp.swift`
  - `ConnectionViewModel` owns one local or SSH connection.
  - `ConnectionFleetViewModel` creates one model per configured definition, keeps all alive, aggregates agents, and selects the active model.
- `Sources/BessieApp/BessieSettings.swift`
  - Persists connection definitions; lists local/SSH connections; adds and removes SSH connections without storing passwords.
- `Sources/BessieCore/AgentProjection.swift`
  - `ConnectedAgentProjection` prevents cross-session ID collision.
- `Tests/BessieCoreTests/BessieConnectionTests.swift`
  - Covers definitions, validation, persistence without credentials, and forwarding both sockets.
- `Tests/BessieAppModelTests/SurfaceProjectionTests.swift`
  - Covers collision-safe connected-agent identity.
- `Tests/BessieCoreTests/PersistenceReconnectTests.swift`, `BootstrapTests.swift`, and `LiveHerdrTests.swift`
  - Cover bounded reconnect, named local session isolation, bootstrap reconciliation, and live local Herdr APIs.

### What works

- Deliberate SSH connection definitions are real persisted product state, not only design placeholders.
- SSH uses the user's OpenSSH configuration/agent and stores no password.
- Remote attach forwards both public sockets over SSH without opening a remote port or using Herdr's private bincode protocol directly.
- Each configured connection gets an independent runner and projection; the Herd aggregates all connected sessions.
- Connection-scoped composite IDs prevent pane collisions in the fleet.
- Activating a remote Herd card selects the owning connection, focuses workspace/tab/pane through the forwarded API, and hosts the ordinary Herdr terminal session through libghostty.
- Terminal controllers are released when the active connection changes, without stopping remote Herdr work.
- Reconnect is bounded and snapshots are refreshed after events rather than treating events as globally ordered truth.

### Gaps

- There is no discovery/listing of named local Herdr sessions, runtime facts per session, client list, attach command, or local session picker.
- There is no explicit attach/detach/observe session-manager surface. Settings only lists configured definitions and offers add/remove for SSH.
- Existing connection rows are not selectable and show a static `INCLUDED` label. `BessieSettingsModel.selectConnection` and `ConnectionViewModel.switchConnection` are not called by current UI.
- `BessieSettingsModel.selectedConnectionID` is persisted, but `ConnectionFleetViewModel.start` starts every connection and initially chooses the first configured model, not the persisted selected connection.
- There is no edit flow for an SSH connection, connection test before save, host-key/auth guidance, capability matrix, degraded read-only mode, or copyable attach command.
- No UI shows per-connection health/topology facts beyond aggregate connected count and connection location on Herd cards.
- No explicit manual retry per connection or detach-without-delete action exists.
- Remote integration tests validate the forwarding plan but do not launch a real SSH tunnel in the ordinary test suite. There is no current clean-machine remote acceptance test in the inspected Swift tests.
- The remote command assumes `herdr` is on the remote noninteractive SSH `PATH`; no remote executable override exists.

### Risky seams

- The code is ahead of the older capability map that said remote JSON control was unavailable: it forwards the Unix sockets with OpenSSH `StreamLocal` forwarding. Release documentation and threat/compatibility review must evaluate the implemented path rather than assume remote is still absent.
- `RemoteHerdrBridge.remoteHerdrCommand` constructs a remote shell command string. Host and session are restricted, but remote executable selection and shell environment remain implicit.
- The bridge stores sockets under `/tmp/bessie-$USER/<connection-id>`, removes stale socket paths, and attempts to stop a stale SSH control master. Multiple Bessie processes using the same connection ID could interfere.
- `RemoteHerdrBridge.stop()` terminates the local SSH tunnel and removes its local directory. It correctly does not stop remote Herdr, but all connection/window owners must agree on tunnel lifetime.
- `ConnectionFleetViewModel` stores models in a dictionary and chooses `connected.first` as failover. Active-connection fallback is not deterministic.
- Removing a connection from Settings causes fleet synchronization to stop its model, but there is no confirmation that active terminal views and pending notification routes are safely handed off.
- Project materialization is permitted over whichever connection is active. Remote Native Project working directories and startup commands rely on remote Herdr semantics, while future local filesystem features must not assume those paths exist on the Mac.

## Cross-cutting implementation risks for the remaining V1 work

1. **Window-owned state is the main lifecycle bottleneck.** Connections live in `ConnectView`, terminal controllers in `BessieProductShell`, and notifications in `BessieApp`. Menu-bar-only operation and cold notification routing need a deliberate ownership split before adding more views.
2. **Connection identity must be carried everywhere.** Herd already uses `ConnectedAgentProjection`; attention, command-palette entities, menu-bar rows, and any future search results must not use raw pane IDs globally.
3. **Local and remote capabilities must diverge honestly.** Herdr topology/actions work through forwarded sockets, but local file/Git access does not. The projection currently does not itself prevent local code from treating a remote cwd as a Mac path.
4. **Presentation state needs explicit ownership.** Seen, resolved, snoozed, quiet, follow, and pin are valid Bessie-owned state, but they must be labeled and keyed by connection plus authoritative entity/revision rather than persisted as Herdr truth.
5. **The app shell files are already concentration points.** Adding all remaining V1 state directly to `BessieProductShell` or `ConnectionViewModel` would make testing and lifecycle reasoning materially harder.
6. **Current tests are strongest below the SwiftUI/AppKit boundary.** Core projections, actions, terminal sequencing, persistence, and notification planning have focused tests. Quit/window behavior, menu-bar lifecycle, UI filtering, notification cold start, and remote end-to-end behavior do not.

## Suggested implementation dependency order from the inventory

This is a dependency map, not an implementation plan:

1. Establish explicit application/window/connection lifetime ownership for quit, last-window closure, and future menu-bar operation.
2. Fix and extend shared connection-scoped entity projections used by Herd, attention, menu bar, and command palette.
3. Build attention presentation state and notification/menu-bar policy on that shared identity model.
4. Add layout presets using the existing typed Herdr action substrate.
5. Add entity-aware command-palette results using the same connection-scoped targets and existing safe action handlers.
6. Introduce a separate local file/Git capability boundary with canonical root and containment rules; do not attach it directly to remote projections.
7. Add coherent appearance/theme environment propagation before multiplying new primary surfaces.

## Verification performed for this inventory

- Inventoried every file under `Sources/BessieApp/` and `Sources/BessieCore/`, then inspected the implementation and tests relevant to each feature area.
- Searched the repository for Rust sources/manifests, status-item APIs, filesystem watchers, Git commands/adapters, explicit application termination, and AppKit window delegates.
- Confirmed the repository remained on `main`.
- No build, tests, Mac verification, packaging, install, commit, push, or product implementation was performed because this task was research-only.
