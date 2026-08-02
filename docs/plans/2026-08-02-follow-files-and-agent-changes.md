# Follow files and agent changes — execution plan (ce-plan)

**Date:** 2026-08-02
**Status:** Implementation-ready
**V1 slice:** F1 (after F0)
**Branch:** `feat/v1-f-follow-files` (after `feat/v1-f0-workspace-fs` merges or stacked)
**Goal-loop ready:** Yes on Mac with F0 available
**Depends on:** [shared substrate](2026-08-02-v1-shared-substrate.md) §5–6; [F0](2026-08-02-workspace-fs-substrate.md); prefer E for agent selection UX
**Companion product:** [media/markdown viewer](2026-08-02-in-app-file-viewer-editor.md)

## 1. Outcome

While supervising a **local** agent, user can:

1. See **Touched** paths for a watch stretch (recency order).
2. **Follow** mode auto-selects latest touched path unless **pinned**.
3. Preview is **diff-first** against **one baseline: stretch-start tree or git HEAD if repo** — pick in F0/F1 spike; default **git HEAD if .git else full-file-as-added**.
4. Honest attribution: "Workspace changes observed while watching" — not "agent wrote line 42".
5. Remote: capability banner; no local FS pretend.

## 2. Substrate gaps (today)

No watcher, git, touch list, pin, diff UI. Have `PaneProjection.cwd`, project path canonicalize patterns.

## 3. Architecture

### 3.1 Depends on F0 types

`WorkspaceFileRoot`, containment, `FileSafePath`, capability check `connection.kind == .local`.

### 3.2 Watch stretch

```swift
public struct FollowWatchStretch: Equatable, Sendable {
    public let id: UUID
    public let connectionID: String
    public let workspaceID: String
    public let root: WorkspaceFileRoot
    public let startedAt: Date
    public var pinnedPath: String?  // relative
    public var followEnabled: Bool
}

public struct TouchedPath: Equatable, Identifiable, Sendable {
    public var id: String { relativePath }
    public let relativePath: String
    public let lastTouchedAt: Date
    public let changeKind: FileChangeKind  // added/modified/deleted/unknown
}

public enum FileChangeKind: String, Sendable {
    case added, modified, deleted, unknown
}
```

### 3.3 Watcher

- Prefer FSEvents (Mac) via a small `WorkspaceFileWatcher` actor/class off main thread.
- Coalesce events 100–250ms.
- Ignore heavy dirs: `.git/`, `node_modules/`, `.build/`, `DerivedData/` (configurable list in Core).
- Cap touched list (e.g. 500) drop oldest.

### 3.4 Diff

- If git repo at or above root: `git diff -- HEAD -- path` and `git status` for kind; run Process off main actor; timeout; no shell injection (argument arrays only).
- Else: treat new files as full content added; modified without baseline show file content with banner "No git baseline".
- Binary/image paths: show "binary" and hand off to media viewer if open.
- Size limit e.g. 1.5MB text.

### 3.5 UI

- Agent detail work panel tab **Changes** or side panel when agent selected.
- List + diff pane; pin toggle; follow toggle; Open in viewer / Reveal in Finder / Open externally.
- Read-only — no save here.

## 4. Files

| File | Role |
| --- | --- |
| `Sources/BessieCore/WorkspaceFS/` or flat files | root, containment (F0) |
| `Sources/BessieCore/FollowWatch.swift` | stretch + touch model |
| `Sources/BessieCore/GitDiffService.swift` | process wrapper |
| `Sources/BessieApp/WorkspaceFileWatcher.swift` | FSEvents |
| `Sources/BessieApp/FollowFilesSurface.swift` | UI |
| `Sources/BessieApp/ProductSurfaces.swift` | entry from agent detail |
| Tests | containment, ignore list, relative path, git parsing fixtures |

## 5. Milestones

### M0 — Spike root resolution + git/no-git (Mac)
Document chosen baseline rule in plan evidence.

### M1 — F0 must be done
Root + containment + capability.

### M2 — Watcher + touch list model + tests (ignore + coalesce unit where possible)

### M3 — Diff service + text preview

### M4 — UI Follow/pin + agent binding lifecycle (start on open panel, stop on close/change agent)

### M5 — Remote honesty + verify

## 6. Acceptance

1. Local agent: edits on disk appear in Touched within ~1s coalesced.
2. Follow jumps to latest unless pinned.
3. Diff shows against locked baseline rule; banner when unavailable.
4. Path escape attempts fail closed.
5. Remote connection: no watcher; banner.
6. Quit Bessie does not affect files/Herdr.
7. check.sh + Mac manual matrix.

## 7. Non-goals

General editor, PR comments, last-turn authorship, remote FS, menu bar.

## 8. Pause

- FSEvents entitlement/sandbox issues on signed app → report.
- Git not installed → degrade gracefully without crash.
