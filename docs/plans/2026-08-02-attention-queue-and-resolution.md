# Attention (thin) — execution plan (ce-plan)

**Date:** 2026-08-02  
**Status:** Implementation-ready  
**V1 slice:** E (pair with Herd)  
**Branch:** `feat/v1-e-herd-attention`  
**Goal-loop ready:** Yes with Herd plan  
**Occam lock:** Needs-you list + Open pane only — **no** snooze, resolved-local, history, keyboard triage pack

## 1. Outcome

Attention is a clear inbox of panes that need the user on the **active connection** (or fleet — see decision), each with **Open pane** only.

Default scope: **active connection** (matches today) unless Herd bar B work already surfaces fleet-wide attention — then use composite IDs. Prefer **fleet-wide Attention** for local+remote vision: items carry `connectionID` + label.

**Jordan vision:** local and remote live together → **fleet-wide Attention list**.

## 2. Substrate

| Piece | Path |
| --- | --- |
| Items | `AttentionSurfaceItem` in `SurfaceProjection.swift` — id is paneID only today |
| UI | `AttentionSurface` in ProductSurfaces |
| Actions | `.openPane` only — keep |
| Notifications | separate planner; Open next attention shortcut |

## 3. Architecture

### 3.1 Fleet attention model

```swift
public struct AttentionItemModel: Equatable, Identifiable, Sendable {
    public var id: String { "\(connectionID)::\(paneID)" }
    public let connectionID: String
    public let connectionLabel: String
    public let paneID: String
    public let state: AgentSemanticState  // blocked or done only
    public let identity: String
    public let location: String
    public let target: RoutedPaneTarget
}

public enum AttentionListBuilder {
    public static func items(from agents: [ConnectedAgentProjection], labels: ...) -> [AttentionItemModel]
    // include state.needsAttention (blocked + done)
    // sort blocked first, then done; secondary connection; tertiary identity
}
```

### 3.2 UI

- List blocked then done sections **or** single list with state glyph (keep simple single list sorted).
- Button Open pane → activate connection → open target.
- Empty: "Nothing needs you".
- No snooze UI.

### 3.3 Shortcut

`openNotificationTarget` / ⌥⌘N: open first attention item fleet-wide (blocked first).

## 4. Files

| File | Change |
| --- | --- |
| `Sources/BessieCore/AttentionList.swift` (**new**) | builder |
| `Tests/BessieCoreTests/AttentionListTests.swift` | sort + composite id |
| `Sources/BessieApp/ProductSurfaces.swift` | AttentionSurface fleet wiring |
| `Sources/BessieApp/BessieApp.swift` | only if fleet API needed |

## 5. Milestones

### M1 — Core builder + tests
### M2 — Wire UI fleet-wide + Open pane
### M3 — ⌥⌘N uses builder ordering
### M4 — Verify with Herd branch checklist

## 6. Acceptance

1. Attention shows blocked+done only, blocked first.
2. Each row has connection label when multi-connection.
3. Open pane routes correct connection + pane.
4. No snooze/history/resolve UI.
5. Unit tests for composite IDs and ordering.
6. check.sh green.

## 7. Non-goals

Typed approve, explain/reason fields unless already free on projection, snooze, menu bar.

## 8. Pause

If fleet-wide attention doubles notification noise semantics — notifications stay per-connection planners; Attention UI is independent.

## 9. Implementation evidence — 2026-08-02

- Added fleet-wide `AttentionListBuilder` models with composite connection/pane IDs, blocked+done inclusion, blocked-first ordering, connection labels, and routed pane targets.
- Wired the Attention destination, rail/status counts, Open pane action, and ⌥⌘N to the same fleet-wide builder ordering. Opening activates the owning connection before focusing the exact pane.
- Kept the surface thin: one ordered list, one Open pane action, and “Nothing needs you” empty copy. No snooze, history, resolve, menu bar, files, or follow behavior was added.
- Added `AttentionListTests` for inclusion, ordering, composite IDs, labels, and routed targets.
- Verification: VPS `./scripts/check.sh` passed. A unique isolated Mac source mirror compiled BessieApp and passed `HerdListTests`, `AttentionListTests`, `SurfaceProjectionTests`, and `KeyboardShortcutTests`: **21 tests, 0 failures**. Full shared-mirror/package/install results are not claimed because concurrent slice synchronization made that shared mirror non-authoritative.
