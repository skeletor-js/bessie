# Notification polish — execution plan (ce-plan)

**Date:** 2026-08-02
**Status:** Implementation-ready
**V1 slice:** G
**Branch:** `feat/v1-g-notification-polish`
**Goal-loop ready:** Yes after E (Needs-you + RoutedPaneTarget stable)
**Superseded scope note:** This plan's notification work remains historical, but the menu-bar deferral was explicitly superseded by `2026-08-04-001-feat-pre-v1-ui-redesign-plan.md` U10/U12.

## 1. Outcome

1. Notification click always activates correct **connection** + **pane** (warm and cold start).
2. Titles/bodies match Herd's state language ("needs you" / "done").
3. Authorization failures surface in Settings (improve error handling; don't swallow silently).
4. Stale targets show an honest route error and open Herd or connection recovery without crashing.
5. No menu bar item, no quiet-hours suite, no phone.

## 2. Substrate

| Piece | Path | Gap |
| --- | --- | --- |
| Planner | `NotificationPlanning.swift` | OK per connection |
| Coordinator | `BessieNotifications.swift` | add errors; cold route |
| Route | `ProductSurfaces.routePendingNotification` | depends on shell existing |
| userInfo | connection_id + target fields | keep schema |

## 3. Architecture

### 3.1 Cold start routing

Problem: pending notification may arrive before `BessieProductShell` exists.

Approach:
1. Keep pending target on `BessieNotificationCoordinator` (already).
2. Ensure `ConnectView` / root also `.onAppear` / `.task` attempts `routePendingNotification` once fleet is ready — not only shell.
3. Add `fleet.activate` + open pane API on fleet/VM callable without shell destination enum if needed.
4. Integration test hard on Mac: launch app via notification response simulation if feasible; else manual checklist.

### 3.2 userInfo schema (frozen)

```
connection_id: String
workspace_id: String
tab_id: String
pane_id: String
```

### 3.3 Copy

- blocked: "{identity} needs you" / body location + connection short label
- done: "{identity} is done"

### 3.4 Errors

Log + Settings banner when authorization denied; request throws logged.

## 4. Files

- `BessieNotifications.swift`
- `NotificationPlanning.swift` (body copy may include connection)
- `BessieApp.swift` / `ProductSurfaces.swift` routing
- Tests: planner still unit-tested; add route resolve tests with multi-connection fixtures if pure

## 5. Milestones

M1 — Schema + copy unit tests
M2 — Cold/warm route reliability
M3 — Settings auth error UX
M4 — Mac matrix multi-connection click

## 6. Acceptance

1. From background, click blocked notification → correct pane focused on correct connection.
2. Cold launch from notification works or documented residual with ticket — **prefer works**.
3. No menu bar code.
4. check.sh green.

## 7. Non-goals

NSStatusItem, Quiet 1h, categories/actions on notifications.

## 8. Pause

If cold-start requires moving fleet ownership out of ConnectView (large refactor) → spike options for Jordan before multi-day rewrite. Minimal fix preferred.
