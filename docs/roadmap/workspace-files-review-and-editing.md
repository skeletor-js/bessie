# Workspace files, review, and lightweight editing

**Status:** Proposed  
**Roadmap horizon:** Post-V1, after the focused Herdr GUI passes hands-on acceptance  
**Product area:** Workspace and agent detail  
**Implementation approval:** Not granted by this document  
**Preferred first slice:** [`follow-files-and-agent-changes.md`](follow-files-and-agent-changes.md) (Proposed, 2026-08-01)

## Outcome

Let a person supervising work in Bessie answer three questions without opening another application:

1. **What files are in the workspace?**
2. **What changed, exactly?**
3. **Can I make this small correction safely?**

The goal is not to turn Bessie into a general-purpose IDE. It is to complete the graphical supervision loop around real Herdr work:

> See the agent and terminal → inspect the workspace it is operating in → review actual changes → make a small correction or hand off to a deeper tool → return to the live pane.

**Sequencing note (2026-08-01):** Product direction prefers shipping **Follow files** first—auto-preview of the path an agent is touching, diff-first, with a session touch list—before the full workspace tree browser and lightweight editing in this document. This plan remains the umbrella for browse/read/edit once Follow files earns trust. Do not block Follow files on Milestone 1 tree completeness or Milestone 3 editing.

## Why this belongs in Bessie

Today a Bessie/Herdr user can run Superfile or another TUI file manager in a pane, or leave Bessie for an editor. Those tools remain useful, but the context switch breaks the graphical relationship between:

- the Herdr workspace and selected pane;
- the agent that is working;
- the files and repository being changed;
- the diff that needs review;
- the instruction or correction that follows.

The existing design exploration already anticipates part of this loop: Agent detail has a real terminal beside a work panel with Trace, Diff, History, and Provenance, completed work exposes **Review diff**, and the later Review & land concept includes file/hunk review. This plan extends that direction rather than creating an unrelated IDE product.

## Product thesis

Bessie should become an **agent development environment** by making Herdr work legible and steerable, not by cloning the breadth of a conventional IDE.

The useful boundary is:

- **Bessie-native:** browse, search by filename, read, inspect changes, navigate between terminal/agent/file/diff context, make bounded text edits, and hand off.
- **Terminal-native:** arbitrary shell workflows, terminal editors, Superfile, and tools already running in Herdr panes.
- **External-editor-native:** language-server depth, refactors, debugging, extensions, project-wide editing workflows, and editor-specific configuration.
- **Herdr-owned:** sessions, pane/process lifecycle, agent state, and actions against panes.

Bessie does not need to beat Superfile at file management or a full IDE at code editing. It needs to make the common review-and-correct loop immediate.

## Product principles

### 1. Workspace-scoped, not machine-wide

The surface opens at the selected Herdr workspace's working directory. It is not a Finder replacement and does not begin as a free-roaming filesystem browser.

Bessie must resolve and display the exact root it is reading. If the root is unknown, missing, inaccessible, or ambiguous, the file surface explains that instead of guessing.

### 2. Read-first, edit-later

Browsing and diff review are useful without editing and carry much less risk. Editing graduates only after file identity, change detection, conflict behavior, undo, and recovery are trustworthy.

### 3. Real files and real diffs

No inferred summaries stand in for source content. The UI names the path, revision/baseline, binary or generated status, line endings where relevant, and whether data may be stale.

### 4. Preserve the terminal

The file surface augments the real pane; it does not replace it. Every relevant view provides a fast route back to the associated Herdr pane, and users can continue running Superfile, Vim, Neovim, or other tools inside that pane.

### 5. Side effects are explicit

Reading is passive. Writing a file, discarding a change, staging a hunk, committing, pushing, or opening a pull request are materially different actions and must not blur together.

The first editing milestone writes only the selected file after an explicit save. Git staging, discarding, commit, push, and landing are outside this initiative unless separately approved.

### 6. Attribution is evidence, not guesswork

A repository diff can truthfully show what changed in the workspace. Claiming which agent or turn caused each hunk requires authoritative events or companion/upstream support. Until then, the product says **Workspace changes**, not **Changes by this agent**.

### 7. Local-first, remote-honest

The first release targets local workspaces. The view must not imply that a remote Herdr workspace is locally readable. Remote files require a versioned transport with path, metadata, read, watch/invalidation, and guarded-write semantics; SSH shell commands stitched into the UI are not a durable product contract.

