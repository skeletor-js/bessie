# Standalone Attention surface

**Status:** Removed from V1; absorbed into The Herd
**Decision:** Jordan, 2026-08-03
**Product area:** The Herd / Needs you
**Execution:** [`../plans/2026-08-02-attention-queue-and-resolution.md`](../plans/2026-08-02-attention-queue-and-resolution.md) and [`../plans/2026-08-03-v1-acceptance-remediation.md`](../plans/2026-08-03-v1-acceptance-remediation.md) §7

## Outcome

V1 does not ship a separate Attention destination. All useful needs-you behavior lives in The Herd:

- blocked-first All view;
- blocked-only **Needs you** filter and count;
- strong blocked state treatment;
- exact Open pane routing;
- next-needs-you command;
- Herd/Zen blocked cues;
- coherent blocked notifications.

## Why

Herdr currently exposes `blocked` as an agent state, not a durable attention-item object. A separate inbox duplicates a filtered Herd and creates pressure to invent Bessie-owned history, age, snooze, dismissal, seen, and resolution state.

Removing the surface is simpler and more faithful to Herdr.

## V1 removal contract

- Remove the sidebar destination and `AttentionSurface`.
- Remove duplicate Attention models/builders/fleet arrays/tests.
- Remove Attention as a generic notification failure destination.
- Rename next-attention language to next needs you.
- Persist no Attention records.
- Keep done in Herd and optional completion notifications, not Needs you.

## Future re-entry condition

Reconsider a dedicated Attention product only after Herdr exposes durable typed attention objects with identity, reason/type, timestamps, lifecycle, and safe typed resolution actions.
