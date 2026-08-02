# Goal progress

## 2026-08-02 — V1 Slice F2: workspace media and markdown viewer

Status: implementation complete; shared-mirror integration verification blocked by unrelated Slice J source drift.

Changed behavior:

- Files is a local-workspace surface backed by `WorkspaceFS`, with capped directory browsing, directories-first sorting, image preview, AVKit video preview, read-only plain text, and honest remote/missing-root states.
- Markdown has native preview and edit modes, explicit atomic Save, content-backed revision checks, and explicit Reload/Overwrite handling for stale files. Saves remain bound to the loaded file even if selection changes, and edits made during an in-flight save remain visibly dirty.
- Rename/move destinations are workspace-relative and containment-checked. Delete requires confirmation and moves the selected item to macOS Trash. Mutations reject symbolic links rather than acting on their referents.
- Directory and file loads cancel stale work so rapid navigation cannot publish older results over the current selection.

Evidence:

- VPS `./scripts/check.sh`: passed.
- Clean disposable Mac checkout `xcrun swift test`: 183 tests executed, 4 live-Herdr tests skipped because the isolated live socket was not supplied, 0 failures.
- Focused Mac F2 suite: 6 tests, 0 failures, covering list sorting/capping, atomic save and stale conflict, escape rejection, Trash injection, symbolic-link mutation rejection, read-only text selection, and Files navigation registration.
- macOS 14 compilation passed after replacing the unsupported `ContentUnavailableView(actions:)` overload.
- `./scripts/mac-verify.sh` was attempted after syncing F2. It stopped during production compilation in unrelated shared-mirror files `AttentionList.swift` and `HerdList.swift`, which reference missing Slice J types (`RoutedPaneTarget` and `AgentSemanticState.sortRank`). Packaging, the new Files screenshot, `/Applications/Bessie.app` replacement, and installed-executable matching did not run in that attempt.
- `git diff --check` passed for the F2 implementation and verification files.

Review and hardening:

- Reuse, quality, and efficiency passes removed duplicate Trash handling and repeated text reads, moved blocking file work off the main actor, canceled stale navigation tasks, and clarified markdown-only errors.
- Independent review found file-identity, in-flight-save, and symbolic-link referent risks; those were repaired and covered by focused tests.
- Descriptor-scoped protection against an adversarial process replacing a validated path between check and mutation remains a limitation of the existing URL-based F0 `WorkspaceFS` contract, not a new F2 guarantee.

## 2026-07-31 — Complete herd roster

Status: complete.

- The herd now reads Herdr's authoritative top-level agent roster instead of deriving membership from panes that happen to carry a legacy `agent` field.
- Every tracked agent is included across every workspace regardless of whether its state is working, idle, blocked, done, or unknown.
- Legacy pane-level agent metadata remains a compatibility fallback and is de-duplicated against the authoritative roster by pane ID.
- Focused Mac `SurfaceProjectionTests`: 11 tests, 0 failures, including a two-workspace roster with idle and unknown agents.
- Full Mac verification: 63 tests, 0 failures; debug and production builds, signing, packaging, live Herdr checks, and design snapshots passed.
- The verified package was installed at `/Applications/Bessie.app`, relaunched, and matched the packaged executable by SHA-256.

## 2026-07-31 — Native shortcuts and command palette

Status: complete.

Changed behavior:

- Bessie now uses native macOS Command shortcuts instead of exposing Herdr's terminal-oriented `Ctrl+B` prefix. Ordinary terminal input and Control sequences remain untouched.
- `Cmd+B` opens a searchable, keyboard-navigable command palette. It shows action names, descriptions, and shortcut glyphs; users can search, use arrow keys, press Return, or click to run an action.
- Workspace, tab, pane focus/swap/split/close/zoom/resize, rail, notification, settings, and direct tab selection route to Bessie's existing public Herdr actions and reconcile through the authoritative snapshot path.
- Directional pane focus resolves against Herdr's projected layout geometry; it does not invent a second topology model.
- Sheets keep their own keyboard input. Nonmatching key combinations pass through to the focused terminal.

Evidence:

- VPS `./scripts/check.sh`: passed.
- Focused Mac `swift test --filter KeyboardShortcutTests`: 6 tests, 0 failures.
- Full `BESSIE_AGENT_KIND=codex ./scripts/mac-verify.sh`: exit 0.
- Mac Swift suite: 62 tests, 0 failures, including native Command routing, palette search metadata, terminal pass-through, and directional geometry.
- Debug and production builds completed; `dist/Bessie.app` was packaged and validated.
- The isolated live Herdr 0.7.5 / protocol 17 checks, real libghostty panes, composite input, process launch, reconnect, app reopen, screenshots, signing, and exact-process cleanup all remained green.

## 2026-07-31 — Milestone 1: native shell and reproducible build

Status: complete.

Changed surfaces:

- SwiftPM manifest with `BessieApp`, `BessieCore`, two focused test targets, and exact `libghostty-spm` `1.3.2` / `GhosttyTerminal` dependency.
- Native SwiftUI Connect state and adapted Bessie cow mark, monochrome palette, spacing, typography, card, and cow-print treatment.
- macOS app packaging plus guarded VPS-to-Mac mirror verification without `rsync --delete`.

Evidence:

- Mac baseline: `xcrun swift test` resolved `libghostty-spm` at `1.3.2` and failed as expected because `BessieCompatibility` and `ConnectPresentation` did not exist yet.
- VPS environment: no Swift executable is installed; `scripts/check.sh` therefore performs static checks here and delegates native build/test/package evidence to `scripts/mac-verify.sh`.
- VPS check: `./scripts/check.sh` passed shell syntax, exact dependency/product pin, Connect model, and resource checks.
- Mac verifier: `./scripts/mac-verify.sh` synced only after validating `/Users/jordanstella/GitHub/bessie/.bessie-mirror`; it does not use `rsync --delete`.
- Mac tests: `xcrun swift test` executed 2 tests with 0 failures. The compatibility baseline and initial Connect presentation both passed.
- Mac build/package: the arm64 release build completed, `dist/Bessie.app/Contents/Info.plist` passed `plutil`, and the ad-hoc signature passed `codesign --verify --deep --strict`.
- Mac launch: `open -na /Users/jordanstella/GitHub/bessie/dist/Bessie.app` produced the expected `BessieApp` process, which remained alive for the smoke interval and was then stopped by exact PID. This stops only Bessie and cannot touch Herdr.
- Visual capture attempt: the packaged app launched, but `screencapture -x` over the SSH session returned `could not create image from display`. The Connect layout received a code-level visual inspection; a screenshot is not claimed for this checkpoint and remains required at the final Mac UI gate.

Deliberate exceptions and next risk:

- The native SwiftUI surface has no image/snapshot test. This checkpoint uses app-model tests plus native compile/package/launch verification because the current SSH session cannot capture the display. Real screenshot inspection remains a required later milestone gate.
- Live Herdr behavior is outside Milestone 1. `mac-verify.sh` explicitly describes its current launch-only scope; later milestones must extend it rather than treating this pass as live-runtime evidence.

## 2026-07-31 — Milestone 2: discovery, compatibility, snapshot, and recovery

Status: complete.

Changed behavior:

- Runtime discovery checks `BESSIE_HERDR_PATH`, PATH candidates, then `.local/herdr/herdr` and `.local/bin/herdr` in that order.
- `herdr status server --json`, `ping`, and snapshot metadata produce explicit runtime version/protocol diagnostics and honest not-found, stopped, incompatible, connecting, connected, retrying, and lost states.
- BessieCore connects only to Herdr's public Unix-socket NDJSON API. It frames partial/multiple records, correlates response IDs, and surfaces typed server, transport, malformed-data, connection-closed, and correlation errors.
- Bootstrap opens and waits for an acknowledged `events.subscribe` connection before requesting `session.snapshot` on a separate connection. Events are buffered while the first snapshot is in flight and any buffered event forces another authoritative snapshot.
- Later subscribed events are invalidation hints: the connection runner resnapshots rather than applying event payloads as durable topology.
- Reconnect uses the bounded delays `0.25, 0.5, 1, 2, 4` seconds and ends in an honest lost state after exhausting them.
- The only Bessie-owned durable model is `BessiePresentationState`, containing terminal/pane preferences and an optional last-workspace identifier hint. Snapshot and workspace collections cannot be persisted through this type.
- The native Connect surface now reports live discovery/compatibility/connection/recovery state and authoritative snapshot counts.

Proof-first and repair evidence:

- Initial Mac compile failed as expected with missing `HerdrRuntimeLocator`, `NDJSONFramer`, response/error/snapshot types, `HerdrAPI`, bootstrap, reconnect, persistence, and connection states.
- The connected-presentation test then failed as expected because `ConnectPresentation(connectionState:)` did not exist.
- First live run reached the official runtime but returned an empty-ID `invalid_request`: the global subscription incorrectly included `pane.agent_status_changed`, whose protocol-17 schema requires a pane ID. The global bootstrap now subscribes only to universal invalidations; pane-targeted agent-status filters must be installed after snapshot discovery. Empty-ID server errors are also decoded as server errors rather than false correlation failures.
- The next live attempt exposed stale local socket files after exact-PID shutdown; the verifier now removes only the two known socket nodes after proving no repository-local Herdr server is running.
- The event test initially expected the subscription selector spelling `workspace.created`; live protocol output correctly uses the event-envelope spelling `workspace_created`. The assertion now matches the observed wire value.
- The first reconnect assertion counted historical-event resnapshots as a restart success. It now captures the pre-restart connected count and requires a strictly newer connected state after restart.

Final verification:

- VPS `./scripts/check.sh`: passed. Swift remains unavailable on the VPS, so this is the documented structural/shell gate.
- Mac `./scripts/mac-verify.sh`: passed.
- Mac Swift tests: 18 executed, 0 failures. The live test used the isolated socket rather than skipping.
- Official runtime: `herdr-macos-aarch64` 0.7.5 downloaded under the Mac mirror and matched SHA-256 `37350546b0012555943b92eaf962665de4e264395baeb44227b8015e8ff5b0d6`.
- Live API: ping returned Herdr 0.7.5 / protocol 17; event subscription was acknowledged; snapshot bootstrap passed; a live `workspace.create` produced `workspace_created`; a subsequent snapshot contained the created workspace; the test closed it afterward.
- Live app: its diagnostic state sequence was `Connecting`, multiple `Connected` resnapshots from invalidations, `Retrying`, `Connecting`, `Connected` after only the isolated Herdr server was restarted.
- Release build, plist validation, ad-hoc signature verification, packaging, and app launch all passed.
- Cleanup check found no remaining `.local/herdr/herdr server` or packaged `BessieApp` process.
- Isolation repair: all isolated Herdr server/status and app-probe invocations now receive task-specific `XDG_CONFIG_HOME` and `XDG_STATE_HOME` under `.local/herdr`. Herdr's own ready output reported API/client sockets under `.local/herdr/runtime` and logs at `.local/herdr/xdg-config/herdr/herdr-server.log`; the verifier rejects the global `/Users/jordanstella/.config/herdr` path. No global log/config cleanup was attempted.

Deliberate exception:

- Persistence encoding and file storage are implemented and unit-tested, but no setting or last-workspace hint exists yet for the Milestone 2 Connect-only UI to write. Later workspace/settings surfaces should use this store; no runtime snapshot data may be added to it.

## 2026-07-31 — Milestone 3: workspaces, tabs, panes, and layout projection

Status: complete.

Changed behavior:

- `HerdrSessionProjection` decodes authoritative workspace, tab, pane, focus, zoom, and flat layout records from `session.snapshot`. It reconstructs recursive split nodes from public split IDs and carries exact Boolean split paths for ratio changes.
- `HerdrAction` covers workspace create/focus/rename/move/close; tab create/focus/rename/move/close; pane split/focus/resize/directional or explicit swap/move/zoom/rename/close; and `layout.set_split_ratio`. Every request uses the public protocol-17 method and payload shape.
- `HerdrActionClient` never maintains a durable local topology: it sends one mutation and immediately returns a fresh projected `session.snapshot`.
- Close metadata states that closing acts on Herdr-owned processes, distinguishes workspace cascades for final tabs/panes, and states that quitting Bessie does not terminate those processes. Focus fallback is derived only from the latest projection.
- The connected app now renders a native workspace sidebar, authoritative tab strip, selected versus Herdr-focused states, and recursive split pane chrome. Pane bodies explicitly say that the terminal surface arrives in Milestone 4; no terminal output is imitated.
- Connected-state diagnostics include the workspace labels from each authoritative snapshot so the Mac verifier can prove external CLI convergence without scraping visual UI state.

Proof-first and repair evidence:

- `ProjectionActionTests` first failed to compile with the missing projection/action types, then passed after the production implementation.
- Exact-payload coverage includes every Milestone 3 action family and all three public pane-move destination variants. A recording API proves mutation then `session.snapshot` ordering.
- The first live action run caught a false assumption that a tab's public identifier remains attached to the same position after reorder. Herdr renumbers public tab identifiers when topology order changes; the integration flow now discards pre-move identifiers and reacquires current tabs and panes from the returned snapshot, matching the product contract.
- The first external-mutation/restart run allowed event-resnapshot backlog to overlap server shutdown. The verifier now waits for the app to observe the CLI-created workspace close, then captures the connected count and requires a later connected state after restart.

Final verification:

- VPS `./scripts/check.sh`: passed the shell and structural gate.
- Mac `./scripts/mac-verify.sh`: passed with exit 0.
- Mac Swift tests: 23 executed, 0 failures; neither live Herdr test skipped.
- Live Bessie-to-Herdr mutations: create, rename, reorder, focus, and close workspace/tab state; split, focus, rename, resize, exact root ratio, explicit swap, zoom on/off, move across tabs, and close pane state all succeeded against isolated Herdr 0.7.5 / protocol 17. Each assertion used the immediately subsequent snapshot.
- Live Herdr-to-Bessie mutation: the public CLI created and renamed a uniquely labeled workspace while the packaged app was already running; app diagnostics recorded both labels from authoritative resnapshots, then recorded an empty workspace set after exact cleanup.
- Release packaging, plist validation, ad-hoc signing, packaged app launch, isolated server restart, running-app reconvergence, final socket snapshot, and exact-PID cleanup passed.
- The verifier used unique run labels, captured initial workspace identifiers, and closed only workspaces created by that test. It left no packaged Bessie or repository-local Herdr server process running.

Deliberate exception and next risk:

- Visual screen capture remains unavailable to the SSH session (`screencapture` cannot create an image from the display), so no screenshot inspection is claimed. The native connected shell was compiled and exercised through live app diagnostics, but the final visual gate still requires an interactive Mac display.
- Milestone 4 must replace every visible pane placeholder with a real `GhosttyTerminal` surface and prove terminal frame, input, scroll, resize, controller-conflict, and reconnect behavior.

## 2026-07-31 — Milestone 4: real terminal surfaces and controller lifecycle

Status: complete.

Changed behavior:

- Every visible pane now hosts the native AppKit `GhosttyTerminal` view with an `InMemoryTerminalSession`; placeholder terminal output is gone.
- `TerminalControllerRegistry` retains one `PaneTerminalController` per visible Herdr pane identifier across SwiftUI updates and releases controllers that leave the authoritative visible layout.
- Each pane owns exactly one `herdr terminal session control` process without implicit `--takeover`. The decoder accepts the pinned 0.7.5 `bytes`/`width`/`height` frame names and documented `bytes_b64`/`cols`/`rows` aliases, but rejects unknown encodings and malformed base64.
- Frame application requires a matching initial full repaint and contiguous sequence numbers. Duplicate frames are ignored; gaps, terminal closure, and controller exits freeze input, restart the controller, and wait for a new full repaint. Resize is debounced and also gates input until the matching full repaint.
- Composite input is ordered through a single router: libghostty committed bytes use `terminal.input`, supported intercepted keys use `pane.send_keys`, paste uses `pane.send_input.text`, and page/wheel scroll uses `terminal.scroll`.
- V1 does not inject inner-application mouse events, focus events, or Kitty keyboard protocol messages. Shift-drag invokes libghostty's local selection behavior.

