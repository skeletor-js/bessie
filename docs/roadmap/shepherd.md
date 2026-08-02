# Shepherd

**Status:** Proposed
**Roadmap horizon:** Post-V1 — after bundled runtime, Native Projects, and the focused Herdr GUI pass hands-on acceptance
**Product area:** Herd dispatch (Bessie-shipped specialized agent capability)
**Implementation approval:** Not granted by this document
**Implementation plan (draft):** [`../plans/2026-08-02-shepherd.md`](../plans/2026-08-02-shepherd.md)
**Related plans:**
- [`new-agent-launch-flow.md`](new-agent-launch-flow.md) — graphical launch sheet; Shepherd is NL handoff into the same Herdr launch substrate
- [`broadcast.md`](broadcast.md) — multi-target send; out of Shepherd v1 (single dispatch)
- [`attention-queue-and-resolution.md`](attention-queue-and-resolution.md) — owns alerts / needs-you; Shepherd does **not**
- [`cross-agent-plans.md`](cross-agent-plans.md) — normalized in-flight work; may feed richer status later
- [`agent-integrations-and-identity.md`](agent-integrations-and-identity.md) — catalog honesty and provenance
- [`richer-herd-dashboard.md`](richer-herd-dashboard.md) — full Herd UI; Shepherd routes into panes, does not replace the dashboard
- [`activity-timeline.md`](activity-timeline.md) — deeper history; not required for Shepherd v1
- Native Projects — optional later placement target (“open in project workspace”); not required for M1

## Outcome

Bessie ships **Shepherd**: a **tiny, invoke-only dispatcher** specialized for Herdr and Bessie.

The user can:

1. open a **small lower-right chat** branded **Shepherd**,
2. hand off a task in natural language (BYOK model interprets intent),
3. have Shepherd **immediately start a new real coding agent** using the user’s **default agent** and **default spawn location** preferences (NL can override agent kind only),
4. **get out of the way** — confirm via **Open pane**, not a pre-flight dialog — so the work lives in an ordinary Herdr pane.

**Status / “what’s going on?” is out of Shepherd v1** (later milestone). v1 is dispatch + Open pane only.

Shepherd is **not** a general-purpose coding agent, not an always-on supervisor, and not the attention system.

> **Shepherd is the dog whistle, not the dog:** call the herd and leave. (Asking where the sheep went is a later whistle.)

## Why this exists

Multi-agent Herdr sessions already have the hard parts: real panes, real agents, survival after quit, graphical Herd and attention. What remains expensive is **human routing and recall**:

- Which agent should take this?
- Where did I put that work?
- What is that thread doing while I was gone?

Generic side-chat agents solve the wrong problem (another coder). Shepherd solves **dispatch** for a herd the user already runs (status-on-ask is later).

Shipping it **with Bessie** matters because the job is fluency in **this** app and runtime — manifest kinds, placements, snapshot state, pane focus — not a portable “computer use” agent.

## Product thesis

| Role | Owner |
| --- | --- |
| Labor (implement, edit, test, commit) | Real Herdr agents (Claude Code, Codex, Amp, Hermes, Grok, shells, …) |
| Alerts / needs-you | Bessie Attention (and related surfaces) |
| Handoff (v1) / “where did it go?” (later) | **Shepherd** (invoke-only) |
| Live sessions, panes, processes | **Herdr** |

Shepherd’s intelligence is **placement and briefing**, not implementation.

## Product principles

### 1. Dispatch layer, not worker

Shepherd routes work to real agents and stays out of the work itself. It must refuse general coding, repo Q&A-as-labor, and “I’ll just fix that in this chat.”

### 2. Invoke-only, single invocations

No persistent Shepherd agent session, no standing meta-thread, no background Shepherd brain. Each open of the corner chat is one or more **short invocations**. After dispatch, the interesting surface is the **worker pane**.

### 3. v1 is handoff, not recall

