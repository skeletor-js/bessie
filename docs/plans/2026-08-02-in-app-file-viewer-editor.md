# Workspace media and markdown viewer — execution plan (ce-plan)

**Date:** 2026-08-02
**Status:** Implementation-ready
**V1 slice:** F2
**Branch:** `feat/v1-f-media-markdown`
**Goal-loop ready:** Yes after F0
**Occam lock:** images + video preview; markdown preview/edit/save; rename/move/delete with confirm; **not** general code editor

## 1. Outcome

User can browse workspace files (simple tree or path list), preview media, edit markdown, and do file ops — local only.

1. Tree/list under WorkspaceFileRoot.
2. Select image → preview (NSImage / SwiftUI Image).
3. Select video → AVPlayer preview.
4. Select markdown → preview (attributed/markdown) + edit mode + **explicit Save**.
5. Other text: **read-only** plain text or Open Externally (no Save).
6. Rename / Move / Delete with confirmation; all containment-checked.
7. Remote: unsupported banner.

## 2. Architecture

### 2.1 Browser model

```swift
public struct WorkspaceBrowserItem: Identifiable, Sendable {
    public let relativePath: String
    public let name: String
    public let isDirectory: Bool
}
```

Directory listing via FileManager off main actor; sort dirs first.

### 2.2 Markdown edit

- Load UTF-8 text (size cap).
- Edit in TextEditor; dirty flag; Save writes atomically (temp + replace) like Project store pattern.
- Conflict: if mtime changed since load → alert overwrite/reload.

### 2.3 File ops

- Rename/move: FileManager move item; validate destination containment.
- Delete: confirm sheet; move to Trash preferred (`NSWorkspace.recycle`) over unlink.

### 2.4 UI

New surface `Files` in workspace or agent panel; share open-path API with Follow files ("open path in viewer").

## 3. Files

| File | Role |
| --- | --- |
| F0 WorkspaceFS | required |
| `Sources/BessieApp/WorkspaceFilesSurface.swift` | browser + previews |
| `Sources/BessieApp/MarkdownFileEditor.swift` | edit/save |
| `Sources/BessieCore/WorkspaceFileOps.swift` | rename/move/delete pure-ish wrappers |
| Tests | ops containment, atomic save conflict detection helpers |

## 4. Milestones

M1 Browser list + open read-only text
M2 Image + video preview
M3 Markdown preview + edit + save + conflict
M4 File ops + confirm
M5 Wire navigation from Follow + Workspace; remote banner; verify

## 5. Acceptance

1. Images and short videos preview locally.
2. Markdown save round-trips; conflict detected.
3. Non-md text not silently saved as code editor.
4. Delete uses Trash when possible; confirm required.
5. Escape path rejected.
6. Remote unsupported.
7. check.sh + Mac manual.

## 6. Non-goals

LSP, syntax highlight suite, git commit, multi-file search, Quick Look panel beyond in-app preview.

## 7. Pause

Video codec/format failures → show open externally fallback. Huge directories → cap list / progress.