Proof-first and repair evidence:

- `TerminalControllerTests` initially failed to compile because the frame envelope, sequencer, protocol commands, input router, process invocation, and failure classifier did not exist. After implementation, all eight focused tests passed.
- The first live terminal proof reached a real full repaint and multiple deltas, but automation checked markers only after generating and scrolling through 80 lines. The marker check now occurs before the scroll workload, while a separate assertion records the public scroll command.
- Direct execution of an AppKit binary over SSH can leave SwiftUI's `WindowGroup` unconstructed. The verifier now launches the packaged app through LaunchServices with explicit per-process environment values, then resolves and controls the exact executable PID.
- A failed verifier run left its intentionally created workspace in repository-local Herdr state. Later runs now use unique repository-local XDG config/state directories, preventing stale test topology from affecting selected-controller assertions without deleting any external state.
- The controller's asynchronous pipe handlers were routed through queue helper methods to avoid Swift 6 concurrent-capture warnings. Cleanup is explicit through the registry; the unsafe synchronous `deinit` release path was removed.

Final verification:

- VPS `./scripts/check.sh`: passed the shell and structural gate.
- Mac `./scripts/mac-verify.sh`: passed with exit 0.
- Mac Swift tests: 31 executed, 0 failures, including eight focused frame/controller/input tests and live Herdr tests.
- The packaged executable linked Apple's Metal framework and contained the `GhosttyTerminal.AppTerminalView` symbols. Live `InMemoryTerminalSession` viewport reads then observed terminal output from the visible surfaces, proving the linked terminal was actually fed by Herdr frames rather than merely present in the build.
- Two live panes each received an independent full repaint, raw Unicode input (`牛é🐄`), an intercepted Enter, paste, deltas, resize traffic, and scroll traffic. Public `pane read` returned distinct raw and pasted markers for both pane identifiers.
- The verifier observed exactly two child controller processes for two visible panes. Killing one produced a reconnecting state and a later fresh ready state; a competing writable controller received Herdr's ownership-conflict response because Bessie never used `--takeover`.
- Bessie quit within the bounded cleanup interval, both controller processes exited, and public pane reads proved terminal processes and output survived. Reopening Bessie reacquired two fresh controllers. Closing the test workspace released both controllers without a hang or pane-owned process leak.
- The isolated server restart/reconnect, release packaging, plist/signature checks, final public snapshot, and exact-PID cleanup also passed.

Deliberate exception and next risk:

- The SSH display session still cannot produce a screenshot, so no visual screenshot inspection is claimed for this milestone. Metal/libghostty linkage and live viewport behavior are proven, but the final interactive Mac visual gate remains open.

## 2026-07-31 — Milestone 5: focused product surfaces and native visual identity

Status: complete.

Changed behavior:

- Connect retains explicit discovery, stopped, incompatible, retrying, and lost states, with retry and provenance-honest setup help. It never claims to install or replace Herdr.
- Workspaces is now the connected chooser/switcher. Every row comes from the current projection and includes tab/pane counts, rolled semantic state, and blocked/done attention count. Create, focus/open, rename, move up/down, and confirmed close controls call `HerdrActionClient` and replace the projection with the subsequent snapshot.
- Workspace retains the real libghostty pane grid and adds a product header, authoritative tab strip, New pane entry point, pane status chrome, and native/context controls for tab create/focus/rename/reorder/close and pane focus/split/resize/zoom/rename/close.
- Attention lists only Herdr-provided blocked and done pane state, names the workspace/tab/pane location and Herdr provenance, and offers only **Open pane**. Opening performs workspace, tab, and pane focus through Herdr and reconciles the final snapshot.
- The native Settings scene contains appearance, cow-print intensity/motion, terminal font size, pane gap, notification policy, startup behavior, and connection/runtime diagnostics. The adaptive warm off-white/cowprint-dark palette visibly follows appearance; cow motion pauses for Reduce Motion; terminal font and pane gap configure the real terminal/grid; last-workspace startup is persisted as a hint and revalidated.
- Notification policy is persisted, but this alpha does not request macOS notification permission or claim notification delivery. That adapter remains unexercised rather than being represented as complete.
- The visual system uses system type, sharp flat surfaces, restrained monochrome cow print, warm off-white/black, and red only for blocked/destructive emphasis. Empty Workspaces, empty Attention, missing layout, Connect failures, and action errors have intentional native states.

Proof-first and repair evidence:

- `SurfaceProjectionTests` first failed to compile on missing surface projection, attention, open-target, and expanded preference types. After implementation, all three focused tests passed, including legacy preference decoding.
- The first app-owned 920×620 PNG contained the rail but a blank main area because `NSView.cacheDisplay` did not composite the main layer. Capture now asks the app for its exact window image and retains `cacheDisplay` only as fallback; it does not use fake HTML or require Screen Recording.
- The next image showed the real split workspace but captured both headers during transient `SYNCING`. Investigation found identical SwiftUI `fitToSize` callbacks repeatedly re-gated the controller. The controller now ignores unchanged grid/cell metrics, and capture requires four consecutive ready polls.
- The old Milestone 3 placeholder workspace views were removed after the new product surface replaced them; there is one native workspace implementation.
- Mac verification receives a unique repository-local presentation path, preventing tests from reading or modifying the user's ordinary Bessie preferences.

Final verification:

- VPS `./scripts/check.sh`: passed.
- Mac `./scripts/mac-verify.sh`: passed with exit 0.
- Mac Swift tests: 34 executed, 0 failures. The three new surface/settings tests and all live Herdr/controller tests passed.
- Debug and production builds completed without warnings. Release packaging, plist validation, ad-hoc signing, Metal/Ghostty symbol checks, two-pane live behavior, app-reopen survival, isolated server restart, and exact-process cleanup passed.
- The app-owned screenshot artifact is `/Users/jordanstella/GitHub/bessie/dist/Bessie-window.png`; the verifier confirmed PNG, 920×620, and greater than 20 KB.
- Visual inspection of that artifact confirmed a substantive native Workspace surface: warm off-white adaptive theme, sharp rail and pane borders, readable system/monospaced hierarchy, selected Workspace navigation, visible New pane control, two distinct real terminal viewports, and both pane headers reading `LIVE`.
- The same run's public pane reads retained the distinct raw Unicode and paste markers, so the screenshot's terminal regions correspond to the live Herdr/libghostty verification rather than decorative stand-ins.

Next risk:

- Native notification delivery is intentionally not claimed. Before a release milestone, add permission handling and event-driven delivery tests for the stored policy.

## 2026-07-31 — Milestone 6: process launch and attention

Status: complete within the available Mac prerequisites.

Changed behavior:

- **New pane** is a native sheet for Shell or Supported agent, with Split right, Split down, and New tab placement. Shell launch uses Herdr's public pane/tab primitives and selects the returned authoritative pane.
- The supported-agent catalog decodes public `server.agent_manifests` data. It shows manifest version data, checks each canonical executable on the app PATH, and disables missing executables with an explicit reason.
- Agent launch generates a unique semantic name, accepts optional one-argument-per-line input, and sends the exact public `agent.start` envelope. A failed agent start reports the error while retaining the already valid shell pane; Bessie never closes it as rollback.
- Pane and workspace surfaces continue to display only Herdr's semantic agent states. Attention remains restricted to Herdr-reported blocked/done items and **Open pane**; terminal text is never treated as an approval signal.
- Notification policy remains persisted presentation state only. Native permission and delivery are not claimed because safe event-driven delivery was not available to exercise in this milestone.

Proof-first and final verification:

- `ProcessLaunchTests` initially failed to compile on the absent catalog, availability, semantic-name, action, and launcher types. Four focused tests now prove manifest-backed availability/reasons, compact optional `agent.start` arguments, unique semantic names, and shell preservation after an agent-start error.
- Live protocol inspection confirmed protocol-17 `agent.start` fields and returned 19 bundled `agent_manifest_status` records through `server.agent_manifests`.
- VPS `./scripts/check.sh`: passed, including structural checks for the catalog, launch action, native sheet, and app-owned live automation path.
- Mac `./scripts/mac-verify.sh`: passed with exit 0. Mac Swift tests executed 38 tests with 0 failures; production packaging, signing, app launch, real libghostty terminals, controller recovery, reconnect, and isolated cleanup also passed.
- The packaged app created a new shell pane through the process-launch flow. The verifier obtained its pane ID from the app-owned state record, waited for its terminal controller, and used public `herdr pane read` to find that pane's distinct raw Unicode marker, proving a real retained Herdr shell rather than decorative UI.
- The live verifier decoded the authoritative agent manifest. No Herdr-supported agent executable was installed on the Mac PATH, so it recorded `Agent live prerequisite unavailable: no Herdr-supported agent executable is installed on the Mac PATH.` The fixture-backed exact-payload and failure-preservation tests cover the agent branch; live agent success is not claimed.

Remaining prerequisite:

- A supported agent CLI must be present on the Mac PATH before the conditional live verifier can prove successful `agent.start`. Installing one is outside this contract. Native notification delivery likewise remains a documented V1 gap rather than a manufactured pass.

## 2026-07-31 — Milestone 7: verification and Mac handoff

Status: complete.

Final verification and repair:

- The required simplification pass removed an unused full-viewport parse and SwiftUI publication from every terminal frame, consolidated diagnostic logging, reused shared action/JSON helpers, made split launch construction safe, prevented duplicate manifest loads, coalesced focus mutations into one final snapshot, added explicit connection cancellation, and bounded controller restart/stderr growth.
- Visual inspection caught stale pane status chrome: a newly split pane displayed `STARTING` after its controller was already live because the header did not observe the controller object. The status label now owns an `@ObservedObject`; the next captured image showed both headers at `LIVE`.
- Two focused tests were added for batched action ordering/single reconciliation and cancellation before discovery.
- Three independent reuse, quality, and efficiency reviewers inspected the full source tree. Applied findings by reviewer dimension: reuse 3, quality 5, efficiency 6, with overlapping findings counted in each relevant dimension. Two suggestions were skipped because they added parameter-grouping abstraction or changed preference-persistence timing without a demonstrated V1 benefit. The formal Compound code-review runner was unavailable because the contract requires an uncommitted unborn repository and that runner excludes untracked files; a direct correctness, standards, safety, and test scan found and repaired the stale status-observation defect.

Final evidence:

- `./scripts/check.sh && ./scripts/mac-verify.sh`: exit 0.
- Mac Swift tests: 40 executed, 0 failures.
- Debug and production builds completed without reported warnings; package plist and strict ad-hoc signature checks passed.
- Live public Herdr checks covered all representative workspace/tab/pane mutations, two real libghostty terminals, input/output/resize/scroll, ownership conflict, controller reconnect, external-to-app convergence, app quit/reopen survival, app-driven shell launch, manifest discovery, and isolated server restart.
- The final inspected 920 x 620 PNG was 70,062 bytes and showed two distinct real terminal viewports with both pane headers at `LIVE`.
- `/Users/jordanstella/GitHub/bessie/dist/Bessie.app` exists and passed launch checks. Its packaged executable was 10,863,024 bytes in the final checked artifact.
- Final Mac process inspection found no BessieApp, repository-local Herdr server, or Bessie terminal-session-control process. Cleanup touched only exact repository-local PIDs.
- `git diff --check` passed. The repository remains uncommitted and wholly untracked as required; no commit, push, publication, global installation, or upstream modification occurred.

Handoff:

- `README.md` provides the ordinary one-path VPS-to-Mac verification commands and explains the isolated runtime, artifact, screenshot, and cleanup behavior.
- `docs/reports/mac-v1-alpha.md` records exact final evidence, exercised criteria, honest limitations, and reset/cleanup instructions.
- Known external prerequisite: no Herdr-supported agent CLI exists on the Mac PATH, so successful live agent startup is not claimed. Notification delivery is also explicitly not implemented.

## 2026-07-31 — UI copy and information-hierarchy goal closure

Goal contract:

- `docs/reports/completed-ui-copy-contract.md` bounded the completed work to reachable user-facing copy and information hierarchy while preserving Herdr/libghostty behavior, safety consequences, errors, visual fidelity, and the complete native verification path.
- Audited 387 app string literals; 295 were mechanically flagged as likely UI-facing and then reviewed in context. Three parallel read-only reviewers independently covered all native app strings, the retained UI kit's canonical voice, and senior UX-writing/product-risk concerns.

Applied product direction:

- Copy now states current condition, consequence, or next action. Product surfaces no longer narrate the public protocol, authoritative snapshots, controller architecture, shadow models, native implementation, or future plans.
- Removed alpha/prototype framing from visible chrome, fake shortcut/status labels, unavailable layout and notification controls, and empty Trace/History/Provenance panels.
- Standardized `workspace`, `tab`, `pane`, `agent`, `needs you`, `Open workspace`, `New pane`, `Pane actions`, `Action failed`, and user-facing untitled fallbacks.
- Reduced redundant empty-state/filter/count copy and made New pane's shell layout compact while preserving the full agent catalog layout.
- Incorporated direct review feedback by removing the duplicate static `Workspace` navigation item, grouping active workspaces under `OPEN`, and replacing the broken/incorrect Attention glyph with a rendered bell.
- Added accessibility labels for rail counts, workspace/tab/pane menus, Settings controls, cowprint motion/contrast, font size, and pane spacing.
- Added `scripts/check-ui-copy.sh` to the normal static-check path. It rejects known planning/implementation residue and requires the accepted product vocabulary.

Final evidence:

- `./scripts/check.sh && ./scripts/mac-verify.sh && git diff --check`: exit 0.
- Full isolated Mac verifier: 40 Swift tests executed, 0 failures, including both live Herdr tests; debug and production builds, plist validation, strict ad-hoc signing, live mutations, terminal control, reconnect, app reopen, server restart, packaging, and connected launch passed.
- Design snapshot: 1180 x 740; rail luminance 11.26; cowprint standard deviation 3.20; mean chroma 0.00.
- Humanizer scan: 0 findings, 0 high.
- Fresh post-copy visual review covered Connect, active workspace, Workspaces, Attention, Settings, New pane, The herd, and Agent Detail. All seven full-window captures were 1180 x 740; New pane shell mode was 760 x 360. No clipped copy, missing symbol, redundant static Workspace item, fake control, or blocking visual defect remained.
- Final packaged executable: 12,379,568 bytes at `/Users/jordanstella/GitHub/bessie/dist/Bessie.app/Contents/MacOS/BessieApp`.
- Final process inspection found no packaged Bessie app, repository-local Herdr server, or Bessie terminal-controller process.
- The repository remains intentionally uncommitted and unpushed.

## 2026-07-31 — Bessie 0.1.0 release candidate 1

Status: ready for Jordan's hands-on acceptance test.

Release-candidate repairs and evidence:

- Added authoritative visible-pane targeting, deferred notification-click routing, and an explicit observer-to-takeover terminal transition that never silently steals control.
- Corrected downward workspace and tab drag reordering against Herdr 0.7.5's pre-removal insertion-slot semantics.
- Strengthened live Codex assertions so pane identity, agent kind, and semantic status come from the same authoritative object.
- Rejected undersized CoreGraphics window thumbnails and fell back to AppKit content capture; the final Workspace and Settings artifacts were both 1180 x 740.
- `./scripts/check.sh`, `git diff --check`, and `BESSIE_AGENT_KIND=codex ./scripts/mac-verify.sh`: exit 0.
- Added signed dark and light desktop icon resources plus a persisted Settings choice for the Dock and app switcher. The verifier loaded the light icon from the packaged resource bundle; legacy preferences retain the dark default.
- Rebuilt `README.md` around the supplied animated light/dark GitHub artwork, verified native screenshots, badges, installation, usage, acceptance testing, architecture, development, and V1 boundaries. Matching social-preview assets are retained under `.github/assets/` for repository setup.
- Mac Swift tests: 50 executed, 0 failures. Production build, both icon resources, default icon metadata, plist validation, ad-hoc signing, live Herdr/libghostty/Codex acceptance, app-reopen survival, isolated restart, screenshots, and exact-process cleanup passed.
- Final packaged executable: 12,980,128 bytes at `/Users/jordanstella/GitHub/bessie/dist/Bessie.app/Contents/MacOS/BessieApp`; SHA-256 `5d4187f2f03787968faf0f796e616d8c7524e2bd11427e23b5d1886cf015bcfe`.
- Verified archive: `/Users/jordanstella/GitHub/bessie/dist/Bessie-0.1.0-rc.1.zip`, 7,744,314 bytes; SHA-256 `7b339292bd611c8fce51b32ee50af53ae732f9eceb08f740cc43fd90fadf7bd4`.
- Installed the verified candidate at `/Applications/Bessie.app`. Its post-install signature and executable hash matched the checked package, and a LaunchServices start with a Finder-minimal `PATH` found the user-local Herdr runtime, applied the persisted dark icon, and presented the honest stopped-server setup state.

