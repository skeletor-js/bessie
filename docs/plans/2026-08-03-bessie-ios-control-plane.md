# Bessie iOS — remote control plane (ce-plan)

**Date:** 2026-08-03  
**Updated:** 2026-08-03 — locked as **first post–Mac-V1 ship** (not in Mac V1)  
**Status:** Implementation-ready · **Queued post-V1**  
**Roadmap:** [`../roadmap/bessie-ios-control-plane.md`](../roadmap/bessie-ios-control-plane.md)  
**Track:** iOS — **P0 after Mac V1 launch** (after L + K + release approval)  
**Branch:** `feat/ios-v1-control-plane` (open when execution starts)  
**Goal-loop ready:** Yes **after** Mac V1 is released (or Jordan explicitly green-lights an early spike) — `GOAL-ios-v1-control-plane.md` (M0→M5; M6 optional)  
**Vision lock:** Always remote Herdr. Mosh-class host connect. One focused real terminal. Structure control. No tiling. No on-device Herdr.  
**Does not block / is not part of:** Mac V1 slices L or K. Do not pull iOS into the V1 release train.  
**Does not include:** Shepherd, file viewer/follow, project authoring, IDE features.

---

## Occam essence

**One job:** From an iPhone/iPad, run a live **remote** Herdr session — see every host, see who needs you, create/focus/rename/close structure, open **one** real pane terminal, pocket the phone without stopping Herdr.

**Cut:**

| Cut | Why |
| --- | --- |
| Bundled / on-device Herdr | Users run Herdr on remote hosts |
| Tiling / multi-pane grids | No mobile real estate; one focused terminal |
| File viewer, Follow, media studio | Not control plane |
| Project create/edit on phone | Mac is the workshop |
| Porting Mac `BessieApp` AppKit chrome | Wrong shell |
| Scraping Herdr TUI | Public JSON API + terminal session bridge only |
| Fake graphical Allow | Same honesty as Mac — answer in the real terminal |
| Shepherd | Post–Mac-V1, separate approval |

**Keep (the point):**

1. Multi-host main list (Tailscale names/IPs normal).  
2. **Mosh required** — Moshi-class connect/resume (SSH bootstraps Mosh the normal way).  
3. Herd with Needs you → open exact pane.  
4. Create / focus / rename / close workspaces, tabs, panes.  
5. One full-screen Herdr pane terminal at a time.  
6. Optional: open/initialize existing Mac project recipes if M0–M5 are solid.

---

## 1. Outcome

After this track:

1. User adds remote hosts (address, user, auth, optional Herdr session name).  
2. Main screen lists **all hosts** with reachability + needs-you count when known.  
3. Opening a host attaches to its Herdr session (compat baseline: Herdr `0.7.5` / protocol `17` unless explicitly bumped with Mac).  
4. User sees herd/agents and needs-you; **Open** focuses that pane’s terminal.  
5. User can create/focus/rename/close workspaces, tabs, and panes from UI.  
6. **One** interactive terminal at a time: real frames + input; leave returns to control plane.  
7. **Mosh host shell** is available on that host and survives sleep/wake + network change at Moshi-class quality.  
8. Killing/backgrounding the app does **not** stop remote Herdr.  
9. Projects **open/init** existing recipes only — **defer** if M0–M5 slip (still count as v1 success without M6).

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
| Project recipes (M6) | `BessieProjects.swift`, materialization request shapes | Open/init only |
| Presentation prefs shapes | `PresentationPersistence.swift` | Where pure Foundation |

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
| Embedded **Mosh** client | Required host-shell path; Moshi-class resume |
| Embedded **SSH** client | Bootstrap Mosh; Herdr API channel; remote `herdr terminal session *` |
| `HerdrRemoteTransport` | Status, socket/streamlocal or stdio bridge to JSON API |
| `HerdrRemoteTerminalSession` | One pane: control/observe/takeover over SSH remote exec NDJSON |
| Terminal `UIView` host | libghostty-class renderer (spike picks embed path) |
| Keychain host store | Credentials, host list |
| `scripts/ios-*.sh` | Build/test/verify hooks as they become real |

---

## 3. Architecture (HOW)

### 3.1 Connection model (one host profile)

```text
HostProfile
  id, displayName
  host (Tailscale MagicDNS / IP / DNS)
  sshUser
  auth (Keychain: key and/or password — prefer key)
  moshPort / moshServerPath (defaults OK)
  herdrSession (default "bessie" or empty = host default)
```

User-facing: **one host**. Under the hood (normal Moshi-shaped stack, not optional flavors):