Shepherd v1 does **not** answer status questions. Optional later: status-on-ask from live Herdr + a thin handoff ledger. Until then, the user uses Herd/Attention/panes for “what’s going on?”

### 4. Default agent and default spawn location are configuration

User sets (1) preferred spawn **kind** from the Herdr-supported catalog and (2) preferred **spawn location** (e.g. split-right from focus, new tab). Overrides of kind are **natural language** in the invoke (“use Codex for this”), not a mandatory picker chrome on every send.

### 5. Corner whistle, not home base

UI is a **small lower-right chat**. It must remain dismissible and secondary. If Shepherd becomes the main window, the product has failed its identity.

### 6. Attention stays separate

Shepherd does **not** own alerts, push, or needs-you routing. Invoke-only: no Shepherd notification channel in v1.

### 7. Always Herdr underneath

Every spawn, focus, and prompt send goes through existing public Herdr paths (`HerdrProcessLauncher` / `agent.start`, pane input, snapshot). Quitting Bessie never stops dispatched agents. No shadow runtime of workers inside Shepherd.

### 8. Honest capability

Only offer agent kinds that are available on the connected runtime’s manifest + PATH (same honesty as New pane). Missing default → clear setup path, not a silent fallback to a different product.

### 9. Local-first, remote-honest

First release targets the ordinary connected session Bessie already supports. Remote/multi-host unity is not a Shepherd v1 requirement; degrade with explicit copy when placement or status cannot be resolved.

### 10. YAGNI on orchestration theater

No multi-agent fan-out, no interrupt-before-send fleets, no use-case auto-router, no chief-of-staff loops in the first ship. Those are later milestones with separate approval.

## Primary user flows

### Flow A — Hand off a task

1. User opens Shepherd (menu/affordance; shortcut chosen at implementation to avoid macOS/Bessie conflicts).
2. Types a task in plain language (optional: “use Codex…”).
3. BYOK model (OpenAI or xAI) interprets intent → dispatch (or refuse/clarify).
4. Shepherd resolves **kind** = NL override if available, else **default agent**; **placement** = user **default spawn location** setting.
5. **Immediate** spawn of a **new** agent: place pane, `agent.start`, deliver **first prompt** after readiness rules — **no confirm dialog**.
6. Brief result line + **Open pane**; corner chat can be dismissed; work continues in Herdr.
7. v1 **never** targets or reuses an existing agent pane (no “tell the existing …” path).

### Flow B — Status on ask

**Out of Shepherd v1.** Later milestone; use Herd / panes until then.

### Flow C — Defaults setup

1. User opens Settings (or first-run Shepherd gate).
2. Sets **default agent** (catalog) and **default spawn location**.
3. Configures **BYOK** credentials/provider for Shepherd intent.
4. If preferred agent missing, Bessie shows unavailable reason and links to install/PATH/Trouble — does not pretend Shepherd can substitute labor.

### Flow D — Explicit refusal

1. User asks Shepherd to implement code, browse the web, or act as a general assistant **in the corner**.
2. Shepherd refuses labor-in-chat and offers to **dispatch** that request to the default agent instead (or asks for a dispatchable brief).

## Surface model

### Corner chat

- Compact floating panel, lower-right of the main window (exact metrics = design)
- Single composer + short transcript **of this invoke** (ephemeral UI; not a second session product)
- Primary actions: Send, Open last pane, Dismiss
- Empty state explains: hand off work or ask status — not “chat with Bessie”

### Settings

- Default agent kind (catalog-backed)
- Default spawn location (user-selectable; e.g. split-right from focused pane, new tab in current workspace)
- BYOK provider/credentials for Shepherd intent (**OpenAI** or **xAI** only in v1)
- Optional: enable/disable Shepherd; keyboard shortcut (implementation picks a non-conflicting binding)

### Not in v1 chrome