Acceptance boundary:

- Automated release-candidate verification is complete. Hands-on testing remains required for native drag feel, split-divider feel, notification authorization and system delivery, notification click routing, and confirmed observe-to-takeover behavior.
- Notarization and general publishing remain outside this candidate.

## 2026-07-31 — Bessie 0.1.0 release candidate 2

Status: verified, installed, and ready for hands-on acceptance.

- Bessie now locates the intended Herdr 0.7.5 runtime, reuses a healthy named `bessie` server, or starts it as a detached background process and waits for readiness before connecting. The unrelated `default` session remains untouched.
- Terminal-controller subprocesses inherit the exact runtime/socket environment, so every visible terminal stays on the same named session.
- A verifier-exposed race in New pane was reproduced with a deliberately slow interactive shell: immediate `agent.start` returned `agent_pane_busy`, while the same request succeeded after the shell became ready. Bessie now retries only the fresh-pane `busy` and `unavailable` errors on bounded delays and preserves the shell for every other failure.
- `./scripts/check.sh`, `git diff --check`, and `BESSIE_AGENT_KIND=codex ./scripts/mac-verify.sh` passed. The Mac run executed 54 Swift tests with 0 failures, production-built and signed the app, exercised automatic detached startup, live Herdr/libghostty/shell/Codex behavior, survival and recovery, and validated both 1180 x 740 screenshots.
- Packaged executable: 13,026,320 bytes; SHA-256 `faec204ea555946f6e8b8162b990e2d1f53808ceecde17f53d5fbd47eb401666`.
- Verified archive: `/Users/jordanstella/GitHub/bessie/dist/Bessie-0.1.0-rc.2.zip`, 7,752,137 bytes; SHA-256 `799efbd84a0622194e8c136ae98f12af2ee46261987e169216a050ddac5ff9f3`.
- Installed `/Applications/Bessie.app` reports version `0.1.0` build `2`. A launch with no runtime/socket/session/PATH override started the user-local Herdr `bessie` session, reached `Connected`, left `default` stopped, and proved the server survived Bessie exit. The app was reopened normally and left running.
- Secure remote use remains `herdr --remote <ssh-host> --session bessie` until Herdr exposes a headless bridge that carries both sockets Bessie's graphical client requires.

## 2026-07-31 — Bessie 0.1.0 release candidate 3

Status: verified, installed, and ready for hands-on acceptance.

- Independent startup review found that an inherited generic `HERDR_SOCKET_PATH` could outrank `HERDR_SESSION` and redirect Bessie to an unrelated session. Bessie now removes generic socket pollution, reapplies its requested/default named session, and honors only the explicit diagnostic `BESSIE_HERDR_SOCKET_PATH` override.
- Added unit coverage for both isolation and the Bessie-specific diagnostic override. The live verifier injects generic `HERDR_SOCKET_PATH` and `HERDR_SESSION=default`, then proves Bessie starts the isolated `bessie` server and leaves `default` stopped.
- `./scripts/check.sh`, `git diff --check`, and `BESSIE_AGENT_KIND=codex ./scripts/mac-verify.sh` passed. The Mac run executed 56 Swift tests with 0 failures and repeated the complete production/signing, live Herdr/libghostty/Codex, survival/recovery, autostart, and visual acceptance path.
- Packaged executable: 13,026,608 bytes; SHA-256 `dbf7d2aeaeb5f566bf4c6628bca4d780074ea66da38d73c274ff7dce0f565f3e`.
- Verified archive: `/Users/jordanstella/GitHub/bessie/dist/Bessie-0.1.0-rc.3.zip`, 7,752,207 bytes; SHA-256 `da15555234e6e511be26e78876707bc2920d816583934047bef1e5fd49cb22e7`.
- Installed `/Applications/Bessie.app` reports version `0.1.0` build `3`; strict signature verification passed, the app is open, the compatible named `bessie` server is running, and `default` remains stopped.

## 2026-08-01 — Bundled Herdr Milestone 0 hard-gate audit

Status: superseded stop. This audit preserved useful release-tag and artifact evidence, but its conclusion was corrected on 2026-08-01 after Jordan confirmed the project-wide Apache-2.0 relicense and clarified the distinct artifact and compatibility commits. No runtime was embedded during this historical checkpoint.

Correction:

- Commit `cd5ea1be0e69ed49b6f32f7ed5b333f6c8526874` explicitly relicensed the Herdr project under Apache-2.0 one day after the v0.7.5 release. Jordan confirms Apache-2.0 is the governing project license. The immutable tag's earlier AGPL text is historical context, not the current redistribution grant.
- `ef4c23f5775bb8cfec05f05d0844226ff959a07a` is the v0.7.5 release artifact commit. `b4112743cff42452b5d18558bf2d55bbbfff8c69` is the later protocol/compatibility inspection baseline. Their expected difference is not an identity failure.

Baseline and protected work:

- `git status --short --branch` showed the expected dirty `feat/native-v1-alpha` worktree. The protected baseline contained modified `AGENTS.md`, `GOAL.md`, `README.md`, nine existing Swift source/test files, `docs/plans/2026-07-31-bessie-v1.md`, this progress report, and `scripts/check.sh`, plus the existing untracked instructions, Swift source/tests, V1/component plans, research/roadmap material, and UI-copy report shown by the command. None was reset, cleaned, stashed, staged, reverted, or overwritten.
- Baseline `./scripts/check.sh`: exit 0. UI-copy and static checks passed; Swift was unavailable on the VPS and remained delegated to Mac verification.
- Files added or appended by this gate audit: `docs/research/herdr-v0.7.5-LICENSE.txt` and `docs/reports/goal-progress.md` only.

Historical Hard Gate A evidence — redistribution:

- The authoritative v0.7.5 annotated tag resolves through `https://api.github.com/repos/ogulcancelik/herdr/git/ref/tags/v0.7.5` and `https://api.github.com/repos/ogulcancelik/herdr/git/tags/99df3ac37be6bd7be2fd2023f0d88a7a7101` to release commit `ef4c23f5775bb8cfec05f05d0844226ff959a07a` (`release: v0.7.5`, 2026-07-21).
- At that exact release commit, `https://raw.githubusercontent.com/ogulcancelik/herdr/ef4c23f5775bb8cfec05f05d0844226ff959a07a/Cargo.toml` declares `AGPL-3.0-or-later`, and `https://raw.githubusercontent.com/ogulcancelik/herdr/ef4c23f5775bb8cfec05f05d0844226ff959a07a/LICENSE` states that Herdr is dual-licensed under AGPL-3.0-or-later or a separately available commercial license.
- The exact tag-era license is retained byte-for-byte at `docs/research/herdr-v0.7.5-LICENSE.txt`. `cmp` against the fetched tag-era license exited 0; SHA-256 is `a7fa24f74382fb3e4d320a608533a7c2999dbc0f780f1f734c8b891b31f0d9bd`. It is retained as historical provenance, not embedded as the governing notice.
- AGPL section 6 permits object-code redistribution only when Corresponding Source is conveyed or offered by one of its enumerated methods. For network distribution, section 6(d) requires equivalent source access through the same place at no further charge, clear adjacent directions if hosted elsewhere, and continued availability. The license must accompany the Program and existing legal/warranty notices must remain intact. Section 5's aggregate clause says inclusion of a separate independent work does not by itself apply AGPL to the other parts of the aggregate.
- The exact release tree contains its root `LICENSE` and vendored license files, but no root `NOTICE` or `COPYRIGHT` file. The release metadata at `https://api.github.com/repos/ogulcancelik/herdr/releases/tags/v0.7.5` contains no separate artifact terms or notice text. A public Bessie distribution would therefore need the exact AGPL/commercial basis settled, the release license embedded, and a durable Corresponding Source delivery method if relying on AGPL. No commercial license was assumed.
- The later compatibility source revision `b4112743cff42452b5d18558bf2d55bbbfff8c69` declares Apache-2.0. The prior audit incorrectly required that compatibility revision to be the artifact build revision and did not account for the intervening project-wide relicense commit.

Historical Hard Gate B evidence — artifact identity:

- VPS download from `https://github.com/herdrdev/herdr/releases/download/v0.7.5/herdr-macos-aarch64`: exit 0; size `17,438,400` bytes; SHA-256 `37350546b0012555943b92eaf962665de4e264395baeb44227b8015e8ff5b0d6`; `file` reported a Mach-O 64-bit arm64 executable.
- GitHub's release asset metadata independently reports the same URL, size, and `sha256:37350546b0012555943b92eaf962665de4e264395baeb44227b8015e8ff5b0d6`. The asset was uploaded by `github-actions[bot]` on 2026-07-21.
- Isolated Mac probe on `jordan-macbook`: exit 0. The freshly downloaded artifact reported `herdr 0.7.5`; `file` reported `Mach-O 64-bit executable arm64`; an isolated named server reported version `0.7.5`, protocol `17`, session `bessie-artifact-gate-19371`, and both the API and terminal sockets existed. The temporary server was stopped by exact PID and its temporary root was deleted by the probe trap.
- The v0.7.5 tag resolves to release artifact commit `ef4c23f5775bb8cfec05f05d0844226ff959a07a`. GitHub's compare API reports compatibility baseline `b4112743...` is 98 commits later. Those facts were correct; classifying their difference as a source-identity failure was not.

Prior stop conclusion — superseded:

- The earlier run stopped before Gate C because it conflated the tag-era license with the later project-wide relicense and conflated release artifact provenance with the compatibility baseline. Jordan corrected both premises. The resumed gate evidence and Milestone 1 result follow in the next checkpoint.

## 2026-08-01: Corrected bundled Herdr gates and Milestone 1

Status: proven and implemented under ad hoc local signing. The pinned runtime is packaged and installed, and all required local and Mac checks pass. A real Developer ID identity was discovered, but its private key is not usable from the non-interactive SSH verification context, so Developer ID signing and notarization remain explicit public-release gates.

Gate A, redistribution:

- Jordan confirmed Apache-2.0 as the governing Herdr project license. The authoritative relicense commit is `cd5ea1be0e69ed49b6f32f7ed5b333f6c8526874`, whose subject is `chore: relicense herdr under apache-2.0`; it replaces the root license and updates package, README, changelog, and Nix metadata from AGPL to Apache-2.0.
- Apache-2.0 section 2 permits redistribution. Section 4 requires recipients to receive a copy of the license and requires retention of applicable attribution, patent, trademark, and modified-file notices. The relicensed root contains `LICENSE` and no root `NOTICE` or `COPYRIGHT` file. GitHub release metadata exposes no separate artifact terms.
- The exact current Apache license is retained at `docs/research/herdr-apache-2.0-license.txt`, SHA-256 `c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4`, and is embedded at `Bessie.app/Contents/Resources/Herdr/LICENSE`. The runtime lock records the license source URL, relicense commit URL, release URL, source path, bundle path, and the absence of separate artifact terms.
- The historical v0.7.5 tag-era AGPL text remains at `docs/research/herdr-v0.7.5-LICENSE.txt` as provenance context. It is not presented as the current governing grant and is not embedded in the app.

Gate B, artifact identity:

- Independent VPS and Mac downloads of `https://github.com/herdrdev/herdr/releases/download/v0.7.5/herdr-macos-aarch64` were `17,438,400` bytes with SHA-256 `37350546b0012555943b92eaf962665de4e264395baeb44227b8015e8ff5b0d6`.
- `file` and `lipo` identified a macOS arm64 Mach-O executable. The executable reported `herdr 0.7.5`. An isolated server reported version `0.7.5`, protocol `17`, and exposed both public sockets.
- Release artifact commit `ef4c23f5775bb8cfec05f05d0844226ff959a07a`, compatibility inspection baseline `b4112743cff42452b5d18558bf2d55bbbfff8c69`, and Apache relicense commit `cd5ea1be0e69ed49b6f32f7ed5b333f6c8526874` are recorded as distinct facts. Their difference is expected and no longer classified as an identity failure.

Gate C, bundle and execution proof:

- A temporary app placed the executable at `Contents/Resources/Herdr/herdr`, preserved mode `755`, signed and strictly verified the nested executable and enclosing app under the available ad hoc identity, and kept the nested checksum unchanged.
- The nested runtime started only against temporary config, state, and socket roots. It exposed both sockets, created workspace `w1` and pane `w1:p1`, and accepted a harmless public API command whose pane output contained `BESSIE_GATE_C_22488_OK`.
- The launched app process exited while the isolated Herdr server remained alive. Cleanup stopped only the recorded isolated PID. The ordinary `default` Herdr status was byte-for-byte unchanged before and after.
- A quarantined ad hoc bundle was rejected by `spctl` with exit 3, as expected. `/usr/bin/security find-identity -v -p codesigning` discovered `Developer ID Application: JORDAN JAMES STELLA (T4K7A3GPQ6)` with certificate fingerprint `5FEE8F7ECA28FA61BD589D44F26C760684FFC822`. Invoking the existing package path with that exact discovered identity reached nested runtime signing and failed with `errSecInternalComponent`, demonstrating that the private key is not currently accessible to `codesign` from the non-interactive SSH context. `notarytool 1.1.2` and `stapler` are installed, but notarization was not attempted after signing failed. No Developer ID or notarization success is claimed.

Milestone 1 implementation:

- Added `scripts/herdr-runtime-lock.json`, `scripts/fetch-herdr-runtime.sh`, and `scripts/check-herdr-runtime.py`. The fetcher uses one lock, a checksum-validated repository-local cache, a temporary HTTP download with retries and failure handling, pre-copy checksum verification, arm64 and version checks, and atomic destination staging. It never writes to a system Herdr path.
- `scripts/package-app.sh` now uses the single fetch path, copies only Bessie's SwiftPM resource bundle contents into the valid app resource location, embeds the locked runtime, Apache license, and provenance lock, verifies permissions and identity, preserves the official artifact's valid ad hoc signature for checksum fidelity, and signs the enclosing app. Its explicit Developer ID branch signs the nested executable before the app.
- `scripts/check.sh` now validates the runtime lock against `BessieCompatibility`, notice metadata and bytes, and package expectations. `scripts/mac-verify.sh` drives every live check through the packaged nested runtime, verifies package and installed identities, preserves a restorable installed-app backup through the smoke test, relaunches the installed app only against isolated state, and proves the ordinary default session is unchanged. It accepts an explicitly supplied `BESSIE_CODESIGN_IDENTITY` and passes it to the Mac packaging process without hardcoding certificate or team data.
- `BessieResources` resolves flat packaged resources from `Bundle.main` while preserving `Bundle.module` for development and tests. Packaging copies the Bessie resource bundle contents into `Contents/Resources`, avoiding an invalid resource bundle at the app root.
- Updated the bundled-runtime setup plan, the canonical V1 plan, and the shared workstream `V1-SCOPE.md` to distinguish artifact, compatibility, and relicense provenance. No runtime-selection UI, onboarding, Trouble, Projects, upstream Herdr changes, private protocol use, commit, push, publication, or deployment was added.

Changed files for this checkpoint:

- `scripts/herdr-runtime-lock.json`
- `scripts/fetch-herdr-runtime.sh`
- `scripts/check-herdr-runtime.py`
- `scripts/package-app.sh`
- `scripts/check.sh`
- `scripts/mac-verify.sh`
- `docs/research/herdr-apache-2.0-license.txt`
- `Sources/BessieApp/BessieDesignSystem.swift`
- `Sources/BessieApp/BessieSettings.swift`
- `docs/plans/2026-08-01-bundled-herdr-runtime-setup.md`
- `docs/plans/2026-08-01-bessie-v1.md`
- `docs/reports/goal-progress.md`
- `/home/hermes/.hermes/workspace/shared/workstreams/bessie/V1-SCOPE.md`

Verification and repair history:

- Baseline and final `./scripts/check.sh`: exit 0. Runtime lock, compatibility, notice, package expectations, UI copy, and static checks passed. Swift remains unavailable on the VPS and was verified on the Mac.
- `git diff --check` and shell syntax checks: exit 0.
- The first resumed full Mac run exposed a clean-build resource lookup failure. Copying the entire SwiftPM bundle to the app root then correctly failed strict code signing with `unsealed contents present in the bundle root`. The final implementation resolves resources through `Bundle.main` and copies only Bessie's resource contents into `Contents/Resources`; these failed runs remain part of the repair history rather than being relabeled as passes.
- Final `./scripts/mac-verify.sh`: exit 0. It ran 70 Swift tests with 0 failures, production-built and packaged the app, verified the locked runtime and Apache notice, exercised isolated live Herdr and libghostty output/input, shell and Codex launches, process survival and reconnect, controller recovery, external CLI convergence, isolated Herdr restart, installation, installed executable identity, and isolated installed-app relaunch.
- Both 1180 x 740 screenshots passed the design checker and were inspected at `/tmp/bessie-window.png` and `/tmp/bessie-settings.png`. The workspace and Settings surfaces showed no clipping, overlap, missing resources, or terminal imitation; the workspace showed distinct live pane output.
- Packaged and installed runtime SHA-256 values equal the lock, mode is `755`, architecture is arm64, version is `herdr 0.7.5`, strict nested and deep app signature verification passes, and packaged/installed license and lock files compare equal. The packaged and installed Bessie executables compare byte-for-byte equal.
- Post-run process checks found no packaged Bessie, installed Bessie, or terminal-controller process left running. The ordinary default Herdr status remained stopped and unchanged.

Remaining release gate:

- Public distribution still requires the discovered Developer ID private key to be unlocked and authorized for non-interactive `codesign`, or the signing step to be run in an interactive Mac login context that can authorize the key. After that succeeds, notarization requires an explicit usable `notarytool` authentication path, such as a named keychain profile or approved App Store Connect API credentials, followed by submission, stapling, validation, and Gatekeeper assessment. The active Apple Developer account and Developer ID certificate are present; the exact blocker is private-key access from the current automation context, followed by notary authentication configuration. This run does not claim Developer ID or notarization proof.

## 2026-08-01: Independent post-loop verification

The supervising Hermes session independently reviewed the implementation and reran the verification rather than relying on the implementation agent's report.

- `git diff --check`: exit 0.
- `bash -n scripts/fetch-herdr-runtime.sh scripts/package-app.sh scripts/mac-verify.sh scripts/check.sh`: exit 0.
- `python3 scripts/check-herdr-runtime.py`: exit 0.
- `./scripts/check.sh`: exit 0.
- A fresh supervising run of `./scripts/mac-verify.sh`: exit 0. It rebuilt the production app, packaged the locked runtime and Apache notice, clean-built tests, ran 70 tests with 0 failures, passed both 1180 × 740 design snapshot checks, exercised the live Herdr/libghostty/process/recovery paths, installed the app, compared identities, relaunched the installed app against isolated state, and left the ordinary default Herdr session unchanged.
- Direct readback from `/Applications/Bessie.app/Contents/Resources/Herdr/herdr` reported `herdr 0.7.5` with SHA-256 `37350546b0012555943b92eaf962665de4e264395baeb44227b8015e8ff5b0d6`; `codesign --verify --deep --strict /Applications/Bessie.app` exited 0.
- Direct Mac identity discovery found both Apple Development and Developer ID Application identities. The installed app remains the ad hoc locally verified build; Developer ID private-key authorization and notarization remain public-release gates rather than claimed successes.
- Direct ordinary-session readback reported Herdr `default` as `not_running` at `/Users/jordanstella/.config/herdr/herdr.sock` after verification.

## 2026-08-01: Bundled runtime resolver, diagnostics, and setup surfaces

Status: implementation checkpoint; VPS checks pass and full native verification is delegated to the supervising Mac run.

Implemented:

- Added a deterministic, versioned bundled/system/custom runtime selection model and store. Fresh, missing, unsupported, or corrupt selection data migrates safely to the included runtime. `BESSIE_HERDR_PATH` remains the explicit test override.
- The app now injects `Bundle.main`'s `Contents/Resources/Herdr/herdr` URL into `BessieCore`. Selected system/custom runtimes resolve exactly and missing or non-executable selections return typed failures without falling back.
- Added typed setup stages, findings, runtime diagnostics, an allowlisted sanitized report, and onboarding state that cannot complete without terminal-controller readiness.
- Added dedicated `OnboardingView.swift`, `TroubleView.swift`, and `RuntimeSettingsView.swift` rather than adding setup UI to `ProductSurfaces.swift`. Runtime Settings provides included and advanced external choices plus Run Setup Again. Runtime resolution/start/API failures now feed the shared Trouble model and surface.
- Removed `BESSIE_HERDR_PATH` from the ordinary packaged, autostart, and installed-app launches in `mac-verify.sh`, so those existing isolated live paths must resolve the packaged runtime through the production bundle injection.

Files changed in this checkpoint:

- `Sources/BessieCore/RuntimeSetup.swift`
- `Sources/BessieCore/RuntimeDiscovery.swift`
- `Sources/BessieCore/ConnectionLifecycle.swift`
- `Sources/BessieCore/ConnectPresentation.swift`
- `Sources/BessieApp/BessieApp.swift`
- `Sources/BessieApp/BessieSettings.swift`
- `Sources/BessieApp/OnboardingView.swift`
- `Sources/BessieApp/TroubleView.swift`
- `Sources/BessieApp/RuntimeSettingsView.swift`
- `Tests/BessieCoreTests/RuntimeSetupTests.swift`
- `Tests/BessieCoreTests/PersistenceReconnectTests.swift`
- `scripts/check.sh`
- `scripts/mac-verify.sh`
- `docs/reports/goal-progress.md`

Verification run on the VPS:

- `./scripts/check.sh`: exit 0. Runtime lock/package checks and UI-copy checks passed; Swift is unavailable on this VPS.
- `git diff --check`: exit 0.
- `bash -n scripts/mac-verify.sh scripts/check.sh`: exit 0.

Mac verification still required for this checkpoint:

- Compile and execute the focused Swift tests and full existing suite.
- Run the extended packaged live checks, inspect setup/runtime screenshots, install the resulting package, and compare packaged/installed identities. Ad hoc signing remains the intended intermediate mode; Developer ID authorization and notarization remain deferred.

### Review correction

Status: the preceding setup checkpoint was incomplete and is superseded as a completion claim. Review found that its validator was still coupled to running-server status, onboarding was not mounted or persisted, runtime choice publication preceded persistence, and the acceptance script did not yet prove the new setup contract.

This correction added an injected Core validator boundary before server status, typed bundled-integrity/external/incompatible/permission/filesystem failures, exact canonical bundled-path/hash/signature policy inputs, and focused validator tests. It also added the versioned first-real-terminal presentation marker with legacy absence migration, persist-before-publish runtime selection with visible persistence errors, persisted Run Setup Again, and a reachable onboarding overlay. The overlay mounts the existing real product shell beneath it, creates a workspace through `HerdrAction.workspaceCreate`, and only permits completion from a visible registry controller's ready full-frame-derived state.

Evidence run after these edits on the VPS:

- `./scripts/check.sh`: exit 0; static runtime/package/UI checks passed. Swift is unavailable on this VPS.
- `git diff --check`: exit 0.
- `bash -n scripts/mac-verify.sh scripts/check.sh scripts/package-app.sh`: exit 0.

Still incomplete and not claimed: application-layer production file/hash/architecture/signature/identity inspector injection, terminal health aggregation and automatic degraded routing, full finding/action coverage, safe-path redaction expansion, and the requested isolated bundled/external/corrupt acceptance sections and screenshots in `mac-verify.sh`. Native compilation and live Mac acceptance remain required.

## 2026-08-01: Bundled Herdr V1 Milestones 2–6 complete

Status: complete under the approved ad hoc intermediate-signing boundary. Milestones 2–6 now pass the full packaged, clean-user, failure-matrix, live terminal, installation, and relaunch definition of done. Developer ID signing and notarization remain deferred public-release gates and were not attempted.

Implemented behavior:

- Production resolves `Contents/Resources/Herdr/herdr` from an application-injected canonical URL even when the executable is missing. The versioned persisted selection defaults/migrates to bundled and supports explicit system/custom choices. `BESSIE_HERDR_PATH` remains test-only; no ordinary packaged verifier launch supplies it.
- Runtime validation precedes server status and checks regular-file/executable state, arm64 architecture, executable identity, version `0.7.5`, protocol `17`, and, for the included runtime, canonical package location, lock SHA-256, and strict signature. Invalid external executables are typed as incompatible rather than filesystem failures. Explicit external failures never select the bundled fallback.
- Typed setup diagnostics cover resolution, validation, server status/start, API connection, terminal control, workspace readiness, prior healthy loss, and the approved finding classes. Missing selected-runtime diagnostics preserve their selected source and safe path. Reports are allowlisted and omit environment dumps, command output, terminal content, and secrets.
- The reachable five-step setup overlay explains Herdr ownership, verifies the included runtime and named session, creates or chooses an ordinary Herdr workspace, and completes only after a real visible libghostty controller receives a ready frame. Completion is presentation-only, survives the second launch, and **Run Setup Again** resets it without deleting Herdr state.
- One Trouble surface handles bundled integrity, external selection, API, and terminal-controller failures. Runtime Settings exposes included/system/custom selection, observed diagnostics, explicit custom-path application, and setup re-entry. Terminal controller failures and ownership conflicts feed the same typed diagnostic route.
- `scripts/mac-verify.sh` now proves clean-user bundled startup with `PATH=/usr/bin:/bin`, explicit compatible custom selection, missing/incompatible external rejection, missing/corrupt included-runtime integrity routing, onboarding persistence, exact named-session isolation, process survival, visual artifacts, installation, and byte-identical installed relaunch.

Files changed for the bundled-runtime loop:

- `Sources/BessieCore/RuntimeSetup.swift`
- `Sources/BessieCore/RuntimeDiscovery.swift`
- `Sources/BessieCore/ConnectionLifecycle.swift`
- `Sources/BessieCore/ConnectPresentation.swift`
- `Sources/BessieCore/PresentationPersistence.swift`
- `Sources/BessieApp/BessieApp.swift`
- `Sources/BessieApp/BessieSettings.swift`
- `Sources/BessieApp/OnboardingView.swift`
- `Sources/BessieApp/TroubleView.swift`
- `Sources/BessieApp/RuntimeSettingsView.swift`
- `Sources/BessieApp/TerminalPaneController.swift`
- `Tests/BessieCoreTests/RuntimeSetupTests.swift`
- `Tests/BessieCoreTests/PersistenceReconnectTests.swift`
- `Tests/BessieAppModelTests/SurfaceProjectionTests.swift`
- `scripts/check.sh`
- `scripts/mac-verify.sh`
- `docs/reports/goal-progress.md`

Final verification evidence:

- Final combined command from `/home/hermes/code/bessie`: `./scripts/check.sh && git diff --check && bash -n scripts/mac-verify.sh scripts/check.sh scripts/package-app.sh && ./scripts/mac-verify.sh`; exit 0 on 2026-08-01.
- VPS static checks: runtime lock/compatibility/notice/package checks passed; UI-copy checks passed; shell syntax and `git diff --check` passed. Swift is unavailable on the VPS and was run on the Mac as required.
- Mac production and debug builds passed. The Swift suite executed **83 tests with 0 failures**, including 13 runtime-setup tests and both non-skipped live Herdr tests.
- The packaged runtime is 17,438,400 bytes, arm64, mode 755, reports `herdr 0.7.5` / protocol `17`, strictly verifies, and has lock-matching SHA-256 `37350546b0012555943b92eaf962665de4e264395baeb44227b8015e8ff5b0d6`. Packaged Apache license and runtime lock compare byte-for-byte with their repository sources.
- Clean-user launch used `PATH=/usr/bin:/bin`, where `command -v herdr` failed, and no `BESSIE_HERDR_PATH`. App diagnostics reached `stage=workspaceReady source=bundled`, the exact packaged runtime path, `finding=none`, and `api=true`.
- Failure matrix used isolated app/state copies and no fallback server: missing included executable and a signed wrong included executable both reached `finding=bundledIntegrity`; missing custom `/definitely/missing/bessie-herdr` reached `source=custom`, its exact path, and `finding=externalMissing`; selected `/usr/bin/true` reached `source=custom`, its exact path, and `finding=incompatible`.
- A compatible explicitly selected custom runtime used the packaged executable through the external-selection path, reached `stage=workspaceReady source=custom ... finding=none api=true`, started only isolated session `bessie`, survived Bessie exit, and was then stopped through that isolated configuration.
- Fresh setup produced `/Users/jordanstella/GitHub/bessie/dist/Bessie-onboarding.png` (1180 × 740, 286,450 bytes), created a real Herdr workspace, reached a ready terminal controller, persisted `"first_real_terminal_completion_version":1`, and bypassed onboarding on the next launch.
- Failure screenshots are 1180 × 740 PNGs: `Bessie-trouble-missing-bundled.png` (156,556 bytes), `Bessie-trouble-corrupt-bundled.png` (155,751 bytes), `Bessie-trouble-missing-external.png` (154,062 bytes), and `Bessie-trouble-incompatible-external.png` (153,627 bytes). Direct inspection confirmed readable, unclipped Trouble surfaces; bundled failures say Bessie is damaged, while external failures show `custom` and the selected path without that claim. The onboarding screenshot was also directly inspected and clearly shows step 1 of 5 and the Herdr ownership/process-survival model.
- Both existing design snapshots passed at 1180 × 740 (workspace: rail luminance 11.15, cowprint σ 3.14, chroma 0.00; Settings: rail luminance 13.50, cowprint σ 4.08, chroma 0.00). Existing live checks again covered real libghostty output/input/paste/resize/scroll, ownership conflict, controller recovery, app quit/reopen survival, CLI convergence, process/agent launch, and isolated server restart.
- The clean-user autostart status reported only named session `bessie`, with `detached_server_daemon=true`; isolated `default` remained stopped. Bessie exit left the named Herdr server running. The verifier then stopped only that isolated named server. A final direct readback showed the ordinary user `default` session still `not_running` at `/Users/jordanstella/.config/herdr/herdr.sock`.
- The verified package was installed at `/Applications/Bessie.app` and relaunched. `codesign --verify --deep --strict` passed. Packaged and installed executables are both 14,349,968 bytes with SHA-256 `5e2bf9b20c7ee7a29193137303a672ff00c86072744d75e42403641024772158`; packaged/installed Herdr executables also compare byte-for-byte. The installed app reports version `0.1.0`, build `3`.
- Final process inspection found no Bessie app, verifier-owned Herdr server, or `terminal session control` process. Temporary failure bundles and isolated runtime roots were removed by exact tracked paths/PIDs.

Repair history retained honestly:

- An earlier full Mac run passed 82 tests and all live checks but exited 127 on a stale verifier typo after the success message; the current script removed that typo and the final run supersedes it.
- Initial corrupt-bundle mutation by appending a byte produced an invalid Mach-O that could not be strictly signed. The final matrix replaces the nested executable with the signed arm64-capable `/usr/bin/true`, preserving a structurally valid app while proving checksum/package identity rejection.
- `/tmp` canonicalizes to `/private/tmp` in application bundle URLs. Failure assertions now launch and compare canonical `/private/tmp` paths rather than weakening path evidence.

