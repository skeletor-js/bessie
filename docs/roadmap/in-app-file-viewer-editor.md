# In-app file viewer/editor

**Status:** Approved
**Roadmap horizon:** V1 (media + markdown + file ops; no general code editor)
**Product area:** Workspace and agent detail
**Implementation approval:** Granted (Occam-locked 2026-08-02)
**Related plans:**
- [`follow-files-and-agent-changes.md`](follow-files-and-agent-changes.md) — agent touch list + diff-first follow; complements this surface
- [`workspace-files-review-and-editing.md`](workspace-files-review-and-editing.md) — broader files/review umbrella; this document is the V1 product slice
- [`review-and-land.md`](review-and-land.md) — stage/commit/PR/land remain separate and later

## Outcome

Let a person supervising work in Bessie **browse the workspace tree**, **open a file**, **read it**, and make a **small explicit text edit/save** without leaving Bessie for Finder or a full IDE.

This is a **workspace-scoped file surface**, not a general-purpose editor product:

> See the agent and terminal → open the file you care about → read or lightly correct it → return to the live pane.

## Why this exists

Follow files answers “what is the agent touching right now?” Users also need ordinary open-and-read (and occasional fix) for paths that are not currently under the agent’s hands. Superfile and external editors remain valid; Bessie should cover the common in-app loop.

## Product boundary (V1)

### In scope

- Resolve and display the exact workspace root for the selected agent/workspace.
- Browse a workspace-scoped tree (depth and ignore rules bounded for performance).
- Open text files read-only first; show binary/unsupported honestly.
- Lightweight text editing with **explicit save** of the selected file only.
- Jump back to the associated Herdr pane without losing place when practical.
- Open externally / copy path handoffs.
- Local workspaces first; remote roots show a clear capability gap.

### Out of scope for V1

- Language servers, refactors, multi-file edits, debug, extensions.
- Git stage/discard/commit/push/PR (see Review and land).
- Machine-wide Finder replacement or free-roaming filesystem browser.
- Shell-scraped remote file bridges as the durable contract.
- Replacing the real terminal or Superfile/Vim-in-pane workflows.

## Relationship to Follow files

| Surface | Job |
| --- | --- |
| Follow files | Auto-track agent touches; diff-first session list |
| File viewer/editor | User-driven browse/open/read/edit any path under the workspace root |

They share root resolution, path identity, and conflict/staleness honesty. They must not invent a second durable session model.

## Product principles

1. **Workspace-scoped, not machine-wide.**
2. **Read-first; edit is explicit.** No silent autosave as the only path unless Jordan later approves.
3. **Real files.** Name path, encoding/binary status, and staleness.
4. **Terminal remains primary.** Fast route back to the live pane.
5. **Side effects are explicit.** Save writes one file; Git actions are not smuggled in.
6. **Local-first, remote-honest.**

## First useful milestones

1. Root resolution + tree + open text read-only.
2. Diff/read handoff with Follow files when both are open on the same root.
3. Explicit save for text files with conflict detection if the file changed on disk.
4. Keyboard, accessibility, and native visual coverage.

## Acceptance criteria (V1)

From a local workspace with a resolvable root:

1. Open the file surface from workspace or agent context.
2. Browse to a known text file and read its contents.
3. Edit and save a harmless change; confirm on disk.
4. Binary or missing root states explain themselves.
5. Quit Bessie; file state remains ordinary filesystem/Herdr reality—no Bessie-owned shadow file model.

## Unresolved decisions

- Exact editor component (native TextEditor vs. embedded code view).
- Ignore rules (`.gitignore` honor level) for tree performance.
- Whether multi-tab file buffers ship in V1 or single open file.
- Shared module boundary with Follow files for root/watch plumbing.
