# Connection UX (local + remote) — execution plan (ce-plan)

**Date:** 2026-08-02
**Status:** Implementation-ready
**V1 slice:** J
**Branch:** `feat/v1-j-connection-ux`
**Goal-loop ready:** Yes after label helper (E or substrate) exists; SSH Mac live tests required
**Occam lock:** Not a fleet console. Unified Herd labels + better settings/onboarding + SSH harden.

## 1. Outcome

1. User always understands **which connection** an agent/pane belongs to (Herd/workspace chrome).
2. Settings: clear list of connections, add SSH, remove non-local, select active, show health summary.
3. Onboarding/first-run mentions remote only as advanced path; local bundled default remains primary.
4. SSH attach reliability: honest errors; reconnect; no stop remote Herdr on disconnect.
5. Capability banners for files on remote.
6. No multi-host mirror product, no attach-any-orphan-session browser beyond existing session field.

## 2. Substrate

| Piece | Path |
| --- | --- |
| Definitions | `BessieConnections.swift` |
| Store | settings connection store |
| Fleet | `ConnectionFleetViewModel` |
| SSH | `RemoteHerdrBridge.swift` |
| Labels | `ConnectionDisplayLabel` (E/F0/substrate) |

## 3. Architecture

### 3.1 Health snapshot per connection

```swift
public struct ConnectionHealth: Equatable, Sendable {
    public let connectionID: String
    public let phase: String          // from ConnectPresentation / runtime diagnostic
    public let isUsable: Bool
    public let detail: String         // user-safe one liner
    public let supportsWorkspaceFS: Bool  // local only V1
}
```

Expose from each `ConnectionViewModel` → fleet aggregates.

### 3.2 Settings UI

- List connections with kind, detail, health.
- Add SSH form (host, session optional default).
- Delete with confirm (not local-bessie).
- Select active connection.
- Link to runtime settings for local.

### 3.3 Onboarding copy

One advanced disclosure: "Use Herdr on another Mac over SSH" → opens connection settings; does not block first local terminal.

### 3.4 SSH harden

- Review `RemoteHerdrBridge` failure paths; map to Trouble/Setup findings where appropriate.
- Disconnect = tear down bridge + local controllers; never `herdr stop` remote.
- Document required remote Herdr already running (product honesty).

### 3.5 Chrome labels

Workspace top bar + agent detail header show connection short label.

## 4. Files

- `RemoteHerdrBridge.swift`, `ConnectionLifecycle.swift`
- `BessieApp.swift` fleet health
- `BessieSettings.swift` / new `ConnectionsSettingsView.swift`
- `OnboardingView.swift` copy
- `ProductSurfaces.swift` labels
- Tests: connection validation (existing), health mapping pure tests

## 5. Milestones

M1 Health model + unit mapping
M2 Settings connections UX
M3 Chrome labels everywhere E left gaps
M4 SSH error honesty + disconnect survival
M5 Onboarding advanced path
M6 Mac verify local+ssh if host available; else local-only + mocked error strings

## 6. Acceptance

1. Multi-connection Herd shows labels (with E).
2. User can add/select/remove SSH connection safely.
3. Disconnect Bessie from SSH does not kill remote processes.
4. Remote files show unsupported in F surfaces.
5. Onboarding still reaches local terminal without SSH.
6. check.sh green.

## 7. Non-goals

herdr-mirror style multi-server sidebar product, session resurrect, Tailscale automation.

## 8. Pause

SSH cannot forward both sockets on user network → document degraded mode; don't fake connected.