Deferred release gate and scope boundary:

- Developer ID private-key authorization and notarization remain deferred exactly as approved. No notarization, publishing, release, commit, staging, push, or upstream modification occurred.
- Native Bessie Projects were not implemented or modified as part of this loop. Pre-existing multi-connection/SSH and other dirty work was preserved.

## 2026-08-01: Trouble action contract repair

Status: complete. Independent post-loop review correctly found that `TroubleView` rendered a fixed three-button set instead of honoring each typed `SetupFinding.safeActions` contract.

Repair:

- `RuntimeDiagnosticSnapshot.availableActions` is now the testable presentation projection for Trouble actions and returns exactly `finding.safeActions`, or no actions when there is no finding.
- `TroubleView` iterates only that projection. Retry still calls the supplied retry closure, Settings still uses SwiftUI's native `openSettings`, and Copy report still writes only `sanitizedReport` to the pasteboard.
- `revealRuntime` is implemented as **Show in Finder** through `NSWorkspace.activateFileViewerSelecting`. Bundled diagnostics resolve to the containing `.app` package, not an internal or nonexistent nested executable. External diagnostics select the executable when present or walk only to the nearest existing parent. The operation does not modify configuration, runtime selection, Herdr state, or files.
- Focused tests enumerate all nine finding classes and assert exact ordered actions: bundled integrity gets Copy report and Show in Finder; external missing/not-executable/incompatible get Open Settings and Copy report; server/API/terminal/prior-loss findings get Try again and Copy report; permission/filesystem gets Show in Finder and Copy report. Separate tests cover bundled-package and nearest-external reveal targets.

Files changed for this repair:

- `Sources/BessieCore/RuntimeSetup.swift`
- `Sources/BessieApp/TroubleView.swift`
- `Tests/BessieCoreTests/RuntimeSetupTests.swift`
- `docs/reports/goal-progress.md`

Exact verification evidence:

- `./scripts/check.sh`: exit 0; runtime lock/compatibility/notice/package, UI-copy, and static checks passed. Swift remains unavailable on the VPS and was run on the Mac.
- `git diff --check`: exit 0.
- `bash -n scripts/mac-verify.sh scripts/check.sh scripts/package-app.sh`: exit 0.
- `./scripts/mac-verify.sh`: exit 0. Mac production and debug builds passed; **85 tests executed with 0 failures**, including **15 RuntimeSetupTests** and the two new Trouble projection/reveal tests. Both live Herdr tests ran and passed.
- The complete packaged-app path remained green: locked Herdr identity/notices, clean-user bundled startup, compatible and rejected external selection, missing/corrupt bundle routing, onboarding, real libghostty input/output, controller recovery, process survival, isolated restart, installation, installed-app identity, and isolated relaunch.
- Design snapshots passed at 1180 × 740 (workspace rail luminance 11.16, cowprint σ 3.13, chroma 0.00; Settings rail luminance 13.46, cowprint σ 4.07, chroma 0.00).
- Fresh failure screenshots were directly inspected. `Bessie-trouble-missing-bundled.png` is 155,439 bytes and renders exactly **Copy report** and **Show in Finder**, with no Try again or Open Settings. `Bessie-trouble-missing-external.png` is 151,173 bytes and renders exactly **Open Settings** and **Copy report**, with no Try again or Show in Finder. Both are readable, unclipped 1180 × 740 PNGs.
- The verified package was installed and relaunched at `/Applications/Bessie.app`. Packaged and installed executables are 14,357,104 bytes with matching SHA-256 `ffb8d4eea035e1ace4535332806427a9573821eba2a5d975ec80096296885e58`; strict deep signature verification and byte comparison passed.
- Final ordinary `default` Herdr status remained `not_running` at `/Users/jordanstella/.config/herdr/herdr.sock`.

Scope and release boundary:

- No commit, staging, push, publication, notarization, release, or Projects work occurred. Existing dirty and untracked work remains preserved.

## 2026-08-02: Projects Milestone 0 blocked by truncated goal contract

- `GOAL.md` is physically 244 bytes and ends without a newline at the literal text `Complete only Milestone 0 o...[truncated]`; `wc -l GOAL.md` reports 7 lines and `od` confirms the truncation marker is stored in the file.
- The complete Projects Milestone 0 objective, constraints, validation, pause conditions, and definition of done are therefore unavailable. The prior Amp thread contains only the completed bundled-runtime goal and does not contain a recoverable copy of this Projects contract.
- No protocol probe, Projects model/store/materializer/UI work, default or `bessie` Herdr session access, staging, commit, push, publication, deployment, notarization, or check change was performed. Existing dirty work was preserved.
- Exact blocker: Milestone 0 cannot be executed **exactly** until the complete intended `GOAL.md` contract replaces the truncated file.

## 2026-08-02: Projects Milestone 0 resumed; protocol-17 readiness blocker

Status: the prior physical `GOAL.md` truncation is resolved. Milestone 0 stopped at the required protocol pause condition; no Projects implementation began.

- Inspected Bessie's public mutation and terminal paths in `HerdrActions.swift`, `HerdrAPI.swift`, `HerdrModels.swift`, `SessionProjection.swift`, `HerdrTerminalController.swift`, `ConnectionLifecycle.swift`, `BessieConnections.swift`, and their focused tests. Inspected pinned Herdr source `b4112743cff42452b5d18558bf2d55bbbfff8c69`, including the response enum, workspace/tab/pane schema and handlers, and creation projection.
- One verifier-owned Herdr 0.7.5 / protocol-17 server ran on `jordan-macbook` under a unique temporary `XDG_CONFIG_HOME`, `XDG_STATE_HOME`, config path, cwd, and `HERDR_SOCKET_PATH`. Readiness was the server's exact socket announcement, not a sleep. Cleanup closed only returned workspace `w1`, terminated only the recorded isolated server process, and removed its temporary root. No ordinary `default`, `bessie`, or unrelated session was started, stopped, attached, queried, or mutated.
- `workspace.create` returned `workspace_created` with authoritative `w1`, `w1:t1`, and `w1:p1`; `tab.create` returned `tab_created` with `w1:t2` and `w1:p2`; `pane.split` returned `pane_info` with `w1:p3`. A fresh snapshot contained every exact returned ID. Duplicate labels were used intentionally, and no ID came from labels, ordering, or set differences. Rename/focus returned their typed info objects.
- Protocol-17 `PaneInfo` exposes optional `cwd` and `foreground_cwd`; `WorkspaceInfo` has no cwd. All three isolated panes reported both paths. Herdr canonicalized the requested `/var/.../project-cwd` path to `/private/var/.../project-cwd`. The frozen fallback requires folder selection/confirmation when any required pane cwd is absent or the values are ambiguous; no terminal text, process arguments, labels, or prompts may supply cwd.
- `pane.send_input` with exact text and `pane.send_keys` with Enter each returned only `{"type":"ok"}`. Pinned source confirms these handlers return `ok` after `try_send_bytes` accepts bytes into the runtime queue. Protocol 17 exposes no public semantic signal that the new shell has initialized or consumed input; creation/snapshot/events/process-info do not close that gap. A terminal full frame is not a headless shell-ready contract.
- Frozen product narrowing: protocol-17 Bessie may store and preview startup commands but must not execute them or silently ignore them. Opening a command-bearing recipe remains blocked; only shell-only recipes can proceed after a future Milestone 0 resolution. Cancellation, disconnect, endpoint generation, unknown mutation outcome, partial-workspace survival, no-retry, no-rollback, and final-snapshot rules are now explicit in the existing Projects plan.
- Exact blocker: safe startup-command execution requires either a narrowly typed public Herdr shell/input-ready contract or Jordan's explicit approval of a release scope that excludes opening command-bearing projects. Prompt parsing, timing sleeps, visible-controller dependence, retries, and inferred correlation are not acceptable substitutes.
- Validation after freezing the contract: `./scripts/check.sh` exit 0; runtime lock/compatibility/notice/package, UI-copy, and static checks passed. `git diff --check` exit 0. `git diff --cached --name-only` remained empty. Full `mac-verify.sh`, packaging, installation, and app relaunch were not run because GOAL's mandatory protocol pause condition was reached; this checkpoint does not claim Milestone 0 completion.
- Scope audit: only the pre-existing untracked Projects plan and this existing progress report were updated by the resumed contract work. No source, test, script, model, store, materializer, UI, check, staging area, commit, push, publication, deployment, notarization, or installed app was changed.

## 2026-08-02: Projects Milestone 0 complete

Status: complete after Jordan approved the fail-safe Herdr Plus technique. This spike froze and proved only the protocol/product contract; no Project model, store, catalog, materializer, editor, or UI was started.

Protocol and source evidence:

- Inspected Bessie's public transport/action/snapshot seams in `Sources/BessieCore/HerdrAPI.swift`, `HerdrActions.swift`, `HerdrModels.swift`, `SessionProjection.swift`, `HerdrTerminalController.swift`, and `UnixSocketTransport.swift`; pinned Herdr `b4112743cff42452b5d18558bf2d55bbbfff8c69` response/schema/mutation handlers; and Herdr Plus `a9aca9da3ca6d7406f3d878a1df1c1b9775e2723` startup sequencing in `herdr.go:134-253`, called from `projects.go:163-223`.
- Added only `Sources/BessieCore/HerdrProtocolContract.swift`, focused `Tests/BessieCoreTests/HerdrProtocolContractTests.swift`, and one isolated live case in `Tests/BessieCoreTests/LiveHerdrTests.swift`. Typed decoders require the exact result type and nonempty IDs: `workspace.create` returns `workspace_created` with `workspace.workspace_id`, `tab.tab_id`, and `root_pane.pane_id`; `tab.create` returns `tab_created` with `tab.tab_id` and `root_pane.pane_id`; `pane.split` returns `pane_info` with `pane.pane_id`. Wrong types and absent/empty IDs fail instead of triggering label/order/diff inference.
- The isolated protocol-17 fixture returned `w1`, `w1:t1`, `w1:p1`, `w1:t2`, `w1:p2`, and `w1:p3`. Duplicate labels were deliberate. Fresh snapshots verified each exact returned ID. Rename/focus returned their typed workspace/tab/pane info objects. Input requests returned only `{"type":"ok"}`, which is never treated as shell consumption or command-start success.
- Protocol-17 pane facts expose optional `cwd` and `foreground_cwd`; workspace facts expose no cwd. The isolated fixture populated both pane fields and canonicalized `/var/.../project-cwd` to `/private/var/.../project-cwd`. Save-current-workspace must require folder selection/confirmation if any required `cwd` is absent or pane values are ambiguous; it may not infer cwd from `foreground_cwd`, output, prompts, arguments, labels, or process text.

Readiness and failure evidence:

- The production seam polls exact `pane.read` requests with `pane_id`, `source:"visible"`, `lines:20`, `format:"text"`, and `strip_ansi:true`, using a 50 ms bounded interval and separate 5-second readiness/echo deadlines. It sends the complete reviewed command through `pane.send_input` with no newline and no keys, then sends `pane.send_input` with empty text and `keys:["Enter"]` only after echo confirmation.
- Echo matching requires the full exact command, not Herdr Plus's short substring. It counts occurrences relative to the pre-submit baseline so already-visible text cannot pass, removes only rendered CR/LF boundaries so a terminal-wrapped command compares as one string, and requires the new occurrence on two consecutive reads. This can fail closed on viewport churn but cannot advance on a partial, stale, or one-read match.
- Focused tests prove: blank readiness timeout sends nothing; echo timeout sends exact text but no Enter; cancellation after text sends no Enter; pre-existing command text cannot false-positive; wrapped full-command echo must be stable before Enter; line-breaking command input is rejected. The isolated live case used a deliberately wrapping command and observed the generated execution marker only after Enter; the marker is not contiguous in the echoed command text, so echo alone cannot satisfy the execution assertion.
- Frozen orchestration boundaries: cancellation before creation mutates nothing; cancellation after workspace creation stops without retry/rollback and reports the known workspace as partial when same-generation verification remains possible; disconnect during tab/split has unknown mutation outcome and must never resend; app quit/connection switch cancels only in-memory orchestration; readiness timeout sends no command; echo timeout/cancellation sends no Enter; post-Enter failure remains partial and non-retriable. Every creation is verified by exact ID in a fresh snapshot on the same `(connection ID, canonical socket, in-memory generation)` scope. Reconnect mints a generation, preventing cross-session reuse of colliding IDs. Surviving workspaces remain visible; no automatic close, retry, rollback, or success without a verified final snapshot is allowed.

Exact validation evidence:

- Focused Mac command `xcrun swift test --filter HerdrProtocolContractTests`: **9 tests, 0 failures**.
- `./scripts/check.sh`: exit 0; Herdr runtime lock/compatibility/notice/package, UI-copy, and static checks passed. `git diff --check`: exit 0. The staging area remained empty.
- Final `./scripts/mac-verify.sh`: exit 0. Production/debug builds and packaging passed; the complete Swift suite ran **95 tests with 0 failures**, including all 9 focused contract tests and the isolated Milestone 0 live proof. Both unchanged 1180×740 design gates passed (workspace: rail luminance 11.26, cowprint σ 3.22; Settings: rail luminance 13.32, cowprint σ 4.07). The first attempt reached the same 95/95 protocol result but captured a transient all-black design frame; no gate or threshold was changed, and the full rerun passed.
- The verifier used only its unique temporary Herdr configuration, state, socket, cwd, run ID, returned workspace IDs, and recorded server PID. It cleaned those verifier-owned resources only. Ordinary `default`, production `bessie`, and unrelated sessions were not started, stopped, attached to, queried, or mutated.
- The verified package was installed and relaunched as required. Packaged and installed `BessieApp` executables are both 14,540,896 bytes with SHA-256 `0176a9ede22ee82d9f77cef0ed996cd92ffd64d9db05f52985829dddd5d150ee`; the verifier's strict identity and isolated installed-app checks passed.
- No check was weakened or skipped. Existing dirty work was preserved. No staging, commit, push, publication, deployment, notarization, Herdr/Herdr Plus modification, ordinary-session access, or general Projects implementation occurred.

## 2026-08-02: Projects Milestone 0 live identity evidence completed

- Independent review found that the durable live test reproduced only `workspace.create` identity even though the earlier isolated probe had also proved `tab.create` and `pane.split`. `testProjectsMilestoneZeroContractAgainstIsolatedHerdr` now performs all three mutations against the verifier-owned socket, decodes them through `HerdrWorkspaceCreationResult`, `HerdrTabCreationResult`, and `HerdrPaneCreationResult`, and takes a fresh snapshot after each creation stage.
- The checked-in proof compares every returned workspace, root-tab, root-pane, second-tab, second-root-pane, and split-pane ID directly against snapshot ID fields. The workspace and second tab share `duplicate-label`; the second root pane and split pane are both renamed `duplicate-label`. No assertion reads those labels, collection order, or set differences. Cleanup remains one exact `workspace.close` using the authoritative returned workspace ID, so all child resources are removed through the same isolated endpoint.
- `requiredID` now rejects IDs whose entire value is whitespace/newlines while preserving valid IDs byte-for-byte. Proof-first focused run: `xcrun swift test --filter HerdrProtocolContractTests` executed 9 tests with 1 expected failure because `" \t\n"` did not throw. After tightening the guard, the same command executed **9 tests with 0 failures**.
- Final `./scripts/mac-verify.sh`: exit 0. Production/debug builds, package/install/relaunch, and the expanded isolated live proof passed; the suite executed **95 tests with 0 failures**. `testProjectsMilestoneZeroContractAgainstIsolatedHerdr` passed in 0.934 seconds. Unchanged design gates passed at 1180×740 (workspace: rail luminance 11.25, cowprint σ 3.18; Settings: rail luminance 13.34, cowprint σ 4.07).
- Final `./scripts/check.sh` and `git diff --check`: exit 0. Packaged and installed `BessieApp` executables are both 14,540,896 bytes with SHA-256 `64de78dd688547a723455af2ae67b69dbe613ba05a1b393098e4bc24fad4091b`. The staging area remained empty. No ordinary Herdr session, general Projects implementation, check, commit, push, publication, deployment, or notarization was added or changed.