## Primary user flows

### Flow A — Inspect a file while watching an agent

1. Select an agent or pane.
2. Open **Files** in the contextual work panel.
3. Bessie resolves the containing workspace and shows its exact root.
4. Browse or search by path and open a text file read-only.
5. Jump back to the same pane without losing file position.

### Flow B — Review current workspace changes

1. Choose **Review diff** from completed work, Agent detail, or the workspace toolbar.
2. See changed files with exact addition/deletion counts and status.
3. Move through files and hunks with keyboard or pointer.
4. Open the resulting file at the relevant line with the hunk context preserved.
5. Copy a path, line range, or selected hunk for use in a prompt.
6. Return to the relevant pane and ask for a correction.

### Flow C — Make a small correction

1. Open a text file from Files or Diff.
2. Enter edit mode deliberately; read mode remains the default.
3. Make a bounded textual change.
4. Save explicitly.
5. If the file changed on disk since it was opened, Bessie refuses a blind overwrite and offers compare/reload/save-as-copy choices.
6. The diff refreshes and clearly shows the new workspace state.

### Flow D — Hand off to a deeper tool

From a file or diff, offer native actions such as:

- copy path;
- reveal in Finder;
- open in the configured external editor at a line when supported;
- focus the associated Herdr pane;
- copy a shell-safe relative path for terminal use.

Bessie should make escalation cheap rather than attempting to absorb every advanced workflow.

## Surface model

The exact layout remains a design decision, but the product needs these roles:

### Files

A workspace-scoped browser containing:

- hierarchical tree with directories and files;
- filename/path filtering;
- ignored and hidden-file policy with an explicit reveal control;
- file status decoration when Git status is available;
- refresh and stale/error state;
- keyboard navigation and contextual actions;
- large-directory protection and lazy loading.

### Viewer

A native read-only text surface containing:

- syntax-aware presentation when cheaply and reliably available;
- line numbers, selection, copy, find-in-file, and jump to line;
- file path and size/encoding facts;
- loading, binary, unsupported encoding, too-large, missing, and permission-denied states;
- image/asset metadata initially rather than a promise of universal preview support.

### Diff

An evolution of the existing `DiffView` direction containing:

- changed-file list and exact counts;
- added, modified, deleted, renamed, untracked, and binary states;
- unified hunk review first; optional side-by-side presentation later;
- whitespace visibility controls;
- baseline label such as working tree vs `HEAD` or another selected comparison;
- navigation from hunk to file and line;
- refresh/staleness state;
- no agent attribution without authoritative evidence.

### Lightweight editor

A deliberately small mode containing:

- plain-text editing;
- selection, undo/redo, find/replace, indentation, and line-number navigation;
- explicit save and dirty-state indicator;
- safe handling of external modifications;
- preservation of encoding and line endings when supported;
- a clear **Open in external editor** escape hatch.

It does not initially include language servers, completion, diagnostics, formatting, refactors, debugging, extensions, multi-cursor depth, notebooks, or an integrated build system.

## Staged roadmap

Each milestone is independently shippable. Do not begin with a monolithic editor project.

### Milestone 0 — Evidence and contract spike

Resolve the facts the product cannot safely assume:

- how a Herdr workspace exposes or derives its canonical working directory;
- behavior for panes with different current directories inside one workspace;
- repository detection and nested repositories;
- symlink boundaries and path traversal policy;
- local filesystem watching/invalidation strategy;
- Git availability and baseline semantics;
- large-file, binary-file, encoding, and permission behavior;
- remote capability requirements;
- minimum viable native text rendering/editing technology on macOS.

Produce a tested capability matrix and disposable UX probes. Do not ship hidden shell-command parsing as the permanent data model.

**Exit:** one selected local Herdr workspace can be mapped to an exact readable root, changed files can be enumerated against a named baseline, and all unsupported cases have explicit product behavior.

### Milestone 1 — Browse and read

Ship the smallest complete value:

- Files tab in the workspace/agent contextual panel;
- workspace-root tree with lazy directory loading;
- filename/path filter;
- read-only text viewer with line numbers, selection, copy, and find;
- copy path, reveal in Finder, open externally, and focus pane;
- robust unsupported/large/binary/error states;
- file-change invalidation without silently moving the user's reading position.

