# Follow files and agent changes

**Status:** Proposed  
**Roadmap horizon:** Post-V1, after the focused Herdr GUI and Native Projects pass hands-on acceptance  
**Product area:** Agent detail and workspace supervision  
**Implementation approval:** Not granted by this document  
**Related plans:**
- [`workspace-files-review-and-editing.md`](workspace-files-review-and-editing.md) — broader files/diff/edit program; this plan is the preferred first product slice
- [`review-and-land.md`](review-and-land.md) — stage/commit/PR/land remain separate and later
- Plugin demand signal: herdr-file-viewer, herdr-reviewr (community), 2026-08-01 research

## Outcome

While an agent works, Bessie can **show the file it is touching right now**, lead with a **diff**, and let the user **flip through every path touched in this working stretch** without leaving the herd.

The feature is an agent-ops surface, not a Finder or IDE:

> Watch the agent → see the file under its hands → review the exact change → swap to other files it already touched → return to the live terminal.

## Why this exists

Agents edit many files in a short run. Today the user must open Superfile, an external editor, or a Herdr plugin pane and reconstruct what changed. Community demand for git-aware file viewers and review sidebars is high; Bessie should absorb the *supervision* loop natively while staying out of full IDE breadth.

Jordan’s product preference (2026-08-01): auto-follow the current edit target, show diff, and make the session touch list first-class. Full workspace tree browsing, lightweight editing, staging, and landing stay in related plans—not this first release.

## Product thesis

**Follow files** completes the graphical supervision loop around real Herdr work. It answers:

1. What is this agent changing *right now*?
2. What has it already touched in this stretch of work?
3. What is the exact diff for the selected path?

It does **not** answer “browse the whole repo like an IDE” or “commit and land from Bessie.” Those are separate products.

## Product principles

### 1. Agent-session scoped, not machine-wide

The surface is rooted at the selected agent’s workspace (local working directory). It is not a free-roaming filesystem browser.

### 2. Diff-first, follow by default

When the agent is **Working**, default mode is **Follow**: the preview tracks the most recently observed touch. Primary presentation is **diff against a named baseline**, not a mystery “smart summary.”

### 3. Honest attribution

Until Herdr or integrations supply authoritative tool-call paths, the product may say **Session changes** or **Workspace changes observed while this agent was working**, not “this agent wrote line 42.” Do not scrape terminal output to invent authorship.

### 4. Read-only in this plan

No Bessie-owned file writes, stage, discard, commit, or push. Copy path / open externally / focus pane are allowed. Editing belongs to [`workspace-files-review-and-editing.md`](workspace-files-review-and-editing.md).

### 5. Terminal remains primary

Follow files augments the real libghostty pane. Every view keeps a fast route back to the agent’s pane. Quitting Bessie must not affect Herdr or file state.

### 6. Local-first, remote-honest

First release targets **local** workspaces with a resolvable filesystem root. Remote Herdr roots show an explicit capability gap until a versioned file transport exists. No shell-scraped remote file bridge as the durable contract.

### 7. Pin beats thrash

The user can **unfollow / pin** a path so the preview stops jumping while the agent keeps editing other files.

## Primary user flows

### Flow A — Watch an agent thrash the tree

1. Select a working agent (Herd, attention, or pane focus).
2. Open **Follow files** (agent detail work panel or split).
3. Bessie resolves the workspace root and begins observing changes.
4. Preview auto-selects the latest touched path and shows its diff.
5. As new paths appear, Follow updates selection unless the user has pinned.

### Flow B — Review everything touched this stretch

1. Open the **Touched** list (recency order by default).
2. See path, status (added/modified/deleted/renamed/untracked when known), and optional +/- counts.
3. Arrow or click through the list; preview stays in sync.
4. Copy path or hunk text into a prompt; focus the live pane to steer.

### Flow C — Hold still on one file

1. While Following, choose **Pin** on the current file (or toggle Follow off).
2. Agent continues; list still updates; preview does not auto-jump.
3. User can manually select another path or resume Follow.

### Flow D — Entry from completed work

1. From a done/needs-review agent card, choose **Review changes**.
2. Land on the same surface with Follow off and the full touched/changed set for the stretch Bessie observed (or current workspace diff if the stretch is unavailable).
3. No staging or landing actions in this plan.

## Surface model

Exact chrome is a design decision; product roles:

### Touched list

- Paths observed during the current **watch stretch** (see lifecycle below)
- Status decorations when Git status is available
- Recency ordering default; optional path sort later
- Empty, loading, stale, non-repo, and error states
- Keyboard navigation