## 2026-08-02: Projects Milestone 1 native model and storage complete

Status: complete. This checkpoint implements only the versioned native Project model, strict validation/migration, and safe injected-root catalog storage. No materializer, Projects UI/editor, launch orchestration, live workspace capture, or Herdr Plus integration began.

Implemented contracts and files:

- Added `Sources/BessieCore/BessieProjects.swift`: public `Codable`, `Sendable`, and `Equatable` Project/tab/pane/placement models; explicit schema version 1 and migration dispatch; strict recursive V1 field decoding; deterministic sorted-key ISO-8601 JSON; structured project/tab/pane/field validation issues; normalization of names, groups, labels, commands, and canonical directory paths; global tab/pane UUID checks; exactly-one-root and procedural parent-order validation; missing/cross-tab/cyclic reference rejection; finite inclusive Herdr ratio bounds `0.1...0.9`; and exact command preservation with CR/LF rejection.
- Added `Sources/BessieCore/BessieProjectStore.swift`: default `~/Library/Application Support/Bessie/Projects` root with `BESSIE_PROJECTS_PATH` resolution and injected test roots; one `<project-uuid>.json` file per recipe; deterministic catalog sorting; isolated corrupt/future-schema/mismatch/duplicate-embedded-ID issues; embedded UUID-authoritative lookup; create/save/update/load/list/duplicate/archive/unarchive/delete operations; same-directory temporary writes and atomic `rename`; store-wide advisory locking across revision compare and mutation; optimistic conflict results carrying existing and attempted versions plus loaded/current identity metadata; cross-root ownership rejection; and injected Trash handoff with same-directory hard-link restoration if the owner removes then fails.
- Added `Tests/BessieCoreTests/BessieProjectTests.swift`: **21 focused tests** covering normalization/round-trip, strict schema and future-version isolation, names/directories/tabs/panes/UUIDs, root and split replay failures, cycles and cross-tab references, ratio bounds/non-finite values, exact command handling, absence/rejection of runtime state, deterministic sorting, atomic CRUD, concurrent and stale writes, corrupt files, UUID/filename mismatch and collisions, duplicate/archive/unarchive, Trash success/failure/restoration, cross-root delete rejection, and root override resolution. Every store test uses a unique temporary injected root; no test accesses the real Projects directory.
- Updated only this existing progress report in addition to those three new focused files. Existing dirty work remained unmodified outside this bounded checkpoint, and the staging area remained empty.

Failure-first and review evidence:

- Before production files existed, `xcrun swift test --filter BessieProjectTests` failed as expected because `BessieProject`, `BessieProjectCodec`, and `BessieProjectStore` were absent. After the first implementation, the focused suite passed 16/16, then 17/17 after future-version catalog isolation was added.
- Independent safety review found check-then-rename concurrency, cross-root delete, embedded-ID collision, destructive Trash-failure, and permissive V1 decoding gaps. Targeted tests initially exposed four failures after the safety changes; canonical `/var` versus `/private/var` URL ownership was corrected without weakening assertions. A second review found future versions were being interpreted as V1 before dispatch; version dispatch now precedes V1 structural validation.
- Final focused Mac command `xcrun swift test --filter BessieProjectTests`: **21 tests, 0 failures**. The concurrent two-store test proves exactly one stale-revision writer succeeds; the destructive Trash fixture removes the source and throws, then proves the original path and recipe are restored while the original owner error is returned.

Required verification evidence:

- Final `./scripts/check.sh`: exit 0. Runtime lock/compatibility/notice/package checks, UI-copy checks, and static checks passed. Final `git diff --check`: exit 0.
- Final `./scripts/mac-verify.sh`: exit 0. Production and debug builds passed; the complete Swift suite executed **116 tests with 0 failures**, including all 21 Project tests and all 3 isolated live Herdr tests. Existing workspace and Settings design checks passed at 1180×740. The verifier completed locked-runtime, packaging, isolated named-session/live terminal, process survival, installation, installed-app identity, and isolated relaunch checks.
- The verified package was installed and relaunched at `/Applications/Bessie.app`. Packaged and installed `BessieApp` executables are both **14,876,064 bytes** with SHA-256 `51d0a9579454fe838d746c944d25eeca22a1657a944723311649d375f46889e1`; `cmp` and strict deep signature verification exited 0.
- Post-verifier ordinary `default` status remained `not_running` at `/Users/jordanstella/.config/herdr/herdr.sock`. Project tests used temporary roots only, and no app code invokes the new store yet, so verification made no write to real user Project storage.
- No staging, commit, push, publication, deployment, notarization, release action, materializer, Projects UI/editor, workspace capture, Herdr Plus dependency, live Herdr ID persistence, secrets, environment recipe fields, worktrees, or remote Project data was added.

## 2026-08-02: Projects Milestone 1 acceptance repair P1

- Repaired canonical lookup isolation in `BessieProjectStore.load(id:)`: when healthy canonical `<UUID>.json` and noncanonical files share an embedded UUID, load now returns the canonical recipe. The mismatched duplicate remains visible through catalog filename-mismatch/duplicate issues and remains non-updatable. Mismatched-only lookup and ambiguous noncanonical duplicates retain their prior behavior.
- Updated `testFilenameMismatchIsIsolatedAndNeverOverwritesCanonicalProject` to assert that the canonical recipe remains loadable by ID and that its canonical source and content are selected. The prior assertion explicitly expected the blocking `duplicateEmbeddedID` failure.
- `./scripts/check.sh`: exit 0. Targeted Mac regression test: **1 test, 0 failures**. Full `BessieProjectTests` Mac suite: **21 tests, 0 failures**. Focused `git diff --check`: exit 0. No materializer, UI, staging, commit, push, publication, or ordinary Herdr-session work occurred.

## 2026-08-02: Projects Milestone 1 acceptance repair P1 directory availability

- Split catalog normalization from save validation. Catalog/list/load still require an absolute standardized path and all structural recipe invariants, but no longer require the saved directory to exist at read time. Public `normalized()` and store create/update continue resolving the path and requiring an existing directory before any write.
- Failure-first Mac evidence: after saving a valid recipe and removing its working directory, the new focused test failed with an empty catalog, a catalog issue, and `load(id:)` returning `notFound`. After the repair, that test and the create/update rejection test each passed.
- Full `BessieProjectTests` Mac suite: **23 tests, 0 failures**. `./scripts/check.sh` and `git diff --check`: exit 0. No materializer, UI, staging, commit, push, publication, or Herdr-session work occurred.

## 2026-08-02: Projects Milestone 1 acceptance repair P2 mismatch recovery

- Added explicit `recoverFilenameMismatch(_:)`. It verifies injected-root ownership and the exact loaded revision, requires a lone embedded UUID, then creates the canonical filename with an atomic no-overwrite hard link before removing the mismatched name. A pre-existing or concurrently appearing canonical path returns `alreadyExists` and is never replaced; another noncanonical embedded-ID duplicate returns `duplicateEmbeddedID`.
- Exact revision-bound `delete(_:)` now permits mismatched source filenames and hands that exact owned path to the injected Trash operation. Existing stale-write, cross-root, Trash-failure restoration, and no-permanent-delete behavior remains unchanged.
- Failure-first compilation rejected the new recovery tests because the operation did not exist. Final focused recovery, canonical-collision, and mismatch-Trash tests passed. Full `BessieProjectTests` Mac suite: **25 tests, 0 failures**. `./scripts/check.sh` and `git diff --check`: exit 0. No materializer, UI, staging, commit, push, publication, or Herdr-session work occurred.

## 2026-08-02: Projects Milestone 1 acceptance repair P2 migration dispatch

- Added public `BessieProjectMigration.migrate(_:)` as the explicit version-dispatch entry point. `BessieProjectCodec.decode(_:)` delegates to it. Dispatch reads only `schemaVersion` first, routes schema 1 through its strict native decoder, and rejects unknown future versions before interpreting them as V1.
- Added a hand-authored native schema-1 JSON fixture in the focused test and proved direct migration dispatch, stable identity/content, codec delegation, and future-version rejection. No schema 0, Herdr Plus type, TOML, importer, or compatibility behavior was invented.
- Failure-first Mac compile failed because `BessieProjectMigration` was absent. Final focused migration test: **1 test, 0 failures**; full `BessieProjectTests`: **25 tests, 0 failures**. `./scripts/check.sh` and `git diff --check`: exit 0. No materializer, UI, staging, commit, push, publication, or Herdr-session work occurred.

## 2026-08-02: Projects Milestone 1 acceptance repair P2 atomic replacement failure

- Added an injectable atomic-replacement primitive to `BessieProjectStore`; production retains the same POSIX `rename` implementation. The same-directory temporary file remains guarded by unconditional deferred cleanup when replacement succeeds or throws.
- Added `testAtomicReplacementFailurePreservesPreviousRecipeAndCleansTemporaryFile`. It injects replacement failure during update and proves the canonical file remains byte-for-byte unchanged, the prior decoded recipe remains loadable, the owner error is returned, and no `.tmp` artifact remains.
- Failure-first Mac compilation rejected the missing injection argument. Focused repaired test: **1 test, 0 failures**. Final `BessieProjectTests`: **26 tests, 0 failures**.

Final five-blocker acceptance verification:

- `./scripts/check.sh` and `git diff --check`: exit 0. Final `./scripts/mac-verify.sh`: exit 0; production/debug builds, **121 tests with 0 failures**, all 26 Project tests, three isolated live Herdr tests, design checks, package/install/relaunch, and installed identity passed.
- Packaged and installed `BessieApp` executables are both **14,879,008 bytes** with SHA-256 `a0b51883aa4a370b6179027e8e4b2d2472920eb9641f0765c9b90d0f906c5757`; `cmp` and strict deep signature verification exited 0. Ordinary `default` Herdr remained `not running` at `/Users/jordanstella/.config/herdr/herdr.sock`.
- No materializer, Projects UI/editor, launch orchestration, workspace capture, Herdr Plus integration, staging, commit, push, publication, deployment, or notarization was added or performed.

## 2026-08-02: Projects Milestone 1 acceptance verification rerun

- Failure-first evidence remains the actual pre-fix runs recorded above: canonical duplicate lookup expected/found `duplicateEmbeddedID`; vanished-directory lookup produced an empty catalog and `notFound`; the recovery, migration, and atomic-replacement tests first failed compilation because their explicit APIs/injection seam were absent. The repaired state was not reverted to manufacture duplicate failures.
- Focused Mac command `swift test --filter BessieProjectTests`: **26 tests, 0 failures**. It includes all five acceptance repairs and the injected replacement-failure case.
- `./scripts/check.sh`: exit 0; runtime lock/compatibility/notice/package, UI-copy, and static checks passed. `git diff --check`: exit 0.
- Fresh `./scripts/mac-verify.sh`: exit 0. Production/debug builds passed; **121 tests executed with 0 failures**, including 26 Project tests and all three isolated live Herdr tests. Workspace and Settings design checks passed at 1180×740 (workspace rail luminance 11.16, cowprint σ 3.08; Settings rail luminance 13.46, cowprint σ 4.07).
- Packaging, installation, relaunch, and identity checks passed. Packaged and installed executables are both **14,879,008 bytes**, have matching SHA-256 `6a7fed04ae451bab5a13a95ee51e89444f4609a2f9a7c2328274cdaa1220bd8d`, compare byte-for-byte, and pass strict deep signature verification. Ordinary `default` Herdr remained `not running` at `/Users/jordanstella/.config/herdr/herdr.sock`.
- No materializer, Projects UI/editor, launch orchestration, workspace capture, Herdr Plus integration, staging, commit, push, publication, deployment, or notarization was added or performed.

## Projects parallel M2 ∥ M3

- 2026-08-02: Started parallel execution after Jordan approval.
- M2 materializer: agent `bessie-projects-materializer`, pane `w1S:pK`, goal `GOAL.md`, monitor will track separately.
- M3 catalog/editor: agent `bessie-projects-ui`, pane `w1S:pM`, goal `GOAL-m3-projects-ui.md`.
- Ownership split: M2 = BessieCore materializer + tests; M3 = BessieApp Projects surfaces + minimal shell/palette hooks.
- Shared locks: only one agent should run `./scripts/mac-verify.sh` / package-install at a time; both use temp project roots / isolated Herdr fixtures.
- M4 open/recover, M5 capture, M6 release remain gated until M2+M3 join.

## Projects Milestone 3

Status: complete within the parallel M2/M3 ownership boundary. This checkpoint adds only the local Projects catalog/editor and minimal destination/command-palette wiring against the existing `BessieProjectStore` API.

- Added a first-class Projects rail destination whose catalog loads independently of Herdr connection health. Search covers name, description, group, working-directory path, and startup commands; optional group sections keep a real group named `Ungrouped` distinct from the ungrouped section. Rows show folder, tab/pane counts, command summary, archived state, and local actions.
- Added native create/edit state and UI for metadata, absolute directory selection, tab add/rename/reorder/duplicate/remove, right/down pane splitting, leaf removal, labels, split ratios, exact single-line startup commands, validation, layout preview, and command preview. Save uses create or revision-bound update; stale-write conflicts preserve the unsaved draft and surface the conflict instead of overwriting disk state.
- Wired duplicate, archive/unarchive, confirmed move to Trash, Finder reveal, copy path, corrupt-catalog issue display, and safe filename-mismatch recovery. Healthy projects remain visible beside catalog issues.
- Open is visibly disabled and `ProjectsViewModel.canOpenProjects` is always false. Its stub only presents the Milestone 4 availability message and has no Herdr, materializer, workspace-capture, or runtime dependency.
- Added focused app-model coverage for search/group identity, offline create/edit/save/duplicate/archive/delete, validation blocking, stale-revision draft preservation, corrupt-file isolation, filename recovery, tab/pane topology, disabled Open, and destination/command-palette routing.

Exact verification evidence:

- Mac focused command with an injected temporary root, `BESSIE_PROJECTS_PATH="$(mktemp -d)/Projects" xcrun swift test --filter ProjectsViewModelTests`: **9 tests, 0 failures**.
- Mac app-model command with an injected temporary root, `BESSIE_PROJECTS_PATH="$(mktemp -d)/Projects" xcrun swift test --filter BessieAppModelTests`: **24 tests, 0 failures**.
- `./scripts/check.sh`: exit 0; Herdr runtime lock/compatibility/notice/package checks, UI-copy checks, and static checks passed. Swift remains unavailable on the VPS and was compiled/tested on the Mac.
- `git diff --check`: exit 0. `git diff --cached --name-only`: empty.
- Full `./scripts/mac-verify.sh`, packaging, installation, relaunch, and UI snapshot capture were intentionally not run because M2 owns the shared Mac package pipeline concurrently; the goal's allowed focused-test fallback was used rather than contending for or destructively resyncing that pipeline.
- Every Projects test/run used an injected temporary `BESSIE_PROJECTS_PATH`. The real Projects directory and ordinary Herdr sessions were not accessed or mutated. Existing dirty work was preserved. No staging, commit, push, publication, deployment, notarization, live Open/materialization, capture, or Core store/protocol/model/materializer change was performed by M3.

## Projects Milestone 3 independent review

- Hermes independent review after Amp `bessie-projects-ui` completed:
  - Open path is stub-only (`canOpenProjects == false`, `requestOpen` only sets notice; no materializer/Herdr calls).
  - New surfaces: `ProjectsViewModel.swift`, `ProjectsSurface.swift`, `ProjectEditorView.swift`, `ProjectLayoutPreview.swift`, plus minimal `ProductSurfaces` / `KeyboardShortcuts` destination wiring.
  - Focused Mac tests re-run by supervisor with temp `BESSIE_PROJECTS_PATH`: `ProjectsViewModelTests` **9/0**, `BessieAppModelTests` **24/0**.
  - `./scripts/check.sh` and `git diff --check` passed on VPS after review.
  - Full `mac-verify`/package/install deferred until M2 releases the shared Mac pipeline; M3 is accepted for catalog/editor scope with that deferred packaging proof.