| Pipe | Carries |
| --- | --- |
| **Mosh** | Full-screen **host shell** (required v1 surface) |
| **SSH** (same host, same credentials) | Herdr JSON API + **one** `herdr terminal session control\|observe` stream |

Do not design for Mosh-without-SSH museums. Do not put Herdr JSON mux through the Mosh PTY.

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

### 3.4 Mosh host shell path

- Full-screen terminal UI (can share renderer with pane terminal if spike allows; separate sessions).  
- Bootstrap via SSH as Mosh normally does; UDP Mosh session thereafter.  
- Library: **spike chooses** in M1 — prefer maintainable Apple-platform option (e.g. pure Swift Mosh stack if it meets resume bar; else established libmosh embed). Pin version in Package/Xcode. Document choice in plan evidence.  
- Acceptance is behavioral (sleep/wake, network flip), not library brand.

### 3.5 Terminal renderer

- Every visible terminal surface is **real emulator**, not a `Text` log.  
- Prefer **libghostty**-class Metal/UIView path on iOS (ecosystem already ships iOS libghostty apps).  
- If `libghostty-spm` `1.3.2` is Mac-only, M2/M3 spike either:  
  - alternate libghostty iOS binding, or  
  - thin UIView host around a pinned iOS-capable ghostty core  
- Do **not** ship a toy VT “for now” as v1 terminal.

### 3.6 App IA

```text
HostsRootView
  HostSessionView
    tabs/segments: Herd | Attention | Structure
    Structure: workspaces → tabs → panes
    entity actions sheet: Focus, Rename, Close, Create…
    Open terminal → FocusedTerminalView (push/fullScreenCover)
    Host shell → MoshTerminalView
Settings: hosts CRUD, keys, session name, about/compat
```

No tiling. No desktop multi-window.

### 3.7 Projects (M6 optional)

- Read recipe store format compatible with Mac `BessieProjects` (iCloud/Files/manual import — spike simplest path; **do not** build a sync product).  
- Action: **Open/Initialize** on selected host → run materialization **on remote Herdr** via existing action/API sequence (port request construction from `BessieProjectMaterialization`, execute through remote API).  
- No editor. Defer entire M6 if M0–M5 incomplete.

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
  Services/Mosh, SSH, HerdrRemote*
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
| `Apps/BessieiOS/**` (new) | App + UI + Mosh/SSH/terminal hosts |
| `Tests/BessieCoreTests/*` | Transport-agnostic + action tests; no weaken |
| `Tests/BessieiOSTests/**` (new as needed) | Projection/VM tests runnable in SPM where possible |
| `scripts/check.sh` | Don’t break Mac; add iOS compile hook when ready |
| `scripts/ios-verify.sh` (new) | Simulator build + unit tests; device notes |
| `docs/plans/2026-08-03-bessie-ios-control-plane.md` | Evidence §11 |
| `docs/reports/goal-progress.md` | Checkpoint log |
| `GOAL-ios-v1-control-plane.md` | Goal contract |

Exact Mosh/libghostty package URLs pinned at M1/M3 with versions in evidence — do not leave floating `main`.

---

## 5. Milestones

### M0 — Scaffold + Core multiplatform

- Branch `feat/ios-v1-control-plane`.  
- iOS app target builds empty shell (Hosts placeholder).  
- `BessieCore` compiles for iOS + macOS; macOS `./scripts/check.sh` green.  
- `HerdrLineConnection` available off macOS-only file isolation.  
- No product claims yet.

**Accept:** iOS simulator launch; Mac check.sh pass.

### M1 — Mosh host connect (required gate)

- Add host + Keychain auth.  
- Full-screen Mosh host shell to a real remote host.  
- Sleep/wake + network change resume documented with real runs.  
- Pin Mosh dependency version.

**Accept:** Moshi-class behavioral bar on at least one Tailscale-reachable host.  
**Pause:** Cannot embed any Mosh stack that meets resume bar after two serious library attempts — stop and report.

### M2 — Herdr control plane attach

- Same host credentials: SSH attach → status → snapshot.  
- events subscribe + resnapshot loop.  
- UI: session structure list from projection.  
- At least three mutations wired: e.g. `tabCreate`, `paneSplit` (or create pane path), `paneClose`, plus rename + focus. Prefer full set in §6 once list works: workspace/tab/pane create/focus/rename/close.

**Accept:** Against live remote Herdr `0.7.5`/proto 17: snapshot renders; create tab; rename; close; focus pane metadata updates after resnapshot. Unit tests for action encoding remain green.

### M3 — One Herdr pane terminal

- Remote terminal session control NDJSON → sequencer → libghostty-class UIView.  
- Input works (type, enter, basic special keys, paste).  
- Observe vs control vs takeover honest.  
- Only one pane controller active.

