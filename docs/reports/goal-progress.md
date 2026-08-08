# Goal progress

## 2026-08-07: BES-40 notched-display full-screen compatibility

- **Reproduction/root cause:** native full screen was reproduced on the Mac15,12 built-in 2560×1664 Retina display while a non-notched Dell 3440×1440 display was also connected. The packaged app omitted `NSPrefersDisplaySafeAreaCompatibilityMode`, allowing macOS to activate display-safe-area compatibility mode and reserve a black strip across the camera-housing region. Bessie's SwiftUI root already keeps controls inside the safe area while extending only its theme backdrop, so the compatibility-mode opt-out is the narrow native fix.
- **Fix/regression:** `scripts/Info.plist.in` now sets `NSPrefersDisplaySafeAreaCompatibilityMode` to `false`. `scripts/check.sh` parses the plist and requires the Boolean opt-out; the check failed before the plist change and passed afterward. No AppKit window, SwiftUI shell, terminal, focus, viewport, or Herdr ownership code changed.
- **Checks:** VPS `./scripts/check.sh` and `git diff --check` passed. On Mac, `./scripts/check.sh` passed with Homebrew tools on `PATH`; focused `testOnlyTheMainWindowReceivesBessieChrome` passed **1/1**; the release package built successfully; `plutil`, strict deep code-sign verification, and the packaged plist check passed. A full-screen enter/exit/enter probe retained app PID `23334` and terminal-controller child PIDs `23346` / `23347` throughout.
- **Evidence:** before capture `dist/BES-40-before-built-in.png` and after capture `dist/BES-40-after-dark-built-in.png` in the Mac mirror. App-window captures exclude macOS's system-owned camera/menu-bar strip, so Jordan is performing the final physical-display and theme confirmation rather than treating those captures as proof of the strip itself. The non-notched Dell remained available for the regression check; no persistent menu-bar preference was changed.
- **Package/install:** packaged and installed `BessieApp` SHA-256 values both equal `1901864b71e66b57eea546dd670c0d32fc4675ffca3d523ded0d398014a66117`. `/Applications/Bessie.app` is ad-hoc signed, contains the Boolean compatibility opt-out, and was relaunched normally as the sole exact-path owner PID `23832`. Full `mac-verify.sh` was not run. No commit, push, PR, Herdr/libghostty change, or persistent macOS setting change was performed.

## 2026-08-07: Herd / Workspace / Tab filters are manual-only

- **Cause:** the previous sidebar fix preserved an already-materialized scope only for pane-row routing. The filter presentation still fell back to live destination/workspace/pane selection whenever `workspaceScope` was nil, while ordinary workspace opens, tab focus, and pane close explicitly cleared that scope. Navigation therefore continued to rewrite the three dropdowns indirectly.
- **Fix:** the hierarchy scope is initialized once from the startup selection, then remains the sole source for the three labels, selected rows, and rail filtering. Only the Herd, Workspace, Tab, and corresponding All dropdown callbacks now replace it. Ordinary pane/workspace navigation and close flows no longer clear or derive the filter state; the selected tab label also comes from the manual scope rather than the currently open pane.
- **Regression:** `PickerPresentationTests` now proves that sidebar pane selection preserves even an uninitialized manual scope and that an explicitly filtered tab wins over a different open pane. The focused picker suite passed **14/14** on Mac. The complete Mac Swift suite passed **574 tests with 5 skipped and 0 failures**, plus **21/21** Swift Testing checks. VPS `./scripts/check.sh` and `git diff --check` passed; Swift is unavailable on the VPS.
- **Package/install:** the focused installer produced a valid ad-hoc-signed package, passed strict deep code-sign and byte-comparison checks, installed `/Applications/Bessie.app`, and relaunched the normal installed app as the sole exact-path owner PID `21511`. Packaged and installed `BessieApp` SHA-256 values both equal `709879bbab1bc7ae60fc7d25de71e31ad49b182aff6bd1066d0eedb368a85199`.
- **Visual check:** the installed app's native 1249×923 window capture at `/tmp/bessie-manual-filters.png` shows the hierarchy controls rendered cleanly as `Hermes VPS` / `Bessie` / `Boss`, with `All Tabs` beneath the selected tab dropdown and the matching pane row visible. No clipping, overlap, corruption, or blocking error is visible. Full `mac-verify.sh` was not run. No commit, push, PR, reset, stash, clean, or upstream Herdr/libghostty change was performed.

## 2026-08-07: Live pane-status invalidation

- **Cause:** the first attempted status fix added `pane.agent_status_changed` to Bessie's broad `events.subscribe` list without the `pane_id` required by Herdr's public schema. Herdr rejected the entire subscription as `invalid_request: missing field pane_id`, so Bessie exhausted reconnects and Setup Doctor reported `previouslyHealthyLoss`; the process itself did not crash. The original stale status arose because broad topology events do not invalidate every semantic agent transition.
- **Fix:** removed the invalid parameterless status subscription and added a one-second quiet-subscription wake-up that resnapshots through the existing authoritative Herdr projection. Real subscribed events still refresh immediately; the bounded poll closes unsupported per-pane status gaps without local status inference, persistence, or shadow pane state.
- **Regression:** the request-shape test failed first with `XCTAssertFalse failed` against the invalid subscription list. Focused tests now cover both exclusion of the parameterized event from the broad request and quiet-socket poll invalidation. The focused Mac Bootstrap selection passed **10/10** tests; the install helper's additional shortcut selection passed **17/17**. VPS `./scripts/check.sh` and `git diff --check` passed; Swift remains unavailable on the VPS.
- **Package/install:** the established focused installer produced a valid ad-hoc-signed package, passed strict deep code-sign and byte-comparison checks, installed `/Applications/Bessie.app`, and relaunched it as the sole exact-path owner PID `15024`. Packaged and installed `BessieApp` SHA-256 values both equal `3eced20d97713a5616bf8df14896bed5c5087ce6f32ed9695b4536565a7194f0`.
- **Live proof:** Bessie's intent bus reported `connected=true`; connection context reported selected/enabled `hermes-vps` as connected; after 92 seconds the same installed process remained healthy and connected. Full `mac-verify.sh` was not run. No Herdr/libghostty change, local status-history table, commit, push, PR, reset, stash, or clean was performed.

## 2026-08-07: BES-38 Hermes terminal theme pairing

- **Mandatory characterization:** before changing behavior, public `herdr api snapshot` and read-only terminal frames identified Hermes panes `w2E:p2Y` / `w20:p1` and Amp control `w2E:p2Z`. Source boot-theme evidence in `/home/hermes/.hermes/tui-theme-boot.json` resolved Hermes dark (`background #282828`, `text #FFF8DC`). The idle Hermes repaint contained 1,399 semantic-default `0;39;49` cells and 428 explicit cream-foreground/default-background `0;38;2;255;248;220;49` cells; Amp remained default/indexed. This confirmed the plan's global pairing branch rather than its light-palette stop condition. A live controlled OSC 10/11 producer could not be run safely: no public Bessie CLI/MCP executable was present on the VPS or in the installed Mac bundle, and terminal input injection was prohibited. No live installed implementation-branch proof is claimed.
- **Hermes fix:** resolved themes now carry a terminal background. Dark/light built-ins use their matching seeds; skins preserve an authored background or fall back by polarity. Theme commits atomically validate and write paired OSC 10/11 defaults, include background in redraw equality, and retain tracked OSC 110/111 exit restoration plus non-TTY no-op behavior. No palette values were retuned.
- **Bessie boundary proof:** production Bessie code is unchanged. Focused tests prove a public Herdr ANSI frame preserves host-default spans, an explicit RGB foreground/background pair, and the following `39/49` reset byte-for-byte; a mounted in-memory libghostty surface preserves all three spans while Bessie's Dark-to-Light transition changes only its host foreground/background configuration.
- **Verification:** `npm run check --prefix ui-tui` in Hermes passed build and typecheck, **1,539 tests passed with 1 skipped**, and lint completed with one unrelated existing `useSessionLifecycle.ts` warning. Focused Hermes characterization tests had already passed **167/167**. Mac `xcrun swift test --filter "BessieThemeTests|TerminalControllerTests"` passed **40/40**. VPS `./scripts/check.sh` and both repositories' `git diff --check` passed. `scripts/mac-verify.sh` was not run.
- **Remaining acceptance:** package the integrated Mac mirror, install `/Applications/Bessie.app`, verify packaged/installed executable identity, relaunch, exercise the shell/Amp/Hermes Dark-Light-System matrix and Hermes theme transitions through public surfaces, and inspect screenshots. Those steps remain because the implementation lives partly in the separate Hermes checkout and the safe live producer/control surface was unavailable; packaging or installing Bessie alone would not incorporate that unshipped Hermes change.
- No Bessie ANSI rewriting, Hermes detection, agent-specific palette, Bessie palette change, Herdr/libghostty/protocol change, system software replacement, worktree, commit, push, PR, stage, stash, reset, clean, or unrelated reformat was performed.

## 2026-08-07: Sidebar pane selection preserves hierarchy filters

- **Cause:** the sidebar pane route updated the active pane's connection/workspace selection, and those same values back the specific Herd/Workspace/Tab filter presentation. The route therefore let navigation silently replace the user's filter context.
- **Fix:** sidebar pane activation now snapshots the effective hierarchy scope before routing and restores that exact scope on both optimistic and authoritative route presentation. Specific Herd/Workspace/Tab selections and All Herds/All Workspaces/All Tabs remain unchanged; non-sidebar routes retain their existing behavior.
- **Regression:** the new reducer test failed first because `selectingSidebarPane` did not exist. After implementation, the four-case focused Mac selection passed **4 tests with 0 failures**, covering the new preservation contract plus existing All-scope membership and fallback behavior. The focused install script's additional shortcut suite passed **17 tests with 0 failures**. VPS `./scripts/check.sh` and changed-file `git diff --check` passed.
- **Package/install:** mirrored the complete dirty working tree to the verified Mac mirror without `--delete`, built a clean ad-hoc-signed production package, passed strict deep code-sign and byte-comparison checks, installed `/Applications/Bessie.app`, and relaunched the normal installed app as sole exact-path owner PID `88237`. Packaged and installed `BessieApp` SHA-256 values both equal `d29268e295e9497ab01e8f8b6bd74a7444d55e947391b4c07c8389d6dc3fccc5`.
- **Visual check:** the installed app's native window capture at `/tmp/bessie-sidebar-filter-fix.png` is 1249×923 and rendered normal Bessie/sidebar chrome with Hermes VPS, Superbud, Superbud Boss, All Tabs, and the matching pane row visible; there was no clipping, overlap, corruption, or blocking error. The terminal body was empty at capture time. Full `mac-verify.sh` was not rerun for this narrow acceptance correction; no check was weakened, and no commit, push, PR, publication, reset, stash, clean, or upstream change was made.

## 2026-08-05: Sidebar context actions and named topology creation

Status: implemented, packaged, and installed on `jordan-macbook`; the feature tests pass, while the full Mac verifier still has a late unrelated performance-profile failure.

- **Sidebar actions:** herd/host, workspace, tab, and pane rows now expose their existing actions through native right-click context menus. The host-level new-workspace action sends `workspace.create` without a `cwd`, leaving Herdr to choose that host's authoritative startup directory instead of copying the selected workspace.
- **Required naming:** every interactive new-tab, split-pane, and move-pane-to-new-tab path now enters a shared required-name sheet before invoking Herdr. Process launch placements carry the required tab/pane name; split creation follows the public `pane.split` with public `pane.rename` after the new pane appears in the authoritative snapshot.
- **Command palette:** opening with Command-Shift-P now focuses the search field immediately.
- **Tests:** the Mac Swift suite passed **424/424**, including `testTopologyCreationControlsUseOrdinaryHerdrActions`, process-launch label coverage, context-menu presentation contracts, and command-palette focus-source coverage. VPS `./scripts/check.sh` passed.
- **Mac verification:** the first run exposed and then fixed a missing `BessieThemeCoordinator` environment injection at launch. The rerun built and packaged successfully, passed all 424 Swift tests plus 21 CLI/MCP tests, passed the design snapshot, and completed the live terminal workload. It then exited at the verifier's asynchronous native `sample` wait after writing the profile; this was outside the sidebar/topology paths, so a complete `mac-verify.sh` green result is still outstanding.
- **Install:** `/Applications/Bessie.app` was replaced from the latest newly packaged `dist/Bessie.app`, deep codesign verification passed, the executable is byte-identical at SHA-256 `eb6cbc1f4ab87b18ac8dd97906d6cc84f8a3461f2e8d1eadba22ae7afef92f66`, and the ordinary installed app was relaunched as pid `83232`. The packaged workspace screenshot showed intact sidebar, titlebar, split layout, and Ghostty terminal rendering.
- No commit, push, PR, or upstream Herdr/libghostty change.

## 2026-08-05: Restore working-status spinner without whole-window commits

Status: fixed, packaged, installed on `jordan-macbook`.

- **Cause:** earlier pane-lag work froze `BessieStatusGlyph` working ring at angle `0` because continuous SwiftUI rotation/`TimelineView` forced shared `NSHostingView` commits (~40% CPU) and starved libghostty.
- **Fix:** working state now uses `BessieWorkingSpinner` / `BessieWorkingSpinnerNSView` — a tiny AppKit view with a Core Animation infinite rotation on a content layer. Same 10pt ring / 0.28 arc / 0.8s cadence. Reduce Motion keeps it static. Path rebuilds do not touch the animated transform.
- **Tests:** `testWorkingSpinnerUsesCoreAnimationAndRespectsReduceMotion` plus existing visual foundation/rail tests — **25/25** on Mac.
- **Verification:** VPS `./scripts/check.sh` passed. Packaged + installed `/Applications/Bessie.app` byte-identical SHA-256 `2c167fe5873c302121af1c42e4de4b8eba19ed226afe70729fbe0815584d502b`. `codesign --verify --deep --strict` ok. Relaunched (pid 8171). No commit/push/PR.

## 2026-08-05: Intermittent pane-switch cold starts and terminal-wide lag

Status: measured fix installed; one real visible click cycle remains to confirm the UI path.

- **The intermittent pattern is now identified:** already-warm pane swaps attached and
  flushed in **20–59 ms**. First selection of a cold pane attached quickly but waited
  **1.2–1.9 s** for its first complete terminal frame; Herdr focus confirmation varied
  from **2.1–2.85 s**. Re-selecting the same warmed pane returned to **20–23 ms**.
- **Cold-start fix:** the current workspace's non-visible panes are bounded by the
  existing warm capacity and receive real offscreen libghostty hosts. This starts the
  public `herdr terminal session control` bridge before selection rather than creating
  a dormant controller that cannot safely accept frames.
- **Warm-stream boundary:** an intermediate candidate paused hidden streams after their
  first complete frame. It displayed cached pixels in **33–50 ms**, but live traces
  showed **0.65–1.3 s** of stale/non-interactive time while the selected stream resumed.
  That candidate was rejected. With the status animation removed, all bounded panes in
  the current workspace can remain live at **2.5–6.1% CPU**, eliminating the reconnect
  gap. Hidden warm hosts remain excluded from interactive presentation and can never
  receive first-responder focus.