- M2 materializer (`bessie-projects-materializer`) still working; M4 not started.

## 2026-08-02: Projects Milestone 2 typed Herdr materializer complete

Status: complete within the Milestone 2 BessieCore boundary. No Projects UI, store redesign, capture, remote opening, Herdr Plus integration, or ordinary-session mutation was added.

- Added `BessieProjectMaterialization.swift`: pre-mutation Project/directory and local-compatible endpoint validation; one socket-bound mutation API with endpoint ping and connection-generation checks before and after authoritative snapshots; typed stages, attempts, progress, exact recipe-to-runtime ID maps, verification facts, command facts, mutation outcomes, complete results, and attributable partial failures.
- Materialization uses only exact protocol-17 IDs decoded from `workspace.create`, `tab.create`, and `pane.split`. It maps the first recipe tab/root onto the workspace-created tab/root, rejects duplicate returned IDs, replays tabs and parent-referenced splits in stored order, and never derives identity from labels or snapshot ordering.
- Fresh verification checks workspace/tab/pane existence and ownership, labels, canonical cwd, layout membership, and the recursive split tree's exact IDs, direction, and Herdr `f32` ratio. Layout partitioning matches Herdr 0.7.5's rounded terminal-cell calculation, including the nested five-column `2/1/2` edge case.
- Reviewed startup commands run only after topology verification through the frozen readiness → exact text → stable newly observed exact echo → Enter sequence. Cancellation/connection checks guard every topology mutation, command text, Enter, and snapshot boundary. Timeout, cancellation, disconnect, malformed response, request failure, and unknown mutation outcomes retain exact acknowledged state without cleanup, rollback, retry, guessed IDs, or blind Enter.
- Extended the isolated live materializer proof to create duplicate-labeled two-tab/three-pane topology with a split and observable wrapping startup command. Cleanup is registered before materialization and closes only workspace IDs newly observed on the verifier-owned isolated socket.

Failure-first and review evidence:

- The first post-topology-fixture Mac compile failed because the test snapshot helper omitted an explicit return. After that repair, the first focused execution exposed an out-of-range partial-snapshot fixture; the helper was narrowed to only the authoritative runtime tabs/panes available at each partial stage.
- Independent acceptance reviews identified and drove concrete regressions for descriptor/transport socket mismatch, duplicate runtime IDs, unknown first-mutation outcome, unverified snapshot labeling, missing recursive topology checks, missing boundary coverage, generation changes during snapshots, Herdr rounded-cell layout partitioning, and overly loose ratio comparison. The final deterministic suite covers those cases directly rather than relying on labels or happy-path live behavior.

Exact final verification evidence:

- Mac focused command `xcrun swift test --filter BessieProjectMaterializationTests`: **22 tests, 0 failures**.
- Final `./scripts/mac-verify.sh`: exit 0. Production/debug builds and the complete Swift suite passed with **153 tests, 0 failures**. All four isolated live Herdr tests ran; `testNativeProjectMaterializerAgainstIsolatedHerdr` passed in 0.812 seconds. Workspace and Settings design checks passed at 1180×740 (rail luminance 11.24 / 13.36; cowprint σ 3.24 / 4.06).
- Packaging, installation, relaunch, and installed identity passed. Packaged and installed `BessieApp` executables match byte-for-byte and both have SHA-256 `7eaab8b5895a27411f1e40b83376e5184509cb325359dc2e92e4d68e38100f35`.
- Final `./scripts/check.sh` and `git diff --check`: exit 0. The staging area remained empty. The Mac verifier confirmed ordinary `default` Herdr status was unchanged before and after its isolated checks.
- Existing dirty work was preserved. No staging, commit, push, publication, deployment, notarization, release action, UI addition, or ordinary Herdr workspace/tab/pane/process mutation was performed by Milestone 2.

## Projects Milestone 2 independent review

- Amp `bessie-projects-materializer` reported complete with 22 focused materializer tests, 153 full Mac tests, live isolated materialization, mac-verify, package/install identity SHA-256 `7eaab8b5895a27411f1e40b83376e5184509cb325359dc2e92e4d68e38100f35`.
- Hermes re-ran focused Mac suites after rsync: `BessieProjectMaterializationTests` **22/0**, combined Projects filters **70 executed / 4 live skipped without socket / 0 failures** (live path remains mac-verify-owned).
- Code review of `BessieProjectMaterialization.swift`: exact returned-ID mapping, connection generation gates, fail-safe command stages, partial results with no cleanup/close, readiness/echo timeout paths covered by tests.
- `./scripts/check.sh` + `git diff --check` passed on VPS after review.
- Milestone 2 accepted for Core materializer scope. Milestone 4 join started.

## Projects Milestone 4

Status: complete. This checkpoint joins the verified materializer to the Projects catalog for local Open/recover only. No Milestone 5 workspace capture behavior was added.

- Open is enabled only for a valid Project with an existing working directory and a compatible connected local Herdr identity. Command-bearing Projects show an explicit pre-mutation review with connection, directory, topology counts, and exact command text; shell-only Projects can launch directly.
- `ProjectLaunchCoordinator` runs materialization in a cancellable asynchronous task, streams structured stages and attempts into the Projects UI, and preserves materializer cancellation boundaries. The connected shell can disappear without losing eventual partial facts, and disconnect/reconnect invalidates actions from the prior connection generation.
- Complete and partial handoff use only the exact returned workspace/tab/pane IDs. Handoff refreshes and revalidates against an authoritative connection-specific snapshot before installing a projection; tokenized action state prevents stale refreshes from winning UI races.
- Partial failures show the owner error, stage, known runtime IDs, mutation outcome, and each command's readiness/text/echo/Enter facts. Created Herdr objects remain alive. Retry is disabled for uncertain mutation or command delivery and is always bound to the exact original connection generation; “Open partial workspace” has the same connection requirement.
- Running-instance records are transient, in-memory hints scoped by Project, connection/socket/generation, and workspace. Multiple live instances of one Project can coexist, and no runtime identity is persisted in Project JSON.
- Independent review found four launch/recovery defects: work continuing after shell disappearance, insufficient retry/partial-open generation scoping, stale projection installation during handoff refresh, and uncertain command delivery rendered as “no.” All four were repaired and covered by the final focused and full verification runs.

Exact verification evidence:

- Focused Mac command with an injected temporary catalog, `BESSIE_PROJECTS_PATH="$(mktemp -d)/Projects" xcrun swift test --filter ProjectsViewModelTests`: **13 tests, 0 failures**. Coverage includes disconnected/incompatible/invalid gating, command review, asynchronous progress, cancellation before mutation, exact-ID completion, honest partial command uncertainty and recovery, reconnect-generation invalidation, transient-instance revalidation, and multiple instances for one Project.
- Broader Mac selections `BESSIE_PROJECTS_PATH="$root/Projects" xcrun swift test --filter BessieAppModelTests` and `xcrun swift test --filter BessieProjectMaterializationTests` passed. The final full verifier executed **157 tests with 0 failures**, including all 13 Projects app-model tests, all 22 materializer tests, and all 4 isolated live Herdr tests.
- Final `./scripts/mac-verify.sh`: exit 0. Production/debug builds, bundled Herdr identity and notices, isolated live topology/materialization, terminal and process automation, package/install/relaunch, installed-app identity, and three 1180×740 design gates all passed.
- The isolated connected Projects catalog screenshot is `dist/Bessie-projects.png`, 131 KB, SHA-256 `c93e814238182ec6aa974408844148f8d7f9b08d6e741abbc2c75b34d8c3e5cc`. Visual inspection confirmed the Projects destination, deterministic valid Project row, and enabled Open action render coherently without clipping, overlap, blank content, or misleading launch state. An unrelated long workspace name in the narrow rail is intentionally ellipsized.
- Packaged and installed `BessieApp` executables are both **16,605,904 bytes**, match byte-for-byte, and have SHA-256 `10a81cac565e4d65acb96eb8e19098318c61b44e91239cc596bb8c1f90db28eb`.
- Final `./scripts/check.sh` and `git diff --check`: exit 0. Runtime lock/compatibility/notice/package, UI-copy, and static checks passed. `git diff --cached --name-only` remained empty.
- Existing dirty work was preserved. No staging, commit, push, publication, deployment, notarization, release action, Milestone 5 capture, remote Open, rollback, or ordinary-session cleanup was performed.

## Projects Milestone 4 independent review

- Amp `bessie-projects-open` completed Open/recover join with 13 ProjectsViewModel tests, 157 full Mac tests, live Herdr, package identity SHA-256 `10a81cac565e4d65acb96eb8e19098318c61b44e91239cc596bb8c1f90db28eb`, Projects screenshot inspected.
- Hermes re-ran after rsync: `ProjectsViewModelTests` **13/0**, `BessieProjectMaterializationTests` **22/0**; `./scripts/check.sh` and `git diff --check` passed.
- Code path review: Open gated on local compatible connection + valid project; command review; generation-scoped retry; no Herdr cleanup; running instances in-memory only.
- Milestone 4 accepted. Milestone 5 capture started.

## Projects Milestone 5

Status: complete. This checkpoint adds only capture of the authoritative focused Herdr workspace into a new, unsaved Bessie Project draft for review in the existing editor.

- Added a pure `BessieProjectCapture` conversion that requires a complete focused-workspace projection and preserves tab labels, pane labels, nested split topology, directions, and Herdr-rounded split ratios. Missing or inconsistent advertised tabs, panes, and layouts, plus duplicate tab or pane facts, are rejected rather than captured lossily.
- Every captured Project, tab, and pane receives a fresh recipe UUID. Encoded-fixture assertions prove that live Herdr workspace, tab, and pane IDs do not appear in Project JSON. Every captured pane command is `nil`; no process arguments, shell history, terminal contents, or other inferred startup command is persisted.
- The working directory is copied only when every captured pane reports the same authoritative absolute CWD. Missing, relative, or differing CWD facts leave the folder blank so the existing editor requires user review before save.
- Added the Projects action and command-palette entry `Save current workspace as project…`. It is disabled with an honest reason when disconnected or when the focused topology cannot be captured. Capture opens a revisionless Create Project draft; only the existing explicit Save path creates a new entry through the injected `BessieProjectStore`. Disconnect discards the prior snapshot, and capture never mutates or claims ownership of the live Herdr session.

Verification evidence:

- Focused Mac tests with an injected temporary `BESSIE_PROJECTS_PATH`: `BessieProjectCaptureTests` **8 tests, 0 failures** and `ProjectsViewModelTests` **15 tests, 0 failures**. Coverage includes missing focus/projection, nested multi-tab splits, duplicate labels and pane facts, fresh IDs, encoded-ID exclusion, blank commands, authoritative-only CWD, stale disconnect state, editor draft creation, and new-store-entry save.
- The duplicate-pane regression test initially exposed a projection dictionary precondition crash. Projection lookup now remains non-crashing so capture validation rejects the duplicate fact; the focused suites then passed.
- Final `./scripts/mac-verify.sh`: exit 0. Production/debug builds and **167 tests with 0 failures** passed, including all four isolated live Herdr tests. Runtime/package checks, isolated Bessie-session startup, terminal/process checks, three visual gates, packaging, installation, relaunch, and installed-app identity all passed.
- The final captured-draft screenshot is `/Users/jordanstella/GitHub/bessie/dist/Bessie-project-capture.png` on the Mac and `/tmp/Bessie-project-capture-m5-final.png` on the VPS, 940×700, SHA-256 `2b5d74a1f8143a1d7f85e8679b05bf027d55459965c5fe49ced3ef2d314b0ec6`. Visual inspection confirmed the native Create Project editor, captured four-pane nested topology and labels, blank startup-command fields shown as shell-only, the expected review prompt for the intentionally nonexistent fixture folder, and no clipping, overlap, blank content, or live-session ownership claim.
- Packaged and installed executables match byte-for-byte with SHA-256 `788c23e93d8fbc948e78ce3d09afe4216cb4f8da81e70d1a562b46e692a9e222`.
- Final `./scripts/check.sh`, `git diff --check`, and shell syntax checks for `mac-verify.sh`, `check.sh`, and `package-app.sh`: exit 0. The staging area remained empty. Existing dirty work was preserved. No staging, commit, push, publication, deployment, or notarization was performed.

## Projects Milestone 5 independent review

- Amp `bessie-projects-capture` completed capture converter + UI entry with blank commands, fresh recipe IDs, authoritative CWD-only path, full mac-verify claimed, package SHA-256 `788c23e93d8fbc948e78ce3d09afe4216cb4f8da81e70d1a562b46e692a9e222`.
- Hermes re-ran: `BessieProjectCaptureTests` **8/0**, `ProjectsViewModelTests` **15/0**; `./scripts/check.sh` and `git diff --check` passed.
- Code review: pure Core capture; no live Herdr IDs in recipe path; disconnect invalidates stale snapshot; save only via existing editor store path.
- Milestone 5 accepted. Milestone 6 release verification started.

## Projects Milestone 6

Status: verification paused at the explicit acceptance-artifact gate. The integrated code, live Herdr checks, package, installation, relaunch, identity, and survival checks are green, but this run did not produce a screenshot that actually shows the Project launch review/progress or partial-recovery presentation. Milestone 6 and full Projects release readiness are therefore not claimed.

Exact command and test evidence:

- `git diff --check`: exit 0 before the Mac run.
- `./scripts/check.sh`: exit 0 before the Mac run; runtime lock/compatibility/notice/package, UI-copy, shell syntax, and static checks passed. Swift remained unavailable on the VPS and ran on the Mac.
- Full `./scripts/mac-verify.sh`: exit 0. Production and debug builds passed; **167 tests executed with 0 failures**, including all four isolated live Herdr tests. `testNativeProjectMaterializerAgainstIsolatedHerdr` passed and exercised public protocol-17 creation, exact returned IDs, fresh snapshots, topology, command readiness/echo/Enter, and observable command output.
- Focused Mac reruns used `BESSIE_PROJECTS_PATH` under a unique `/tmp/bessie-m6-focused.*` root and `--skip-build`: `BessieProjectTests` **26 tests, 0 failures**; `BessieProjectMaterializationTests` **22 tests, 0 failures**; `BessieProjectCaptureTests` **8 tests, 0 failures**; `ProjectsViewModelTests` **15 tests, 0 failures**. The temporary root was removed by the verifier-owned trap.
- The full verifier used `/Users/jordanstella/GitHub/bessie/.local/herdr/runtime/projects-<pid>` as its clean `BESSIE_PROJECTS_PATH` and removed it during exact cleanup. It did not target the real `~/Library/Application Support/Bessie/Projects` catalog.

Acceptance evidence established:

- Herdr Plus was absent: `find` plus a case-insensitive packaged-app string scan found no Herdr Plus path, source, binary, or reference and printed `no Herdr Plus strings in packaged app`. Native model/store/view-model tests prove local recipe CRUD; recipe codec tests reject runtime/environment fields and encoded capture fixtures exclude live Herdr IDs.
- Materializer and protocol tests prove opening uses only public Herdr protocol-17 requests, retains exact creation-response IDs, and verifies them in fresh snapshots. Command tests prove exact reviewed text, bounded nonblank readiness, stable newly observed exact echo, no Enter on readiness/echo failure, and no blind timeout fallback.
- Partial-failure tests prove visible structured facts, surviving exact IDs, no automatic retry/close/rollback, and disabled unsafe retry. Capture tests prove fresh recipe IDs, blank commands, and CWD only when every authoritative pane CWD agrees.
- The full verifier exercised an isolated live workspace and pane output, quit Bessie, proved Herdr panes/output and a semantic agent record survived, relaunched Bessie, and reattached controllers. It later stopped and removed only verifier-owned isolated processes and paths.
- The verifier compared ordinary system `default` status before and after. Final explicit status was `{"status":"not_running","running":false,"version":null,"protocol":null,"capabilities":null,"compatible":null,"socket":"/Users/jordanstella/.config/herdr/herdr.sock","session":null,"restart_needed":false}`. The isolated autostart fixture also proved its `default` session remained `running:false` while the named `bessie` session survived app quit until the verifier explicitly stopped that isolated session.

