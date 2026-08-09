# Bessie iOS — remote control plane (ce-plan)

**Date:** 2026-08-03  
**Updated:** 2026-08-08 — reconciled with the settled 15-screen iOS atlas; locked as **first post–Mac-V1 ship** (not in Mac V1)  
**Status:** Implementation-ready · **Queued post-V1**  
**Roadmap:** [`../roadmap/bessie-ios-control-plane.md`](../roadmap/bessie-ios-control-plane.md)  
**Track:** iOS — **P0 after Mac V1 launch** (after L + K + release approval)  
**Branch:** `feat/ios-v1-control-plane` (open when execution starts)  
**Goal-loop ready:** Yes **after** Mac V1 is released (or Jordan explicitly green-lights an early spike) — `GOAL-ios-v1-control-plane.md` (M0→M5)  
**Vision lock:** Always remote Herdr. SSH-only V1 transport. One focused real terminal. Structure control. No tiling. No on-device Herdr.  
**Notification lock:** V1 assumes the Bessie end-to-end encrypted Cloudflare → APNs relay is available. It is included at no user charge initially; product packaging may place it behind a paid entitlement later, so clients must not encode a perpetual-free promise.  
**Does not block / is not part of:** Mac V1 slices L or K. Do not pull iOS into the V1 release train.  
**Does not include:** Shepherd, file viewer/follow, project open/init/management, IDE features.
**Settled design atlas:** [Bessie iOS — Screen Atlas](https://skeletorjs.here.now/bessie-ios-atlas) — product IA and composition authority; copy and exact native materials may refine during implementation.  
**Design lock:** 15 screens; first-run Welcome → Add host → Connection check; Inbox as the default live destination; persistent five-item bottom dock plus detached Command control; Pinned, Snoozed, and Hierarchy as compact popouts over the current destination; one focused Shell; inline headings with no redundant app top bars, back labels, or path bars.

---

## Occam essence

**One job:** From an iPhone/iPad, run a live **remote** Herdr session — see every host, see who needs you, create/focus/rename/close structure, open **one** real pane terminal, pocket the phone without stopping Herdr.

**Cut:**

| Cut | Why |
| --- | --- |
| Bundled / on-device Herdr | Users run Herdr on remote hosts |
| Tiling / multi-pane grids | No mobile real estate; one focused terminal |
| File viewer, Follow, media studio | Not control plane |
| Project create/edit/open/init on phone | The settled mobile atlas excludes project management; Mac is the workshop |
| Porting Mac `BessieApp` AppKit chrome | Wrong shell |
| Scraping Herdr TUI | Public JSON API + terminal session bridge only |
| Fake graphical Allow | Same honesty as Mac — answer in the real terminal |
| Shepherd | Post–Mac-V1, separate approval |

**Keep (the point):**

1. Multi-host **Herds** connection profiles (Tailscale names/IPs normal) feeding one cross-host Inbox.  
2. **SSH-only V1** — one authenticated native client carries host shell, Herdr API, and the focused pane stream.  
3. Inbox grouped by Needs You, Working, Done, Idle, conditional Unknown, and Shells; selecting work opens the exact pane.  
4. Pinned and Snoozed presentation collections plus a compact Herds → Workspaces → Tabs hierarchy popout.  
5. Create / focus / rename / close workspaces, tabs, panes from hierarchy drill-ins and entity actions.  
6. One full-screen Herdr pane terminal at a time, with swipe navigation and current herd/workspace/tab context.  
7. Restricted mobile Command for live-session navigation only.

---

## 1. Outcome

After this track:

1. User adds remote hosts (address, user, auth, optional Herdr session name).  
2. Connection check visibly proves host reachability, SSH authentication, Herdr attachment, and protocol compatibility before entering the app.  
3. Inbox is the default post-onboarding destination and merges live work from every reachable configured herd into Needs You, Working, Done, Idle, conditional Unknown, and Shells sections.  
4. Selecting Inbox work, Pinned work, Snoozed work, or a deep link focuses the exact Herdr pane.  
5. User can create/focus/rename/close workspaces, tabs, and panes from the hierarchy flow without turning the phone into a desktop tree browser.  
6. **One** interactive Shell at a time: real frames + input; swipe moves through the same pane order exposed by the hierarchy; leaving returns to the control plane.  
7. The Shell context strip shows the current herd, workspace, and tab as icon + value only; it does not repeat the words “Herd,” “Workspace,” or “Tab.”  
8. **SSH host shell** is reachable from mobile Command; after suspension or network change Bessie reconnects and resumes the remote Herdr-owned session rather than promising transport-level continuity.  
9. Pinned and Snoozed are Bessie-owned presentation preferences; hiding or leaving a pane never stops the Herdr-owned process.  
10. Killing/backgrounding the app does **not** stop remote Herdr.

---

## 2. Substrate (reuse vs new)

### Reuse from Mac (`BessieCore` — make multiplatform)

| Piece | Path | iOS use |
| --- | --- | --- |
| Compat pins | `BessieCompatibility.swift` | Same protocol/version checks |
| Models / snapshot decode | `HerdrModels.swift`, projections | Session browser |
| Actions | `HerdrActions.swift` + `HerdrActionRunner` | Structure mutations |
| Consolidated Herd builder | `HerdList.swift` | Main supervision and blocked-only Needs you |
| Connection definitions | `BessieConnections.swift` | Multi-host list (no local-primary requirement on iOS) |
| Terminal frame protocol | `TerminalProtocol.swift`, `NDJSON.swift` | Pane stream decode/sequencing |
| Terminal input planning | `TerminalInput.swift` | Key/paste routing helpers |
| Presentation prefs shapes | `PresentationPersistence.swift` | Pinned, snoozed, appearance, and mobile presentation preferences where pure Foundation |
| Brand assets / semantic tokens | `Sources/BessieApp/BessieDesignSystem.swift`, `Sources/BessieApp/Resources/BessieLogo.svg`, `Sources/BessieApp/Resources/CowprintTile.png` | Native iOS adaptation must reuse the actual Bessie visual language and packaged assets |

### Mac-only — do not call from iOS

| Piece | Why |
| --- | --- |
| `UnixSocketTransport.swift` as sole API transport | Needs remote path; protocol `HerdrLineConnection` must leave `#if os(macOS)` |
| `HerdrTerminalController` **Process** launcher | No local `herdr` binary — replace with remote session transport |
| `RemoteHerdrBridge` Process + system `ssh` | Replace with embedded SSH client |
| `RuntimeDiscovery` / `RuntimeSetup` bundled engine | No on-device engine |
| Entire `BessieApp` AppKit terminal host | New UIKit/SwiftUI app |

### New

| Piece | Responsibility |
| --- | --- |
| `Apps/BessieiOS` (or `Sources/BessieiOS`) | SwiftUI app shell, iOS 17+ (iPhone + iPad) |
| Embedded **SSH** client | Host shell, Herdr API channel, and remote `herdr terminal session *` |
| `HerdrRemoteTransport` | Status, socket/streamlocal or stdio bridge to JSON API |
| `HerdrRemoteTerminalSession` | One pane: control/observe/takeover over SSH remote exec NDJSON |
| Terminal `UIView` host | Exact `libghostty-spm 1.3.2` `GhosttyTerminal`; M3 proves Bessie-specific mobile integration |
| Keychain host store | Credentials, host list |
| Mobile presentation store | Pinned/snoozed entries and settings; only Bessie-owned preferences, never copied live Herdr state |
| iOS design system adapter | Native SwiftUI/UIKit tokens and components derived from Bessie’s canonical assets and semantic palette |
| `scripts/ios-*.sh` | Build/test/verify hooks as they become real |

---

## 3. Architecture (HOW)

### 3.0 Platform decision — native Swift, not React Native

Build Bessie iOS as a **native Apple app in Swift**:

- **SwiftUI** owns the 15 product screens, persistent dock, compact overlays, settings forms, Dynamic Type, dark/light appearance, and iPhone/iPad adaptation.  
- **UIKit** is used narrowly where a real platform view is required: `GhosttyTerminal`’s `TerminalView` (`UIView` on iOS), keyboard/focus coordination, and gesture arbitration around the terminal. SwiftUI hosts it through the package’s existing `TerminalSurfaceView`/representable boundary.  
- **BessieCore** remains the shared pure-Swift layer used by macOS and iOS: Herdr models, snapshots, actions, projections, compatibility checks, presentation identifiers, and terminal frame/input sequencing.  
- **Platform adapters** stay separate: AppKit and local-process runtime code remain in `BessieApp`; UIKit, Keychain, scene lifecycle, embedded SSH, local notifications, and mobile presentation state live in the iOS target.  
- **No React Native, web view, or Mac Catalyst shortcut.** Those options add a second UI/runtime stack while still requiring native terminal, networking, Keychain, keyboard, backgrounding, and notification bridges. Native Swift shares more useful code with the existing Mac app and is the direct path to libghostty.

```text
SwiftUI iOS shell
  ├─ feature view models / mobile presentation store
  ├─ BessieCore (shared Swift)
  │    ├─ Herdr snapshots, actions, projections
  │    ├─ compatibility + connection models
  │    └─ terminal frame/input sequencing
  └─ iOS adapters
       ├─ host-managed SSH client built on pinned native foundations + Keychain
       ├─ GhosttyTerminal host-managed UIKit/SwiftUI surface
       └─ scene lifecycle + local notifications + E2EE relay client

User-owned Mac/VPS watcher
       └─ Herdr event observer → device-public-key encryption → Cloudflare relay → APNs
```

This is one Apple-native product with a shared core, not a port of the Mac AppKit chrome. Rebuild the settled mobile IA in SwiftUI; do not try to compile `Sources/BessieApp` for iOS wholesale.

### 3.1 Connection model (one host profile)

```text
HostProfile
  id, displayName
  host (Tailscale MagicDNS / IP / DNS)
  sshUser
  auth (Keychain: key and/or password — prefer key)
  herdrSession (default "bessie" or empty = host default)
```

User-facing: **one host**. Under the hood, one native SSH client may maintain the bounded channels needed for that profile:

| Pipe | Carries |
| --- | --- |
| **SSH PTY** | Full-screen **host shell** |
| **SSH exec/forward channels** | Herdr JSON API + **one** `herdr terminal session control\|observe` stream |

Keep host-shell PTY bytes separate from Herdr JSON and pane-session channels. Resnapshot after reconnect; do not treat an SSH socket as durable Herdr state.

### 3.2 Herdr API path

Mirror Mac remote semantics without local Unix sockets as the app-facing API:

1. SSH connect (embedded client; mux/channels).  
2. Discover remote Herdr: `herdr [--session S] status --json` (same idea as `RemoteHerdrBridgePlan.remoteStatusCommand`).  
3. Attach API via the best available channel **in this order**:  
   - **A (preferred):** SSH StreamLocal/direct-tcpip style forward of remote `herdr.sock` → in-process NDJSON client implementing `HerdrLineConnection`.  
   - **B (fallback):** remote exec wrapper that proxies one request/response if forward is blocked — only if A fails and B is proven in spike; do not invent a second protocol.  
4. `session.snapshot`, `events.subscribe`, `HerdrAction` methods — reuse Core types.  
5. Invalidation = events as hints + resnapshot (same discipline as Mac).

Lift `HerdrLineConnection` + response decode off pure-macOS isolation so Core tests stay shared.

### 3.3 Herdr pane terminal path

Mac today: local `Process` → `herdr terminal session control` + socket.  

iOS:

```text
SSH channel: remote exec
  herdr [--session S] terminal session control --pane <id> ...
  (observe / takeover flags as Mac)
  stdin/stdout = NDJSON terminal envelopes
```

- Decode with existing `HerdrTerminalEnvelope` / `TerminalFrameSequencer`.  
- Input: composite path equivalent to Mac — raw text, `pane.send_keys` / `pane.send_input` where interception requires API, ordering preserved.  
- **One** active pane session controller at a time; starting another tears down or releases the previous.  
- Ownership conflict → honest UI + Takeover action (reuse classify strings from `TerminalControllerFailure`).

### 3.4 SSH host shell path

- Full-screen SSH PTY rendered through the same `GhosttyTerminal` integration as pane terminals, with a separate session controller.  
- SwiftNIO SSH is a credible first foundation, but upstream explicitly calls it building blocks rather than a production-ready client. Bessie must implement and prove host-key trust UX, Keychain integration, key/password auth, PTY and remote exec, half-closure, stream backpressure, cancellation, forwarding where used, reconnection, and concurrent channels before adoption.  
- Background/network loss closes or suspends transport; foreground recovery reconnects and opens a fresh shell or refocuses the durable Herdr pane. Do not claim seamless shell-process roaming in V1.  
- **Mosh is explicitly deferred beyond iOS V1.** The 2026 feasibility record remains below for future reconsideration, but no Mosh code, C++/Protobuf artifact, port field, bootstrap path, GPL obligation, or Mosh acceptance criterion belongs in V1.

### 3.5 Terminal renderer

- Every visible terminal surface is **real emulator**, not a `Text` log.  
- Exact `libghostty-spm 1.3.2` is already iOS-capable: its manifest declares iOS 15+, its XCFramework contains Apple-mobile slices, `GhosttyTerminal` exposes UIKit and SwiftUI surfaces, and its host-managed `InMemoryTerminalSession` accepts remote bytes without an on-device PTY. Keep the repository’s exact pin unless a separately approved compatibility change bumps Mac and iOS together.  
- M3 is therefore an **integration gate**, not an upstream-platform-support gamble. Prove keyboard/IME, hardware modifiers, selection/copy, multiline-paste confirmation, touch scroll, viewport resize, safe areas, scene suspension, Metal surface recreation, and input/frame ordering against real Herdr and SSH sessions.  
- Do **not** ship a toy VT “for now” as v1 terminal. The renderer consumes remote terminal bytes; it never owns Herdr or remote process lifetime.

### 3.5.1 iOS lifecycle truth

iOS does not grant a normal terminal app an indefinitely running background socket. Assume SSH and Herdr channels can be suspended or terminated after leaving the foreground:

- Foreground: maintain live snapshots, terminal streams, and reachable-session local notification logic.  
- Short background transition: use only the supported finite cleanup window; persist Bessie-owned identifiers/preferences and release render resources cleanly.  
- Resume/foreground: reconnect transports, fetch a fresh snapshot, revalidate persisted identifiers, and reopen the requested pane. Herdr—not the SSH socket—owns the durable remote process.  
- Force quit: the iOS app performs no monitoring or polling, but the paired user-owned Mac/VPS watcher continues observing Herdr and may trigger a remote Needs You notification through the relay. Remote Herdr and pane processes continue because they live on the host.  
- V1 includes an end-to-end encrypted Cloudflare Worker → APNs relay and assumes it is operational. The iPhone generates the decryption key, pairs its public key and an opaque relay capability directly to the user-owned Mac/VPS watcher over the authenticated host connection, and the watcher encrypts every event before transmission. The relay retains only the minimum APNs routing-token/capability mapping, validates authentication, rate limits, expiration, and replay metadata, and forwards generic alert text plus ciphertext; it never receives a decryption key.  
- Cloudflare and Apple can observe routing, timing, source IP, ciphertext size, and delivery metadata and can drop or delay notifications. They cannot read the Herdr event body. Do not log request bodies, ciphertext, device tokens, or capabilities. Do not retain event payloads. On tap, Bessie reconnects directly and revalidates fresh Herdr state; rich notification decryption through an iOS notification-service extension is optional and must not be required for correctness.  
- Relay delivery is included at no user charge at launch. Treat availability as a capability/entitlement returned by service configuration rather than hard-coding “free forever”; a future paid plan may gate new registrations or continued delivery with explicit product messaging and a graceful foreground-only fallback. Never silently strand paired watchers or claim a purchase requirement before that policy exists.  
- CloudKit is not the selected V1 path. Retain it only as rejected feasibility context: a signed Mac companion can use a user’s private database, but unattended Linux/VPS private-database access is not a clean product route.  
- Do not abuse unrelated background modes (silent audio, VoIP, location, VPN). `BGContinuedProcessingTask` is for finite user-started work with visible progress and expiration, not an always-on socket loophole.

### 3.6 App IA

```text
First run (when no configured herd)
  Welcome → Add host → Connection check → Inbox

Persistent shell (after first run)
  Current destination
    Inbox (default)
    Shell (one focused pane or host shell)
    Settings / settings detail
  Bottom dock
    Inbox | Pinned | Snoozed | Hierarchy | Settings
  Detached Command control
    Jump to live pane | Open Needs You | Next pane | Previous pane | Open host shell

Dock popouts over the dimmed current destination
  Pinned
  Snoozed
  Hierarchy: Herds → Workspaces → Tabs → panes/entity actions
```

**Composition contract from the settled atlas:**

- The iOS status area is the only system top chrome. Product content starts immediately below it.  
- Do not add a redundant app top bar, breadcrumb/path bar, or persistent Back label to Inbox, Shell, Command, popouts, Settings, or settings detail screens. Add Host uses an inline title and Cancel action; settings and detail titles are inline content headings.  
- The five-item dock persists across core and settings destinations. Command remains a detached circular control beside it rather than becoming a sixth dock segment.  
- Pinned, Snoozed, Hierarchy, and Command are compact overlays over a dimmed current destination; they are not replacement full-screen tabs.  
- Inbox is a cross-host supervision surface grouped as **Needs You**, **Working**, **Done**, **Idle**, conditional **Unknown**, and **Shells**. Rows retain enough herd/workspace/tab context to identify and open the exact remote pane.  
- Shell starts directly under the status area and includes, in order: compact pane header with pane position, real terminal viewport, mobile input composer, icon+value context strip, and persistent dock. The context values are current herd, workspace, and tab; do not include redundant category words.  
- Swiping between panes follows the same ordered pane projection exposed by hierarchy; optional wrap-at-ends is a user preference.  
- Mobile Command is limited to navigation and live-session actions. It contains no project creation/management, file actions, tiling, or desktop-only catalog.  
- Settings root contains On startup, Herds, Terminal, Notifications, and Appearance. Herds is connection-profile CRUD. There is **no Compatibility/About screen or row**; compatibility remains a connection check and inline failure state.  
- Terminal settings cover font size, keep-awake, Return behavior, multiline-paste confirmation, keyboard haptics, swipe-between-panes, and wrap-at-ends. Notification settings cover Needs You policy, permission/test, exact-pane deep links, and badges. Appearance covers theme, density, app icon, cowprint, pane context, and reduce motion—without a decorative preview box.  
- Use the actual packaged Bessie logo and cowprint tile. Adapt `BessieDesignSystem` semantics natively: flat low-radius surfaces, compact typography, semantic status marks, no generic gradient/floating-card kit. Cowprint repeats as an accent-template texture; dark-mode target opacity is 11% unless the canonical design system changes.  
- No tiling and no desktop multi-window, including on iPad V1.

### 3.7 Settled screen inventory

| # | Screen/state | Required behavior |
| --- | --- | --- |
| 01 | Welcome | Brand-led first run; remote-only promise; Add remote host; prerequisites help |
| 02 | Add host | Display name, address, SSH user/auth, Herdr session; Connect + inline Cancel |
| 03 | Connection check | Reach host, authenticate SSH, attach Herdr, verify protocol; Open Bessie + notification preferences |
| 04 | Inbox | Cross-host Needs You, Working, Done, Idle, conditional Unknown, Shells; exact-pane open |
| 05 | Pinned | Bessie-owned pinned live-pane collection over Inbox |
| 06 | Snoozed | Bessie-owned hidden-until collection with return time; remote work continues |
| 07 | Hierarchy | Compact Herds, Workspaces, Tabs drill-in over Inbox; reaches pane and structure actions |
| 08 | Shell | One real terminal, pane order, composer, current context strip, swipe navigation |
| 09 | Command | Search/jump, Needs You, next/previous pane, host shell; no project/file/tiling commands |
| 10 | Settings | On startup, Herds, Terminal, Notifications, Appearance; no compatibility destination |
| 11 | Herds | Connection profiles, reachability/session labels, add/edit; removal never stops Herdr |
| 12 | Edit host | Edit/test/remove connection profile and credentials reference |
| 13 | Notifications | Needs You push policy, encrypted-relay status, test, exact-pane deep link, badges |
| 14 | Terminal | Display, input safety, haptics, keep-awake, swipe order, wrap preference |
| 15 | Appearance | Theme, density, icon, cowprint, pane context, reduce motion; no preview card |

### 3.8 Package / project layout (target shape)

```text
Package.swift
  platforms: macOS 14+, iOS 17+
  BessieCore          // multiplatform; gate Process/AppKit/mac-only files
  BessieCoreTests
  BessieApp           // macOS only (unchanged product)
  ...

Apps/BessieiOS/       // Xcode app target (recommended) OR executableTarget if viable
  BessieiOSApp.swift
  Features/Hosts, Session, Terminal, Settings
  Services/SSH, HerdrRemote*
```

Mac targets must keep compiling. `./scripts/check.sh` stays green on Core/macOS.

---

## 4. Files (expected touch set)

| Path | Change |
| --- | --- |
| `Package.swift` | iOS platform; Core multiplatform; optional iOS-only deps |
| `Sources/BessieCore/UnixSocketTransport.swift` | Split protocol vs macOS Unix impl |
| `Sources/BessieCore/*` | `#if os` on Process/SSH-mac bridges; keep actions/models shared |
| `Sources/BessieCore/HerdrRemote*.swift` (new) | Shared remote attach interfaces if pure Foundation |
| `Apps/BessieiOS/**` (new) | App + UI + SSH/terminal hosts |
| `Tests/BessieCoreTests/*` | Transport-agnostic + action tests; no weaken |
| `Tests/BessieiOSTests/**` (new as needed) | Projection/VM tests runnable in SPM where possible |
| `scripts/check.sh` | Don’t break Mac; add iOS compile hook when ready |
| `scripts/ios-verify.sh` (new) | Simulator build + unit tests; device notes |
| `docs/plans/2026-08-03-bessie-ios-control-plane.md` | Evidence §11 |
| `docs/reports/goal-progress.md` | Checkpoint log |
| `GOAL-ios-v1-control-plane.md` | Goal contract |

Pin the selected SSH foundation at M1 with source/version/checksum and license evidence. `libghostty-spm` is already exactly pinned to `1.3.2` in `Package.swift`; do not replace it with a floating requirement.

---

## 5. Milestones

### M0 — Scaffold + Core multiplatform

- Branch `feat/ios-v1-control-plane`.  
- iOS app target builds the native app shell with the Welcome placeholder, real Bessie logo/cowprint assets, semantic mobile tokens, and the settled dock/Command composition available behind fixture data.  
- `BessieCore` compiles for iOS + macOS; macOS `./scripts/check.sh` green.  
- `HerdrLineConnection` available off macOS-only file isolation.  
- Add deterministic atlas-sized fixture states so screenshots can validate composition before live transport is ready; fixture state must never masquerade as a connected product path.

**Accept:** iOS simulator launch; Welcome and fixture-backed core shell visually conform to §3.6–3.7; Mac check.sh pass.

### M1 — SSH foundation + first-run connection (required gate)

- Implement Welcome → Add host → Connection check with Keychain auth and inline, stage-specific failures.  
- Full-screen SSH host shell to a real remote host.
- Host-key trust, Keychain auth, PTY, exec, cancellation/backpressure, and concurrent-channel behavior documented with real runs.
- Background/suspension + network-change reconnect documented honestly; Herdr-owned remote work survives, while an ordinary SSH shell may not.
- Pin the SSH dependency source/version/checksum and complete its licensing/security review before product code depends on it.

**Accept:** First-run screens match atlas composition; connection check proves reach/auth/Herdr/compat stages; SSH host shell and bounded Herdr channels work on at least one Tailscale-reachable host; foreground recovery reconnects and resnapshots.  
**Pause:** No SSH foundation clears host-key/auth/PTY/exec/backpressure/concurrency behavior after two serious attempts — stop and report.

### M2 — Herdr control plane attach

- Same host credentials: SSH attach → status → snapshot.  
- events subscribe + resnapshot loop.  
- UI: fixture/live Inbox sections and Hierarchy drill-in from the shared projection; no per-host root tab or redundant top bar.  
- At least three mutations wired: e.g. `tabCreate`, `paneSplit` (or create pane path), `paneClose`, plus rename + focus. Prefer full set in §6 once list works: workspace/tab/pane create/focus/rename/close.

**Accept:** Against the compatible live remote Herdr baseline: Inbox and hierarchy render authoritative data; create tab; rename; close; focus pane metadata updates after resnapshot. Unit tests for action encoding remain green.

### M3 — One Herdr pane terminal

- Remote terminal session control NDJSON → sequencer → libghostty-class UIView.  
- Input works (type, enter, basic special keys, paste).  
- Observe vs control vs takeover honest.  
- Only one pane controller active.
- Shell composition matches §3.6: pane header/order, terminal, composer, current icon+value herd/workspace/tab strip, and dock; horizontal swipe follows the hierarchy pane order.

**Accept:** Open needs-you or arbitrary pane; interactive shell/agent usable; leave releases/detaches cleanly; remote process still runs.  
**Pause:** Exact `libghostty-spm 1.3.2` cannot pass the real-device keyboard/render/lifecycle integration bar after two focused attempts — stop (do not ship toy VT as done).

### M4 — Cross-host Inbox + mobile chrome

- Herds settings lists all connection profiles and exposes add/edit/test/remove without implying ownership of remote work.  
- Cross-host Inbox groups Needs You, Working, Done, Idle, conditional Unknown, and Shells (reuse consolidated builders and connection labels).  
- Needs you selection → switch host context if needed → open pane terminal.  
- Pinned and Snoozed presentation collections persist and open the authoritative live pane; snoozing only hides work until its return time.  
- Hierarchy and structure action sheets complete per §6.  
- Persistent dock, detached Command overlay, popout behavior, and restricted Command catalog match §3.6–3.7.

**Accept:** Two configured hosts feed one Inbox; Needs You, Pinned, Snoozed, Hierarchy, and Command each hit the correct host and pane; structure CRUD from UI; no project/file/tiling actions.

### M5 — Lifecycle harden

- Reconnect API + terminal after background.  
- Honest errors (auth, herdr down, ownership).  
- Pair the iPhone notification key/capability to a user-owned Mac/VPS watcher without exposing the private key; register and revoke the APNs route through the E2EE Cloudflare relay.  
- Needs You notifications arrive through APNs while Bessie is suspended or terminated, carry no relay-readable Herdr content, and deep-link to a direct fresh reconnect for the exact pane. Foreground local notification behavior remains the fallback when relay capability is unavailable.  
- Settings behavior complete for On startup, Herds, Terminal, Notifications, and Appearance. Compatibility failures remain inline in connection/reconnect flows; do not add a Compatibility/About screen.  
- Appearance uses packaged logo/cowprint and semantic tokens, supports theme/density/icon/cowprint/context/reduce-motion, and does not add a decorative preview card.  
- Confirm kill app ≠ kill Herdr (live check).

**Accept:** Checklist in §6. `ios-verify` + Core tests green; installed simulator/device screenshots cover all 15 atlas states; Mac check.sh still green.

---

## 6. Acceptance checklist (v1 done = M0–M5)

1. Welcome → Add host → Connection check works with the fields/stages in §3.7; successful connection enters Inbox.  
2. Herds settings shows every configured connection profile; add/edit/test/remove works, and removing a profile does not stop remote Herdr.  
3. SSH host shell connects; foreground recovery after suspension or network change reconnects and freshens state without claiming seamless PTY roaming.  
4. Compatible Herdr snapshots feed one cross-host Inbox grouped by Needs You, Working, Done, Idle, conditional Unknown, and Shells.  
5. Pinned and Snoozed persist as Bessie presentation preferences and resolve back to fresh authoritative pane state.  
6. Hierarchy exposes Herds → Workspaces → Tabs → panes and supports create workspace/tab/pane with simple defaults.  
7. Focus, rename, and close workspaces/tabs/panes work and resnapshot into the correct UI state.  
8. Inbox, Pinned, Snoozed, Hierarchy, Command, and notification deep links open the correct host and pane.  
9. One focused real terminal; typing, Return, special keys, paste safety, takeover, and ownership errors are honest; no second simultaneous pane terminal.  
10. Shell shows the current herd/workspace/tab as icon + value only; swipe uses hierarchy order and obeys wrap-at-ends preference.  
11. Persistent dock, detached Command control, compact popouts, no redundant top/back/path bars, and all 15 screen states match the settled atlas composition.  
12. Command contains only live-session navigation/actions; no project, file, tiling, or desktop-only commands.  
13. Notifications expose policy, relay/pairing health, test, badge behavior, and exact-pane deep links; a real Needs You transition from a paired Mac/VPS reaches a suspended or terminated device through Cloudflare → APNs without Cloudflare, Apple, or Bessie infrastructure receiving plaintext Herdr content. Revocation, token rotation, expiry/replay rejection, rate limits, and graceful foreground-only fallback are proven.  
14. Settings exposes only On startup, Herds, Terminal, Notifications, and Appearance; no Compatibility/About screen exists, while compatibility mismatch still fails clearly inline.  
15. Packaged Bessie logo/cowprint and semantic visual tokens are used; Appearance has no decorative preview card; Reduce Motion is honored.  
16. App background/kill does not stop remote Herdr; reconnect restores the control plane without reinstall.  
17. Mac `./scripts/check.sh` still passes.  
18. No file viewer, project management, on-device Herdr, tiling, Shepherd, or desktop multi-window.

---

## 7. Non-goals

- Local Herdr runtime / onboarding engine install on phone  
- Project create/edit/delete studio  
- Follow files, workspace FS browser, markdown editor  
- Tiling, multi-terminal split view (even on iPad v1)  
- Menu bar, Mac chrome, Agent Intent Bus, CLI/MCP on iOS  
- Shepherd
- Mosh transport in iOS V1
- Plaintext notification relay, relay-held decryption keys, event-payload retention, or human-readable Herdr content in APNs
- Graphical approve without typed RPC  
- Weakening Mac tests or rewriting Mac V1 scope  

---

## 7.1 Mobile feasibility audit

| Design/capability | Feasibility | Implementation truth / gate |
| --- | --- | --- |
| Welcome, Add host, Connection check | **Straightforward** | Native SwiftUI forms, SecureField, validation, async progress, Keychain. Never store private key/password in `UserDefaults`. |
| Cross-host Inbox and compact hierarchy | **Straightforward** | Shared Core projections + SwiftUI lists/scroll views. Diff and coalesce snapshots off-main; publish view state on `MainActor`. |
| Five-item dock + detached Command circle | **Straightforward with accessibility work** | Custom SwiftUI safe-area inset/overlay. Preserve ≥44×44 pt hit targets, VoiceOver labels, Dynamic Type, home-indicator clearance, landscape, and iPad width; the atlas is composition authority, not a reason to hard-code one phone size. |
| Pinned/Snoozed/Hierarchy/Command popouts | **Straightforward** | Custom overlay or presentation API with dimming and focus trapping. On compact phones use the atlas-sized popout; on iPad the same state may present as an anchored popover without changing information architecture. |
| Shell terminal + composer + dock | **Feasible; focused integration required** | `libghostty-spm 1.3.2` supports iOS/UIKit/SwiftUI and host-managed bytes. Use keyboard-safe-area/layout-guide behavior so the terminal resizes above the software keyboard; test hardware keyboards and rotation. Keep the dock reachable without permanently wasting terminal height when the keyboard is up. |
| Swipe between panes | **Feasible with gesture arbitration** | Install the horizontal pager gesture outside the terminal’s selection/scroll gesture path; require a clear horizontal threshold/edge policy and test trackpad/iPad input. Swipe changes one active controller only after orderly detach/release. |
| Herd/workspace/tab context strip | **Straightforward** | Shared projection supplies values. Icons require accessibility labels even though visible category words are intentionally absent. |
| Structure create/focus/rename/close | **Straightforward if Herdr API supports it** | SwiftUI confirmation/action sheets call typed public Herdr actions and resnapshot. Destructive controls need confirmation and honest remote failure states. |
| Mosh host shell | **Deferred beyond iOS V1** | Feasibility is proven, but C++/Protobuf integration and GPL/product-distribution obligations are not justified for V1. Do not add Mosh artifacts, fields, commands, or acceptance criteria unless Jordan explicitly reopens scope. |
| Embedded SSH + remote Herdr streams | **Feasible; client product work required** | SwiftNIO SSH is the preferred first foundation, not a drop-in client. Build and prove host-key trust UX, Keychain auth, exec/PTY, half-closure, forwarding where used, cancellation, backpressure, reconnection, and concurrent channels on a real host. |
| Reachable Needs You local notifications | **Required fallback** | Use while Bessie has fresh reachable state and when relay capability is unavailable. Do not present fallback as equivalent to asleep-app delivery. |
| End-to-end encrypted Cloudflare → APNs relay | **Selected V1 dependency; assume available** | A user-owned watcher encrypts to an iPhone-generated key before transit. The Worker holds Bessie’s APNs provider credential and routes ciphertext without plaintext access. Prove direct key pairing, capability revocation, replay protection, metadata disclosure, no-body logging, no event retention, APNs token rotation, abuse controls, and real-device suspended/terminated delivery. Included free initially; capability/entitlement architecture must permit future paid packaging without promising it. |
| CloudKit private-database notifier | **Not selected** | Feasible for a signed Mac companion but a weak VPS fit. Keep only as research context; do not implement alongside the selected relay. |
| Appearance, cowprint, themes, alternate icons | **Feasible** | SwiftUI semantic tokens and packaged assets. Alternate icons require all icon variants in the signed asset catalog and user-mediated `setAlternateIconName`; do not promise arbitrary downloadable icons. |
| Reduce Motion / haptics / keep-awake | **Feasible with platform limits** | Respect accessibility Reduce Motion, gate haptics, and use idle-timer disabling only while the user explicitly has an active foreground Shell. It is not a background keepalive. |
| iPhone + iPad | **Feasible as one native target** | Adaptive SwiftUI layout, size-class tests, pointer/hardware-keyboard support; no iPad tiling or desktop multi-window in V1. |

**Architecture go/no-go before broad UI implementation:** M0 may build the native shell and fixture states, but production execution must not move beyond bounded scaffolding until M1 proves (a) native SSH PTY/exec channels against a real Herdr host, (b) host-key/auth/backpressure/concurrency behavior, and (c) real-device lifecycle recovery. The terminal renderer itself is no longer an unknown platform capability; its remaining risk is Bessie-specific integration quality.

**Feasibility research anchors (checked 2026-08-08):**

- [`libghostty-spm 1.3.2` manifest](https://raw.githubusercontent.com/Lakr233/libghostty-spm/1.3.2/Package.swift) — iOS 15 platform declaration, products, binary URL, and checksum.  
- [`GhosttyTerminal` package documentation](https://swiftpackageregistry.com/Lakr233/libghostty-spm) — UIKit, SwiftUI, and host-managed session surfaces.  
- [`GhosttyTerminal` iOS example](https://github.com/Lakr233/libghostty-spm/blob/1.3.2/Example/MobileGhosttyApp/ViewController.swift) — `TerminalView`, in-memory backend, safe-area/keyboard layout, resize, selection, and first-responder precedent.  
- [SwiftNIO SSH](https://github.com/apple/swift-nio-ssh) — first SSH foundation only; upstream explicitly does not ship a production-ready client.  
- [Blink `mosh-apple` 1.4.0+blink-18.4.5](https://github.com/blinksh/mosh-apple/releases/tag/v1.4.0%2Bblink-18.4.5) and its [`mosh_main` C bridge](https://github.com/blinksh/mosh/blob/3640d36678dc415ba24f03d7f6fb20a0dac1fa6b/src/frontend/moshiosbridge.h) — current iOS binary/C++ integration precedent, not approved dependencies.  
- [Upstream Mosh](https://github.com/mobile-shell/mosh) and its [iOS GPL waiver](https://raw.githubusercontent.com/mobile-shell/mosh/master/COPYING.iOS) — App Store conflict waiver plus continuing GPL/source obligations.  
- [Apple background-task guidance](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados) — finite, system-managed work; not an always-on terminal/network entitlement.
- [CloudKit subscriptions](https://developer.apple.com/documentation/cloudkit/ckquerysubscription) — record changes can generate push-notification hints.
- [CloudKit Web Services authentication](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/SettingUpWebServices.html) — server-to-server keys access the public database; private database access requires user authentication.
- [APNs token authentication](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns) — the provider signs short-lived ES256 JWTs and submits through Apple’s HTTP/2 provider API.
- [Cloudflare Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/) and [Web Crypto API](https://developers.cloudflare.com/workers/runtime-apis/web-crypto/) — current cost envelope and supported cryptographic primitives for capability validation and APNs-provider signing.

---

## 8. Verification

| Gate | Command / proof |
| --- | --- |
| Mac Core unaffected | `./scripts/check.sh` |
| iOS unit (SPM-capable) | `swift test` where targets allow; else `xcodebuild test` |
| iOS build | `scripts/ios-verify.sh` (create by M0/M1): simulator build BessieiOS |
| M1 live | Device or sim + real Tailscale host; SSH PTY/exec/concurrency plus suspension/network-reconnect notes in goal-progress |
| M2–M5 live | Real remote compatible Herdr `0.8.0` / protocol `19` session; pane readback / interactive check |
| Install | Not Mac `/Applications` path — iOS: simulator and/or device run; TestFlight only with Jordan approval |
| Design | Fixture and live screenshots for all 15 atlas states at compact iPhone, large iPhone, and iPad widths; inspect light/dark, Dynamic Type, software/hardware keyboard, landscape, Reduce Motion, and VoiceOver labels |
| Background truth | Run outside Xcode: foreground → background → suspension/termination → reopen; prove fresh resnapshot and remote process survival; prove copy never promises guaranteed offline notifications |

Do not claim success from compile alone. Do not delete/skip/weaken tests to pass.

---

## 9. Pause and ask

Stop and report (do not invent scope) if:

1. No SSH foundation clears host-key/auth/PTY/exec/backpressure/concurrency behavior after two serious candidates.  
2. Cannot attach Herdr API over SSH forward/exec against real host after focused spike.  
3. Exact `libghostty-spm 1.3.2` cannot clear real-device render/input/lifecycle integration after two focused approaches.  
4. Herdr protocol/version on host ≠ pinned compat and bump needs Mac product decision.  
5. Apple signing/network entitlements block SSH in a way that needs Jordan account/config.  
6. Pressure to add Mosh, files, tiling, Shepherd, local runtime, plaintext relay processing, or relay-held decryption keys to V1.  
7. The assumed Cloudflare/APNs relay cannot prove client-side encryption, direct key pairing, revocation, no-payload logging/retention, abuse controls, or suspended/terminated real-device delivery after two focused approaches.  
8. Mac check.sh broken by multiplatform split and not fixable quickly — restore Mac first.

---

## 10. Goal-loop binding

- **When:** First feature train **after Mac V1 launches**. Do not run the iOS goal loop during L/K unless Jordan explicitly says start early.  
- **Contract file:** `GOAL-ios-v1-control-plane.md`  
- **Order:** M0 → M1 → M2 → M3 → M4 → M5.  
- **Do not start M4 UI polish before M1–M3 pipes work.**  
- **Stop when:** §6 items 1–18 are true with evidence, or hard pause in §9.  
- Update `docs/reports/goal-progress.md` after each milestone with files + real command output.  
- Append §11 evidence; no commit/push/PR/TestFlight without Jordan approval.

---

## 11. Implementation evidence

_(empty — fill as milestones complete)_

### Template per milestone

```text
### M# — <name> — YYYY-MM-DD
- Done:
- Files:
- Commands + results:
- Live host checks:
- Paused / deferred:
```
