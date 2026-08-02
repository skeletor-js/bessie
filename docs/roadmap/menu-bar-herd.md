# Menu-bar Herd and Mac push notifications

**Status:** Proposed  
**Roadmap horizon:** Post-V1, after the focused Herdr GUI passes hands-on acceptance  
**Product area:** macOS menu bar, notifications, ambient supervision  
**Implementation approval:** Not granted by this document  
**Related plans:**
- [`attention-queue-and-resolution.md`](attention-queue-and-resolution.md) — in-window triage; menu bar is the away-from-window surface
- [`activity-timeline.md`](activity-timeline.md) — deeper history; digests already partially exist in-app and are **not** the first menu-bar milestone
- [`richer-herd-dashboard.md`](richer-herd-dashboard.md) — full window Herd
- Design assets: workstream `source-material/macos-icons/bessie-menubar*.png`

## Outcome

Keep the herd **visible and lightly actionable** when the main Bessie window is closed, minimized, or in the background—using a native **menu bar extra** and **polished Mac push notifications** that route to the exact pane.

This is Bessie’s answer to community remote-attention tools (Collie, Herdi) **on the Mac desktop**. Phone PWA is **out of scope**; a native iOS client is a later product, not a web shell.

## Why this exists

People leave the full window while agents run. They still need:

- a glanceable blocked / needs-you signal
- a short list of urgent agents
- one click back to the exact live pane
- notifications that do not lie about ownership or stop Herdr when Bessie quits

Native notifications already exist in the foundation preview. The gap is a real **menu-bar Herd** and tighter push routing/policy—not a second attention product.

## Product thesis

Ambient supervision should feel like a **Mac status item for the herd**, not a mini IDE and not a remote shell:

> Counts → top urgent agents → open exact pane or main window → optional quiet controls.

Approve/reply/interrupt that already work in the main app remain authoritative there. The menu bar **routes and surfaces**; it does not invent a second resolution model.

## Product principles

### 1. Glanceable over complete

At most a handful of agents. Full triage stays in the main window.

### 2. Exact-pane routing

Every agent row and notification deep-links to the same Herdr pane the main app would focus.

### 3. Herdr keeps running

Menu-bar presence must never imply that quitting Bessie stops Herdr. Copy and lifecycle must match the survival rule.

### 4. Notification and tray stay coherent

One urgency model shared with Herd / attention (blocked-first, done-unseen if that concept ships). No double-noise without user control.

### 5. Local connection first

First release assumes the existing local (or already-supported) Bessie↔Herdr connection. Multi-host unity is not this plan’s job.

### 6. No phone PWA

Explicit product decision (2026-08-01): do not build Collie-style mobile web. Native iOS is separate and later.

## Primary user flows

### Flow A — Background watch

1. User leaves Bessie in background with menu-bar extra enabled.
2. Status item shows blocked count (and optionally done-unseen).
3. Agent becomes blocked → push notification (per policy) and tray count updates.
4. User clicks notification or tray row → Bessie activates and focuses that pane.

### Flow B — Tray triage

1. Open menu-bar panel.
2. See up to five agents ordered by urgency (blocked → done-unseen → working…).
3. Click agent → focus pane.
4. Optional: New agent (opens main window flow), Quiet for one hour, Open Bessie.

### Flow C — Quiet

1. User enables Quiet / pause notifications for a defined period from tray or Settings.
2. Tray may still show counts; pushes suppress per policy.
3. Quiet end restores previous policy.

## Surface model

### Status item

- Bessie menu-bar glyph (existing design assets)
- Optional count badge or compact numeric subtitle for blocked (design system decision)
- Click → panel; option-click or secondary actions as needed

### Menu-bar panel

- Connection/health one-liner when degraded (reuse Trouble vocabulary, do not fork diagnostics)
- Counts: Needs you / Done (if unseen semantics exist) / Working summary
- Agent rows (≤5): name/label, state, workspace hint, age if blocked
- Actions: Open pane / Open Bessie, New agent, Quiet…
- Footer: Settings deep link, Quit Bessie (with survival-clear copy if needed)

### Push notifications

- Build on existing blocked/done notification authorization and policy
- Title/body: agent label + short reason when Herdr provides state (not scraped prose)
- Action: open exact pane
- Respect Quiet, focus modes where feasible, and user notification settings
- Do not spam on every Working tick

## Staged roadmap

### Milestone 0 — Lifecycle and policy spike

