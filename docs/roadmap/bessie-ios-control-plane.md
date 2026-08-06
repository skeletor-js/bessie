# Bessie iOS — remote control plane

**Status:** Approved direction — **first post-V1 ship**  
**Roadmap horizon:** Post-V1 (starts only after Mac V1 launch / K gate + explicit release)  
**Product area:** Mobile remote Herdr client  
**Implementation approval:** Plan ready; **execution gated** on Mac V1 launch  
**Implementation plan (ce-plan):** [`../plans/2026-08-03-bessie-ios-control-plane.md`](../plans/2026-08-03-bessie-ios-control-plane.md)  
**Goal contract:** [`../../GOAL-ios-v1-control-plane.md`](../../GOAL-ios-v1-control-plane.md)  
**Priority:** **P0 after Mac V1** — first feature train once V1 is released. Ahead of Shepherd and other Proposed/Deferred Mac extras unless Jordan reorders.

## Outcome

Ship Bessie on iPhone/iPad as a **remote control plane** for live Herdr:

- All hosts in one main view (Tailscale-friendly)
- **Mosh** host shell (Moshi-class resume)
- Herd with Needs you → open exact pane
- Create / focus / rename / close workspaces, tabs, panes
- **One** focused real terminal at a time (no tiling)
- Always remote; never on-device Herdr
- Optional: open/initialize existing Mac project recipes

## Why this exists

Mac V1 is the workshop. Away from the desk, users still need to see who needs them, shape the session, and answer in a real terminal without stopping Herdr. iOS is that pocket client — not a port of the full Mac chrome.

## First useful slice (execution milestones)

See ce-plan M0–M5 (M6 Projects open/init optional):

1. Scaffold + multiplatform Core  
2. Mosh connect  
3. Herdr API + structure mutations  
4. One Herdr pane terminal  
5. Multi-host + Herd + Attention UI  
6. Lifecycle harden  

## Explicitly not this item

- Mac V1 work (L/K)  
- Bundled Herdr on iPhone  
- File viewer / Follow on iOS v1  
- Project authoring on phone  
- Tiling  
- Shepherd  

## Dependencies

- Mac V1 released (or Jordan explicitly green-lights early spike)  
- Live remote Herdr hosts (user already runs Herdr remotely)  
- Public Herdr JSON API + terminal session bridge (no private bincode)  
- iOS Mosh + SSH embed; libghostty-class terminal surface  

## Graduation / start criteria

**Do not start implementation goal loops until:**

1. Mac V1 L + K complete and Jordan has approved the Mac V1 release (or Jordan explicitly says “start iOS now”), and  
2. Goal contract is used: `GOAL-ios-v1-control-plane.md`.

## Related

- Mac connection UX (J) — multi-host labels and SSH lessons inform iOS host profiles  
- Mac Herd with Needs you — consolidated builder reused in Core  
- Shepherd — separate post-V1 proposal; not a dependency  