- **Post-switch lag root cause:** both `TimelineView(.animation)` and a replacement
  continuously animated SwiftUI transform forced display-cadence commits of the shared
  `NSHostingView`. With one active terminal this held Bessie near **40–42% CPU**. Making
  the 14 px working glyph static reduced the same live workload to **3.5–7.1% CPU**.
  The final keep-live candidate remained at **2.5–6.1% CPU** with all three current
  workspace terminal controllers continuously ready.
- **Verification:** VPS `./scripts/check.sh` and `git diff --check` passed. Focused Mac
  suites (`SurfaceProjectionTests|TerminalControllerTests|BessieDesignSystemTests`)
  passed **70/70**, including bounded precreation, hidden-host no-focus, and controller
  release/resume coverage. Packaged and installed executables are byte-identical and
  deep codesign verification passed.
- **Install:** a later integrated mouse-debug package from the shared working tree
  replaced the initial candidate while verification was active. `/Applications/Bessie.app`
  and `dist/Bessie.app` are byte-identical at SHA-256
  `440f4860aee98e0fa3fe55197afc579aa4fb3da6e7fd52566786cbeba2e7208e`.
  Payload-free timing is active at `/tmp/bessie-mouse-debug5.log`. Bessie's public
  `pane.focus` intent changes authoritative Herdr focus but does not drive visible UI
  selection, so it was not misrepresented as a click-path verification.

## 2026-08-05: Remote startup follow-up — host and API bootstrap

Status: installed and live-measured on `jordan-macbook`; full verifier has an AppKit test-runner crash.

- Set Jordan's saved launch policy to remote-only: `local-bessie=false`, `hermes-vps=true`.
- Removed the redundant `ping` RPC for explicit socket/SSH connections. Compatibility is still checked against the subscribed snapshot before it is installed.
- Added payload-free `remote_bridge_start` and `remote_tunnel_ready` performance milestones.
- Live installed warm-master measurement: tunnel ready `225.6 ms` after connection start; snapshot installed `2590.7 ms`; shell ready `2676.8 ms`.
- Direct API probes identified the remaining variance: `events.subscribe` and `session.snapshot` each vary between roughly `180 ms` and `790 ms`; buffered events can require a correctness-preserving second snapshot.
- SSH review: Tailscale is direct at roughly `76–96 ms`; one ED25519 identity is offered and accepted; fresh SSH is roughly `2.9–3.9 s`; multiplexed commands are roughly `0.2–0.9 s`.
- Host review: two 19-hour-old `workerd` processes from the Bessie landing-site worktree each consumed roughly one CPU. Jordan approved stopping them; both ignored `SIGTERM`, were identity-checked, then stopped with `SIGKILL`. Host idle improved from `19–26%` to `60–65%`, though provider-side steal remained `13–19%`.
- Post-cleanup live measurement: snapshot installed `1888.0 ms` and shell ready `1973.6 ms` after connection start, versus `2590.7 ms` / `2676.8 ms` before cleanup.
- Network review: the Mac's own Wi-Fi gateway measured `3.8/141.7/587.5 ms` min/avg/max with no loss. Public and tailnet routes showed the same roughly `680–704 ms` spikes, establishing local Wi-Fi jitter as the dominant remaining environmental delay. SSH compression made API latency worse and should remain disabled.
- Verification: `./scripts/check.sh` passed; focused Mac suite passed 46/46; package built, signed, installed, and packaged/installed executable SHA-256 matched (`8e66efb0…adc3a`). `mac-verify.sh` twice reached the full suite but `xctest` crashed in AppKit `_NSWindowTransformAnimation` teardown; the named test passed alone. The full verifier is not recorded as passed.

## 2026-08-05: Why Ghostty mouse works and Bessie's didn't (+ fix)

Status: fixed — packaged and installed on `jordan-macbook`.

### Why Ghostty is flawless here
- Ghostty **owns the PTY + VT**. When a TUI enables mouse mode (`CSI ? 1000h`
  etc.), Ghostty sees it on the real byte stream, sets `mouse_captured`, and only
  then encodes pointer events into the PTY.
- Bessie is a **remote renderer** of Herdr-owned panes. Herdr sends **painted ANSI
  frames**, not the original PTY stream. Live probe confirmed frames do **not**
  re-emit mouse DECSET. Herdr 0.8.0 also has **no public mouse-capture API**.
- So Bessie cannot copy Ghostty's "only send mouse when captured" path without
  upstream Herdr capability. It has to synthesize button SGR (or give up TUI mouse).

### Why the previous Bessie path still failed for TUIs
1. Every click called `requestFocus` → full Herdr `pane.focus` navigate + snapshot
   refresh (Ghostty only does local `makeFirstResponder`). That async churn on
   every mouseDown breaks mouse-aware TUIs.
2. The "only when first responder" gate was the wrong control plane and blocked
   legitimate TUI clicks in practice.

### Fix just shipped
- Default policy `.buttons`: button/drag → SGR; **free motion never** (no flood);
  wheel → Herdr `terminal.scroll`; Shift → local selection.
- Click path: local `makeFirstResponder` only; Herdr navigate **only if the pane
  is not already selected**.
- Zen / agent-detail surfaces get local focus hooks too.
- Tests: `TerminalMouseRoutingTests` **8/8**.
- Packaged/installed SHA-256
  `8e66efb0b0638afe58d19500f870a12cc6a9c60139d0cac93c70843c369adc3a`
  (byte-identical). Binary contains `Terminal mouse SGR`. No commit/push/PR.

### Honest remaining gap
Hover/any-event motion reporting still needs Herdr public capture state. Clicking
in a plain shell may insert a short SGR burst (not a continuous flood). Shift-drag
still selects.

## 2026-08-04: Intermittent pane refresh / resize oscillation

Status: fixed candidate installed with timing diagnostics armed.

- **Observed code path:** `TerminalSurfaceHostView.layout()` ran `fitToSize()` on
  every SwiftUI/AppKit layout pass, then called `terminalWasPresented()`, which
  performed another full refresh. `fitToSize()` already sends the newly computed
  grid through `InMemoryTerminalSession.resize`; the second path explicitly sent
  another Herdr resize using the potentially stale grid in controller status.
  Variable layout-pass counts therefore produced variable resize/full-frame churn.
- **Fix:**
  1. `TerminalSurfacePresentationTracker` permits one full presentation for a new
     attachment or real size change; repeated same-size layout is a no-op.
  2. Removed the explicit status-grid resize after `fitToSize()`; the in-memory
     session resize is now the single grid authority.
  3. Added payload-free switch stages to the optional state log: request,
     host attach, display flush, and Herdr confirmation with monotonic elapsed ms.
- **Tests:** VPS `./scripts/check.sh` passed. Mac focused suites
  `SurfaceProjectionTests|ProjectionActionTests|IntentActionDispatcherTests|TerminalControllerTests`
  passed **78/78**. The isolated notification test also passed **1/1**.
- **Full verification:** `./scripts/mac-verify.sh` reached `xcrun swift test`,
  where the aggregate XCTest process exited with signal 11 during an unrelated
  `SettingsAndNotificationsTests` run. A direct aggregate rerun reproduced that
  teardown/concurrency crash; the test at the crash boundary passes alone. The
  full verifier therefore did **not** pass and is not reported as passing.
- **Install:** `/Applications/Bessie.app` relaunched; packaged and installed
  executable SHA-256 `fb04e6c9dac80c9f699b39ed5a6aaf86cb4855e59640ed1424fa15c3996e2c52`
  (byte-identical), deep codesign verification passed, no startup faults.
  Temporary timing capture is armed at `/tmp/bessie-pane-switch.log`; terminal
  contents are never logged. Screenshot capture was blocked by macOS Screen
  Recording permissions in the SSH session, so visual inspection is not claimed.

## 2026-08-05: Mouse TUIs without gibberish flood

Status: fixed — packaged and installed on `jordan-macbook`.

- **Problem:** Unconditional SGR mouse inject fixed TUI clicks but flooded new
  shells with free-motion escape sequences. Disabling all SGR stopped the flood
  and also killed mouse-aware TUIs.
- **Constraint (verified live):** Herdr 0.8.0 protocol 19 has no public mouse
  capture command/state. Rendered ANSI frames do **not** re-emit DECSET mouse
  modes (`1000/1002/1003/1006`), so local libghostty cannot track PTY mouse mode
  from frames either.
- **Fix — `buttonsWhenFocused` policy (default):**
  1. Free **motion never** becomes PTY bytes (stops the gibberish stream).
  2. Click that establishes first-responder → focus + local selection only (no
     SGR into shells on click-to-focus).
  3. Click/drag on an **already-focused** pane → SGR button sequences for mouse
     TUIs; gesture stays armed through drag/up.
  4. Wheel → Herdr `terminal.scroll` (host vs alternate-screen routing).
  5. Shift → local selection always.
  6. `.full` (motion SGR) reserved until Herdr advertises capture; `.unavailable`
     remains for locked-down surfaces.
- **Tests (Mac):** `TerminalMouseRoutingTests` + `TerminalSGRMouseTests` → **13/13**.
- **Verify:** VPS `./scripts/check.sh` ok. Packaged + installed
  `/Applications/Bessie.app`, relaunched. SHA-256
  `d8451bc8ed89791d5bab7ba9247f766e5f7afc078c71386be88a4e4d839519bb`
  (byte-identical). Binary contains `buttonsWhenFocused`. No commit/push/PR.
- **UX note:** After focusing a pane (click or keyboard), mouse clicks reach the
  TUI. The focus-establishing click itself does not inject SGR.

## 2026-08-04: Pane-switch latency (batch + optimistic + light refresh)


Status: packaged and installed on `jordan-macbook`.

- **Why switches still felt laggy:** each focus hop did per-action Herdr RPC + full `session.snapshot` (often 3× for openPane); same-tab hops forced Herdr resize; multi async full refreshes and host recreate added cost.
- **Shipped:**
  1. Navigation batches via one `client.perform([actions])` → **one snapshot**.
  2. `prunedNavigationActions` skips already-focused workspace/tab/pane RPCs.
  3. Optimistic `applyingLocalFocus` paints chrome before Herdr returns.
  4. `SurfaceRefresh.display` vs `.full` — same-tab skips resize storms; park/reattach still full.
  5. Dropped forced `.id(paneID)` recreate (park-on-swap keeps correctness cheaper).
  6. Single focus activation path instead of double/triple refresh.
- **Tests:** `ProjectionActionTests|IntentActionDispatcherTests|SurfaceProjectionTests` → **58/58**.
- **Verify:** `./scripts/check.sh` ok. Packaged + installed `/Applications/Bessie.app`, relaunched. SHA-256 `913acbd56c349c0a7bf996bc42cf30c4ab4356de96d288c205d36cc1e1c93ec5` (byte-identical). No commit/push/PR.

## 2026-08-05: Remote connect fast path

Status: complete — packaged and installed on `jordan-macbook`.

- **RemoteHerdrBridge:** `ControlMaster=auto` + `ControlPersist=600`; cache remote socket path under `/tmp/bessie-$USER/<id>/remote-socket.path`; reuse healthy local forwards without a new SSH; cached-path tunnel before status; status multiplexes through existing control when present; tighter tunnel-ready poll (no 100ms flat sleep loop).
- **ConnectionLifecycle:** when `HERDR_SOCKET_PATH` is set (SSH tunnel / diagnostics), skip local sha256/codesign/`herdr status` and go socket ping → bootstrap. Local cold start probes readiness immediately (no sleep-before-first-check).
- Tests: `BessieConnectionTests` + `PersistenceReconnectTests` → **24/24**. `./scripts/check.sh` OK.
- Packaged/installed BessieApp SHA-256 `1180436fa51200eb7a87c974c1ec44d1bb904c6fcba2929fdda2f92f32a1049b` (byte-identical). `codesign --verify --deep --strict` ok. Binary contains `remote-socket.path`. No commit/push/PR.

## 2026-08-05: Start-at-launch herds (settings-controlled)

Status: complete — packaged and installed on `jordan-macbook`.

- Per-herd `connectAtLaunch` on `BessieConnectionDefinition` (`connect_at_launch` in `connections.json`). Defaults: local **on**, SSH **off**. Legacy JSON without the key keeps those defaults.
- Fleet no longer starts every configured herd at app open. Launch set = herds with Start at launch; if none enabled, falls back to the selected herd. Selecting a herd (or Connect) still starts it on demand. Turning launch off does not disconnect a live herd.
- Settings → Herds: Launch toggle per row + helper copy. Not-started herds show phase `Not started` with Connect.
- Tests (Mac): `BessieConnectionTests` + `testSettingsConnectAtLaunchPersistsPerHerd` + `testFleetStartsOnlyLaunchEnabledConnections` → **16/16 pass**. Hardened `applyAppAppearance` for nil `NSApp` in XCTest.
- `./scripts/check.sh` passed on VPS. Packaged `dist/Bessie.app`, installed `/Applications/Bessie.app`, relaunched. Packaged/installed BessieApp SHA-256 `8c18589ad8f30f92bfda77937291ac49973c24b20aa75b27a845ddc4629079dc` (byte-identical). `codesign --verify --deep --strict` ok. Binary contains `connect_at_launch` / Start at launch copy. No commit/push/PR.

## 2026-08-05: New-pane gibberish character flood

Status: fixed — packaged and installed on `jordan-macbook`.

- **Symptom:** Opening a new pane started an uncontrollable stream of random gibberish characters.
- **Root cause:** `BessieTerminalView` unconditionally injected xterm SGR mouse sequences (`\x1b[<…M`) into Herdr `terminal.input` on every `mouseMoved`/click/drag/wheel, with `mouse-reporting=true` and a motion tracking area. New shells have no mouse capture, so free pointer motion became a raw byte flood.
- **Fix (contract-aligned):**
  - Added pure `TerminalMouseRouting` policy: capture `.unavailable` never emits SGR; motion is silent; click → focus + local selection; wheel → Herdr `terminal.scroll`.
  - `BessieTerminalView` routes all pointer events through that policy; default capability stays `.unavailable`.
  - Restored `mouse-reporting=false` so local libghostty cannot encode PTY mouse bytes from the rendering-only surface.
  - Removed the always-on mouse-moved tracking area that fed the flood.
- **Tests (Mac):** `TerminalMouseRoutingTests` + `TerminalSGRMouseTests` → **10/10 pass**, including `testUnavailableCaptureNeverEmitsSGREvenForMotionFlood`.
- **Verify:** VPS `./scripts/check.sh` passed. Full `./scripts/mac-verify.sh` still fails on pre-existing LiveHerdr socket / XCTest SIGSEGV (unrelated). Packaged `dist/Bessie.app`, installed `/Applications/Bessie.app`, relaunched. Packaged/installed BessieApp SHA-256 `913acbd56c349c0a7bf996bc42cf30c4ab4356de96d288c205d36cc1e1c93ec5` (byte-identical). Process running. No commit/push/PR.
- **Honest limitation:** Mouse-aware TUI clicks remain off until a negotiated public Herdr mouse-capture capability exists (per TERMINAL-BEHAVIOR). Do not re-enable unconditional SGR inject.

## 2026-08-04: Stuck pane switch / no refresh until Projects detour

Status: fixed — packaged and installed on `jordan-macbook`.