- Confirm app lifecycle: accessory vs regular activation policy when last window closes
- Map current notification emission paths and Herd ordering
- Define done-unseen: implement minimal client-local seen state **or** ship tray without done-unseen until Herd shares semantics
- Document what happens on quit vs hide vs crash
- Remote/unsupported connection behavior

**Exit:** written lifecycle matrix + recommendation for LSUIElement / `NSApplication.activationPolicy` behavior; Jordan can accept windowless menu-bar mode or require a window.

### Milestone 1 — Status item + panel

- Menu-bar extra with counts
- ≤5 urgent agents from existing projections
- Click through to exact pane / main window
- New agent and Open Bessie
- Clear empty and disconnected states

**Exit:** usable ambient Herd without depending on push polish.

### Milestone 2 — Push notification polish

- Unified policy with tray
- Exact-pane deep links verified cold and warm start
- Quiet for one hour (or Settings-defined)
- Deduping so tray + banner do not feel like two products screaming
- Authorization repair path via Settings / Trouble

**Exit:** user can leave the Mac, get a trustworthy blocked ping, and land on the right pane.

### Milestone 3 — Refinement

- Working snippet line if cheap and non-scraped
- Configurable count badges
- Optional launch-at-login coherence with Bessie settings (no silent Herdr kill on login items)
- Accessibility for panel and status item

## Source-of-truth and ownership

| Fact or action | Owner | Bessie behavior |
| --- | --- | --- |
| Agent state, pane IDs, session liveness | Herdr | Existing snapshot/event projections |
| Menu-bar UI, quiet timer, local seen flags | Bessie | Transient / app preferences only |
| Notification authorization | macOS | Request and explain; never fake delivery |
| Pane focus / window activation | Bessie → Herdr focus APIs | Same path as main window |
| Killing Herdr on Quit | Forbidden | Quit Bessie ≠ stop Herdr |

## Local vs remote

| Capability | First release | Later |
| --- | --- | --- |
| Tray for active local connection | Yes | — |
| Push for blocked/done on that connection | Yes | — |
| Multi-session host picker in tray | No | Session manager plan |
| iOS / PWA | No | Native iOS product |

## Explicitly out of scope

- Phone PWA / Tailscale web shell
- Telegram or third-party push bridges as product dependencies
- Full attention queue, structured approve-all, or typed approvals in the tray
- Activity digest redesign (in-app digests already cover part of this; timeline plan owns deeper history)
- Menu-bar terminal or agent CDP browser
- Implying Bessie is required for Herdr to keep running

## Principal risks

- **Noise:** duplicate tray + notification → Quiet and shared urgency model
- **Zombie expectations:** users think quitting the menu-bar app stops agents → copy and QA
- **Windowless lifecycle bugs:** SwiftUI/AppKit activation policy footguns → Milestone 0
- **Stale projections:** background app throttled → validate event/snapshot refresh while backgrounded
- **Security:** menu bar must not expose secret prompt contents in banners

## Open questions

1. When the last window closes, does Bessie remain running as menu-bar-only (preferred for ambient watch) or quit?
2. Are done-unseen counts required for M1, or blocked-only first?
3. Default launch: menu bar always on, or opt-in in Settings?
4. Should Quiet live only in tray or also mirror notification settings?
5. Do we show agents from all workspaces or only the last focused workspace in M1?

## Graduation criteria

Before **Approved** implementation:

1. Milestone 0 lifecycle decision signed off
2. Notification deep-link cold-start path specified
3. Acceptance scenarios below agreed
4. `docs/plans/` implementation plan written after Jordan’s approval

## Acceptance scenarios

1. Window in background, agent blocks → count updates; notification optional per policy
2. Click notification → correct pane focused, app activated
3. Click tray agent row → same
4. Quiet one hour → no pushes; counts may remain
5. Quit Bessie from tray → Herdr session and panes still alive; ordinary `herdr` attach works
6. Disconnected Herdr → honest empty/error in tray; no fake agents
7. Five-plus blocked agents → panel shows top five with overflow affordance to Open Bessie
8. Reduce Motion / VoiceOver usable on panel
9. Authorization denied → Settings/Trouble path, no crash loops

## Success criteria

- Users keep Bessie around as ambient herd awareness without parking the full window
- Push feels like the same product as in-window attention, not a second brain
- No regression to Herdr survival or terminal fidelity
- No pressure to ship mobile web

## Decisions locked by this proposal

- **Ship Mac menu bar + push polish** as the away-from-window bet
- **No phone PWA**; native iOS is later and separate
- **Do not rebuild** in-app digests/approve/reply/interrupt here—route into existing surfaces
- Community tools (Collie, herdr-remote) are competitive inspiration, not dependencies