### Preview

- **Diff mode (default):** unified hunks vs named baseline (working tree vs `HEAD` unless spike proves otherwise)
- **File mode (secondary):** read-only text at current disk contents when useful
- Path header, baseline label, stale indicator
- Binary / too-large / missing / permission-denied states
- No agent-attribution chrome without evidence

### Follow controls

- Follow on/off
- Pin current path
- Refresh
- Focus agent pane
- Copy path

### Placement (open until design lock)

Preferred direction from product discussion:

- **Primary:** Agent detail work panel tab (**Changes** / **Follow files**)
- **Optional later:** split beside the agent pane for dual-watch
- Avoid a single global preview that thrash-switches across multi-agent herds without explicit user binding

## Watch stretch lifecycle

Define a clear, user-visible stretch so “files it touched this session” is not ambiguous:

| Event | Behavior |
| --- | --- |
| User opens Follow files on an agent | Start or resume a watch stretch bound to that agent + workspace root |
| Agent state → Working | Ensure observation is active; Follow may auto-select latest touch |
| New path appears in observed set | Append/update list; if Follow and unpinned, select it |
| Agent → Done / Idle / Blocked | Keep the stretch’s list for review; stop auto-follow jumps (or keep Follow only while Working—product default: **auto-follow only while Working**) |
| User clears stretch / starts new run | Explicit **Clear** or automatic new stretch when a new Working period begins after Idle/Done (spike must pick one and label it in UI) |
| Workspace root changes / agent moves | Re-resolve root; do not silently show another tree’s files |
| Bessie quits | No durable Bessie file index required; stretch is session-local projection |

## Staged roadmap

Each milestone is independently shippable.

### Milestone 0 — Evidence and contract spike

Prove facts the UI cannot invent:

- How Bessie resolves a selected agent/pane to a **canonical local workspace root**
- Behavior when panes inside one workspace have different cwds
- Git availability, baseline (`HEAD` vs index), nested repos
- Observation strategy: filesystem events, `git status`/`diff` polling, or both—with coalescing so terminal render stays hot
- How to choose “latest touched” without tool-call events (mtime within changed set, last path entering the set, etc.)
- Large repos, vendor dirs, binary files, permission errors
- Remote workspace explicit unsupported matrix
- Disposable UX probe: list + diff only

**Exit:** one local working agent’s workspace can be mapped to a root; a changing file set can be enumerated against a named baseline; “latest touch” rule is written and demoable; unsupported cases have copy.

### Milestone 1 — Touched list + manual preview

- Changes / Follow files entry on Agent detail
- Observed touched list for the active stretch
- Select path → read-only diff (or file view if not a git repo / untracked policy)
- Focus pane, copy path
- Honest empty and error states
- No auto-follow yet if it risks thrash before pin exists

**Exit:** user can see what changed while supervising one agent and flip files without Superfile.

### Milestone 2 — Follow + pin

- Follow mode while agent is Working
- Auto-select latest touched path
- Pin / unfollow
- Auto-follow pauses when not Working
- Stretch clear / new-run rules implemented and labeled

**Exit:** user can leave Follow on and watch the preview track an active agent, then pin when they want stillness.

### Milestone 3 — Polish and entry points

- Entry from Herd completed-work / Review changes
- +/- counts, rename detection when cheap
- Keyboard-first list and hunk navigation
- Stale/refresh UX under rapid writes
- Optional split placement if Agent detail proves too narrow
- Performance pass on large dirty trees

**Exit:** the loop “agent done → review everything it touched → back to pane” is shorter than external tools for local work.

### Milestone 4 — Capability-gated intelligence (separate approval)

Only after M1–M3 earn trust:

- Authoritative agent/turn path events from Herdr or integrations
- Trace → file / hunk links
- Remote read via versioned transport
- Hand-off into lightweight edit milestone of the broader files plan

Each item may become its own roadmap amendment.

## Source-of-truth and ownership

| Fact or action | Owner | Bessie behavior |
| --- | --- | --- |
| Agent/pane/workspace identity and live state | Herdr | Public snapshot/events only |
| Workspace root | Herdr when exposed; else documented local resolution | Show root + source; never silent guess |
| File bytes and mtimes | Filesystem | Read inside approved root; invalidate from FS/Git |
| Diff and status | Git | Named baseline; degrade if Git missing |
| Touch list / follow / pin | Bessie, transient projection | Not durable session state; not a second VCS |
| File writes / stage / commit | Out of scope here | Separate plans only |
| Agent authorship of hunks | Upstream/companion when authoritative | Hide or soften until then |

