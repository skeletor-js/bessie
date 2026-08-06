# Standalone Attention surface — folded into The Herd

**Date:** 2026-08-02
**Superseded:** 2026-08-03 by Jordan's product decision
**Status:** Remove from V1; functionality absorbed into The Herd
**V1 slice:** M correction over integrated slice E
**Canonical execution:** [`2026-08-03-v1-acceptance-remediation.md`](2026-08-03-v1-acceptance-remediation.md) §7

## Decision

Bessie V1 has no standalone Attention destination, list, route, or persisted Attention model.

Herdr 0.7.5 exposes `blocked` as an authoritative agent status, not a durable attention-item object. The useful behavior therefore belongs in The Herd:

- blocked-first ordering in All;
- **Needs you** filter and count;
- strongest blocked card treatment;
- exact **Open pane** action;
- next-needs-you command;
- sidebar Herd cue and Zen blocked cue;
- blocked notification policy and direct pane routing.

This removes a duplicate product surface and avoids inventing Resolved, history, age, snooze, or dismissal semantics that Herdr does not own.

## Integrated baseline to remove

The earlier slice E implementation added:

- `AttentionItemModel` and `AttentionListBuilder`;
- `ConnectionFleetViewModel.attentionAgents`;
- `AttentionSurface` and an Attention navigation destination;
- `attentionFallback` notification routing;
- blocked + done tests and next-attention terminology.

Those are historical implementation facts, not the accepted V1 contract.

## Required correction

1. Keep/rename a shared Core `requiresUserAction` predicate that is true only for `.blocked`.
2. Make `HerdListBuilder` the sole agent-status/needs-you presentation builder.
3. Apply `ConnectionScope` before Herd cards, filter counts, and next-needs-you ordering.
4. Remove `AttentionItemModel`, `AttentionListBuilder`, `attentionAgents`, `AttentionSurface`, the sidebar destination, route enum case, and duplicate tests.
5. Rename user-facing next-attention commands/accessibility labels to **next needs you** or **open next agent that needs you**.
6. Make workspace/sidebar blocked counts consume the same predicate where counts remain useful.
7. Remove notification routing's generic Attention fallback. Missing/unavailable targets report an honest error and open Herd or connection recovery.
8. Keep completion notifications independent: `done` remains Herd state and optional notification policy, never Needs you.
9. Persist no attention records or compatibility stub.

## Acceptance

- No Attention destination appears in the sidebar, menus, shortcuts, command palette, onboarding, Settings, or deep-link fallback.
- All shows blocked agents first.
- Needs you includes connected authoritative blocked agents only and reports the correct scoped count.
- Open pane activates the owning host and exact workspace/tab/pane.
- Blocked→working/idle/done removes the agent from Needs you after Herdr reconciliation.
- Disconnected/stale agents do not count as live Needs you; host unavailability remains visible.
- Done remains visible in Herd and may notify according to policy.
- Test notifications and stale notification routes never mutate or open a hidden Attention surface.
- Core/App tests lock one shared predicate and no duplicate list model.

## Future re-entry condition

A dedicated Attention product may return only when Herdr exposes durable typed attention objects with event identity, reason/type, lifecycle, timestamps, and safe typed resolution actions. Until then, it is a Herd filter—not a product area.