**Accept:** Open needs-you or arbitrary pane; interactive shell/agent usable; leave releases/detaches cleanly; remote process still runs.  
**Pause:** No iOS libghostty-class embed after two approaches — stop (do not ship toy VT as done).

### M4 — Multi-host shell + Herd/Needs you

- Hosts root list all profiles.  
- Herd list with blocked-only Needs you filter (reuse the consolidated builder and connection labels).  
- Needs you selection → switch host context if needed → open pane terminal.  
- Structure browser + action sheets complete per §6.

**Accept:** Two configured hosts; Needs you/Open hits the correct host and pane; structure CRUD from UI; no tiling.

### M5 — Lifecycle harden

- Reconnect API + terminal after background.  
- Honest errors (auth, herdr down, ownership).  
- Local notifications while app/session reachable → deep link pane (best-effort; no offline push relay required).  
- Confirm kill app ≠ kill Herdr (live check).

**Accept:** Checklist in §6 M5 rows. `ios-verify` + Core tests green; Mac check.sh still green.

### M6 — Projects open/init (optional)

- Import/list existing recipes.  
- Initialize on selected host via remote materialize path.  
- **Skip** without failing v1 if M0–M5 done and this is large.

**Accept:** One Mac-created recipe materializes on remote Herdr from phone, or explicit defer note in evidence.

---

## 6. Acceptance checklist (v1 done = M0–M5)

1. Multi-host list shows all configured hosts.  
2. Mosh host shell connects and resumes after sleep/wake and network flip.  
3. Herdr snapshot and Herd—including Needs you—visible for the attached host.  
4. Create workspace, tab, pane (simple defaults; fixed split direction OK).  
5. Focus, rename, close workspace/tab/pane.  
6. Needs you/Open opens the correct pane terminal.  
7. One focused real terminal; input works; no second simultaneous pane terminal.  
8. Takeover/ownership conflict is honest.  
9. App background/kill does not stop remote Herdr.  
10. Reconnect restores control plane without manual reinstall.  
11. Compat mismatch fails clearly.  
12. Mac `./scripts/check.sh` still passes.  
13. No file viewer, no project editor, no on-device Herdr, no tiling.  
14. M6 either shipped (open/init only) or explicitly deferred in evidence.

---

## 7. Non-goals

- Local Herdr runtime / onboarding engine install on phone  
- Project create/edit/delete studio  
- Follow files, workspace FS browser, markdown editor  
- Tiling, multi-terminal split view (even on iPad v1)  
- Menu bar, Mac chrome, Agent Intent Bus, CLI/MCP on iOS  
- Shepherd  
- Offline push relay / APNs herd server  
- Graphical approve without typed RPC  
- Weakening Mac tests or rewriting Mac V1 scope  

---

## 8. Verification

| Gate | Command / proof |
| --- | --- |
| Mac Core unaffected | `./scripts/check.sh` |
| iOS unit (SPM-capable) | `swift test` where targets allow; else `xcodebuild test` |
| iOS build | `scripts/ios-verify.sh` (create by M0/M1): simulator build BessieiOS |
| M1 live | Device or sim + real Tailscale host; sleep/wake notes in goal-progress |
| M2–M5 live | Real remote Herdr 0.7.5 session; pane readback / interactive check |
| Install | Not Mac `/Applications` path — iOS: simulator and/or device run; TestFlight only with Jordan approval |

Do not claim success from compile alone. Do not delete/skip/weaken tests to pass.

---

## 9. Pause and ask

Stop and report (do not invent scope) if:

1. Mosh embed cannot meet resume bar after two serious implementations.  
2. Cannot attach Herdr API over SSH forward/exec against real host after focused spike.  
3. No acceptable libghostty-class iOS renderer after two approaches.  
4. Herdr protocol/version on host ≠ pinned compat and bump needs Mac product decision.  
5. Apple signing/network entitlements block Mosh UDP or SSH in a way that needs Jordan account/config.  
6. Pressure to add files/tiling/Shepherd/local runtime.  
7. Mac check.sh broken by multiplatform split and not fixable quickly — restore Mac first.

---

## 10. Goal-loop binding

- **When:** First feature train **after Mac V1 launches**. Do not run the iOS goal loop during L/K unless Jordan explicitly says start early.  
- **Contract file:** `GOAL-ios-v1-control-plane.md`  
- **Order:** M0 → M1 → M2 → M3 → M4 → M5 → (M6 optional).  
- **Do not start M4 UI polish before M1–M3 pipes work.**  
- **Stop when:** §6 items 1–13 true with evidence, or hard pause in §9.  
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
