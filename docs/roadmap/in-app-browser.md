# In-app browser (URL preview)

**Status:** Proposed  
**Roadmap horizon:** Post-V1, after the focused Herdr GUI passes hands-on acceptance  
**Product area:** Workspace / agent preview surfaces  
**Implementation approval:** Not granted by this document  
**Related plans:**
- [`follow-files-and-agent-changes.md`](follow-files-and-agent-changes.md) — file/diff supervision; browser is for **URLs**, not source files
- [`herdr-plugins.md`](herdr-plugins.md) — community herdr-browser (Chromium + CDP) remains an optional Herdr plugin path for agent automation
- Terminal hyperlink behavior (foundation) — detection may feed “Open in Bessie browser”

## Outcome

Let someone supervising Herdr work **open a URL inside Bessie**—localhost previews, docs, dashboards, auth pages—beside the real agent terminal, without leaving the herd for a separate browser window unless they choose to.

This is a **human preview browser**, not an agent automation browser.

## Why this exists

Agents constantly produce or need URLs: `localhost` apps, docs, CI, OAuth, internal tools. Community demand for “browser in the herd” is strong ([herdr-browser](https://github.com/ogulcancelik/herdr-browser) embeds Chromium + CDP for *agents*). Bessie is already a GUI: the native fit is **WKWebView preview** for the human, while CDP automation can stay a Herdr plugin when needed.

Jordan’s product preference (2026-08-01): **definitely add an in-app browser option.**

## Product thesis

Bessie should make the common loop immediate:

> Agent prints or needs a URL → open preview in Bessie → interact lightly → return to the terminal → escalate to Safari/Chrome when the full browser is better.

It should **not** become Chrome, a second Electron, or the host for headless agent browsing.

## Product principles

### 1. Preview surface, not default OS browser

Bessie browser is optional and herd-contextual. System browser remains one click away.

### 2. Human-driven first

M1 is address bar + navigation + open-from-Bessie. Agent-driven CDP control is **out of scope** for this plan.

### 3. Real web content, explicit trust boundaries

Show page title, URL, security state (secure/insecure/localhost). Do not silently enable dangerous configurations. Separate from terminal content security.

### 4. Terminal stays real

Browser panes/tabs are **not** libghostty terminals and must never be presented as Herdr panes. Layout chrome must keep the distinction obvious.

### 5. Herdr does not own browser state

No durable Herdr session objects for cookies/tabs. Bessie may keep ephemeral preview state; quitting Bessie may discard it (document the choice).

### 6. Localhost is a first-class customer

Local dev servers are the primary win. File URLs and exotic schemes need an explicit allow/deny policy.

## Primary user flows

### Flow A — Open localhost while agent runs

1. Agent is serving or printing `http://127.0.0.1:3000`.
2. User opens **Browser** (command palette, menu, or link action).
3. Preview loads beside or as a non-terminal tab in the work area.
4. User clicks around; agent terminal remains available.
5. User chooses **Open in Safari** when needed.

### Flow B — Open link from terminal

1. Terminal shows a detected hyperlink (existing terminal capabilities where present).
2. User chooses **Open in Bessie** vs **Open in default browser**.
3. Bessie browser navigates to that URL with referrer/context = manual user action.

### Flow C — Simple navigation

1. Address bar edit, back/forward/reload/stop.
2. Error pages for DNS, TLS, connection refused (common for dead localhost).
3. Pop-ups: block by default or open in same preview with clear affordance—spike decides.

## Surface model

### Browser chrome

- Address bar with editable URL
- Back / forward / reload / stop
- Page title
- Security indicator
- **Open in system browser**
- **Close preview**
- Optional: home to blank or last URL this session

### Placement

Open product choices (pick in Milestone 0/design):

| Option | Pros | Cons |
| --- | --- | --- |
| A. Work-panel tab next to Follow files / agent detail | Keeps agent context | Narrow for many apps |
| B. Non-terminal split in the workspace grid | Side-by-side with pane | Must not look like a Herdr pane |
| C. Dedicated Bessie browser window | Full size | Leaves “one window” feel |

**Preferred starting point:** A or B with easy pop-out to system browser; avoid claiming Herdr pane IDs.

### What it is not

- Not a Herdr-owned pane
- Not a libghostty surface
- Not a CDP endpoint for agents in M1–M2
- Not a full tabstrip browser with extensions, profiles, and password manager parity

## Staged roadmap

### Milestone 0 — Technology and threat spike

- Confirm **WKWebView** (or chosen native WebKit host) integration path in the Swift app without breaking libghostty focus/keyboard routing
- Keyboard focus: when browser focused, terminal does not steal keys; when terminal focused, browser chrome shortcuts do not eat input incorrectly
- Navigation policy: which schemes allowed (`http`, `https`, `about`; deny `file` by default or prompt)
- Cookie/storage process pool: ephemeral vs persistent profile under Application Support
- Localhost mixed content and self-signed cert policy (dev-friendly but explicit)
- Relationship to terminal hyperlink detection APIs already in Ghostty/Bessie
- Accessibility and screenshot performance next to Metal terminals

**Exit:** ADR-style note in implementation plan: WebKit host, process model, scheme policy, focus rules; disposable demo loads localhost beside a live pane.

### Milestone 1 — Single preview surface

- Open Browser from command palette / menu
- Address bar + back/forward/reload
- Load http(s) and localhost
- Open in system browser
- Connection error states
- Distinct visual treatment from terminal panes
- No multi-tab yet if it delays the slice

**Exit:** user can preview a local dev server inside Bessie and return to the agent terminal without confusion about what is a real pane.

### Milestone 2 — Herd wiring

- Open link from terminal → Bessie browser (user gesture)
- Command palette: “Open URL…”
- Remember last URL per workspace or per agent (ephemeral is OK)
- Basic find-in-page if cheap
- Download policy: deny or hand to system browser (prefer handoff)

**Exit:** URL appearing in agent work has a one-gesture in-app path.

### Milestone 3 — Multi-preview polish

- Multiple previews or simple tab strip **inside Bessie browser only**
- Pop-out window option
- Zoom, reader-unrelated readability tweaks only if needed
- Settings: default open-in Bessie vs system for terminal links
- Hardening pass (popup, JS dialogs, permission prompts: camera/mic deny by default)

### Later / separate plans

- Agent CDP automation (leave to herdr-browser plugin or future explicit automation product)
- Shared profile with Safari
- Extensions
- Embedded browser *as* Herdr pane type via plugin protocol

## Source-of-truth and ownership

| Fact or action | Owner | Bessie behavior |
| --- | --- | --- |
| Herdr panes/terminals/agents | Herdr | Unchanged; browser is not a pane substitute |
| Web content rendering | WebKit / page origin | Standard web trust model |
| Preview chrome, last URL, open preferences | Bessie | App state only |
| Default OS browser handoff | macOS | `NSWorkspace` open |
| Agent browser automation | Out of scope / Herdr plugin | Not M1 |

## Safety and trust

- Prefer ephemeral data store unless user opts into persistence
- Deny microphone, camera, screen capture, and notifications from web content by default
- Clearly mark non-https non-localhost as less trusted
- Never auto-navigate the preview from untrusted terminal OSC without an explicit user gesture setting
- Do not pass Herdr auth cookies into random sites
- Isolate from file Follow surface—no silent `file://` open of workspace secrets
- JS `window.open` and downloads need explicit policy

## Local vs remote

Browser preview runs **in the local Bessie app**. It can open:

- localhost on the Mac
- public https URLs
- remote dev URLs if the Mac network can reach them

It does **not** automatically tunnel to a remote Herdr host’s localhost. Remote-agent localhost requires separate port-forward UX (future; do not pretend).

## Explicitly out of scope

- Chromium + CDP agent driver (herdr-browser’s job)
- Replacing Safari for general browsing
- Password manager, bookmarks sync, extensions
- Treating browser views as Herdr panes in snapshots
- Phone/web shell browser

## Principal risks

- **Identity bleed:** users think a web view is a Herdr terminal → visual and IA separation is mandatory
- **Focus/keyboard fights** with libghostty → Milestone 0
- **Security:** web content + agent secrets nearby → strict permissions and no auto-file open
- **Scope creep** toward full browser or IDE webview farm
- **Remote localhost confusion** → honest copy when URL is not reachable from the Mac

## Open questions

1. Default placement: work panel vs split vs window?
2. Ephemeral vs persistent cookies/localStorage for dev login flows?
3. Terminal links: default to Bessie browser, system browser, or ask once?
4. One global preview vs per-workspace preview state?
5. Do we ever allow `file://` for static preview inside the workspace root?

## Graduation criteria

Before **Approved** implementation:

1. Milestone 0 spike accepted (WebKit host + focus + scheme policy)
2. Placement and persistence decisions answered
3. Explicit rejection of CDP-in-core remains documented
4. `docs/plans/` implementation plan after Jordan’s approval

## Acceptance scenarios

1. Load `http://127.0.0.1:<port>` for a running dev server; interact; terminal still works
2. Dead localhost → clear connection error, easy reload
3. Open in system browser shows same URL
4. Focus browser, type in address bar; focus terminal, type reaches Herdr pane only
5. HTTPS public docs page loads; insecure http non-localhost warns appropriately
6. Camera/mic permission prompts do not appear without an explicit future policy change
7. Quit Bessie → Herdr intact; browser state discarded or restored per documented choice
8. Command palette opens browser and focuses address bar
9. Visual design: cannot confuse browser chrome with libghostty pane grid chrome

## Success criteria

- Localhost and doc preview no longer require leaving Bessie for the common case
- Users still escalate to a real browser without friction
- No one describes Bessie as “an IDE with a bundled Chrome”
- Agent automation browser demand is pointed at plugins, not core scope creep

## Decisions locked by this proposal

- **In-app URL preview is a desired post-V1 native feature**
- **Human WKWebView-style preview**, not core CDP Chromium
- **Not a Herdr pane**; never part of durable Herdr layout state
- Unlocks the older blanket deferral of “browser” only for this narrow preview meaning—not a general workbench free-for-all