- Agent picker control on every message (NL override only)
- Persistent Shepherd history browser
- Shepherd-owned notification center
- Multi-select broadcast targets
- Existing-agent / reuse controls
- Status query UI

## Staged roadmap

Each milestone is independently valuable.

### Milestone 0 — Evidence and contract spike

Prove before UI promises:

1. **First-prompt path** after `agent.start`: reuse or extend the same readiness discipline as process launch (no arbitrary sleeps as the contract; bounded busy retry already exists for fresh panes). Document when `pane.send_input` / keys may carry the user brief.
2. **Intent shape**: structured result of an invoke — `dispatch | refuse | clarify` (no `status` in v1; no existing-target in v1) — with no general tool belt; BYOK model must be constrained to this schema.
3. **BYOK path (locked providers: OpenAI, xAI):** Keychain/storage shape, failure copy when key missing/invalid, privacy of briefs sent to the provider.
4. **Spawn location setting**: enumerate supported placement values and map each onto existing `NewProcessPlacement` / pane APIs.
5. Disposable probe: harness that dispatches one brief end-to-end without polished chrome.

**Shepherd brain (locked 2026-08-02):** **BYOK model from day one** for intent — **OpenAI and xAI only** to start. Not templates-first, not on-device-first. Still **not** a general agent runtime — model output is schema-bound ops only.

**Spawn policy (locked):** **new agents only** in v1. No reuse / “tell the existing …” path until a later approved milestone.

**Exit:** written spike report under `docs/reports/`; first-prompt path demoed or blocked with honest gap; intent schema frozen for v1; OpenAI + xAI key storage approach chosen.

### Milestone 1 — Preferences

- Settings: default Shepherd **agent** (live catalog)
- Settings: default **spawn location**
- Settings: **BYOK** provider/key for Shepherd (**OpenAI** or **xAI**)
- Persist in Bessie preferences (not Herdr); secrets in Keychain
- Unavailable default agent surfaced honestly
- No chat required

**Exit:** user can set preferred agent + spawn location + OpenAI/xAI key; catalog availability matches New pane.

### Milestone 2 — Corner chat shell + BYOK intent (no spawn yet optional)

- Lower-right **Shepherd** panel + non-conflicting shortcut
- BYOK intent (OpenAI/xAI) → `dispatch | refuse | clarify` only (status and existing-target intents refused or “not in v1”)
- Wire preview of resolved kind + placement in the result line once dispatch exists
- Can ship combined with M3 if thinner

**Exit:** user can open Shepherd, configure OpenAI or xAI, and get honest refuse/clarify without a fake agent runtime.

### Milestone 3 — Dispatch invoke

- Immediate place + `agent.start` + first prompt under readiness rules
- Default kind + default spawn location; NL kind override
- **Always new agent only** (no existing-pane targeting)
- Result line + **Open pane**; no confirm dialog
- Quit Bessie leaves worker running

**Exit:** “add a smoke test for login” produces a real working agent pane with that brief.

### Milestone 4 — NL kind override + refusal polish

- “use Codex for this” selects kind when available
- Clear errors when override missing on PATH
- Refusal copy locked so Shepherd never roleplays as the coder
- Requests to reuse existing agents → honest “not in v1; spawning new” or refuse/clarify (product pick in implementation: spawn-new-anyway vs ask to rephrase as a new task)

**Exit:** defaults stay simple; language covers kind override without a picker.

### Milestone 5 — Hardening

- Partial failure: shell created but agent start fails (retain shell, report — match existing launcher behavior)
- Disconnected / no default / bad BYOK states
- Accessibility, keyboard, reduced-motion for the corner panel
- Tests for intent schema, kind selection, launch request construction

**Exit:** failure modes are boring and honest; `./scripts/check.sh` and Mac verify paths cover non-UI core.

### Milestone 6 — Status on ask (separate approval; was deferred from v1)

- “What’s going on with X?” from live projection (+ optional thin ledger)
- Still invoke-only; still not Attention