## Safety and trust

- Canonicalize paths; block traversal outside workspace root via `..`, bad symlinks, or aliases unless an explicit symlink policy allows a visible exception
- Do not execute files to preview them
- File content is never auto-injected as agent or Bessie instructions
- Do not log file bodies or secrets by default
- Rapid invalidation must not stall libghostty or Herdr reconciliation
- Diff meaning cannot depend on color alone

## Local vs remote

| Capability | Local first release | Remote |
| --- | --- | --- |
| Resolve root | Required | Explicit unsupported / later bridge |
| Touched list | FS + Git observation | Later |
| Diff preview | Git / read file | Later |
| Follow/pin | Yes | Later |
| Writes | No | No |

## Explicitly out of scope

- Full workspace file tree browser (later slice of workspace-files plan)
- Lightweight editing, stage, discard, commit, push, PR, land
- Worktree create/switch UI ([`worktrees-and-branches.md`](worktrees-and-branches.md) is **Deferred** by product choice)
- In-pane Chromium / CDP agent browser ([`in-app-browser.md`](in-app-browser.md) is URL preview, separate)
- Inferring edits by scraping terminal ANSI
- Replacing Superfile, Vim, or external IDEs

## Principal risks

- **Thrash:** Follow without pin becomes unusable on multi-file agents → pin and Working-only auto-follow are required before calling Follow “done”
- **False authorship:** labeling Git noise as “this agent” destroys trust → soft wording until events exist
- **Wrong root:** showing another project’s files is worse than empty → fail closed
- **Perf:** naive `git status` loops on huge repos fight the terminal → coalesce, cap, and virtualize
- **Scope creep into IDE:** tree + edit + git client must not hitchhike on Follow’s first ship

## Open questions

1. Default placement: Agent detail tab only, or tab + optional split in M3?
2. New Working period after Done: auto-clear touch list or keep until user clears?
3. Default baseline: working tree vs `HEAD` only, or include untracked file contents policy?
4. Non-git workspaces: file-mode + mtime touch list only, or hide Follow entirely?
5. Multi-root / monorepo agents: single workspace root or allow pin-to-subdir later?
6. Should Herd cards show a badge count of touched files from the active stretch?

## Graduation criteria

Before **Approved** implementation:

1. Milestone 0 spike results checked in under `docs/reports/` or the implementation plan
2. Placement and stretch lifecycle decisions answered
3. Acceptance scenarios below pass on a disposable prototype or harness
4. Explicit non-goals reconfirmed (no edit/stage in v1 of this feature)
5. Jordan grants implementation approval and a `docs/plans/` implementation plan is written

## Acceptance scenarios

1. Local git repo, agent modifies one file → appears in list; diff matches `git diff`
2. Agent creates new untracked file → listed with honest untracked state
3. Agent touches many files quickly → Follow tracks latest; pin holds selection
4. Agent goes Idle/Done → list retained for review; auto-follow stops jumping
5. Nested vendor noise → product remains usable (ignore policy or perf caps)
6. Binary and large files → explicit states, no hang
7. Missing Git → degraded but honest behavior
8. Workspace root missing/unreadable → empty/error, not wrong tree
9. Remote-only agent workspace → unsupported capability copy
10. Quit Bessie mid-watch → Herdr and files untouched; no corrupt durable index required

## Success criteria

- Supervising a busy local agent no longer requires a second app to see what is changing
- Users describe the feature as “watching the agent’s hands,” not “Bessie’s file manager”
- Terminal performance and Herdr fidelity remain unchanged
- Broader files/edit/land plans remain unblocked but not smuggled in

## Relationship to plugin research (2026-08-01)

| Community plugin pattern | Bessie response |
| --- | --- |
| herdr-file-viewer (tree + diff + md) | Absorb **diff + current file** supervision; defer full tree to workspace-files |
| herdr-reviewr (comment on diff → agent) | Later: copy hunk + focus pane / send prompt; not full reviewr clone in M1 |
| Generic IDE sidebars | Reject as identity; keep agent-scoped Follow |

## Decisions locked by this proposal

- Prefer **Follow files** as the first native files/diff product, ahead of full explorer and editing
- **Worktrees UI deferred** (user does not want it now)—do not block Follow on worktree features
- Read-only first; no landing pipeline here