Package, install, and screenshot evidence:

- `/Users/jordanstella/GitHub/bessie/dist/Bessie.app/Contents/MacOS/BessieApp` and `/Applications/Bessie.app/Contents/MacOS/BessieApp` are each **16,672,112 bytes**, compare byte-for-byte (`cmp` exit 0), and share SHA-256 `42ee171eb37b43dd6ab5f7ded34dede234df35fdb5c9c6276ecaa6b83c31a502`. Deep strict signature checks, installation, installed-app launch, isolated connection, and relaunch all passed.
- Projects catalog: `/Users/jordanstella/GitHub/bessie/dist/Bessie-projects.png`, **1180×740**, **136,115 bytes**, SHA-256 `aa3dc8326d7e6819f3685b18c1e327265b87c5b75465af86b17d1ca7378b58ad`. The design gate passed (rail luminance 9.80, cowprint σ 1.07, chroma 0.00). Direct inspection showed the populated `VERIFICATION` group, local Project path, tab/pane/command summary, and enabled Open/Edit actions with no overlap or blank/misleading Projects content. A long unrelated workspace label in the rail is intentionally ellipsized.
- Captured draft/editor: `/Users/jordanstella/GitHub/bessie/dist/Bessie-project-capture.png`, **940×700**, **71,611 bytes**, SHA-256 `18d0f194fee61c3c180a017bcbbc080de399ed6b795b286b567a3d6a732a50f1`. Direct inspection showed the native Create Project editor, four-pane nested layout, matching pane list, blank optional startup-command inputs, exact-command preview showing `Shell only`, and the honest absolute-folder review requirement, with no clipping, overlap, or blank misleading state.
- Existing workspace and Settings screenshots also passed their unchanged 1180×740 design gates. `Bessie-window.png` is 191,187 bytes with SHA-256 `cac658309e31ab26c0675e223305922790223c665a709f59bc82bfee11d4bc70`; `Bessie-settings.png` is 329,068 bytes with SHA-256 `e47020528eca2c53716dce08801e2218c7a92e811fb172c6ee2f437831b9d8f5`.

Pause condition and scope boundary:

- The populated catalog screenshot proves the enabled Open entry point, and `ProjectsViewModelTests` proves command review, progress, exact-ID completion handoff, and partial-recovery state. However, no captured image from this run visibly contains the launch-review sheet, opening-progress card, or partial-recovery sheet. GOAL.md requires UI screenshot evidence for the open/progress path and says to stop rather than greenwash when an acceptance criterion cannot be exercised. That missing visual artifact is the sole recorded Milestone 6 blocker.
- No product feature, test, check, source file, runtime dependency, or packaging behavior was changed. Existing dirty work and the empty staging area were preserved. No staging, commit, push, publication, deployment, notarization, release, ordinary-session mutation, or Herdr/Herdr Plus upstream modification occurred.

## Projects Milestone 6 closed

Status: complete for V1 Projects release verification (not public notarization).

Blocker closed after Amp paused only for missing launch-review visual evidence:

- Added verification-only `BESSIE_DESIGN_PREVIEW=project-launch-review` path that presents the real launch-review sheet without materializing or mutating Herdr.
- Extended `mac-verify.sh` to capture `dist/Bessie-project-launch-review.png`.
- Full `./scripts/mac-verify.sh`: exit 0; **167 tests, 0 failures** in the packaged run; live isolated Herdr suite green; package/install/relaunch identity matched.
- Launch-review artifact: `/Users/jordanstella/GitHub/bessie/dist/Bessie-project-launch-review.png` and VPS `/tmp/Bessie-project-launch-review.png`, **560×520**, **29,607 bytes**, SHA-256 `e1fde414f9dc5d0fd2c13b64a52a65355ff76afbd9e9de93c341922424bf6bac`.
- Visual inspection: title **Review Project launch**; connection **This Mac**; working directory shown; tab **Main** / pane **Proof shell**; exact command `printf bessie-project-open-proof`; **Cancel** and **Confirm and Open**; no clipping, blank content, or misleading launch state.
- Packaged and installed executables byte-identical SHA-256 `d3c2a80637a057a02dbf031e24eb37213f6006651112538e0992cb9bac9f6493`.
- Focused follow-up test `testDesignPreviewLaunchReviewShowsExactCommandWithoutMaterializing`: **1/0** after rebuild.
- Catalog and capture screenshots remain green from the same verifier run.
- Ordinary sessions untouched; staging empty; no commit/push/publish/notarize.

Native Projects Milestones 0–6 are accepted for V1 product scope. Public notarization remains deferred.

## V1 Slice E — Herd B + Attention thin

Status: code milestones complete; focused native verification passed. Shared-mirror package/install verification was intentionally not claimed because concurrent slice synchronization overwrote a mirrored source file during the first run.

- Added Core Herd and Attention builders, shared connection labels and routed pane targets, explicit Needs-you = blocked filtering, count and ordering tests, and fleet-wide blocked+done Attention ordering.
- Wired Herd counts/cards/connection chips/degraded banners and fleet-wide Attention/Open pane/⌥⌘N routing in the product shell.
- VPS `./scripts/check.sh`: exit 0.
- Isolated Mac `xcrun swift test --filter "HerdListTests|AttentionListTests|SurfaceProjectionTests|KeyboardShortcutTests"`: BessieApp compiled; **21 tests, 0 failures**.
- No full `mac-verify.sh`, screenshot, package install, executable identity, push, or PR result is claimed for this slice.

## V1 Slice I — Appearance

Status: complete. Bessie now honors System, Dark, and Light appearance preferences instead of forcing dark; exposes Comfortable and Compact density; and lets users disable cowprint texture without discarding contrast or motion preferences.

- Added legacy-safe persisted defaults for density (`comfortable`) and cowprint texture (`on`), with round-trip and sparse legacy decode coverage.
- Added a warm light semantic palette while retaining the existing dark palette. SwiftUI chrome follows the selected or system color scheme live; the libghostty terminal surface remains explicitly dark and independent of chrome appearance.
- Density metrics now drive shell gaps, rail width and rows, top bars, Herd cards, Attention rows, Settings rows, workspace tab chrome, and pane headers.
- Settings exposes Theme, Density, and Cowprint texture controls. No token editor or terminal theme marketplace was added.
- `mac-verify.sh` now uses a deterministic dark fixture, permits marked isolated temporary mirrors for concurrent worktrees, canonicalizes temporary paths, and serializes Mac verification/install work with a host-wide lock.

Verification evidence:

- `./scripts/check.sh`: passed.
- Native focused preference test: **1 test, 0 failures**.
- Native release build of `BessieApp`: passed after the final review fixes.
- A prior full native run on the Slice I source completed **177 tests with 0 failures**; later isolated full runs repeatedly hit the pre-existing flaky `testProjectsMilestoneZeroContractAgainstIsolatedHerdr` live decode failure, unrelated to appearance. One isolated run completed **168 tests with 0 failures** before stopping at temporary-path canonicalization, which is now fixed.
- Light + Compact + cowprint-off Settings proof: 1180×740 PNG, SHA-256 `ace26ddca75678f1852cb1cbb0dbde62959b567f6f04ab607a9c30ca74eafa01`. Visual inspection confirmed readable warm light chrome, selected Light/Compact controls, cowprint texture off, no visible texture, and no clipping or overlap.
- Packaged-install replacement was not repeated after the final review fixes because another `/Applications/Bessie.app` process was active from concurrent Bessie work; the existing app was not interrupted or overwritten.

## 2026-08-02: V1 Slice F0 Workspace FS substrate complete

Status: complete for the Core-only F0 acceptance contract. No watcher, Git diff service, file-operation UI, or SwiftUI surface was added.

- Added `WorkspaceFS.swift` with local-only root resolution from authoritative Herdr pane CWDs, explicit workspace-consensus versus selected-pane provenance, fail-closed stale/contradictory pane selection, readable-directory validation, and optional Git top-level discovery without changing the browse root.
- Added component-wise POSIX symlink resolution for existing files and contained missing destinations. Traversal, sibling-prefix paths, direct/nested symlink escapes, stale roots replaced by outside symlinks, and remote connections fail closed. `WorkspaceFileRoot` cannot be constructed by external consumers outside the resolver.
- Added shared heavy-directory ignores for `.git`, `node_modules`, `.build`, and `DerivedData`, plus bounded metadata classification for directory, markdown, text, image, video, and binary content. Text-like extensions still pass the UTF-8/NUL heuristic; non-regular filesystem entries are not sampled.
- Added `WorkspaceFSTests.swift` with 14 focused tests covering remote unsupported, consensus and selected-pane roots, invalid selections, Git discovery, traversal and sibling-prefix rejection, contained and escaping symlinks, nested missing-target escapes, root replacement, POSIX tilde targets, ignore rules, metadata, binary markdown, and size limits.
- Failure-first Mac evidence: before production code existed, the focused test target failed compilation because `WorkspaceFS` and `WorkspaceFileRoot` were absent. The first implementation then passed 9 focused tests. Independent review found stale-pane fallback, missing-destination containment, provenance loss, externally constructible roots, extension-only text classification, non-regular file handling, nested symlink targets, and stale-root rebinding; each in-scope finding was repaired and covered by focused tests.

Verification evidence:

- Final `./scripts/check.sh`: exit 0; runtime lock/compatibility/notice/package, UI-copy, shell, package, and F0 static anchors passed.
- Final focused isolated Mac command `xcrun swift test --filter WorkspaceFSTests`: **14 tests, 0 failures**.
- Full isolated Mac `xcrun swift test`: **182 tests, 0 failures, 4 expected live-Herdr skips**. The final error-classification hardening was then recompiled and covered by the 14-test focused rerun.
- Focused `git diff --check` for the F0 source, tests, progress report, and check script: exit 0. Repository-wide `git diff --check` remains blocked by pre-existing trailing whitespace in unrelated dirty roadmap files; those files were not modified by F0.
- `./scripts/mac-verify.sh`, package installation, and relaunch were not run because the shared Mac mirror currently contains concurrent E/F2 slice files not present in this worktree, including an incomplete `AttentionList`/`HerdList` dependency set. Running the shared verifier would overwrite or mix unrelated work. F0 compilation and tests instead ran from verifier-owned temporary Mac directories that were removed afterward.
- URL-returning containment cannot make a later consumer's separate read or mutation race-free against a malicious concurrent directory swap. F1/F2 operation wrappers must revalidate immediately before use; descriptor-relative `openat`-style operations are a later hardening option if that stronger threat model is adopted.

No UI, dependency, watcher, Herdr runtime, ordinary Herdr session, push, PR, publication, deployment, or installed app was changed by F0.

## 2026-08-02: V1 Slice F1 Follow files complete on VPS

- Added Core-owned watch stretches, recursive 250 ms workspace polling, ignored-directory pruning, coalesced touched-path recency with a 500-path cap, follow-latest selection, and one pinned selection. Initial filesystem state is the stretch baseline and is not reported as touched.
- Added read-only previews against git HEAD for tracked modifications/deletions and full-file-as-added previews for untracked or non-git files. Git runs use argument arrays with `--`, a bounded timeout, and a 1.5 MB text limit; binary, oversized, missing, escaped, and unavailable paths degrade explicitly.
- Added the native Agent detail Changes panel with Follow latest and Pin controls, an honest “Workspace changes observed while watching” attribution label, local working-directory lifecycle, same-pane cwd restart handling, and an explicit remote-unsupported state. No editor, save path, remote filesystem transport, or Herdr mutation was added.
- Added focused Core tests for touch ordering/coalescing/capping, pin behavior, watcher initial suppression and add/modify/delete events, ignored directories, containment, git tracked/deleted/untracked previews, non-git fallback, binary files, and size limits. Added App model tests for same-pane cwd reconfiguration and remote capability gating.
- `./scripts/check.sh`: exit 0. Runtime lock/compatibility/notice/package anchors, UI copy, and F1 structural anchors passed. Swift is unavailable on this VPS, and the goal contract explicitly prohibited fake or remote Mac verification, so native compilation, Swift test execution, packaging, installation, app relaunch, and screenshot inspection were not run or claimed.
- Simplification review consolidated relative-path containment, batched touch updates, reduced redundant preview reloads, and rejected oversized files before reading them. Focused code review found one P1 stale-root lifecycle defect; the configuration identity now includes workspace and cwd, with regression coverage. A final independent Swift/concurrency review found no high-confidence blockers.
- Existing planning and roadmap dirt remained untouched. No push, PR, publication, deployment, Mac sync, app installation, or Herdr/file mutation occurred.

## 2026-08-02: Agent Intent Bus U1 registry complete

- Added the versioned `BessieCore` intent registry, typed owner/risk metadata, JSON Schema parameter descriptions, and all nine pilot definitions. Herdr-scoped routes require `connection_id`; Bessie Project reads are explicitly `offline_ok`; `workspace.close` is marked destructive.
- Failure-first Mac run `xcrun swift test --filter AgentIntentRegistryTests` failed because the registry and catalog types did not exist. After implementation, the focused suite passed **4 tests with 0 failures**, covering Codable round-trip, exact pilot membership, unique MCP-safe names, required metadata, and exported JSON Schema field names.
- `./scripts/check.sh`: exit 0. Swift is unavailable on the VPS; focused Swift compilation and tests ran on `jordan-macbook`. No app lifecycle, socket, CLI, MCP, skill, Herdr session, push, PR, publication, deployment, or notarization work occurred in U1.

## 2026-08-02: Agent Intent Bus U2 executor complete

- Added the versioned request/result wire model and one Core executor for all pilot intents. It performs strict schema validation, returns structured error codes, requires explicit connection IDs for Herdr-scoped routes, exposes connection-scoped projection/focus/layout facts, and maps focus/close through injectable `HerdrAction` paths. Effective intent discovery omits live-only intents while disconnected.
- Added in-memory lock-protected one-shot confirmation tokens bound to the destructive intent plus canonical sorted params. `workspace.close` uses the exact authoritative projection cascade text; changed arguments and token reuse fail with `confirm_token_invalid`.
- Failure-first Mac compilation proved the executor/request/result/port types were absent. A second proof-first run failed on missing connection-scoped focus/layout output. Final `xcrun swift test --filter AgentIntentExecutorTests`: **7 tests, 0 failures**. `./scripts/check.sh` and `git diff --check`: exit 0.

## 2026-08-02: Agent Intent Bus U3 UI dispatch complete

- Added a persistent app-side dispatcher around the Core executor and routed all current pilot workspace/pane focus and workspace-close paths through it, including routed pane opening and Project handoff sequences. Non-pilot actions retain the existing action client path. Disconnected UI actions now surface an error instead of silently returning.
- Workspace-close UI confirmations explicitly grant the destructive follow-up; an unconfirmed programmatic close receives the executor's `needs_confirmation` result and cannot auto-confirm. MainActor projection updates and connection/request generation guards remain intact.
- Failure-first Mac compilation proved the pilot mapping seam was absent. Final `xcrun swift test --filter IntentActionDispatcherTests`: **2 tests, 0 failures**. The command compiled both `BessieApp` and `BessieAppModelTests`. `./scripts/check.sh` and `git diff --check`: exit 0.

## 2026-08-02: Agent Intent Bus U4 local socket complete

- Added the Core NDJSON Unix-socket client/server, a 0600 Application Support endpoint with isolated-path override, stale-endpoint and competing-owner protection, structured malformed-request handling, and honest `bessie_not_running` client failures. No TCP listener exists.
- BessieApp now hosts one persistent executor/socket for the fleet, backed by the real Project store and explicit multi-connection live routing. It starts with the app and releases only the local bus endpoint on termination; Herdr and pane processes are untouched.
- Failure-first Mac compilation proved the socket server/client contract was absent. Final `xcrun swift test --filter AgentIntent`: **15 tests, 0 failures** across XCTest and Swift Testing; `xcrun swift test --filter IntentActionDispatcherTests`: **3 tests, 0 failures**. `./scripts/check.sh` and `git diff --check`: exit 0.
