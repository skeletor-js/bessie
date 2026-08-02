# V1 shared substrate contract

**Date:** 2026-08-02
**Status:** Execution contract — required before parallel V1 slices
**Audience:** goal-loop / ce-work / worktree agents
**Locked with:** [2026-08-02-v1-vision-occam-scope.md](2026-08-02-v1-vision-occam-scope.md)

## Why this exists

Remaining V1 slices share identity, attention, routing, and capability concepts. Parallel work without this contract will fork models inside `ProductSurfaces.swift` and break multi-connection Herd.

## Non-negotiable product rules

1. Herdr owns live sessions, workspaces, tabs, panes, terminals, processes, agents.
2. Every visible terminal is real libghostty attached to a Herdr pane.
3. Quitting or disconnecting Bessie never stops Herdr or pane processes.
4. No typed approve/resolve UI without a versioned Herdr/agent contract.
5. Remote file/media features must degrade honestly (local-only until transport exists).
6. Raw Herdr IDs are never globally unique across connections — always pair with `connectionID`.

## Package ownership

| Layer | Path | Owns |
| --- | --- | --- |
| Core | `Sources/BessieCore/` | Projections, actions, connections, notifications planning, shortcuts catalog, pure logic + tests |
| App | `Sources/BessieApp/` | SwiftUI/AppKit shell, libghostty, settings UI, UNUserNotificationCenter, window lifecycle |
| Tests | `Tests/BessieCoreTests`, `Tests/BessieAppModelTests` | Pure unit tests; Mac live checks via `scripts/mac-verify.sh` |

No Rust core in this repo. Do not invent a Rust rewrite.

## 1. Connection identity

**Source of truth:** `BessieConnectionDefinition` in `Sources/BessieCore/BessieConnections.swift`.

| Field | Meaning |
| --- | --- |
| `id` | Stable Bessie-owned ID (e.g. `local-bessie`) |
| `name` | User-visible short name (`This Mac`, host nickname) |
| `kind` | `.local` or `.ssh` |
| `sshHost` | Required when ssh |
| `session` | Herdr session name (default product: `bessie` for local) |

### Display label contract (all surfaces must use)

Introduce or centralize a pure helper (prefer `BessieCore`):

```swift
public struct ConnectionDisplayLabel: Equatable, Sendable {
    public let short: String   // card chip: "This Mac" | host short
    public let detail: String  // "Local · bessie" | "SSH · host · session"
    public let kind: BessieConnectionKind
}
```

Rules:
- Prefer `connection.name` for `short` when non-empty.
- For `.ssh`, if name is empty/generic, fall back to `sshHost`.
- Never show only a raw pane ID without connection when fleet count > 1.
- Single local-only connection may omit the chip in dense UI, but navigation/debug still keep IDs.

### Fleet aggregation

`ConnectionFleetViewModel` (`BessieApp.swift`) already unions agents across connections via `ConnectedAgentProjection`.

Rules:
- Herd, Attention (when multi-connection), notification routing, and Open pane **activate owning connection** before using raw Herdr IDs.
- Sorting: primary semantic state rank, secondary connection name, tertiary identity — stable.

## 2. Agent and pane identity

**Source:** `ConnectedAgentProjection` + `AgentProjection`.

| ID | Scope |
| --- | --- |
| `ConnectedAgentProjection.id` | `"\(connection.id)::\(agent.id)"` — Bessie-global |
| `agent.id` / `paneID` | Herdr-local only |
| `workspaceID`, `tabID`, `terminalID` | Herdr-local only |

Open-pane path always carries:

```swift
struct RoutedPaneTarget: Equatable, Sendable {
    var connectionID: String
    var workspaceID: String
    var tabID: String
    var paneID: String
}
```

Notification userInfo already uses `connection_id` + pane fields — keep that schema; do not invent a second deep-link format.

## 3. Needs-you / attention semantics

**Source:** `AgentSemanticState` in `SurfaceProjection.swift`.

| State | Herdr values | Needs-you? | Attention list? |
| --- | --- | --- | --- |
| blocked | `blocked` | **Yes** | Yes (primary) |
| done | `done` | Optional presentation | Yes (secondary) |
| working | `working` | No | No |
| idle | `idle` | No | No |
| unknown | other | No | No |

**V1 Attention product (Occam):** list items that need the user; only action is **Open pane**. No snooze, no local resolved history.

**Needs-you filter (Herd):** must mean `AgentSemanticState.blocked` (and optionally include `done` only if product copy says so — **default V1: Needs you = blocked only**; Done stays its own filter).

### Known bug to fix in slice E

`HerdFilter.includes` compares `rawValue.lowercased()` (`"needs you"`) to `state.rawValue` (`"blocked"`) — always false for Needs you.

**Required fix:** map filter cases to `AgentSemanticState` explicitly; add unit tests.

```swift
// Correct pattern
func includes(_ state: AgentSemanticState) -> Bool {
    switch self {
    case .all: true
    case .blocked: state == .blocked
    case .working: state == .working
    case .done: state == .done
    case .idle: state == .idle
    }
}
```

