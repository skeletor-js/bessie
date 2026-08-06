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

**Objective:** Ship Bessie iOS as a remote Herdr control plane: multi-host list, Mosh-class host shell, Herdr structure control (create/focus/rename/close workspaces·tabs·panes), herd + attention, one focused real pane terminal at a time — without on-device Herdr, tiling, files, or project editing. Complete milestones M0→M5 in order; M6 (open existing Projects) only if cheap after M5.

**Read first:**
- `docs/plans/2026-08-03-bessie-ios-control-plane.md`
- `docs/roadmap/bessie-ios-control-plane.md`
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
- Mosh host shell is required (M1 gate). SSH is the Herdr API + pane stream path on the same host (normal Moshi-shaped stack).
- One interactive terminal at a time. No tiling / multi-pane grids.
- Real terminal renderer only (libghostty-class). No toy VT as “done.”
- Reuse `BessieCore` models/actions/projections; do not port Mac AppKit `BessieApp` chrome.
- Keep Mac product building: `./scripts/check.sh` must stay green.
- Herdr compat baseline unless Jordan bumps: `0.7.5` / protocol `17`.
- No Shepherd, file viewer/follow, project editor, graphical fake Allow, intent bus, CLI/MCP on iOS.
- No commit, push, PR, TestFlight, or App Store action without explicit Jordan approval.
- Do not weaken, skip, delete, or relabel tests/checks to force a pass.
- Prefer small checkpoints; update `docs/reports/goal-progress.md` with files changed and real command output.
- Append evidence to the plan §11 when milestones complete.
- VPS edit path: `/home/hermes/code/bessie`. iOS build/verify on Mac (`jordan-macbook`) via Xcode/simulator as needed. Never `rsync --delete` blindly against a non-mirror.

**Milestone order (mandatory):**
1. **M0** — Scaffold iOS app target + multiplatform `BessieCore`; Mac check.sh green  
2. **M1** — Mosh host connect + sleep/wake/network resume (required gate)  
3. **M2** — Herdr API attach + structure mutations + session UI list  
4. **M3** — One Herdr pane terminal (remote session control + real renderer + input)  
5. **M4** — Multi-host + Herd + Attention + full structure action sheets  
6. **M5** — Lifecycle harden (reconnect, ownership, kill-app survival, reachable notifications)  
7. **M6** — Optional: open/init existing Projects only — skip if costly  

Do not start M4 chrome before M1–M3 pipes work.

**Validate after each milestone:**
1. `./scripts/check.sh` on VPS (Mac Core/app path)  
2. iOS simulator build (and `scripts/ios-verify.sh` once it exists)  
3. Live remote host checks required for M1–M5 (not compile-only)  
4. Plan §11 evidence block + `docs/reports/goal-progress.md` update  

**Document:** Plan §11 + goal-progress. Do not invent ADRs unless a real irreversible fork appears (then write one short decision in the plan evidence).

**Reward-hacking guard:** Do not delete, skip, weaken, narrow, or relabel tests/checks. Do not mark M3 done with a text log terminal. Do not mark M1 done without resume evidence. Do not claim multi-host without two profiles tested.

**Pause and ask if:**
- Mosh cannot meet resume bar after two serious embed attempts  
- Herdr API cannot attach over SSH forward/exec on a real host  
- No libghostty-class iOS renderer after two approaches  
- Compat/protocol mismatch needs a product bump decision  
- Signing/entitlements need Jordan’s Apple setup  
- Scope pressure toward files, tiling, Shepherd, or local runtime  
- Multiplatform split breaks Mac and cannot be restored quickly  

**Stop when:**
- Plan §6 acceptance items 1–13 are true with evidence in §11 and goal-progress  
- M6 either done (open/init only) or explicitly deferred in evidence  
- OR blocked on a pause condition above with a clear written blocker  

## Non-goals

On-device Herdr, project authoring, file/follow surfaces, tiling, Shepherd, Mac V1 L/K work, shipping to App Store/TestFlight without approval.