- **Symptom:** Switching panes/tabs left the terminal surface stuck/stale. Detour through Projects then back fixed it (full host teardown).
- **Root cause:** SwiftUI reused `TerminalSurfaceHostView` across pane identity changes. `attach` rebound `paneController` without parking the previous Ghostty surface, so the old terminal could remain a host subview under/over the new one. Going to Projects emptied `presentedTerminalPaneIDs` and dismantled every host, masking the bug.
- **Fix:**
  - `TerminalSurfaceHostView.attach` parks the previous controller before rebinding, then lays out immediately when already sized/windowed.
  - `attachTerminal` keeps exactly one host subview (the active terminal).
  - Registry `activatePresentedSurface` always `refreshAfterReattach` after deferred focus attach (not focus-only).
  - Workspace + Zen terminal surfaces use `.id(paneID)` so representables do not silently reuse hosts.
  - Pane/tab focus paths re-focus and refresh on the next runloop after navigation settles.
- **Tests:** Mac `swift test --filter SurfaceProjectionTests` → **46/46**, including new `testHostControllerSwapParksPreviousTerminalAndShowsOnlyNewSurface`.
- **Verify:** `./scripts/check.sh` passed on VPS. Packaged `dist/Bessie.app`, installed `/Applications/Bessie.app`, relaunched. Packaged/installed BessieApp SHA-256 `11bbf6510d8179b97593949d0ea966cf80aa5acbf7f21f10df275c7c7da05998` (byte-identical). Process running. No commit/push/PR.

## 2026-08-05: Gate 2 follow-through (notify policy + windowless + verify)

Status: partial — code landed for settled + windowless; signing blocked on interactive keychain; mac-verify still SIGSEGV.

- **#4 Settled notifications:** planner treats Settled as `done|idle` under `blockedAndDone`, emits only on `working|blocked → done|idle`. Focused planner tests pass.
- **#3 Windowless reconcile:** fleet notify watching on `BessieAppDelegate` (survives main-window close). Product shell keeps active connection while window visible.
- **#2 Signing:** added `scripts/dogfood-install-signed.sh` (Developer ID default). SSH codesign fails `errSecInternalComponent`. Installed app this pass still ad-hoc `7b21259e…2b8b`.
- **#5 mac-verify:** re-run failed — XCTest signal 11 in `SettingsAndNotificationsTests.testTestNotificationRequestsPermission…`. Intent/CLI 21/21 ok.
- **#1 Mouse:** SGR inject path already in tree; Ghostty≠Bessie architecture. Live regression debug still needed.
- **#6 Identity split:** confirmed required; not implemented in package/mac-verify yet.
- No commit/push/notarize.

## 2026-08-05: Cold-open video only on first open

Status: complete — packaged and installed on `jordan-macbook`.

- Reverted every-start video playback. Ordinary launches still enter `ColdOpenSplashView` while bootstrap runs, but only the native "joining the herd" loader is shown when onboarding is already completed.
- Video plays at 1× only for first-run / Run Setup Again (`!settings.onboarding.completed`), plus design artboard `09`. `playsVideo` gates AVPlayer setup so completed launches never load or start the MP4.
- Removed the completed-user 2× rate path. Dismissal still requires playback-end (immediate for loader-only) and bootstrap settled; Reduce Motion / env fallbacks unchanged.
- Verification: `./scripts/check.sh` passed on VPS. Mac: rsync (no `--delete`) → `./scripts/package-app.sh` → install `/Applications/Bessie.app` → relaunch. Packaged/installed BessieApp SHA-256 `afa2f0739657cb5d409d005acba03bb2f1ff226378aec3da2adb0294706f55f6` (byte-identical). `codesign --verify --deep --strict` ok. Cold-open video still `f68f09d8…b871`. Binary contains `ColdOpenSplashView` / `joining the herd`. No commit/push/PR.

## 2026-08-05: Sidebar install, landing deploy, workspace cleanup

Status: complete on Jordan's explicit request.

- Packaged current dirty tree (includes sidebar pane context-menu parity) on `jordan-macbook` after rsync from VPS. Focused Swift tests: `SurfaceProjectionTests|HerdRailPresentationTests` → **46/46 pass**. `./scripts/package-app.sh` exit 0.
- Installed `/Applications/Bessie.app`, relaunched, and matched packaged executable byte-for-byte. SHA-256 `2df61a9da0a71d813a20bd547e5d50b3361d4139c9e21e856b3a45bb45fd40be`. `codesign --verify --deep --strict` exit 0. Binary contains `PaneContextMenuContent` and `ColdOpenSplashView`. Cold-open video still `f68f09d8…b871`. Herdr server process left running across the Bessie quit/relaunch.
- Deployed landing cold-open from `.worktrees/feat-bessie-dev-landing/site` with `npm run check` (ok) then `npm run deploy` (wrangler). Workers preview: https://bessie-dev.jordanjstella.workers.dev — version `4d288868-71ae-45f3-a42b-6cb33cb0b988`. Live checks: `/` 200, `/assets/bessie-cold-open.mp4` 200 with SHA-256 `f68f09d8…b871`, `/install` 200, `config.js` has `coldOpen:true`. No custom-domain/DNS changes; `bessie.dev` not attached.
- Closed all other Bessie workspace tabs; left only this Hermes pane (`w2E:tQ` / `w2E:p1P`). Workspace now 1 tab / 1 pane.
- Full `mac-verify.sh` not re-run (known unrelated XCTest SIGSEGV risk). No commit/push/PR.

## 2026-08-05: Corrected cold open on app startup and landing

- Replaced the app, retained V1 release, and landing cold-open copies with the corrected-logo video. The source MP4 reported 7.105 seconds but contained non-monotonic timestamps and played as 2.483 seconds in Chromium, so the shipped copies were intentionally normalized to H.264 1920×1080, 60 fps, 7.083333 seconds, fast-start MP4. All three shipped copies have SHA-256 `f68f09d8b31cd6b5af0483c50fb79dd33fbe619a358c81c8438d04ab9f67b871`; the inbox source remains unchanged at `74fe32a1d3b1ccf7cc48911da00a7b9e449402b8d18e0b5c058be92841caf86a`.
- Ordinary first-window startup now enters `ColdOpenSplashView` while connection bootstrap runs. First-run/onboarding playback remains 1×; launches with completed onboarding use 2×. Playback-end and bootstrap-settled are both required before dismissal, with explicit failure fallback, final-frame hold, design-artboard suppression, Reduce Motion, and existing cold-open environment overrides preserved.
- The landing uses the same normalized asset as a muted, non-looping, aspect-fill video layer over an already-landed hero and ambient canvas. `prefers-reduced-motion`, `data-reduce-motion`, and `coldOpen:false` skip the video without loading it.
- `./scripts/check.sh`, focused diff checks, landing `npm run check`, JavaScript syntax checks, and landing visual proof passed. The enabled-video browser proof observed duration 7.083333, muted playback, no loop, completion-driven handoff, reduced-motion/no-motion skips, and a clean cold-open screenshot at `site/proof/cold-open-1440.png`.
- Two `./scripts/mac-verify.sh` attempts against this checkout production-built and packaged the normalized resource; the final attempt synced and debug-compiled the completed playback/fallback implementation and all app sources. Both cumulative XCTest runs later exited with the repository's previously documented signal 11, at different unrelated test locations, so the verifier stopped at remote line 608 before live checks, installation, relaunch, and installed-executable identity. The only subsequent Swift edit increased the already-compiled safety-timeout literal from 7.75 to 15 seconds and passed static checks. Those later gates are not claimed, and `/Applications/Bessie.app` was not replaced.
- Independent review identified elapsed-time and asset-regression risks. The implementation now treats playback-end events as authoritative, converts deadline misses to explicit fallback rather than successful playback, pins the normalized hash in both static check lanes, and exercises enabled playback in Playwright. No remaining high-confidence review finding is known.
- No commit, staging, push, PR, deployment, publication, or remote creation was performed. Unrelated dirty work in both checkouts was preserved.

## 2026-08-04 — Pre-v1 redesign U7 Settings and preference migration

Status: U7 implementation and VPS static verification complete; native Swift compilation and screenshots were not run because this bounded unit requested `check.sh` and focused static checks only.

- Screen 08 now follows the binding General, Herds, Terminal, Notifications, Menu bar, Appearance, and Advanced & diagnostics structure. Existing startup, connection, terminal, appearance, notification permission/test, setup rerun, reset, and diagnostic actions remain functional; Copy diagnostics now writes a compact runtime report to the pasteboard.
- Added persisted menu-bar visibility (default on), badge policy (Needs you / Needs you + Unknown / Nothing), and row-click behavior (Focus pane / Open Bessie). The published preferences object is the observation seam for U10; no menu-bar controller was added.
- Presentation persistence now writes schema-versioned envelopes, migrates legacy unversioned state losslessly, preserves `blockedAndDone` as blocked plus done only, and rejects unknown newer schemas without rewriting them. The settings model surfaces that error and disables all presentation writes while the unsupported file remains.
- Notification planning is explicitly Off = none, blockedOnly = blocked, blockedAndDone = blocked + done; idle is never eligible.
- Added real 512×512 dark and light running-app icon resources. Selection is persisted and applied at launch/change through `NSApplication.applicationIconImage`; this does not claim Finder bundle-icon mutation.
- Verification: `./scripts/check.sh` passed; focused changed-file `git diff --check` passed; both icon resources were verified nonempty 512×512 RGBA PNGs. Swift is unavailable on the VPS, so new Swift tests were added but not executed here.
- No reset, clean, stash, rebase, staging, commit, push, publish, or install action was performed.

## 2026-08-04 — Ghostty parity, terminal performance, Herd status buckets, and mouse spike

Status: shortcut, Herd, and terminal-performance product changes are implemented. The packaged terminal workload passes every budget. Mouse-aware TUI input remains blocked on a missing public Herdr capability. Jordan stopped the final repeated verifier and waived another final screenshot, so cold-start sampling and installation of the exact current package are not claimed.

Shipped behavior:

- Ghostty macOS shortcut ownership now applies only while the terminal is first responder. `Cmd+B` sends raw byte `0x02`; the command palette moved to `Cmd+Shift+P`. Copy-or-interrupt, paste, clear scrollback, Select All, prompt jumps, pane/tab cycling, directional focus/swap, split creation, zoom, resize, direct tab selection, and system passthrough follow the Ghostty/Bessie matrix. Plain left Option reaches libghostty with `macos-option-as-alt=left`; terminals also use `mouse-hide-while-typing=true` and retain `mouse-reporting=false`.
- Live packaged automation observed `input=shortcut_cmd_b_control_b value=true` on both verifier panes. The first-responder regression test proves a parked/background terminal cannot steal `Cmd+C`, `Cmd+V`, `Cmd+A`, `Cmd+B`, or `Cmd+K` from text fields or sheets.
- The Herd now presents exactly Needs you (`blocked`), Working (`working`), Settled (`done` or `idle`), and Unknown (unknown or unrecognized), with All retained as an aggregate filter. Counts, card labels, accessibility labels, filters, and sorting use those buckets. Raw `.done` and `.idle` remain distinct in Herdr models, notifications, and diagnostics.
- Terminal input from AppKit/libghostty now enters one nonblocking FIFO router. Raw, special-key, paste, and scroll operations preserve order; the slower public Herdr key/paste requests no longer occupy the terminal frame-consume queue or block the main thread. A 10,000-operation mixed-input test proves no drop or reorder, and a gated transport test proves enqueue returns before transport completion.
- Hidden warm libghostty views are detached from the window so their display links do not burn idle CPU. Delta frames feed libghostty without republishing an unchanged ready state through SwiftUI. Performance evidence serialization is deferred, selected tabs present immediately from the local selection, release packaging cleans SwiftPM products before building, pane-switch and terminal workloads run separately, and the sustained producer is anchored to a monotonic 305-second deadline.

Performance investigation and packaged evidence:

- Baseline suffix `26483`: idle CPU was about 81%; parked terminal views remained attached and kept display links active.
- Suffix `37375`: hidden-view detachment reduced idle CPU to 0%; the remaining failure was a CPU >80% burst lasting 3 seconds against a 2-second budget.
- Suffix `49094`: the remaining failure was first pane-switch usability at about 106.6 ms.
- Suffix `60421`: the earlier terminal/resource plan passed after immediate selected-tab presentation; printable echo p95 was 25.753 ms, pane switching 54.568 ms, five-minute CPU 1.979%, idle CPU 0.87%, and RSS 176.266 MB.
- Suffix `73663`: every metric except sustained input passed. The old probe measured paste plus intercepted Enter and reported 238.087 ms. Investigation found public Herdr paste/special-key control calls commonly taking about 106–111 ms under output. Oracle review confirmed that the plan's <100 ms typing contract should use raw printable input, while paste/special keys remain covered by FIFO/order/drop tests rather than a false latency claim.
- Final completed terminal run suffix `87557`, packaged local app, overall PASS:
  - printable echo: p50 21.295 ms, p95 24.998 ms, p99 28.024 ms across 200 samples;
  - frame receive to libghostty feed: p95 0.044 ms across 1,457 frames;
  - 1 MB output max 183.366 ms and 50,000-line output max 66.783 ms across five runs each;
  - pane switch first usable max 48.835 ms across 20 switches;
  - resize convergence 105.682 ms;
  - sustained raw-input max 25.935 ms across 100 samples during 305.089 seconds of output;
  - five-minute CPU average 4.686%, CPU >80% longest burst 0 seconds, idle CPU 0%, and maximum RSS 142.781 MB.
- The same run completed 20 warm startup samples: first-window p95 219.068 ms and warm-shell p95 419.669 ms, both within budget. One of 500 startup main-thread probes measured 106.946 ms against the 100 ms maximum. The run stopped before five cold bundled-Herdr samples, so cold-shell p95 and the complete startup gate are unresolved rather than greenwashed.

Validation and package state:

- `./scripts/check.sh`, `bash -n scripts/mac-verify.sh`, benchmark Python compilation/self-test, and focused diff checks pass.
- Focused Mac `TerminalControllerTests`: 19 tests, 0 failures.
- The exact current source production-built and packaged `Bessie.app`, passed missing/corrupt bundled-runtime and external-runtime cases, then passed 317 XCTest cases and 21 Swift Testing cases with zero failures. Jordan stopped the repeated full verifier during its long packaged performance phase and waived another final screenshot.
- The current `dist/Bessie.app` is version `0.1.0`, build `3`, passes deep/strict code-sign verification, and contains Herdr 0.8.0/protocol 19 with SHA-256 `d53a9f93fccfdfcc55632927bf51002f5add0aa7990bcdf508ffbd84ac658178`. Its app executable SHA-256 is `8133656440e22ee54e342362cca484b4578d17669c8a16083c8c9cb194c0f70c`.
- The current package was not installed after the stopped run. `/Applications/Bessie.app` still has the prior executable SHA-256 `58dcf0ba9693602fecca2478bde20621435e163833583eca7836395b3cc5be92`; both packages contain the same locked Herdr binary, but the app executables do not compare equal.
- Repository-wide `git diff --check` remains nonzero only because of pre-existing trailing whitespace in unrelated dirty plan/roadmap files. Focused changed-file diff checks pass. No file was staged, committed, pushed, published, or deployed.

Mouse and remaining limits:

- The bundled Herdr 0.8.0/protocol-19 public terminal bridge exposes raw input, resize, vertical scroll/page, and release, but no typed negotiated button, drag, pointer-motion, horizontal-wheel, or authoritative mouse-capture state. Bessie therefore does not claim mouse-aware TUI clicks and does not copy private bincode or guess ANSI sequences.
- `docs/research/2026-08-04-herdr-public-terminal-mouse-capability.md` specifies a versioned public capability, ordered typed events, authoritative capture state, Shift-drag local selection, and live acceptance proof. Bessie can implement clicks only after Herdr exposes that contract.
- `libghostty-spm` 1.3.2 has Select All but no embedded action for Ghostty's semantic “select previous command output” behavior. `Cmd+Shift+A` falls through rather than being faked with Select All. Herdr also exposes no public equalize-splits mutation, so that shortcut is omitted honestly.
- The <100 ms sustained-input claim is specifically raw printable typing under the measured local output workload. Public Herdr paste and intercepted special-key calls were observed around 110 ms under load; saturated output beyond the measured producer and remote SSH latency remain outside that claim.

## 2026-08-03 — Bessie iOS control plane: ce-plan + goal contract

Status: planning only (not implementing). **Locked as first post–Mac-V1 ship** — not in V1 L/K; do not goal-loop until V1 release (or Jordan early green light).

- Plan: `docs/plans/2026-08-03-bessie-ios-control-plane.md` — ce-plan; Queued post-V1; M0→M5 (+ optional M6).
- Roadmap: `docs/roadmap/bessie-ios-control-plane.md` — P0 after V1 launch.
- Goal: `GOAL-ios-v1-control-plane.md` — start-gated contract.
- Also noted in `docs/roadmap/README.md`, `docs/plans/2026-08-01-bessie-v1.md`, vision-occam deferred list, workstream `V1-SCOPE.md`.
- Branch when execution starts: `feat/ios-v1-control-plane`.

## 2026-08-03 — V1 Slice L brand shell and chrome hygiene

Status: M0–M6 complete; Mac verification, installation, and installed-app identity passed.

M0 violation map:

- Warm light shell ladder and low-contrast light cowprint: `BessieDesign.palette(for:)` and `BessieCowprintTexture` in `BessieDesignSystem.swift`.
- Shouted status/count chrome, repeated connection badges, filled row actions, and dual workspace overflow: `HerdSurface`, `AttentionSurface`, `PaneControllerStatusLabel`, `BessieProductShell`, `WorkspaceSurface`, and `ProductPane` in `ProductSurfaces.swift`; connection rows in `BessieSettings.swift`; Project rows in `ProjectsSurface.swift`.
- Dual Follow latest/Pin controls: `FollowFilesSurface.swift`.
- Repeating or incomplete zero states: Herd, Attention, Workspaces, Workspace, and Agent states in `ProductSurfaces.swift`; Projects in `ProjectsSurface.swift`; Files preview in `WorkspaceFilesSurface.swift`.
- Files dual-verb action: `WorkspaceFilesBrowser` in `WorkspaceFilesSurface.swift`. Selection gating already existed for both destructive controls.
- Project launch review lacked a concise Herdr reverse-line: `ProjectLaunchReviewView` in `ProjectsSurface.swift`.
- Onboarding was a single floating card without a visible step list; Trouble was a single full-bleed card: `OnboardingView.swift` and `TroubleView.swift`.
- Pane fallback order produced `Untitled pane`, blocked state was only a generic glyph, and top-level workspace exposed separate pane/tab menus: rail, Agent detail, `WorkspaceSurface`, and `ProductPane` in `ProductSurfaces.swift`.
- Drop-shadow product chrome remained on the Project launch progress card and command palette. Slice L owns the Project chrome shadow; the transient command-palette overlay is outside the sampled product-card chrome.

Baseline evidence:

- Branch: `feat/v1-l-brand-chrome`.
- `./scripts/check.sh`: exit 0. Runtime lock/compatibility/notice/package checks, intent parity for 9 intents, UI-copy checks, and static checks passed. Swift is unavailable on the VPS.
- Existing unrelated modified roadmap/plan files and the untracked Slice L goal/plan were present before implementation and were not staged, reverted, or cleaned.

M1 shell and window chrome:

- Replaced every warm light semantic token with the locked achromatic greyscale ladder from Slice L §2.
- Preserved the independent dark terminal plate in light mode.
- Rebuilt the light cowprint tile as black RGBA ink from the artwork's alpha mask. The previous bridged template-image shading left the source tile's white RGB visible on a near-white plate; the fresh light captures now show unmistakable dark cow spots. Dark mode continues to use the original white artwork.
- Confirmed `BessieTopBar` already uses the main `background` plate with only a bottom hairline; comfortable/compact gap floors remain `cardGap` 9/6 and `paneGap` 7/5-or-higher by preference validation.
- Made the native window toolbar background transparent and extended the adaptive desk/cowprint beneath the safe area. `BessieAppDelegate` retains native traffic lights, hidden title, transparent titlebar, full-size content, and the existing titlebar double-click behavior; it now uses the adaptive Bessie window backing rather than system grey.
- Fixed the root cowprint background's missing `BessieSettingsModel` injection, which had caused a SwiftUI fatal error. Disabled AppKit secure-state save/restore and verifier persistent UI so stale crash-restoration state cannot block test launches.

M2–M5 product chrome:

- Converted product labels and actions to sentence case, removed repeated connection/status badges, reduced filled row actions, consolidated workspace overflow, and replaced Follow Files' competing follow/pin controls with one stateful control. Herd and Attention filtering/builders were not changed.
- Added honest, action-oriented empty states across Herd, Attention, Workspaces, Workspace, Projects, Follow Files, and Files. Files selection is cleared on directory loads; rename, move, and trash are enabled only for a current valid selection, with distinct rename and move dialogs.
- Added the concise Herdr create sequence to project launch review and quieted project section chrome.
- Restyled Onboarding and Trouble as flat rail/content plates, retained explicit Herdr-survival copy, and removed product-card shadow elevation.
- Workspace pane titles now derive from authoritative label/agent/title/CWD/process information before falling back to `Shell`; needs-you state is visible in pane chrome and the workspace has one overflow locus. Light mode keeps terminals on readable semantic dark code colors.

M6 evidence:

- Final VPS `./scripts/check.sh`: exit 0. Runtime lock/compatibility/notice/package checks, parity for 9 intents, UI-copy checks, and static checks passed. Swift remains unavailable on the VPS.
- Final `./scripts/mac-verify.sh`: exit 0. Production and debug builds passed; 227 XCTest cases and 21 intent/CLI tests passed with zero failures; isolated live Herdr/libghostty checks, runtime failure routes, packaging, signing, design captures, quit survival, installation, and installed-app relaunch passed.
- Fresh light screenshots: `dist/Bessie-herd-light.png` and `dist/Bessie-workspace-light.png`. Inspection confirmed visible achromatic cowprint; the workspace capture retained readable dark terminal panes and visible pane gaps.
- Fresh windowed screenshot: `dist/Bessie-titlebar-windowed.png`. Inspection confirmed cowprint visible beneath native colored traffic lights, no solid system-grey titlebar strip, and rail/main plates beginning below the native strip.
- Installed executable SHA-256: `89396ef50b2fdebc5080e2b1e738d122e2d4c6724ddafa7d16e466377d1407fb`; packaged and `/Applications/Bessie.app` executables matched byte-for-byte (`cmp=passed`).
- One preceding full run hit a transient intent-socket ownership assertion after all 227 XCTest cases passed. The unchanged test passed immediately on rerun, and the final unchanged full verifier passed. No test or check was weakened or skipped.

Manual-only remainder:

- Jordan's final visual preference judgment on cowprint strength and chrome quietness remains subjective. The automated light-capture check now requires actual darkened-pixel coverage rather than generic variance, and the captured result was inspected directly.
- Double-click titlebar behavior is preserved in code and the app relaunches successfully, but the SSH verifier does not synthesize a native titlebar double-click.

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

## 2026-08-02: Agent Intent Bus U5 CLI complete

- Added the thin `bessie` executable with only `intents`, `status`, and generic `call` forms. It translates arguments to the shared request/client, emits one structured JSON result on stdout, keeps usage diagnostics on stderr, preserves confirmation tokens, and exits nonzero on failed results or invalid input. Offline `intents` falls back to the static Core catalog; live calls fail honestly when the app is absent.
- Failure-first Mac build proved the executable target had no source. Final `xcrun swift test --filter BessieCLIArgumentsTests`: **8 tests, 0 failures**; `swift build --product bessie`: exit 0. Offline smoke exits were intents=0, status=1, invalid-args=2 with valid JSON results. `./scripts/check.sh` and `git diff --check`: exit 0.

## 2026-08-02: Agent Intent Bus U6 MCP complete

- Added the stdio-only `bessie-mcp` executable with MCP initialization, notifications, `tools/list`, and `tools/call`. Tools are projected directly from the effective registry with exact dotted names and schemas; destructive tool schemas expose the protocol-level `confirm_token`. Calls return one structured result JSON text item with correct `isError`; stdout remains protocol-only.
- Failure-first Mac build proved the MCP target was absent. Additional proof-first tests caught missing confirm-token schema advertisement and omitted-arguments handling before repair. Final `xcrun swift test --filter BessieMCPTests`: **7 tests, 0 failures**; `swift build --product bessie-mcp`: exit 0. Scripted smoke returned three protocol lines, nine exact tools, an honest offline error, and empty stderr. `./scripts/check.sh` and `git diff --check`: exit 0.

## 2026-08-02: Agent Intent Bus U7 skill and parity complete

- Added the repo-local `operating-bessie` skill and linked it from `AGENTS.md`. It teaches discovery-first CLI/MCP operation, Herdr ownership and quit survival, explicit connection scoping, one-shot confirmation, honest offline errors, human-only boundaries, and the prohibition on GUI puppeting, terminal injection, private protocols, or a shadow `bessie server`.
- Added destructive confirmation metadata to the registry and a static parity checker wired into `check.sh`. It enforces unique MCP-safe names, generic CLI/MCP projections without copied domain catalogs, destructive metadata, Package products/targets, Swift parity anchors, and discovery-first skill guidance.
- Final focused Mac suites: CLI **9 tests**, MCP **8 tests**, registry **4 tests**, all with 0 failures. `./scripts/check.sh`, `git diff --check`, parity-checker syntax, skill frontmatter validation, and workspace skill reload all passed.

## 2026-08-02: Agent Intent Bus U8 live verification complete

- Extended `mac-verify.sh` with a verifier-owned 0600 app socket and live CLI coverage for exact nine-intent discovery, app/connection status, session projection, Project list, workspace focus, and pane focus. Ordinary Herdr snapshots prove the agent mutations reached Herdr's authoritative state.
- Added stdio MCP initialize/list/call coverage with exact CLI tool-name parity and empty stderr, an honest `bessie_not_running` assertion after app shutdown while Herdr remains alive, and an isolated destructive workspace-close flow that verifies exact cascade text, one-shot confirmation success, Herdr-observed closure, and replay rejection.
- The first full run exposed a pre-existing unbounded Git-root traversal on the current Mac/Foundation version. `WorkspaceFS` now stops before deleting the filesystem root path; its stale nil-projection assertion now matches the documented Files-home behavior. The focused regression test passed before the full verifier was repeated.
- Final `./scripts/check.sh && ./scripts/mac-verify.sh`: exit 0. The native suite executed **224 XCTest tests and 21 Swift Testing tests with 0 failures**; both CLI products built; packaging, isolated live Herdr checks, app-hosted bus checks, screenshots, installation to `/Applications/Bessie.app`, relaunch, and executable identity verification passed.
- Packaged and installed executable SHA-256 values both equal `0175768a4b0f5ba453ebea0ae200479ad232fa4e92290ad71c5a95ecd3be5335`. The inspected 1180×740 live screenshot showed a usable Bessie window with two rendered terminal panes and no blank, clipped, corrupt, or blocking-error surface; minor glyph overlap in deliberate terminal test output does not affect the intent bus.
- Final `git diff --check`: exit 0. No push, PR, notarization, network listener, daemon, private Herdr protocol, ordinary Herdr session, or unrelated untracked planning artifact was changed.

## 2026-08-02: V1 Slice D production UI/UX cleanup complete

Status: complete for Slice D. No Herd, Attention, files, menu-bar, theme, remote, Herdr-runtime, or upstream libghostty feature was added.

Milestone evidence:

- M0 analysis pinned the unsafe seam: the local monitor already returned unknown system chords, but terminal `performKeyEquivalent` could still delegate them to libghostty; quit cleanup existed only on SwiftUI disappearance; and hidden custom chrome had no native zoom gesture.
- M1/M3 added a pure-Core key policy. Unmodified ⌘Q, ⌘H, ⌘M, and ⌘` are explicit passthrough before Bessie product mappings; unknown Command chords also pass through. The coordinator returns the original `NSEvent` for passthrough, while mapped product commands remain consumed. `BessieTerminalView` returns `false` for those system chords. `KeyboardShortcutTests` cover system passthrough and retain existing ⌘B/⌘W behavior.
- The app supplies a standard **Quit Bessie** command and an app delegate termination path. Shared exit cleanup releases Bessie-owned terminal controllers, connection runners, and SSH bridges idempotently. It does not call any Herdr workspace/pane/server stop API.
- M2 moved title/crumb content into the non-control drag region. Its AppKit view routes ordinary mouse-down to `performWindowDrag` and double-click to `NSWindow.performZoom`; action buttons remain outside that hit region.
- M4 audited Herd, Workspace, Attention, Projects, Settings, Onboarding, and Trouble. No visible dead-action or “coming soon” control was safe to remove. Functional actions, honest empty states, and zero-sized verifier probes remain. The final 1180×740 screenshot had no clipping or overlap; repeated workspace/tab/pane labels were authoritative Herdr fixture data.

Exact verification:

- Final VPS `./scripts/check.sh`: exit 0; runtime lock/compatibility/notice/package, UI-copy, and static checks passed.
- Clean Mac copy `/tmp/bessie-slice-d-verify`: `xcrun swift test` executed **169 tests with 4 socket-gated live tests skipped and 0 failures**; `./scripts/package-app.sh` completed a production build and packaged the app. Focused `KeyboardShortcutTests` repeatedly passed **7/7**.
- Two earlier full `./scripts/mac-verify.sh` runs passed before the final transient minimize diagnostics, including production/debug builds, all 169 tests, isolated live Herdr checks, packaging/install/relaunch, executable identity, and visual gates. A later shared-mirror attempt was invalid because concurrent Slice E source files arrived without their dependency; final Slice D verification therefore used the clean temp copy rather than changing those concurrent files.
- The clean package was transactionally installed at `/Applications/Bessie.app`; `cmp` and strict deep code-sign verification passed. Packaged and installed executables matched with SHA-256 `84ea6fecc87465fb94dd6c29b0802b6bda019d7d7891d3c6dc1034f7017c93c7`.
- With the installed app's terminal area focused, ⌘H made Bessie hidden and ⌘Q exited it in one chord. **Bessie → Quit Bessie** also exited it. Herdr session `bessie` reported 0.7.5 / protocol 17 / `running:true` / `compatible:true` before quit, after terminal-focused ⌘Q, and after menu Quit. Relaunch reattached without restarting Herdr.
- Window → Zoom changed the Bessie frame through the native `performZoom` path. Remote synthetic point double-clicks did not form a double-click in Bessie or an ordinary TextEdit titlebar; remote minimize actions likewise failed against both Bessie and TextEdit. Those invalid automation results were not greenwashed. The gesture and ⌘M ownership are evidenced by the explicit AppKit path, unchanged enabled standard menu items, and passthrough tests; no app-specific minimize interception remains.
- Final screenshot: `/tmp/Bessie-slice-d-final.png`, **1180×740**, SHA-256 `c6dcc91ee6dd24829777f94c685f16aaf0da433f488bf24373c41102397f9658`. Direct inspection found no obvious dead prototype chrome, clipping, or overlap.

No check was weakened. Existing unrelated dirty planning/roadmap work and concurrent Mac files were preserved. No Herdr session was stopped, and no push, PR, publication, deployment, notarization, or upstream modification occurred.

## 2026-08-03: V1 Slice M4 Herd consolidation

- Removed the standalone Attention destination, surface, pane-reconstructed list model, fleet list, and duplicate tests. The Herd now owns the blocked-only Needs you count, sidebar cue, and next-needs-you shortcut.
- Added one Core `requiresUserAction` predicate (`blocked` only), authoritative-agent workspace cues and notification projections, connected-connection freshness gating, connection-scope filtering, deterministic state/connection/location/identity ordering, and exact routed pane targets.
- Stale or unavailable notification and Herd targets now consume the route, report an honest failure, and recover to The Herd instead of navigating to Attention.
- `./scripts/check.sh`: exit 0. Runtime lock/compatibility/notice/package, intent parity, UI copy, and M4 static anchors passed. Swift is unavailable on this VPS, so native compilation, focused Swift tests, Mac runtime checks, screenshots, packaging, installation, and visual acceptance were not run or claimed.
- Focused `git diff --check` over M4-owned source, tests, and `scripts/check.sh`: exit 0. Repository-wide `git diff --check` remains blocked by pre-existing trailing whitespace in unrelated dirty planning and roadmap files.

## 2026-08-04: Pre-v1 redesign U3 pickers

- Added native SwiftUI popovers anchored to the expanded rail for screens 03/04. The Herd picker presents All, local, and SSH scopes with current fleet health, selection, per-connection retry, and the existing Settings add-connection route. The Workspace picker projects only fresh authoritative workspaces in the selected scope, focuses the owning Herdr connection/workspace, and creates through the existing `workspace.create` action.
- Native popover controls own keyboard traversal, Escape/outside-click dismissal, focus return, accessibility, and constrained narrow-window placement. No custom popover state machine or durable topology was introduced. Existing feature-flagged Files/Follow routes were unchanged.
- Added focused picker presentation tests for healthy/disconnected multi-connection rows, selected-scope authoritative workspaces, and ordinary Herdr workspace creation. Swift is unavailable on this VPS, so the requested native test target could not compile here; `./scripts/check.sh` passed with all runtime-lock, intent-parity, UI-copy, and static checks green.
- Full `mac-verify.sh`, terminal performance probes, installation, commit, staging, push, PR, publication, deployment, and Herdr session mutation were not run.

## 2026-08-04: Pre-v1 redesign U4 workspace panes

- Preserved the existing recursive authoritative pane renderer, warm terminal registry/controller identity, terminal shortcut actions, input ordering, focus state machine, and performance probes. Updated pane Expand to public `pane.zoom` maximize/restore rather than entering Zen, and made Add Tab require a connected workspace, reconcile from the action's fresh snapshot, and restore terminal focus.
- Completed the direct workspace-terminal shortcut contract: `Option+P`, `Cmd+D`, `Cmd+Shift+D`, `Cmd+W` Close Pane, `Cmd+Shift+J/K` rendered-rail traversal with wrap, and the existing one-shot terminal copy/paste/`0x02`/`0x03` actions. Direct topology/rail commands now pass through when a text or modal control owns first responder. Close Tab remains in the command palette without the `Cmd+W` chord; pane-close cancellation restores terminal focus without mutation.
- Added focused shortcut policy and responder-gate tests. `./scripts/check.sh` and focused changed-file `git diff --check` passed. Swift is unavailable on this VPS, so native compilation/tests and live Mac verification were not run or claimed.
- No terminal controller/input implementation, performance budget/probe, U1 design constant, U3 picker, Herdr session, stage/index, commit, push, PR, install, or shared visual source was changed.

## 2026-08-04: Pre-v1 redesign U1-U7 verified; U8 blocked by Herdr 0.8 SSH lifecycle

- Implemented the design foundation, herd-centric shell/rail, herd and workspace pickers, workspace pane chrome and direct shortcut contract, Projects list/editor, entity-aware palette, and versioned Settings/preferences through U7. The existing terminal performance code and budgets remain unchanged.
- Focused Mac verification passed in successive waves: U1-U3 ran 71 tests with 0 failures; U4-U5 ran 159 tests with 0 failures, including the 10,000-operation terminal ordering test; U6-U7 ran 77 tests with 0 failures. The VPS `./scripts/check.sh` remained green after each wave.
- U8 stopped before edits at a public-capability blocker. Herdr 0.8.0 exposes `session list`, `attach`, `stop`, and `delete`, but no public noninteractive detached named-session start. The safe attach auto-start path also seeds a workspace from its current directory before Bessie can issue U8's required public `workspace.create` for the selected path. Shell-specific detachment, a supervisor, private protocol use, silently accepting the seeded workspace, or reusing an unrelated session would violate the plan.
- U8-U12 were not implemented or claimed. Resolving the blocker requires either a public Herdr detached empty-session lifecycle or an explicit product-plan amendment allowing the attach-created selected-path workspace. No package install, commit, push, reset, clean, stash, or rebase was performed.

## 2026-08-04: Pre-v1 redesign U8 implementation attempt

- Recorded the approved remote amendment in U8: validated selected remote cwd, forced-PTY public `session attach`, strict fresh-session/collision proof, exact attach-created topology adoption, detached-daemon proof, and post-bootstrap status/snapshot/tunnel survival.
- Added the exact H.264 1920×1080 cold-open resource, four-step native onboarding presentation, native local folder picker/remote absolute-path input, Finish-versus-Skip notification behavior, a versioned pending-attempt model/store, safe IDs/path validation, coordinator stages and duplicate-submit guard, and safe forced-PTY attach argument construction.
- `./scripts/check.sh`: exit 0, including packaged video metadata. Swift is unavailable on this VPS, so native compilation and tests were not run.
- U8 is not complete: the cold-open entry gate is not yet routed from `BessieApp`; the coordinator is not yet wired to local/remote launch, collision/status/snapshot/detached survival reconciliation, exact topology adoption, first-frame focus completion, or rerun cancellation; bootstrap concurrency and failure handoff remain unwired. These are compile/runtime risks for the host to resolve before Mac verification.
- No stage/index operation, commit, push, reset, clean, stash, rebase, Mac command, install, Herdr session mutation, secret access, private RPC, nohup, supervisor, or fake topology was performed.

## 2026-08-04: Pre-v1 redesign U8 lifecycle wiring follow-up

- Routed each incomplete/setup-again entry through the cold-open once, with a bounded static/reduced-motion fallback, then into the existing bootstrap Connect/onboarding surfaces. Ordinary completed starts do not enter the splash.
- Wired selected connection/path into a persisted, duplicate-submit-guarded coordinator and a narrow injectable materialization service. The production service uses public `workspace.create`, diffs fresh authoritative topology, rejects anything other than one exact workspace/tab/pane at the selected path, persists those IDs, navigates/focuses that pane, and completes only after its real terminal controller reports a ready frame.
- Added setup-again pre-materialization cancellation restoration and focused coverage. `./scripts/check.sh` passed; Swift is unavailable on this VPS, so native compilation and the host-owned Mac lifecycle verification remain unclaimed.
- The forced-PTY remote argument seam remains present and tested. This follow-up does not claim a live SSH bootstrap execution on Linux; host Mac verification must exercise that process lifecycle before release.

## 2026-08-04: Amended U8 remote bootstrap lifecycle

- Replaced remote onboarding's pre-ready `workspace.create` assumption with an injectable OpenSSH/Herdr bootstrap adapter. It proves absence through `herdr session list --json`, validates the path via fixed BatchMode/strict-host-key SSH arguments with path bytes on stdin, launches forced-PTY attach in the selected cwd, decodes Herdr 0.8 capabilities honestly, and requires `detached_server_daemon=true` before stopping only the attach client.
- The production adapter then opens the existing `RemoteHerdrBridge`, pings and snapshots through its tunnel, and accepts only one workspace/tab/pane with exact parent IDs and selected effective cwd. Exact persisted IDs reconcile without a second attach. Focused fakes cover collision/auth/path failures, attach ordering, detached wait and survival, topology rejection, and resume idempotency.
- `./scripts/check.sh` passed. Swift remains unavailable on this VPS, so native compilation, focused XCTest execution, Mac verification, installation, and live SSH mutation were not run or claimed. No git staging, commit, push, reset, clean, stash, rebase, Herdr stop/delete, nohup, supervisor, private RPC, or credential access was performed.

## 2026-08-04: Pre-v1 redesign U11 accessibility hardening

- Added shared, testable accessibility/minimum-window contracts for the 1080×680 desktop floor, bounded scrollable pickers, reduced spatial motion, opaque Reduce Transparency surfaces, and opaque increased-contrast materials. The command palette now removes scale/scroll animation under Reduce Motion while preserving its existing terminal-focus return.
- Added deterministic picker entry/return focus, scrollable onboarding content with initial path focus, expanded/selected accessibility values, spoken herd state/location and connection health, non-color menu-bar health symbols, and explicit VoiceOver labels for rail disclosures, palette, onboarding errors, and menu-bar actions.
- `./scripts/check.sh` and restricted changed-file `git diff --check` passed. Swift is unavailable on this VPS, and the request prohibited Mac sync, so native compilation, Accessibility Inspector, keyboard-only walkthrough, screenshots, and live minimum-window/IME verification were not run or claimed.

## 2026-08-04: Pre-v1 redesign U12 capture and release gate

- Added a packaged-native 15-screen × dark/light capture harness with a deterministic fixture seed, binding frame table, exact 30-entry JSON manifest, and semantic image checks for exact dimensions, opacity, monochrome chroma, cowprint regions, visible copy via Vision OCR, and packaged assets. It reuses production views and the isolated Herdr fixture; preview inputs select presentation only and do not own runtime topology.
- Wired the matrix into `mac-verify.sh` after the unchanged startup/terminal performance probes and before destructive fixture cleanup. Existing budgets and the known `terminal_workload` failure were not removed, relabeled, narrowed, or relaxed.
- Reconciled roadmap and older plan authority: menu bar and entity palette are Pre-v1, the newer floating-card shell/four-step onboarding supersedes older visuals, four-state Settled vocabulary is canonical, elapsed-age UI is absent, and `Cmd+B` / empty-selection `Cmd+C` remain one-shot terminal mappings rather than a Bessie prefix mode.
- Linux-only `./scripts/check.sh` and focused diff checks are the verification for this host run. Per instruction, no Mac sync, native capture, package install, relaunch, or performance execution was performed; the host must run `./scripts/mac-verify.sh` and inspect `dist/redesign-matrix/manifest.json` plus all 30 PNGs.

## 2026-08-04: Pre-v1 redesign U12 final release proof

- Closed U12 with a final packaged-native 30-state dark/light matrix at every binding frame. The complete manifest, references, native captures, raw/amplified diffs, overlays, per-state metrics, contact sheets, and logs are under `/tmp/bessie-u12-evidence/`; the approved-mask structural mismatch set is empty.
- Fixed the release-blocking capture states: deterministic open Herd/Workspace pickers, `sch` palette seed, Projects destination, fixed opaque material tint, portable macOS Bash zero-padding, and a segmented 1180×1720 Settings stitch that retains the titlebar, herd rail, Settings header, correct appearance, and complete document.
- `./scripts/check.sh`, scoped `git diff --check`, production packaging, strict deep codesign, and 36 focused Mac tests pass. The live Projects contract passed on immediate focused retry after one transient output timeout. The cumulative native lane repeated the documented U11 XCTest signal-11 residual; no check or performance probe was weakened.
- Installed and launched `/Applications/Bessie.app`. Packaged and installed executable SHA-256 values both equal `066ad29dea825d1b374e6a660813332bab38418dc39747abfe15d33b31c6147f`; the installed screenshot is `/tmp/bessie-u12-evidence/installed-app.png`.

## 2026-08-04: Sidebar pane context-menu parity

- Added one shared pane context-menu view used by workspace terminal panes, the visible Herd rail pane rows, and the retained nested Sessions pane rows. It exposes focus/open, Zen, split right/down, zoom, directional resize, connection-scoped tab/workspace moves, conditional terminal takeover, the existing pane rename editor, and the existing confirmed close flow.
- Sidebar action dispatch and move choices resolve through the pane's owning connection projection. Takeover is shown only when that connection already has a ready observe-mode terminal controller. Action and close reconciliation now also ignore stale completions after the user switches connections.
- VPS `./scripts/check.sh` and focused `git diff --check` passed. On the Apple Silicon Mac, the final focused Swift build and sidebar action-contract test passed; the preceding complete `SurfaceProjectionTests` and `HerdRailPresentationTests` runs passed 46 tests with 0 failures.
- Full `mac-verify.sh`, packaging, installation, relaunch, and live right-click screenshot proof were not run because the shared dirty tree contains extensive unrelated in-progress work that this scoped change must not package or install.

## 2026-08-05: Sidebar hierarchy creation and keyboard palette UX

- Added right-click action menus to expanded and collapsed herd, workspace, and tab hierarchy rows. The menus dispatch the existing connection/workspace/tab actions and use the same mutation and tab-boundary availability as the visible controls.
- Every workspace `+` path now sends public `workspace.create` without `cwd`, leaving the targeted Herdr runtime's startup directory authoritative. New tabs, splits, and move-to-new-tab actions request a non-empty name before mutation; split naming follows public `pane.split` with public `pane.rename` after identifying the created pane from a fresh projection.
- `Cmd-Shift-P` now mounts the command-palette search field and then focuses it from a view-scoped cancellable SwiftUI task. Existing fuzzy ranking remains live on every query update, and existing local key routing handles arrows, Return, Command-Return, and Escape while the text field owns first responder.
- Red-first focused test commands could not start on the VPS because `swift` is unavailable. Tests were added before production edits for named topology action construction, process placement naming, and hierarchy menu availability. Mac `BessieCore` and `BessieCoreTests` targets compile. `./scripts/check.sh` and focused `git diff --check` pass.
- Full `./scripts/mac-verify.sh` currently stops during production compilation on unrelated concurrent Catppuccin appearance cases that are not handled in existing switches in `BessieSettings.swift`, `HerdRail.swift`, and `ProductSurfaces.swift`. The previous run compiled and ran the suite but later stalled in the long terminal performance probe; its state log does contain the 20-transition pane-switch completion marker. Because the required Mac lane is not green, no package was installed or claimed as verified.

## 2026-08-05: Curated Bessie themes implementation checkpoint

- Added the settled seven-choice selection catalog with six authored concrete app/terminal definitions: Bessie Dark, Bessie Light, and official Catppuccin Latte, Frappé, Macchiato, and Mocha terminal values pinned to `catppuccin/ghostty` commit `5a58926563ddacbde4a12b4a347464c2c6945393`. System resolves only to Bessie Dark/Light. No `GhosttyTheme`, Tokyo Night, Dracula, custom-theme schema, or independent terminal selector was added.
- Theme selection is terminal-first through one coordinator. Existing and warm controllers update transactionally, earlier controllers roll back after a mid-fan-out rejection, app chrome/persistence commit only after terminal success, and future controllers receive the effective concrete theme before presentation. System light/dark changes use the effective terminal-theme fingerprint while keeping the persisted `system` selection. Light themes use Aqua rather than forced Dark Aqua.
- Added the finite native picker, transactional rail/context-menu routes, semantic diff colors, theme-authored cowprint treatment, packaged Catppuccin MIT attribution, the deferred advanced-custom-theme roadmap item, and a same-process six-theme live capture gate with real terminal/controller identity checks and ANSI/input readback.
- Focused Apple Silicon Mac command `xcrun swift test --filter "BessieThemeTests|PersistenceReconnectTests|BessieVisualFoundationTests|HerdRailPresentationTests|SurfaceProjectionTests"`: **98 tests, 0 failures**. Coverage includes exact catalog/order and Catppuccin values, contrast, all ANSI slots, legacy/unknown persistence, first and mid-fan-out rejection, rollback, System fingerprint transitions, fixed-theme OS-change behavior, visible/warm/future propagation, controller identity, override composition, and future-controller rejection state.
- VPS `./scripts/check.sh`: exit 0; runtime lock/compatibility/notice/package, intent parity, UI copy, and static checks passed. Swift remains unavailable on the VPS. Full Mac verification, packaging/install/relaunch, installed executable identity, live captures, and visual inspection remain pending at this checkpoint and are not yet claimed.

## 2026-08-05: Curated themes and UI follow-up installed for testing

- Completed the requested pane-gutter, theme-toggle visibility, single-pane Zen, live fuzzy command-palette filtering, menu-bar popover, and alphabetical workspace/tab presentation follow-ups. Tab move-left/right actions and drag/drop ordering are absent; Herdr's authoritative topology order is not mutated.
- The final full Mac lane was intentionally stopped at Jordan's request after its native suite passed **432 XCTest tests and 21 Swift Testing tests with 0 failures** and the theme design snapshots reported success. The full lane was not restarted or claimed complete.
- Enlarged the wide Bessie menu-bar mark from a constrained 18×18-point drawing to a 24×18-point transparent template canvas with a 23×16-point visible mark. Focused Mac test `MenuBarPresentationTests/testStatusIconIsATransparentMonochromeTemplate` passed with 0 failures.
- Packaged and installed `/Applications/Bessie.app` through the focused rebuild/install path, then relaunched one installed instance. Packaged and installed executable SHA-256 values both equal `9fe767bd5473140427dceff5a12c31dd579a72bb07c3016f3d9caee2bb89be0f`.

## 2026-08-05: Live theme, menu-bar icon, and sidebar acceptance fixes

- Propagated the effective concrete theme through the SwiftUI environment and made semantic chrome colors resolve from that value, fixing stale mounted chrome during same-dark Catppuccin changes without recreating the terminal controller or view. Jordan confirmed live theme switching works in the installed app.
- Replaced the menu-bar image drawing path with a transparent 52×36 bitmap representation whose 26×18-point logical size is set before AppKit installs it as a template image, eliminating the undersized drawing and uncleared backing-pixel path.
- Removed the explicit 2.5-point leading selection stripe beside the active Tab row in the sidebar after Jordan identified it as an unwanted white line.
- Rebuilt, installed, and relaunched `/Applications/Bessie.app`. The final packaged and installed executable SHA-256 values both equal `3fabee1b22b15eb5092f0103ccdcf085d4cda35e111fb8dc4c0baeddfc1a5f6e`; the install script's 17 focused tests passed with 0 failures. Full `mac-verify.sh` was not rerun for this visual follow-up.

## 2026-08-05: Global hierarchy views

- Added All Herds, All Workspaces, and All Tabs options to the top sidebar hierarchy. All Herds opens the existing fleet-wide Herd surface; the two new aggregate surfaces derive their rows from fresh connection-qualified Herdr projections and do not persist shadow topology.
- Global workspace rows open their owning connection/workspace. Global tab rows resolve a focused-or-first live pane inside the connection-qualified tab and use the existing routed-pane path, preserving normal focus and stale-target handling.
- Focused Mac coverage for global route mapping, aggregate labels/counts, duplicate-ID connection scoping, and tab open-target resolution passed. The install path's 17 checks also passed with 0 failures.
- Rebuilt, installed, and relaunched `/Applications/Bessie.app`. Packaged and installed executable SHA-256 values both equal `782f5e6594f6050219a10f86759ae09ceeefa155d951efd9ebb7538be6a587d4`. Full `mac-verify.sh` was not rerun.

## 2026-08-06: Unified in-place workspace scopes

- Reinterpreted All Tabs, All Workspaces, and All Herds as pure workspace scopes rendered by the existing `WorkspaceSurface`. Scope groups retain connection/workspace/tab identity and authoritative layout order; All Herds receives only fleet projections with a current endpoint and connected health.
- Added connection-owned supplemental terminal registries for aggregate herds, exact routed pane targets, connection-routed mutations, ordinary-selection narrowing, and text-only All rows with selected accessibility state.
- Added focused model coverage for scope boundaries, deterministic order, duplicate pane IDs, exact routes, stale-input exclusion, and in-place callback reduction.
- `./scripts/check.sh`: exit 0. Focused changed-file `git diff --check`: exit 0. Swift is unavailable on this VPS, so focused XCTest compilation/execution, UI screenshot inspection, full `mac-verify.sh`, packaging, installation, and relaunch were not run or claimed.

## 2026-08-06: Command palette refactor U1 typed index

- Added the pure `BessieCore` command-palette index, typed semantic state/freshness/provider metadata, stable connection-plus-pane identity, complete sectioned browse ordering, context-aware query tie-breaks, and session MRU. Pane and workspace inputs from disconnected herds are excluded while their retry-capable connection row remains.
- Added red-first Core coverage for browse curation, state-word search, attention/active-connection ranking, cross-herd identity, moved panes, disconnected freshness, MRU bounds, command exclusion, wrap selection, and deterministic duplicate merging. The first Mac compile failed on the intentionally missing index APIs; implementation then made the focused palette suites pass 20 tests with 0 failures.
- Mac `xcrun swift test --filter BessieCoreTests`: **286 XCTest tests executed, 5 isolated-live tests skipped, 0 failures**; the Swift Testing socket suite also passed 4 tests. VPS `./scripts/check.sh` and `git diff --check`: exit 0.
- No terminal controller, Herdr lifecycle, snapshot writer, upstream dependency, plan text, stage/index state, commit, push, PR, publication, deployment, or installed app was changed in U1.

## 2026-08-06: Command palette refactor U2 extraction

- Mechanically moved the palette view, row, and controller into `Sources/BessieApp/BessieCommandPalette.swift`, renamed the controller to `BessieCommandPaletteModel`, and left `KeyboardShortcutCoordinator.swift` with the global shortcut coordinator only. The artboard query seed and snapshot probe moved with the view.
- Mac focused palette command `xcrun swift test --filter "CommandPaletteControllerTests|CommandPaletteTests|CommandPaletteIndexTests"`: **26 tests, 0 failures**. VPS `./scripts/check.sh` and `git diff --check`: exit 0.

## 2026-08-06: Command palette refactor U3-U7 installed test build

- Integrated one shell-owned palette index lifecycle and session MRU across every fresh herd. One openability predicate now gates the shortcut, menu, rail, and preview paths. Disconnected herds retain retry rows, and palette construction does not run on ordinary closed-shell renders.
- Routed pane activation by stable connection-plus-pane identity against the current projection. Moved panes use their current Herdr location; vanished targets stay in the palette for bounded event-driven recovery. Project rows navigate without creating Herdr topology. Pane routes retarget Zen, while destination-changing routes exit it.
- Folded palette keys into the one existing global key-down monitor. The modal policy covers wrap navigation, IME, shell-mutation suppression, pre-focus typing and paste buffering, explicit app/editing pass-throughs, and origin-aware responder restoration. Click and keyboard activation share the same one-dispatch gate.
- Rebuilt the native palette as a top-anchored, sectioned, accessible modal with typed status/provider presentation, dynamic footer capabilities, no-connections/no-results/recovery notices, retry state, and the retained deterministic artboard-07 `sch` preview contract. No terminal output is indexed, and palette open/close preserves each pane's existing `GhosttyTerminal` controller, native view, in-memory session, and Herdr stream.
- Red-first regressions covered the pure index/order contract, moved and vanished targets, project navigation, Zen routing, modality, focus, accessibility copy/geometry, presentation identity, very-fast pre-focus input, and hidden terminal lifecycle. A Retina-dependent image fixture was replaced with a pixel-deterministic 2×2 bitmap; production image decoding was unchanged.
- Oracle challenged the architecture before implementation, identified presentation-identity and pre-focus input races during review, and approved the final palette plus attach-once/park terminal-lifecycle diff after both were repaired test-first.
- Final VPS `./scripts/check.sh` and `git diff --check`: exit 0. The final full Mac attempt compiled and packaged the current app, passed **473 XCTest cases and 21 Swift Testing cases with 0 failures**, and passed every reported terminal/resource metric except the unchanged 1 MiB output maximum: run suffix `66447` measured 269.458 ms against the existing 250 ms budget. Printable echo p95 was 4.459 ms, frame receive-to-feed p95 0.023 ms, pane switching 42.886 ms, sustained input 22.299 ms, five-minute CPU 6.713%, idle CPU 0%, and RSS 195.516 MB. The full verifier therefore exited 1 before its matrix and install phases; no full-lane pass is claimed and no budget or probe was weakened.
- Jordan accepted the current throughput result for hands-on palette testing and requested installation without further benchmark work. The exact current packaged app was transactionally installed and relaunched at `/Applications/Bessie.app`; strict deep code-sign verification and byte comparison passed. Packaged and installed `BessieApp` SHA-256 values both equal `3972a2f96fb2df40f8b25bee1378130b9c4efa2c18830ba4572d4e83d8acf763`, with installed owner PID `80972`. Herdr servers and pane processes were not stopped.
- The authoritative refactor plan remains byte-unchanged at SHA-256 `934f492f45f57f26995a9d51ab6e49e97dc434ad839b142312274ccab0a5f6d4`. No commit, push, PR, publication, deployment, upstream Herdr/libghostty change, or unrelated plan edit was made.

## 2026-08-06: Command palette Project activation follow-up

- Jordan's installed-build acceptance changed the post-plan interaction contract: a Project result now invokes the existing `ProjectsViewModel.requestOpen` flow instead of navigating to its editor. Projects with commands still present the canonical launch-review sheet before any Herdr mutation; the explicit **Manage projects** command remains the only palette route to the Projects catalog.
- Added focused controller coverage proving a Project entity and the **Manage projects** command remain distinct route intents. The pre-change route-intent test passed on the Mac; Jordan's hands-on installed-app result supplied the failing integration evidence for the old route executor.
- VPS `./scripts/check.sh` and `git diff --check` passed. Focused Mac command-palette and Project-launch suites passed **53 tests with 0 failures**; the clean release package/install path's additional focused suite passed **17 tests with 0 failures**.
- The replacement `dist/Bessie.app` was transactionally installed at `/Applications/Bessie.app`, strict deep code-sign and byte-comparison checks passed, and the installed app relaunched as the sole exact-path owner PID `86013`. Packaged and installed `BessieApp` SHA-256 values both equal `27dab917624c7a0066841160243a0e9f7d6522d0da33ce49d02721ab29164ffe`; two Herdr server processes remained running.
- The authoritative refactor plan remains byte-unchanged at SHA-256 `934f492f45f57f26995a9d51ab6e49e97dc434ad839b142312274ccab0a5f6d4`. No commit, push, PR, publication, deployment, or upstream Herdr/libghostty change was made.

## 2026-08-06: BES-41 standard sidebar pane filtering installed

- Replaced the provisional workspace-scope terminal aggregation path with one ordinary rail projection. Individual tabs, All Tabs, individual workspaces, and All Workspaces now filter connection/workspace/tab-qualified pane rows while preserving their existing stable order and exact `RoutedPaneTarget` identities.
- Scope reconciliation retains a selected pane that remains visible, then falls back to a focused matching pane or the first matching row. All scope is anchored to the active Herdr connection. Selecting All changes only local rail scope/selection: it does not change the center destination, exit Zen, invoke Herdr navigation, or call terminal registry/prewarm APIs.
- Removed `WorkspaceScopeProjection`, `WorkspaceScopeGroup`, `AggregatePaneGroup`, the aggregate `ScrollView`, supplemental aggregate registries/actions, and every multi-`ProductPaneLayout` scope presentation. `WorkspaceSurface` now always renders only the ordinary selected-tab layout. Individual workspace/tab option rows expose selected styling only when no All scope owns that hierarchy level.
- BES-41 implementation/test files: `Sources/BessieCore/HerdList.swift`, `Sources/BessieApp/ProductSurfaces.swift`, `Sources/BessieApp/WorkspaceTitlebarChrome.swift`, and `Tests/BessieAppModelTests/SurfaceProjectionTests.swift`. This report is the fifth changed file. The pre-existing dirty hunks in `ProductSurfaces.swift` and `SurfaceProjectionTests.swift` retain unrelated command-palette and terminal-lifecycle work.
- Focused VPS `git diff --check` over those four source/test files: exit 0. Static search found no remaining `WorkspaceScopeProjection`, `WorkspaceScopeGroup`, `AggregatePaneGroup`, `scopeGroups`, `registryForConnection`, `performRoutedAction`, or `routedPaneID` references under `Sources` or `Tests`.
- Synced only the four BES-41 source/test files to `/Users/jordanstella/GitHub/bessie` with `rsync -az --relative` and no `--delete`; the verified mirror marker remained `source=/home/hermes/code/bessie`.
- Focused Mac command `xcrun swift test --filter "SurfaceProjectionTests/testWorkspaceScopesFilterOrdinaryPaneRowsWithExactRoutesAndOrder|SurfaceProjectionTests/testWorkspaceScopeSelectionRetainsVisiblePaneThenUsesFocusedOrFirstFallback|PickerPresentationTests/testHierarchyAllOptionsSelectWorkspaceScopesInPlace|PickerPresentationTests/testGlobalHierarchyPresentationShowsAggregateLabelsAndPaneCount"`: app and test targets compiled in 11.88 seconds; **4 tests executed with 0 failures**.
- `./scripts/package-app.sh` completed the release build in 51.71 seconds, packaged `dist/Bessie.app`, and passed its strict code-sign checks. The package was transactionally installed at `/Applications/Bessie.app` and relaunched as the sole exact-path owner PID `24051`.
- Packaged and installed `BessieApp` SHA-256 values both equal `0e635b679462852114cd88cf7bbea4bd6e0d1a0efbf07d8929aa8ad0ced9973a`; a later `cmp`, hash, and exact-owner postcheck also passed.
- Per BES-41 scope, no screenshot, broad suite, full `check.sh`, or `mac-verify.sh` run was performed. Jordan will do hands-on UI acceptance. The checkout and installed package still include the substantial unrelated pre-existing command-palette and terminal-theme work; none was reset, stashed, cleaned, committed, pushed, or published.

## 2026-08-06: BES-42 direct local and remote Project launch installed

- Enter and click still share the command palette's one-dispatch activation path, but a Project route now starts the existing `ProjectsViewModel` materialization flow immediately. It does not present the command review, navigate to Manage Projects, or conflate the separate **Manage projects** and **Create project** commands.
- Local recipes retain local folder-existence validation. SSH recipes retain structural path and recipe validation but do not resolve or check the remote path through the Mac filesystem; the existing materializer sends that path through the active SSH-forwarded Herdr socket using the same public workspace/tab/pane/input APIs and Herdr-owned live objects as a local launch.
- Preflight failures now identify stale projects, busy launch state, incompatible/disconnected herds, and local-versus-remote recipe problems. Materialization failures present owner-specific recovery text with the connection name and partial-workspace guidance rather than redirecting to Project management.
- BES-42 implementation/test files: `Sources/BessieApp/BessieApp.swift`, `Sources/BessieApp/ProductSurfaces.swift`, `Sources/BessieApp/ProjectLaunchCoordinator.swift`, `Sources/BessieApp/ProjectsSurface.swift`, `Sources/BessieApp/ProjectsViewModel.swift`, `Sources/BessieCore/BessieProjectMaterialization.swift`, `Sources/BessieCore/BessieProjects.swift`, `Sources/BessieCore/KeyboardShortcuts.swift`, `Tests/BessieAppModelTests/CommandPaletteControllerTests.swift`, `Tests/BessieAppModelTests/ProjectsViewModelTests.swift`, and `Tests/BessieCoreTests/BessieProjectMaterializationTests.swift`. This report is the twelfth changed file. Existing dirty hunks and untracked files from the command-palette foundation, terminal-theme work, and BES-41 were preserved.
- The first focused Mac compile failed as expected because the test-first `launchImmediately` contract did not exist. After implementation, the narrow seven-case BES-42 selection passed, followed by `xcrun swift test --filter "CommandPaletteControllerTests|ProjectsViewModelTests|BessieProjectMaterializationTests|BessieProjectTests|KeyboardShortcutTests"`: **106 tests executed with 0 failures**.
- Intentionally mirrored the complete VPS working tree to `/Users/jordanstella/GitHub/bessie` using `rsync -az` with the repository's standard build/runtime exclusions and no `--delete`. The `.bessie-mirror` marker remained `source=/home/hermes/code/bessie`, and sampled source/test SHA-256 values matched across hosts.
- A clean `./scripts/package-app.sh` release build completed in 56.25 seconds and passed strict deep code-sign verification. The package was transactionally installed with a restorable backup at `/Applications/Bessie.app`; executable, bundled Herdr, and license byte comparisons passed. The installed app stabilized after relaunch as the sole exact-path owner PID `25806` in a five-second postcheck.
- Packaged and installed `BessieApp` SHA-256 values both equal `243daa92e72ef70337a6b93a5ee4fbc0c464f707f9f4363a673c3b0a5b5d4c94`. Per BES-42 scope, no screenshot, full `check.sh`, full `mac-verify.sh`, or live remote Project mutation was run; Jordan will perform hands-on UI acceptance. No check was weakened and no reset, stash, clean, commit, push, publication, PR, worktree, or upstream change was made.

## 2026-08-06: BES-42 remote Project acceptance correction

- Jordan's hands-on result showed that direct palette dispatch worked, but Project `DD6BC3DF-6F86-4983-A149-F163877CD729` created only bootstrap workspace `w2X` on Hermes VPS and stopped at `verifying creation`. Its schema-v2 recipe contained the Mac-only cwd `/Users/jordanstella/Desktop/Hermes/workstreams/catapult`; Bessie sent that unqualified path to the selected SSH Herdr connection, Herdr fell back to `/home/hermes`, and Bessie performed full cwd verification before tab naming, pane creation/labels, and command submission.
- Project schema v3 now pins every recipe to a `targetConnectionID` and defines folder paths in that target host's filesystem namespace. Captures and duplicates preserve the target. Transactional v1/v2 migration retains exact backups and conservatively assigns legacy unqualified paths to `local-bessie`; Bessie does not guess a Mac-to-remote path mapping.
- Project launch state now tracks every connected fleet target instead of assuming the active herd. Palette launch routes to the recipe's configured target, carries that target's current Herdr connection/snapshot and SSH file access, presents remote progress even when another herd is active, and hands the completed or partial workspace back to its owning connection. The editor exposes the target herd and accepts an absolute target-host path for SSH recipes.
- Before any Herdr mutation, SSH launches resolve each recipe folder through the configured remote SSH file client and require the target-host path to exist as a directory. Remote cwd verification no longer resolves target paths through the Mac filesystem. Missing/disconnected targets and unavailable remote folders produce target-specific recovery text without redirecting to Project management.
- Bootstrap verification now establishes only the authoritative workspace/tab/pane identities returned by public Herdr APIs. Bessie then applies all intended tab names, tabs, pane splits, and pane labels; only after that does it verify authoritative target-host cwd, labels, parents, and layout. Startup commands remain blocked until topology verification succeeds, then use the existing ordered public Herdr input path, followed by final topology verification.
- Focused Mac command `xcrun swift test --filter "BessieProjectTests|BessieProjectCaptureTests|BessieProjectMaterializationTests|ProjectsViewModelTests|CommandPaletteControllerTests"`: **107 tests executed with 0 failures**. This includes regressions for the Mac-path remote preflight failure before bootstrap mutation, client/target symlink namespace separation, fallback cwd after acknowledged workspace creation without premature topology abort, complete topology before command submission, configured remote routing while local is active, v2-to-v3 migration, partial-failure evidence, direct Enter/click dispatch, and separate Manage/Create commands. VPS `git diff --check` also passed.
- No live remote Project was launched during this correction, and workspace `w2X` was not read, renamed, closed, mutated, or cleaned. The legacy Catapult recipe cannot be corrected safely by inference or by mutating Jordan's application data: after migration, Jordan must explicitly select `hermes-vps` and set `/home/hermes/.hermes/workspace/shared/workstreams/catapult`, then rerun hands-on remote acceptance.
- Mirrored the complete VPS tree to `/Users/jordanstella/GitHub/bessie` with the standard exclusions and no `--delete`; the mirror marker remained `source=/home/hermes/code/bessie`. A clean ad-hoc-signed production package completed in 58.39 seconds and passed strict deep code-sign verification. The package was transactionally installed with a restorable backup, byte-compared for the app executable, bundled Herdr, and Herdr license, and relaunched as the sole exact installed-path owner PID `29323`; the same owner remained alive after a five-second stabilization check.
- Packaged and installed `BessieApp` SHA-256 values both equal `17e7d7c25f9b023e4c7e89be205e8998e6838a4a669c0f9c36b9111732ae63b2`. No screenshot, full `check.sh`, full `mac-verify.sh`, live remote Project mutation, commit, push, PR, publication, worktree, reset, stash, clean, or upstream change was performed.

## 2026-08-06: BES-42 on-demand target readiness acceptance correction

- Jordan's next hands-on run proved direct palette dispatch reached Project target selection, but every migrated Project stopped with **“Connect This Mac, this Project's target herd, then launch it again.”** Read-only inspection of `~/Library/Application Support/Bessie` found 18 current schema-v3 recipes, each backed by a retained schema-v2 migration file. All 18 target `local-bessie`; all 18 use `/Users/jordanstella/...` Mac folder paths; none uses a VPS path or currently targets `hermes-vps`.
- The same read-only inspection found `connections.json` configuring **This Mac** (`local-bessie`) with `connect_at_launch: false`, **Hermes VPS** (`hermes-vps`) with `connect_at_launch: true`, and Hermes selected. `runtime-selection.json` is absent, so the existing default bundled runtime selection applies. No recipe, connection, preference, application-data file, or Herdr workspace was mutated during diagnosis; workspace `w2X` remained untouched.
- Root cause: `ConnectionFleetViewModel.projectLaunchTargets` intentionally contains only connected, compatible targets with authoritative snapshots. `ProjectsViewModel.launchImmediately` incorrectly treated absence from that ready-only map as a manual-connect failure, so it never asked the already configured fleet to start the on-demand local herd. This bypassed `ConnectionViewModel.start`, including its normal bundled/system/custom runtime resolution, runtime integrity and compatibility checks, and public Herdr connection lifecycle.
- Direct launch now accepts one request, asks the fleet to start the configured target through its existing idempotent lifecycle, waits up to 20 seconds for a compatible materialization connection and authoritative snapshot, then continues the unchanged target-aware materialization flow. Already-ready targets bypass startup. Already-connecting targets are joined without another start. Repeated Enter/click for the same opening Project is accepted as the same request without another readiness task or materialization. The bounded wait leaves a timed-out connection attempt running and does not install, replace, stop, or shadow Herdr.
- Missing configurations, runtime/startup failure, unavailable connections, incompatibility, and timeout now produce distinct actionable failures in the normal global action alert. They do not redirect to Manage Projects. Local path checks, schema-v3 target routing, remote SSH path preflight, materialization serialization, authoritative topology verification, and partial-workspace evidence remain in place.
- This acceptance correction changed only `Sources/BessieApp/BessieApp.swift`, `Sources/BessieApp/ProjectLaunchCoordinator.swift`, `Sources/BessieApp/ProjectsSurface.swift`, `Sources/BessieApp/ProjectsViewModel.swift`, `Tests/BessieAppModelTests/ProjectsViewModelTests.swift`, `Tests/BessieAppModelTests/SurfaceProjectionTests.swift`, and this report. All pre-existing dirty and untracked command-palette, theme, BES-41, and earlier BES-42 work was preserved.
- Focused Mac command `xcrun swift test --filter "BessieProjectTests|BessieProjectCaptureTests|BessieProjectMaterializationTests|ProjectsViewModelTests|CommandPaletteControllerTests|SurfaceProjectionTests/testProjectLaunchReadinessStartsConfiguredOnDemandHerdOnlyOnce"`: **113 tests executed with 0 failures**. Coverage includes configured on-demand startup then materialization, already-connected bypass, concurrent/repeated activation deduplication, local folder validation before startup, startup failure, unavailable runtime, timeout, incompatibility, genuinely missing target, prior remote path/cwd and partial-bootstrap regressions, direct Enter/click dispatch, and separate Manage/Create commands. `git diff --check` passed before packaging.
- Mirrored the complete VPS tree to `/Users/jordanstella/GitHub/bessie` with the standard exclusions and no `--delete`. A clean ad-hoc-signed `./scripts/package-app.sh` production build completed in 60.84 seconds and passed strict deep code-sign verification. The package was transactionally installed with a restorable backup; executable, bundled Herdr, and Herdr license byte comparisons passed. The installed app relaunched as the sole exact-path owner PID `32495`, which remained the sole owner after a five-second stabilization check.
- Packaged and installed `BessieApp` SHA-256 values both equal `fba406c3485adf06a17aebf1ddd7cd4cb9a6bda0d9fb065ae22d918deeb0470c`. No screenshot, full `check.sh`, full `mac-verify.sh`, live Project launch, commit, push, PR, publication, worktree, reset, stash, clean, or upstream change was performed. Direct on-demand launch still requires Jordan's hands-on acceptance in the installed build.

## 2026-08-07: Remote-only herds, Project targets, BES-43, and audited 18-Project migration installed

- Implemented the approved remote-only invariant end to end: connection definitions persist `enabled`; normalization always retains at least one enabled selected herd; disabling or removing the final enabled herd is rejected before memory, disk, selection/default, or fleet mutation; disabled herds remain configured but do not start, route, project health, or appear launch-ready. Start-at-launch remains independent, disabling releases only Bessie-owned client resources, and onboarding/startup no longer requires an enabled local herd.
- Project create, edit, capture, duplicate, palette launch, and recovery now use an explicit enabled selected/default target rather than hard-coding `local-bessie`. Direct palette activation retains one-dispatch launch deduplication, target readiness, schema-v3 host namespaces, remote canonical-path preflight, ordered public-Herdr materialization, and partial-failure evidence. Read-only `connection.context` exposes normalized configured/enabled/selected/default/live state without mutation or sensitive fields.
- Completed BES-43 by removing connection lifecycle/health content and its divider from the pane-status menu-bar presentation while retaining fresh pane/agent status. The installed read-only context after migration reports This Mac disabled/disconnected and Hermes VPS enabled, selected, default, and connected.
- Product implementation paths for this plan are `Sources/BessieCore/{AgentIntentExecutor,AgentIntentRegistry,BessieConnections,BessieProjectCapture,BessieProjectMaterialization,BessieProjectStore,BessieProjects,HerdList,SSHRemoteFileClient}.swift`, `Sources/BessieApp/{AppIntentServer,BessieApp,BessieMenuBarController,BessieMenuBarPopover,BessieSettings,HerdPicker,IntentActionDispatcher,OnboardingView,ProductSurfaces,ProjectEditorView,ProjectLaunchCoordinator,ProjectsSurface,ProjectsViewModel}.swift`, `README.md`, and `.agents/skills/operating-bessie/SKILL.md`. Focused coverage is in the corresponding `Tests/BessieCoreTests` and `Tests/BessieAppModelTests` connection, fleet, intent, menu-bar, Project, materialization, palette, picker, Settings, and surface suites. Existing dirty command-palette, theme, brand-chrome, and BES-41 hunks remain preserved.
- Added the generic checked-in `BessieMigrationTool` product in `Package.swift`, with `Sources/BessieCore/BessieProjectTargetMigration.swift`, `Sources/BessieMigrationTool/main.swift`, `Tests/BessieCoreTests/BessieProjectTargetMigrationTests.swift`, and `Tests/BessieMigrationToolTests/BessieMigrationToolTests.swift`. It owns explicit-manifest preflight/apply/resume/rollback/audit/status, exact source/result hashes, metadata-preserving backup, durable journal phases, connection-last mutation, bounded operation-owned SSH masters, exact short control paths, active startup markers, and explicit resumable pre-journal evidence recovery. It contains no Jordan-specific mapping.
- Focused Mac product verification passed **215 tests with 0 failures**. The migration/startup characterization set passed **24 tests with 0 failures**. After the real preflight exposed an overlong Unix socket path, the final migration path/recovery suites passed **33 tests with 0 failures**, including the 18-Project fixture, interruption/resume/rollback, exact journal path spelling, OpenSSH socket-suffix headroom, nonrecursive late-artifact preservation, and pre-journal recovery idempotency. Final `BessieMigrationTool` and `BessieApp` release builds passed; `git diff --check` passed; no check was weakened.
- The first live preflight failed before journal/backup publication because the operation-directory SSH ControlPath exceeded macOS's Unix socket limit. No Project or connection bytes changed. The failed owner/marker evidence was archived by the reviewed one-time exact operator after a lock-contention fail-closed check. Its terminal report is `~/Library/Application Support/Bessie/Migrations/20260807T014645Z-72616101-7E4F-4E96-A483-3F020E009419/legacy-prejournal-recovery/recovery.json` (SHA-256 `004b256c90d4c10bc8c2d2bddfc0a03148904815c3bac42be4c64172c16e16cd`); the exact executed operator SHA-256 is `202d15be47eaa14ce9357022176826afcb16d6ebb3f2d679fe12f13e3bd9a359`. The earlier failed operator is retained separately rather than overwritten.
- The uncommitted explicit manifest is `~/Library/Application Support/Bessie/Migrations/20260807T014645Z-72616101-7E4F-4E96-A483-3F020E009419/manifest.json` (SHA-256 `3e032cba9e3f284358200ade227b856c2f6fabfa8db7995ed55d43c33d59499a`). Independent `ssh -n` validation proved all 18 distinct destinations canonical, existing, non-symlink directories; retained evidence is `remote-validation-18-targets.json` (SHA-256 `c6b17d21566d7b99bf281a93371315711572d3df8f008717564265b56c0cec53`). No basename-only or generic Mac-to-VPS inference was used.
- The exact verified candidate was installed transactionally while Bessie was stopped. Strict deep signing, bundled Herdr `0.8.0`/arm64 identity, executable/runtime/license byte comparisons, and unchanged pre-migration data hashes passed. The retained prior-app backup is `/tmp/Bessie.app.pre-remote-only-final-20260807T024558Z-82910`. Packaged and installed `BessieApp` SHA-256 values both equal `d03eaeca939fbf04f4398fddf465518d40037c52e404cde784bcafb542609aa9`.
- Live preflight published a complete 18-Project backup at `~/Library/Application Support/Bessie/Migrations/20260807T014645Z-72616101-7E4F-4E96-A483-3F020E009419/backup`. Apply completed all 18 prepared Project hashes before changing connections. Audit and a second status pass reached `readyForRelaunch` with outcome `migrated`, closed both owned SSH masters, removed the active marker, and recorded `journal.json` SHA-256 `47e8f5d1f0fba71aa66615ffe7b6bfc27b2fa5ec702fb3f2fc0d03286a2c7d4f`.
- Independent postflight proved all 18 current schema-v3 recipes target `hermes-vps` at their exact manifest paths while preserving recipe IDs, folder IDs, topology, labels, and commands. `local-bessie.enabled == false`; `hermes-vps.enabled == true`; Hermes remains connect-at-launch; selected and default Project target are both `hermes-vps`; every live result hash matches the journal. Durable independent evidence is `independent-final-audit.json` (SHA-256 `7b3018d3d4f3d5eb739d1b1750682df7ec085eec12997f90cef26ef37fa43e51`).
- Relaunched the exact installed app as sole owner PID `85932`. Read-only `connection.context` reports Hermes connected and This Mac disabled/disconnected. The pre-existing Herdr server PID `35163` remained running; Bessie did not stop Herdr or pane processes. No automated live Project launch occurred, and partial workspace `w2X` was not read, renamed, closed, mutated, or cleaned. Jordan owns final hands-on BES-42/BES-43 acceptance.
- Jordan then opened a migrated Project from the installed command palette and confirmed direct remote launch worked correctly. This supplies the deferred hands-on BES-42 remote-launch acceptance; the resulting Jordan-owned Herdr workspace was not inspected or mutated by automation.
- No reset, stash, clean, stage, commit, push, PR, publication, deployment, worktree, upstream Herdr/libghostty edit, live-workspace cleanup, or check weakening occurred.

## 2026-08-07: BES-45 pinned and snoozed panes installed

- Added a Bessie-owned exact-incarnation (`connection_id + pane_id + terminal_id`) preference ledger with monotonic revisions, tagged preset snoozes, additive bounded persistence, immutable load blockers, retryable newest-state saves, exclusive presentation leases, file-mode hardening, launch normalization, and supervised nearest-deadline expiry. Herdr remains the sole owner and source of truth for every live pane, terminal, process, and agent.
- Added exactly-once routed rail placement with `Pinned > Snoozed > ordinary`, Pinned before semantic groups, independently collapsible Shells and Snoozed sections, snoozed-excluding attention/navigation, pinned routed-order traversal, expanded/collapsed summaries, native shared context/overflow menus, all seven presets, wake timing, relocation focus, accessibility labels/actions, and explicit-action announcements. Every terminal surface remains `GhosttyTerminal`.
- Added trustworthy local-use wake hooks for validated Bessie routes and controller-bound terminal mouse-down/raw input/special-key/paste/wheel forwarding. Passive snapshots, output, semantic changes, responder restoration, and remote activity do not wake panes. Snoozed exact incarnations are removed from Needs-you/status/Zen routing and synchronously cancel Bessie's cancellable notification stage while planner history continues advancing.
- Registered `pane.presentation.list`, `pane.pin`, `pane.unpin`, `pane.snooze`, and `pane.wake` across the shared intent registry, CLI, MCP, and operating skill. Mutations require fresh exact incarnation plus expected revision, use bounded request-ID coalescing/replay, return structured current state on conflicts, and share the same main-actor mutation port as SwiftUI.
- Focused Mac verification compiled the final implementation and passed the selected BES-45 suites (**52 XCTest cases, 0 failures**) plus all **8 MCP adapter tests**. A subsequent clean native package run passed the entire **567-case XCTest suite** and all **21 Swift Testing CLI/MCP/socket tests** before its unrelated live 1 MiB terminal-performance probe timed out. `./scripts/check.sh` and `git diff --check` both exited 0; no check or budget was weakened.
- Jordan explicitly changed the validation policy after the broad verifier proved slow and flaky: `./scripts/mac-verify.sh` must not run unless Jordan asks for that exact script. `AGENTS.md` now records focused native tests, direct behavior checks, packaging/install identity, relaunch, and screenshots as the default. The last broad run was terminated cleanly; its exact app/server processes and `/tmp/bessie-mac-verify.lock` were verified absent.
- The current ad-hoc-signed package passed strict deep signing and was transactionally installed at `/Applications/Bessie.app`. Packaged and installed `BessieApp` SHA-256 values both equal `2d4a398c77f7caf59b9c47ae119e903baef6312c722ca9ea31b98eb4e164a997`; byte comparison passed. The installed executable relaunched as exact owner PID `75765` (later normal relaunch PID `76751` after a focused isolated fixture attempt).
- Installed screenshot `/Users/jordanstella/GitHub/bessie/dist/BES-45-installed.png` is a valid 1249×923 PNG. Visual inspection found intact native window/sidebar/terminal layout with no clipping, blank surface, or corruption. The current real user state contained no pinned or snoozed preference, so this screenshot does not claim visual acceptance of populated Pinned/Snoozed sections or the preset menu. Pure projection/menu/accessibility coverage and live CLI/MCP mutation passed; populated-section hands-on visual acceptance remains with Jordan.
- No commit, push, PR, publication, reset, stash, upstream Herdr/libghostty edit, or real Herdr pane/process mutation was performed. The reviewed plan modification was preserved.

## 2026-08-07: Sidebar hover and terminal-input crash fix installed

- Removed the accidental hover-only ellipsis overlay from expanded Herd rail pane rows. The existing right-click pane action menu and snoozed-row hover opacity remain unchanged.
- Diagnosed two installed-app crash reports from 2026-08-06 22:24. Both terminated with `SIGTRAP` after libghostty's `io` thread invoked the local-pane-use callback and reached main-actor-isolated `ConnectionFleetViewModel.topologyConnections`. `PaneLocalUseCallback` now dispatches background delivery to the main queue, while each installed callback captures its exact connection/pane/terminal incarnation so a queued event cannot wake a replacement pane with a reused pane ID.
- Red-first focused Mac verification first failed because the callback seam was private. After the fix, the final focused selection passed **6 tests with 0 failures**, covering background-to-main delivery, reused-pane incarnation retention, terminal local-use ordering, and Herd rail presentation. VPS `./scripts/check.sh` and focused `git diff --check` passed. Independent focused review approved the final fix. `./scripts/mac-verify.sh` was not run.
- Packaged the current Mac mirror with strict deep code-sign verification and transactionally installed `/Applications/Bessie.app`. Packaged and installed `BessieApp` SHA-256 values both equal `422396e48a4689c8f8d1aa7570b883f0be03e894d9f0ef2bd40e61d71168c8ab`. The installed app relaunched as sole exact-path owner PID `78824`; the pre-existing bundled Herdr server remained running.
- Installed-app screenshot `/Users/jordanstella/GitHub/bessie/dist/bessie-crash-hover-fix-installed.png` is a valid 1249×923 PNG. Inspection found an intact native window/sidebar/terminal with no blank or corrupt surface and no ellipsis overlay on the visible agent row. No commit, push, PR, publication, upstream edit, or Herdr pane/process mutation was performed.

## 2026-08-07: Full-screen floating-shell outer inset fixed

- Root cause: the shell's full-screen state started as `false` and changed only when the mounted shell received AppKit enter/exit notifications. If macOS entered or restored native full screen before the connected product shell was created, that past transition was missed permanently and the shell retained its intentional windowed-mode zero top inset. The fix recovers current state from the identified main `NSWindow` when the shell appears and scopes later transition notifications to that same main-window policy; the existing density-owned full-screen inset, windowed titlebar behavior, terminal sizing, and Zen geometry are unchanged.
- Regression: `testMainWindowFullScreenStateCanBeRecoveredAfterMissingTheTransitionNotification` was added to `MenuBarPresentationTests`. Before implementation, the focused test failed to compile because no current-state classifier existed. After implementation, `xcrun swift test --filter 'BessieVisualFoundationTests|MenuBarPresentationTests'` passed **39 tests with 0 failures** on `jordan-macbook`.
- VPS verification: `./scripts/check.sh` exited 0 with runtime-lock, intent-parity, UI-copy, and static checks passing; `git diff --check` exited 0. `./scripts/mac-verify.sh` was not invoked.
- Native package/install: the exact VPS dirty tree was copied to isolated Mac scratch `/tmp/bessie-fullscreen-baseline-1786145361` without modifying the dirty Mac mirror, then `./scripts/package-app.sh` and `codesign --verify --deep --strict dist/Bessie.app` passed. The package was transactionally installed at `/Applications/Bessie.app`; packaged and installed `BessieApp` SHA-256 values both equal `7279e30649c3fc78f38f4e8d581bc6ac6ddf7e92e1b5237b73af28729d741de4`, and executable/runtime byte comparisons passed.
- Installed native full-screen evidence: `/Users/jordanstella/GitHub/bessie/dist/Bessie-fullscreen-layout-fixed.png`, **3440×1440**, SHA-256 `71feefa59d6f02652b492fcfc13bc35fe3fa1c71c11d6caeb1078d9658d0b32e`. Inspection measured visually balanced approximately 10 px top/bottom/left/right outer gaps with no clipping or overlap. Jordan independently confirmed, “It's fixed!” After capture, the isolated fixture process was stopped and the installed app was relaunched normally as the sole exact-path owner PID `42549`.
- Protected pre-existing edits in `Sources/BessieCore/HerdrAPI.swift`, `Tests/BessieCoreTests/BootstrapTests.swift`, `scripts/Info.plist.in`, and `scripts/check.sh` retained their pre-work SHA-256 values. This entry was appended without rewriting the report's existing changes. No commit, push, PR, publication, worktree, reset, stash, clean, upstream Herdr/libghostty change, or terminal ownership/input change was performed.

## 2026-08-08: BES-2 notification lifecycle and package identity implementation

- Notification planning is now keyed by exact pane/terminal incarnation and request IDs include the terminal ID. A replacement terminal seeds its own history; blocked and settled transitions retain the existing no-retroactive-delivery behavior, and `done ↔ idle` churn remains one Settled condition rather than duplicate delivery.
- The coordinator now tracks condition, token, frozen target, and presentation fingerprint per incarnation. Every reconcile invalidates queued, pending, and delivered requests when the pane works again, becomes active or snoozed, changes condition/incarnation/target/presentation, disappears, or its configured connection is removed. Topology moves cancel stale routes without manufacturing a replacement transition. A coordinator-level policy pass invalidates disallowed tracked requests even when a configured connection has no current source, while retaining planner history for reconnect. Post-`add` success/failure handling is token-scoped: late superseded failures are ignored and a current success clears the prior delivery error.
- The existing app-lifetime ownership split remains: the product shell owns the active connection while the main window is visible, and `BessieAppDelegate` owns all available fleet sources after close. A focused seam verifies the same coordinator carries history across that handoff without duplicate delivery.
- Packaging now uses a closed `production|verify` variant. `production` resolves only to `dev.bessie.app` and refuses ad-hoc signing; `verify` resolves only to `dev.bessie.app.verify`. The plist template contains no live identity. `mac-verify.sh` selects verify identity for `BESSIE_SKIP_INSTALL=1`, derives activation from that identity, and requires stable signing for its install path. Both production installers explicitly select production and reject ad-hoc signing; the documented install path now uses the stable-signing dogfood installer.
- Proof-first Mac command `xcrun swift test --filter 'SettingsAndNotificationsTests/testBlockedNotificationIsCancelledWhenPaneReturnsToWorkingBeforeCommit|SurfaceProjectionTests/testNotificationPlannerSeedsReplacementTerminalBeforeEmittingTransitions'` failed on checkpoint `0da336d`: the queued blocked notification still delivered, and the replacement terminal inherited the old state. After implementation, final focused command `xcrun swift test --filter 'SettingsAndNotificationsTests|SurfaceProjectionTests/testNotification'` passed **37 tests with 0 failures**, including queued, committed, and in-flight invalidation; settled semantics; exact routing; window-close takeover; transient reconnect retention; definitive connection cleanup; permission failure; and terminal-incarnation replacement.
- Follow-up proof-first command `xcrun swift test --filter 'SettingsAndNotificationsTests/testDisconnected|SettingsAndNotificationsTests/testQueuedNotificationIsInvalidatedWhenPaneMoves|SettingsAndNotificationsTests/testCommittedNotificationIsInvalidatedWhenPaneMoves|SettingsAndNotificationsTests/testSupersededLateAddFailure|SettingsAndNotificationsTests/testCurrentAddSuccessClearsEarlierDeliveryError'` in fresh isolated Mac scratch `/tmp/bessie-verify-bes2-followup-3856753` first executed **6 tests with 8 assertion failures**, characterizing disconnected policy, stale target, stale async error, and uncleared-current-success defects. After the fixes, the same selection passed **6 tests with 0 failures**. Oracle then identified a missing active-window trigger for connection-label-only presentation changes; the shell signature now includes the label, with added identity/label, selective-policy-history, and inverse stale-success race coverage. Final focused command `xcrun swift test --filter 'SettingsAndNotificationsTests|SurfaceProjectionTests/testNotification'` passed **46 tests with 0 failures**.
- Final VPS `./scripts/check.sh` exited 0. Its executable queries assert production/verify derivation and the selected configurations of `mac-verify.sh`, `dogfood-install-signed.sh`, and `rebuild-install-shortcuts.sh`; unsupported variants and ad-hoc production are rejected. `bash -n scripts/package-app.sh scripts/mac-verify.sh scripts/dogfood-install-signed.sh scripts/rebuild-install-shortcuts.sh scripts/check.sh` and `git diff --check` both exited 0.
- In `/tmp/bessie-verify-bes2-followup-3856753`, `BESSIE_PACKAGE_VARIANT=verify BESSIE_CODESIGN_IDENTITY=- ./scripts/package-app.sh` completed a real release package. The executable identity query and generated plist both reported `dev.bessie.app.verify`, and `codesign --verify --deep --strict dist/Bessie.app` passed. `mac-verify.sh` now derives activation identity from the package query and rejects a generated-plist mismatch before any activation.
- `./scripts/mac-verify.sh` was not invoked. No app was installed or relaunched, and no visible banner, Notification Center history, System Settings association, `ncprefs`, Developer ID keychain usability, notarization, or production signing acceptance is claimed. Those operator-only gates remain explicitly unresolved for Hermes.
- No stage, commit, push, PR, deployment, publication, reset, stash, clean, account/credential change, upstream Herdr/libghostty edit, or Herdr-owned runtime mutation was performed.
