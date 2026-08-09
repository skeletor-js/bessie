# Goal: Bessie iOS v1 — remote control plane

**Status:** Queued — **first post–Mac-V1 feature** (do not execute during Mac V1 L/K)  
**Owner:** goal-loop / implementing agent (after V1 launch gate)  
**Branch:** `feat/ios-v1-control-plane`  
**Plan:** `docs/plans/2026-08-03-bessie-ios-control-plane.md` (source of truth)  
**Roadmap:** `docs/roadmap/bessie-ios-control-plane.md`

## Start gate

**Do not begin this goal until one of:**

1. Mac V1 is released (slices L + K done, Jordan release approval), or  
2. Jordan explicitly says to start iOS early.

Until then this file is the locked contract for the first post-V1 ship — not an active loop.

## Goal contract (paste into /goal when start gate passes)

**Objective:** Ship Bessie iOS as a native SwiftUI/UIKit remote Herdr control plane: cross-host Inbox, Pinned/Snoozed presentation collections, hierarchy + live-session Command, SSH host shell, Herdr structure control (create/focus/rename/close workspaces·tabs·panes), one focused real pane terminal at a time, and end-to-end encrypted Needs You delivery from a user-owned Mac/VPS watcher through the assumed-available Bessie Cloudflare → APNs relay — without on-device Herdr, Mosh, tiling, files, projects, plaintext relay processing, or relay-held decryption keys. Complete milestones M0→M5 in order and preserve the settled 15-screen atlas composition.

**Read first:**
- `docs/plans/2026-08-03-bessie-ios-control-plane.md`
- `docs/roadmap/bessie-ios-control-plane.md`
- Settled atlas: `https://skeletorjs.here.now/bessie-ios-atlas`
- `AGENTS.md`
- `Sources/BessieCore/HerdrActions.swift`
- `Sources/BessieCore/HerdrAPI.swift`
- `Sources/BessieCore/HerdrTerminalController.swift`
- `Sources/BessieCore/TerminalProtocol.swift`
- `Sources/BessieCore/RemoteHerdrBridge.swift`
- `Sources/BessieCore/HerdList.swift`
- `Sources/BessieCore/AttentionList.swift`
- `Sources/BessieCore/BessieConnections.swift`
- `Sources/BessieCore/BessieCompatibility.swift`
- `Package.swift`

**Constraints:**
- Branch: `feat/ios-v1-control-plane` (create from post-V1 mainline when starting).
- Always remote Herdr. Never bundle or run Herdr as an on-device engine.
- SSH is the only V1 transport for host shell, Herdr API, and focused pane streams. Mosh is explicitly deferred beyond V1.
- One interactive terminal at a time. No tiling / multi-pane grids.
- Real terminal renderer only (libghostty-class). No toy VT as “done.”
- Architecture: native SwiftUI product screens + narrow UIKit terminal/focus bridge; shared pure-Swift `BessieCore`; no React Native, web view, or Catalyst shortcut.
- Exact `libghostty-spm 1.3.2` supports iOS/UIKit/SwiftUI; M3 is a real-device input/render/lifecycle integration gate.
- The selected SSH foundation is the M1 gate: host-key trust, Keychain auth, PTY/exec, backpressure, cancellation, concurrency, and reconnect must work against a real host.
- Reuse `BessieCore` models/actions/projections; do not port Mac AppKit `BessieApp` chrome.
- Keep Mac product building: `./scripts/check.sh` must stay green.
- Herdr compat baseline unless Jordan bumps: `0.8.0` / protocol `19`.
- No Shepherd, file viewer/follow, project open/init/management, graphical fake Allow, intent bus, CLI/MCP on iOS.
- iOS may suspend/terminate sockets in background. Resume by reconnect + fresh snapshot. Assume the Bessie Cloudflare → APNs relay is available: the user-owned Mac/VPS watcher encrypts to an iPhone-generated key before transit, the relay holds the shared APNs credential but no decryption key, and a push tap reconnects directly for fresh Herdr state. Never use fake background modes or place readable Herdr content in APNs.
- Relay delivery is included at no user charge initially. Model availability as a service capability/entitlement so a future paid offering is possible, but do not show or enforce a purchase requirement until Jordan defines one and do not hard-code “free forever.”
- No commit, push, PR, TestFlight, or App Store action without explicit Jordan approval.
- Do not weaken, skip, delete, or relabel tests/checks to force a pass.
- Prefer small checkpoints; update `docs/reports/goal-progress.md` with files changed and real command output.
- Append evidence to the plan §11 when milestones complete.
- VPS edit path: `/home/hermes/code/bessie`. iOS build/verify on Mac (`jordan-macbook`) via Xcode/simulator as needed. Never `rsync --delete` blindly against a non-mirror.

**Milestone order (mandatory):**
1. **M0** — Scaffold iOS app target + multiplatform `BessieCore`; Mac check.sh green  
2. **M1** — SSH foundation + first-run connection + foreground recovery (required gate)  
3. **M2** — Herdr API attach + structure mutations + session UI list  
4. **M3** — One Herdr pane terminal (remote session control + real renderer + input)  
5. **M4** — Cross-host Inbox + Pinned/Snoozed/Hierarchy/Command + full structure action sheets  
6. **M5** — Lifecycle harden + E2EE notification delivery (watcher pairing, relay/APNs, reconnect, ownership, kill-app survival)  

Do not start M4 chrome before M1–M3 pipes work.

**Validate after each milestone:**
1. `./scripts/check.sh` on VPS (Mac Core/app path)  
2. iOS simulator build (and `scripts/ios-verify.sh` once it exists)  
3. Live remote host checks required for M1–M5 (not compile-only)  
4. Plan §11 evidence block + `docs/reports/goal-progress.md` update  

**Document:** Plan §11 + goal-progress. Do not invent ADRs unless a real irreversible fork appears (then write one short decision in the plan evidence).

**Reward-hacking guard:** Do not delete, skip, weaken, narrow, or relabel tests/checks. Do not mark M3 done with a text log terminal. Do not mark M1 done without real SSH and foreground-recovery evidence. Do not claim multi-host without two profiles tested.

**Pause and ask if:**
- No SSH foundation clears host-key/auth/PTY/exec/backpressure/concurrency behavior after two serious attempts  
- Herdr API cannot attach over SSH forward/exec on a real host  
- Exact `libghostty-spm 1.3.2` cannot clear real-device render/input/lifecycle integration after two focused approaches  
- Compat/protocol mismatch needs a product bump decision  
- Signing/entitlements need Jordan’s Apple setup  
- Scope pressure toward Mosh, files, tiling, Shepherd, local runtime, plaintext relay processing, relay-held decryption keys, or event retention  
- The assumed relay cannot prove direct key pairing, revocation, replay/expiry rejection, token rotation, no-payload logging/retention, abuse controls, and suspended/terminated real-device delivery after two focused approaches  
- Multiplatform split breaks Mac and cannot be restored quickly  

**Stop when:**
- Plan §6 acceptance items 1–18 are true with evidence in §11 and goal-progress  
- OR blocked on a pause condition above with a clear written blocker  

## Non-goals

On-device Herdr, Mosh, plaintext notification relay processing, relay-held decryption keys, event-payload retention, readable Herdr content in APNs, project open/init/management, file/follow surfaces, tiling, Shepherd, Mac V1 L/K work, shipping to App Store/TestFlight without approval.
