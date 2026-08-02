# Workspace FS substrate (F0) — execution plan (ce-plan)

**Date:** 2026-08-02
**Status:** Implementation-ready
**V1 slice:** F0
**Branch:** `feat/v1-f0-workspace-fs`
**Goal-loop ready:** Yes (Core-heavy; Mac for live path checks)
**Unblocks:** F1 Follow files, F2 media/markdown viewer

## 1. Outcome

Shared, testable workspace filesystem primitives:

1. Resolve a **WorkspaceFileRoot** for a local workspace/agent context.
2. **Containment**: candidate URLs must stay inside root after standardization + symlink resolve.
3. **Capability**: remote → unsupported.
4. Shared ignore list and file meta (size, UTI/mime guess, text vs binary heuristic).

## 2. Root resolution algorithm

Inputs: `BessieConnectionDefinition`, `HerdrSessionProjection`, selected `paneID` or workspaceID.

1. If `connection.kind != .local` → `.unavailableRemote`.
2. Collect pane cwds for workspace (or selected pane cwd).
3. If all absolute cwds equal → candidate = that path (same honesty as Project capture).
4. Else if selected pane has absolute cwd → candidate = pane cwd (document in UI "Using pane working directory").
5. Else → `.missing`.
6. Standardize: expand symlink, require directory, require readable.
7. Optional: walk up for `.git` to set `gitTopLevel` optional URL without changing browse root (browse root stays cwd-based unless product later chooses repo root — **V1 browse root = resolved cwd candidate**, record git top if found for diff).

## 3. Types (Core)

```swift
public struct WorkspaceFileRoot: Equatable, Sendable { /* substrate doc */ }

public enum WorkspacePathError: Error, Equatable {
    case remoteUnsupported
    case missingRoot
    case notDirectory
    case unreadable
    case pathEscape
    case tooLarge
    case notFound
}

public enum WorkspaceFS {
    public static func resolveRoot(...) -> Result<WorkspaceFileRoot, WorkspacePathError>
    public static func resolveFile(root: WorkspaceFileRoot, relativePath: String) -> Result<URL, WorkspacePathError>
    public static func isIgnoredRelativePath(_ path: String) -> Bool
}

public struct FileContentMeta: Equatable, Sendable {
    public let relativePath: String
    public let byteSize: Int
    public let kind: FilePreviewKind  // text, markdown, image, video, binary, directory
}
```

Containment: `standardizedFileURL` + `hasPrefix(root standardized)` after resolving symlinks file carefully (resolve file URL; ensure path components under root).

## 4. Files

- `Sources/BessieCore/WorkspaceFS.swift` (or folder)
- `Tests/BessieCoreTests/WorkspaceFSTests.swift` — temp dirs, symlink escape, remote, ignore
- `scripts/check.sh` anchors

## 5. Milestones

M1 types + resolveRoot tests
M2 resolveFile containment + symlink escape tests
M3 ignore list + meta kind detection
M4 export small API used by F1/F2

## 6. Acceptance

1. Symlink pointing outside root cannot be read via API.
2. Remote returns remoteUnsupported.
3. Consensus cwd and single-pane cwd cases tested.
4. No UI required in F0.

## 7. Non-goals

Watcher, git diff, SwiftUI.