### Milestone 7 — Use-case routing (separate approval)

- Optional router suggests agent kind by task class
- Still single dispatch; still no Shepherd labor
- User default remains fallback

### Later (explicitly not scheduled here)

- Multi-agent fan-out / map-reduce (Puck-style)
- Broadcast integration
- Shepherd-driven interrupts or approvals
- Persistent Shepherd sessions or home-base meta-agent
- Shepherd-owned push/alerts
- Shipping a **coding** agent binary inside Bessie
- Replacing New pane / Herd UI

## Source-of-truth and ownership

| Fact or action | Owner | Bessie / Shepherd behavior |
| --- | --- | --- |
| Workspaces, tabs, panes, agents, processes | Herdr | Public API + snapshot only |
| Agent catalog / kinds | Herdr manifests + PATH availability | Same as New pane |
| Default preferred kind + spawn location | Bessie preferences | Shepherd reads; user edits in Settings |
| BYOK credentials for intent | Bessie Keychain + provider choice **OpenAI \| xAI** | Not Herdr; never log keys |
| Handoff ledger | Deferred with status (M6); optional later | Not required for dispatch-only v1 |
| Invoke transcript chrome | Bessie UI, ephemeral | Not durable session truth |
| First prompt content | User brief via Shepherd → pane input | After readiness; no fake “agent accepted” |
| Alerts / blocked push | Attention + notification plans | Shepherd invoke-only |
| Coding labor | Target agent in pane | Shepherd refuses to do it |
| Project recipes | Native Projects | Optional later placement; not required |

## Safety and trust

- No silent multi-target sends in v1 (single dispatch).
- No scraped Allow/Deny or approval automation.
- Do not inject full terminal buffers into a cloud model without an explicit later privacy design; prefer structured projection fields.
- Ledger must not store secrets from briefs beyond what is needed for short status matching; define retention (e.g. in-memory + optional short local cap).
- Dispatch is a deliberate side effect: show kind + placement in the confirmation line.
- Connection switch / quit invalidates in-flight invoke orchestration only; never kills Herdr workers.
- Shepherd must not present itself as Herdr or as the coding agent.

## Local vs remote

| Capability | First release | Remote / degraded |
| --- | --- | --- |
| Default agent pref | Yes | Yes (catalog from connected runtime) |
| Status from projection | Yes | Yes if snapshot exists |
| Dispatch spawn | Yes on supported connection | Same public APIs when connection supports agent.start |
| pane.read deep status | Only if already safe/local policy allows | Explicit limitation |
| Multi-host herd unify | No | No |

## Explicitly out of scope (v1)

- Persistent Shepherd agent sessions or daemon
- Shepherd notifications / alert ownership
- General-purpose tools (browser, arbitrary shell as Shepherd, MCP marketplace)
- Coding agent runtime forked into Bessie
- Broadcast, fan-out, auto-router (until M6+)
- Graphical approval resolution
- Replacing Attention, Herd dashboard, or New pane

## Principal risks

| Risk | Mitigation |
| --- | --- |
| Identity slide into “Bessie chat app” | Corner UI + refuse labor + invoke-only principle |
| First prompt races / lost briefs | M0 readiness contract; reuse launcher busy retry; partial failure copy |
| Wrong pane after restart | v1 has no ledger/status; Open pane only for this invoke’s result |
| Model does work in the corner | Hard tool allowlist: dispatch/refuse/clarify only |
| Default agent missing | Setup honesty; block dispatch with fix path |
| Scope creep to Puck-like home base | M6+ gated; v1 success = handoff + Open pane |
| Privacy (briefs to cloud) | BYOK required; minimal structured context; never log keys |

## Open questions (remaining)

Product questions from the first pass are **closed** (see locked table). Engineering/M0 still owns:

1. **Keychain/storage shape** for OpenAI and xAI API keys; failure copy when missing/invalid.
2. **Exact spawn-location enum** values exposed in Settings and their Herdr mappings.
3. **Keyboard shortcut** final binding after audit of Bessie + macOS conflicts.
4. **First-prompt readiness** contract details on live Herdr 0.7.5 / protocol 17.
5. **Reuse-request UX:** when user asks to talk to an existing agent, spawn-new-anyway vs clear “not supported yet” (pick one in M0/M4; default lean: honest not-supported + offer new dispatch).

## Graduation criteria

Before **Approved** implementation:

1. M0 spike report checked in (`docs/reports/` or implementation plan appendix)
2. Principles above reconfirmed (especially invoke-only, no alerts, no labor, no status-in-v1, **new-only spawn**, **OpenAI/xAI only**)
3. Acceptance scenarios below demoable on a harness or thin UI
4. Jordan grants implementation approval; `docs/plans/2026-08-02-shepherd.md` (or successor) marked approved
5. Sequence remains **post-V1** unless Jordan explicitly reprioritizes

## Acceptance scenarios

1. Default agent + spawn location set → dispatch creates real agent pane with brief; agent appears in Herd.
2. Quit Bessie after dispatch → worker still running.
3. “use {other kind} for this” with other kind installed → that kind starts, not the default.
4. Override kind missing → clear error; no wrong agent silent substitute.
5. Ask Shepherd to write code in the corner → refusal + offer to dispatch.
6. No default agent / no OpenAI|xAI key → dispatch blocked with Settings path.
7. Disconnected Herdr → Shepherd explains connection requirement; no fake success.
8. Agent start fails after shell create → shell retained, error shown (parity with New pane launcher).
9. Status question in v1 → honest “not in Shepherd yet” (or clarify to dispatch), not a fake briefing.
10. “Tell the existing Codex…” in v1 → not supported (honest message); does not silently attach to a live pane.
11. Open pane from result focuses the **newly** dispatched pane.

## Success criteria

- Users describe Shepherd as **“I throw work at the herd from the corner”**, not “Bessie’s chatbot.”
- Dispatch is faster than opening New pane + typing the same brief for the common case.
- Herdr remains the place work lives; Attention remains the place alerts live.
- Status-on-ask and smart routing can wait without blocking the whistle.
- V1 Bessie release train is not delayed by Shepherd unless explicitly rescheduled.

## Decisions locked by product exploration (2026-08-02)

| Decision | Choice |
| --- | --- |
| Name | **Shepherd** (lean into the name in UI) |
| Role | Dispatch layer — routes work, does not implement |
| Session model | **Single invocations**, not persistent Shepherd sessions |
| Alerts | **Invoke-only**; Attention stays separate |
| UI | Tiny **lower-right** chat |
| Brain | **BYOK model from day one** for intent (schema-bound) |
| BYOK providers (v1) | **OpenAI** and **xAI** only |
| Default agent | User preference; catalog-backed |
| Default spawn location | **User setting** (not a single hard-coded placement) |
| Override kind | **Natural language only** in v1 (no mandatory picker) |
| Confirm before start | **No** — immediate dispatch; Open pane feedback |
| Spawn vs reuse | **New only** in v1 — no existing-agent targeting |
| Status on ask | **Out of v1** (later milestone) |
| Shortcut | Implementation picks **non-conflicting** binding |
| Shipped with Bessie | Yes — specialized Herdr/Bessie orchestrator capability |
| Use-case multi-agent routing | **Later**, separate approval |
| General-purpose agent | **No** |

## Relationship to “ship our own agent”

“Ship our own agent” means:

- Bessie includes a **first-class Shepherd capability** (UI + invoke pipeline + herd-fluent behavior),
- specialized **only** for dispatch and status over Herdr/Bessie,

It does **not** mean:

- Bessie replaces Claude/Codex/Amp/Hermes,
- Bessie vendors a coding model as the worker,
- Bessie becomes an agent cloud.

Workers remain ordinary Herdr-started processes from the supported catalog.