Move `HerdFilter` (or equivalent) into testable `BessieCore` or `BessieApp` model file with tests — do not leave pure filter logic only inside private SwiftUI without coverage.

## 4. Notification deep links

**Sources:** `NotificationPlanning.swift`, `BessieNotifications.swift`, `ProductSurfaces.routePendingNotification`.

Contract:
1. Planner is **per connectionID**.
2. Events carry exact pane topology + connectionID.
3. Click → activate connection → resolve target against **current** projection → focus pane.
4. Stale target → fall back to Attention destination; never crash.
5. Policy: blocked-only or blocked+done (existing settings).
6. Suppress notifications for the actively focused pane (existing).

Slice G only polishes reliability/copy/routing — does not redesign planner schema unless tests demand a fix.

## 5. Workspace filesystem root (slices F)

Local-only V1:

```swift
public struct WorkspaceFileRoot: Equatable, Sendable {
    public let connectionID: String
    public let workspaceID: String
    public let rootURL: URL           // absolute file URL
    public let resolution: RootResolution
}

public enum RootResolution: String, Sendable {
    case herdrCwd          // from pane/workspace cwd if authoritative
    case agentWorkingDir
    case unavailableRemote
    case missing
    case unauthorized
}
```

Rules:
- All file reads/writes/previews must stay inside `rootURL` after standardization (no `..` escape).
- Remote connections: surface `unavailableRemote` — do not shell-scrape files over SSH as product path.
- Follow files and media viewer share one root resolver + one containment helper in Core (or small FileSupport module in Core).

## 6. Capability matrix (connection-scoped)

| Capability | Local | SSH remote V1 |
| --- | --- | --- |
| Terminal | Yes | Yes if bridge healthy |
| Herd/Attention list | Yes | Yes if snapshot healthy |
| Open pane | Yes | Yes |
| Follow files / media / markdown save | Yes | **No** — honest banner |
| Notification deep link | Yes | Yes if app connected |
| Projects materialize | Local first (existing) | Follow existing Projects constraints |

## 7. Parallelism graph

```
D Production polish          [solo first, Mac]
        │
        ▼
E Herd B + Attention thin    [same worktree; shares Needs-you + labels]
        │
        ├──────────────► G Notification polish   [after Needs-you + RoutedPaneTarget stable]
        │
        ▼
F0 Shared FS root + containment
        │
        ├── F1 Follow files
        └── F2 Media/markdown viewer + file ops
              (parallel after F0 lands on main or shared branch)

I Appearance                 [parallel after D; low coupling]
J Connection UX              [after label helper exists; can start docs/settings copy early]
K Notarized gate             [last]
```

**Do not parallel:** F1/F2 before F0; E before Needs-you contract tests; K before features claim done.

**Worktree naming (suggestion):**
- `feat/v1-d-production-polish`
- `feat/v1-e-herd-attention`
- `feat/v1-f0-workspace-fs`
- `feat/v1-f-follow-files`
- `feat/v1-f-media-markdown`
- `feat/v1-g-notification-polish`
- `feat/v1-i-appearance`
- `feat/v1-j-connection-ux`

## 8. Verification baseline every slice

After meaningful work:
1. `./scripts/check.sh` (VPS-safe structural + unit where available)
2. On Mac: `./scripts/mac-verify.sh` for UI/live slices
3. No unrelated Herdr sessions stopped
4. Quit survival invariant preserved

## 9. What agents must not do

- Expand Deferred items (search, menu bar item, layout presets, entity palette, general code editor)
- Add snooze/resolved history to Attention
- Introduce second notification route schema
- Use raw pane IDs across fleet without connectionID
- Implement remote file access via ad-hoc SSH commands
- Rewrite ProductSurfaces as a mega-PR without extracting testable Core helpers

## 10. Slice readiness

| Slice | Plan | Goal-loop ready? |
| --- | --- | --- |
| D Production polish | `2026-08-02-production-ui-ux-cleanup.md` | **Yes (Mac)** |
| E Herd + Attention | `2026-08-02-richer-herd-dashboard.md` + `attention-...` | **Yes** (prefer after D) |
| F0 Workspace FS | `2026-08-02-workspace-fs-substrate.md` | **Yes** |
| F1 Follow files | `2026-08-02-follow-files-and-agent-changes.md` | **Yes after F0** |
| F2 Media/markdown | `2026-08-02-in-app-file-viewer-editor.md` | **Yes after F0** |
| G Notifications | `2026-08-02-menu-bar-herd.md` (notify-only) | **Yes after E** |
| I Appearance | `2026-08-02-design-system-customization.md` | **Yes** (parallel-ish after D) |
| J Connection UX | `2026-08-02-herdr-session-connection-manager.md` | **Yes after labels** |
| K Hardening | `2026-08-02-v1-hardening-gate.md` | **Yes last** |