**Exit:** a user can navigate from a selected Herdr pane to a real file in its workspace, inspect it, and return to the pane without opening Superfile for basic reading.

### Milestone 2 — Workspace diff review

Add trustworthy review:

- changed-file inventory for a named Git baseline;
- exact statuses and addition/deletion counts;
- unified file/hunk diff;
- keyboard-first changed-file and hunk navigation;
- jump from hunk to file/line;
- copy path, line range, and hunk;
- entry from Agent detail, completed-work cards, and Workspace;
- clear refresh, stale, non-repository, missing-Git, and command-failure states.

The milestone presents **workspace changes**. Agent/turn attribution is capability-gated and not required.

**Exit:** a user can review every current workspace change and route a correction back to the live pane without using an external diff tool.

### Milestone 3 — Lightweight editing

Add bounded direct correction:

- deliberate read/edit mode transition;
- edit ordinary text files;
- undo/redo and find/replace;
- explicit save and dirty-state handling;
- optimistic concurrency guard using the opened file's identity/metadata/content fingerprint;
- compare/reload/save-as-copy recovery when external changes conflict;
- atomic write where supported, permissions preserved, and failures surfaced;
- diff refresh after save;
- unsaved-change confirmation when switching file, workspace, connection, or closing Bessie.

**Exit:** a user can make and verify a small correction without Bessie losing another process's concurrent change or silently altering file metadata it promised to preserve.

### Milestone 4 — Review intelligence, capability-gated

Consider only after the first three milestones prove useful:

- authoritative agent- or turn-attributed changes;
- trace-to-file and trace-to-hunk links;
- test/build status associated with a reviewed change;
- compare changes from concurrent agents or worktrees;
- remote read/write support through a versioned bridge;
- richer previews or language-aware navigation where evidence warrants the carrying cost.

Each item can graduate into its own roadmap plan. None is implied by the initial editor milestone.

## Source-of-truth and ownership model

| Fact or action | Owner | Bessie behavior |
| --- | --- | --- |
| Session/workspace/tab/pane/process/agent state | Herdr | Read and mutate only through Herdr's public contracts. |
| Workspace root association | Herdr when exposed; otherwise an explicitly documented local resolution contract | Display the resolved root and confidence/source; never guess silently. |
| Local file contents and metadata | Filesystem | Read directly within the approved workspace boundary and invalidate from filesystem events. |
| Working-tree status and diff | Git repository | Query against a named baseline; present failures and exact command/tool ownership. |
| Editor buffer | Bessie, transient | Never presented as saved until filesystem persistence succeeds. |
| Agent/turn attribution | Herdr/companion/upstream event contract | Hide or label unavailable unless authoritative. |
| Stage/commit/push/PR/land | Outside initial scope | Requires separate ownership, safety, and approval plan. |

## Safety and trust requirements

- Resolve canonical paths before access and prevent unintended traversal outside the workspace root through `..`, symlinks, aliases, or malformed remote paths.
- Treat symlink targets outside the root as a visible capability decision, not an accidental escape.
- Never follow recursive symlink loops.
- Avoid loading entire huge files or repositories into memory.
- Preserve permissions and supported encoding/line-ending facts when saving.
- Do not overwrite an externally modified file without presenting the conflict.
- Do not execute repository files merely to preview them.
- Render source as source; file content must never become instructions to Bessie or an agent automatically.
- Keep write, discard, stage, commit, push, and land controls visually and behaviorally distinct.
- Record useful local diagnostics without logging file contents or secrets by default.

## Performance expectations

Targets should be validated on representative repositories rather than treated as paper guarantees:

- reveal the file surface immediately with progressive loading;
- keep navigation responsive in repositories with large dependency/vendor trees;
- virtualize long trees, files, and diffs;
- cancel stale reads when selection changes quickly;
- coalesce filesystem and Git invalidations rather than recomputing on every event;
- avoid blocking terminal rendering or Herdr snapshot reconciliation.

## Accessibility and keyboard behavior

- Files, viewer, diff, and editor must be fully keyboard navigable.
- Bessie shortcuts must not steal ordinary terminal input when the terminal is focused.
- Focus transitions between terminal and work panel must be visible and reversible.
- Text selection, copy, VoiceOver labels, contrast, Reduce Motion, and system text settings must remain coherent with the native app.
- Diff meaning cannot depend on color alone; additions/deletions use symbols, labels, and luminance consistent with the Bessie design system.

