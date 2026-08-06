# Richer Herd dashboard — execution plan (ce-plan)

**Date:** 2026-08-02  
**Status:** Integrated baseline; slice M consolidation required  
**V1 slice:** E baseline + M correction  
**Branch:** `feat/v1-e-herd-attention` (historical integrated branch)  
**Goal-loop ready:** Yes after D merges preferred; can start pure Core filter extract anytime  
**Depends on:** [v1-shared-substrate](2026-08-02-v1-shared-substrate.md) §2–3; prefer D merged to reduce `ProductSurfaces` conflict  
**Superseding decision:** Standalone Attention is removed; [its useful behavior folds into Herd](2026-08-02-attention-queue-and-resolution.md).

## 1. Outcome (Occam bar B)

The Herd is a trustworthy multi-connection ops list:

1. **Needs you** filter shows **blocked** agents (bug fix).
2. Simple filters: All / Needs you / Working / Done / Idle with **counts**.
3. Cards show: identity, semantic state, location (workspace · tab), **connection label**, optional title if present.
4. Primary actions: **Open pane**, Details (existing).
5. Local + remote agents in **one list**; connection chip always when `fleet.models.count > 1` (or always for clarity — prefer always show short label).
6. Ordering: blocked → working → done → idle → unknown; secondary connection name; tertiary identity.
7. Honest empty/degraded: no agents vs no match vs connection errors visible without faking offline-all.
8. No standalone Attention destination: Needs you, count, Open pane, next-needs-you, notifications, and Zen blocked cues share Herd's blocked-only predicate.

## 2. Current substrate

| Piece | Path | Notes |
| --- | --- | --- |
| Fleet agents | `ConnectionFleetViewModel.agents` | Already multi-connection |
| Card UI | `HerdSurface` in `ProductSurfaces.swift` ~688+ | 3-col grid |
| Filter bug | `HerdFilter.includes` | compares `"needs you"` to `"blocked"` |
| State | `AgentSemanticState` | blocked/working/done/idle/unknown |
| Connected agent | `ConnectedAgentProjection` | composite id |
| Tests | `SurfaceProjectionTests` | no Herd filter tests |

## 3. Architecture

### 3.1 Extract testable Herd presentation model to Core (or App model file with tests)

```swift
public enum HerdListFilter: String, CaseIterable, Sendable {
    case all, needsYou, working, done, idle
}

public struct HerdCardModel: Equatable, Identifiable, Sendable {
    public let id: String                 // ConnectedAgentProjection.id
    public let connectionID: String
    public let connectionLabel: String    // from ConnectionDisplayLabel.short
    public let connectionDetail: String
    public let identity: String
    public let state: AgentSemanticState
    public let location: String           // "ws · tab"
    public let activity: String?          // agent.title only if non-empty; never invent
    public let paneTarget: RoutedPaneTarget
}

public enum HerdListBuilder {
    public static func cards(
        agents: [ConnectedAgentProjection],
        filter: HerdListFilter,
        connectionLabels: [String: ConnectionDisplayLabel]
    ) -> [HerdCardModel]

    public static func counts(agents: [ConnectedAgentProjection]) -> [HerdListFilter: Int]
}
```

Filter mapping:
- needsYou → `.blocked` only
- others → exact state
- all → everything including unknown

### 3.2 Connection labels

Implement `ConnectionDisplayLabel` helper per substrate (can land in this branch if D didn't).

### 3.3 UI wiring

`HerdSurface` becomes a thin view over `HerdListBuilder` + fleet. Add count badges on filter chips. Show connection chip on cards. Keep Open pane / Details callbacks.

Degraded: if a connection model is disconnected/erroring, show a slim banner listing connection name + state (from fleet presentation) above the grid — do not remove agents from other connections.

## 4. Files

| File | Change |
| --- | --- |
| `Sources/BessieCore/HerdList.swift` (**new**) | Filter, builder, counts, card model |
| `Sources/BessieCore/ConnectionDisplay.swift` (**new** if not exists) | labels |
| `Tests/BessieCoreTests/HerdListTests.swift` (**new**) | filter bug regression, counts, sort |
| `Sources/BessieApp/ProductSurfaces.swift` | Wire HerdSurface |
| `scripts/check.sh` | grep anchors for HerdList / Needs you fix |

## 5. Milestones

### M0 — Contract tests first (RED)

- Write `HerdListTests` encoding Needs you = blocked; counts; sort stability.
- Confirm current UI bug documented.

**DoD:** tests fail against old includes logic if extracted with bug, or tests specify correct behavior before UI wire.

### M1 — Core builder + labels

- Implement builder + ConnectionDisplayLabel.
- Unit tests green.

### M2 — Wire HerdSurface

- Replace private HerdFilter with Core.
- Counts on chips; connection chip; sort.
- Manual Mac: multi-connection if available; at least single local.

### M3 — Empty/degraded

- Empty copy for no agents / no match.
- Optional connection error banner from fleet.

### M4 — Verify

- Remove standalone Attention surface/models/routes and rename next-attention language.
- Check.sh; Mac screenshot required for final M acceptance; no filter regression.

## 6. Acceptance

1. Needs you shows blocked agents only; unit test locks it.
2. Each filter count matches builder.
3. Cards show state, location, connection label, identity.
4. Open pane focuses exact pane on owning connection.
5. Local+remote appear together when both connected.
6. No Collie overhaul, no LLM activity, no new approve actions.
7. check.sh green.
8. No Attention destination or duplicate Attention list model remains.

## 7. Non-goals

Snooze, search, virtualization, custom sort UI, interrupt-from-card, menu bar, graphical approve.

## 7a. Visual contract (slice L — do not expand E)

Logic/builders for Herd are **done** (see §10). Remaining visual quieting is **slice L** only:

- One quiet Open control (not white primary on every card).
- Connection label once; no uppercase LOCAL/LIVE soup.
- Empty detail line is a next step, not a repeated title.
- Sentence case on card actions.

Do not reopen filter semantics or add card approve actions under L.

## 8. Pause conditions

- Fleet cannot supply connection name for an agent → stop.
- Product wants Needs you = blocked+done → ask Jordan (default blocked only).

## 9. Consolidation

Treat the old Herd and Attention implementation as one correction unit. Remove the duplicate Attention list rather than maintaining two worktrees or two presentation models.

## 10. Implementation evidence — 2026-08-02

- Added the Core `HerdListBuilder`, explicit Needs-you = blocked mapping, per-filter counts, stable state/connection/identity ordering, connection display labels, and connection-aware pane targets.
- Wired `HerdSurface` to Core cards, count-bearing filters, always-visible connection chips, honest no-agent/no-match states, and fleet connection issue banners. Open pane activates the owning connection before focusing the exact target.
- Added `HerdListTests` covering the Needs-you regression, counts, ordering, labels, location, and routed connection identity.
- Verification: VPS `./scripts/check.sh` passed. A unique isolated Mac source mirror compiled BessieApp and passed `HerdListTests`, `AttentionListTests`, `SurfaceProjectionTests`, and `KeyboardShortcutTests`: **21 tests, 0 failures**.
- Full shared-mirror `mac-verify.sh` was not claimed: another active slice overwrote one mirrored source file between sync and build. The isolated focused run avoided that shared-directory race. No screenshot, package install, push, or PR was claimed for this slice.
