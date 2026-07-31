# Goal progress

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

- `GOAL.md` bounded the work to reachable user-facing copy and information hierarchy while preserving Herdr/libghostty behavior, safety consequences, errors, visual fidelity, and the complete native verification path.
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
- Mac Swift tests: 50 executed, 0 failures. Production build, plist validation, ad-hoc signing, live Herdr/libghostty/Codex acceptance, app-reopen survival, isolated restart, screenshots, and exact-process cleanup passed.
- Final packaged executable: 12,937,200 bytes at `/Users/jordanstella/GitHub/bessie/dist/Bessie.app/Contents/MacOS/BessieApp`; SHA-256 `21ed77d17750ad85547ae11260d707fe965ac06a8a9a4be195d8a79415ee00f9`.

Acceptance boundary:

- Automated release-candidate verification is complete. Hands-on testing remains required for native drag feel, split-divider feel, notification authorization and system delivery, notification click routing, and confirmed observe-to-takeover behavior.
- Notarization and general publishing remain outside this candidate.