## Explicitly deferred for separate plans

- staging or unstaging files/hunks;
- discard/revert actions;
- commit, amend, rebase, merge, push, pull, PR creation, or landing;
- a full source-control client;
- agent-attributed hunks without authoritative provenance;
- language servers, autocomplete, diagnostics, refactoring, debugging, or extensions;
- arbitrary machine-wide file management;
- remote editing before a versioned file transport exists;
- collaborative editing;
- replacing Superfile, terminal editors, or external IDEs.

## Outside Bessie's product identity

- becoming a generic IDE whose primary model is files, projects, and editor tabs rather than Herdr work;
- creating a Bessie-owned agent runtime or durable session model;
- hiding the real terminal because a graphical editor exists;
- silently running destructive Git operations;
- inferring agent authorship by scraping terminal output or process heuristics.

## Dependencies and assumptions

- Focused V1 is accepted and the core Herdr workspace experience is stable enough to carry another major surface.
- Bessie can identify a selected workspace and an exact local working-directory root.
- macOS remains the first implementation target.
- Native file coordination/watching and text rendering can meet the conflict and performance requirements without importing a full IDE framework.
- Git is optional at runtime: browsing and reading still work outside a repository; diff review degrades honestly when Git is absent.
- Remote parity requires upstream or companion transport work and is not smuggled into the local milestone.

## Success criteria

The feature is successful when:

- basic source inspection no longer requires opening Superfile or another application;
- users can review all current workspace changes against a clearly named baseline;
- the route from agent/pane → changed file/hunk → pane is shorter and clearer than the current workaround;
- small direct edits are trusted because conflicts and unsaved state are explicit;
- users still choose terminal and external editors for deep workflows without feeling trapped;
- terminal responsiveness, Herdr convergence, and process survival remain unchanged;
- user testing describes Bessie as better for supervising agent work, not as a worse copy of an IDE.

## Acceptance scenarios

Before any milestone is called shipped, verify at least:

1. ordinary repository and non-repository workspaces;
2. nested directories, hidden files, ignored files, and symlinks;
3. renamed, deleted, untracked, binary, large, and permission-denied files;
4. workspace path disappearing or changing while open;
5. file changed externally while merely viewed;
6. file changed externally while Bessie has unsaved edits;
7. rapid agent writes while the diff is open;
8. Git absent, repository corrupt, command failure, and unusual baseline state;
9. app quit/reopen with no corruption or unintended Herdr/process effects;
10. a remote workspace receiving an explicit unsupported/capability state rather than incorrect local files.

## Decisions required before implementation approval

1. Where should Files/Diff live by default: Agent detail, Workspace, or one shared contextual inspector?
2. Is the canonical root always the Herdr workspace root, or can the user deliberately pin a narrower pane/agent root?
3. Should ignored and hidden files be concealed by default, and how are those policies explained?
4. Which diff baseline is the default: working tree vs `HEAD`, index vs `HEAD`, or a combined view?
5. What native text component best supports large-file virtualization, selection, accessibility, and later editing?
6. What exact external-editor handoff contract is supported in the first milestone?
7. Which filesystem operations, if any beyond save, deserve their own later roadmap item?
8. What evidence would justify moving staging/commit/land into Bessie rather than leaving those actions in a Herdr pane or external Git tool?

## Relationship to existing Bessie plans

This roadmap item builds on:

- **[`follow-files-and-agent-changes.md`](follow-files-and-agent-changes.md)** — preferred first ship; touch list + follow + diff without full tree or edit;
- the existing Agent detail work-panel concept: Trace, Diff, History, Provenance;
- `D07` agent-attributed diff, while deliberately shipping workspace diff without unsupported attribution first;
- `RV01` file/hunk diff review from Review & land;
- worktree and branch status concepts, without taking on worktree mutation ([`worktrees-and-branches.md`](worktrees-and-branches.md) is **Deferred**);
- [`in-app-browser.md`](in-app-browser.md) for URL preview (not file preview);
- the focused V1 rule that Herdr remains the engine and every terminal remains real.

If approved, implementation planning should split the milestones into separate `docs/plans/` documents rather than scheduling this roadmap file as one large project. Follow files should get its own implementation plan first.
