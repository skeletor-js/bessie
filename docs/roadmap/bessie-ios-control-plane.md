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

- Native SwiftUI/UIKit app sharing pure-Swift `BessieCore` with Mac
- Cross-host Inbox for Needs You, Working, Done, Idle, conditional Unknown, and Shells (Tailscale-friendly)
- Persistent mobile dock with Pinned, Snoozed, Hierarchy, Settings, and detached Command
- **SSH** host shell with foreground reconnect; Mosh deferred beyond iOS V1
- Herd with Needs you → open exact pane
- Create / focus / rename / close workspaces, tabs, panes
- **One** focused real terminal at a time (no tiling)
- Always remote; never on-device Herdr
- End-to-end encrypted Needs You delivery from a user-owned Mac/VPS watcher through the assumed-available Bessie Cloudflare → APNs relay, including while Bessie is suspended; foreground local notifications remain the fallback
- Relay delivery is included at no user charge initially. Product packaging may add a paid entitlement later, so V1 must not promise perpetual free service.

## Why this exists

Mac V1 is the workshop. Away from the desk, users still need to see who needs them, shape the session, and answer in a real terminal without stopping Herdr. iOS is that pocket client — not a port of the full Mac chrome.

## First useful slice (execution milestones)

See ce-plan M0–M5:

1. Scaffold + multiplatform Core  
2. SSH foundation + first-run connection  
3. Herdr API + structure mutations  
4. One Herdr pane terminal  
5. Cross-host Inbox + settled mobile chrome  
6. Lifecycle harden + E2EE watcher/relay/APNs notification delivery  

## Explicitly not this item

- Mac V1 work (L/K)  
- Bundled Herdr on iPhone  
- File viewer / Follow on iOS v1  
- Project authoring on phone  
- Project open/init or management on phone  
- Mosh transport in iOS V1  
- Plaintext notification relay, relay-held decryption keys, event retention, or readable Herdr content in APNs  
- Tiling  
- Shepherd  

## Dependencies

- Mac V1 released (or Jordan explicitly green-lights early spike)  
- Live remote Herdr hosts (user already runs Herdr remotely)  
- Public Herdr JSON API + terminal session bridge (no private bincode)  
- iOS SSH embed; libghostty-class terminal surface  
- Assumed-available Bessie Cloudflare Worker → APNs relay plus a user-owned Mac/VPS watcher that encrypts before transmission  

## Graduation / start criteria

**Do not start implementation goal loops until:**

1. Mac V1 L + K complete and Jordan has approved the Mac V1 release (or Jordan explicitly says “start iOS now”), and  
2. Goal contract is used: `GOAL-ios-v1-control-plane.md`.

## Related

- Mac connection UX (J) — multi-host labels and SSH lessons inform iOS host profiles  
- Mac Herd with Needs you — consolidated builder reused in Core  
- Shepherd — separate post-V1 proposal; not a dependency  
