import Foundation

public enum BessieProjectCaptureError: Error, Equatable, Sendable {
    case missingProjection
    case missingFocusedWorkspace
    case missingTabs
    case missingLayout(tabID: String)
    case missingPane(paneID: String)
}

public enum BessieProjectCapture {
    public static func validate(_ projection: HerdrSessionProjection?) throws {
        _ = try source(from: projection)
    }

    public static func capture(
        from projection: HerdrSessionProjection?,
        targetConnectionID: String = BessieConnectionDefinition.localBessie.id,
        now: Date = Date()
    ) throws -> BessieProject {
        let source = try source(from: projection)
        let tabs = try source.tabs.map { tab -> BessieProjectTab in
            let layout = source.layouts[tab.id]!
            var panes: [BessieProjectPane] = []
            let rootID = UUID()
            let rootLeaf = Self.firstLeaf(in: layout.root)
            let rootPane = source.panesByID[rootLeaf.paneID]!
            panes.append(.init(id: rootID, label: rootPane.label, command: nil, placement: .root))
            try Self.appendSplits(
                from: layout.root,
                existingPaneID: rootID,
                panesByID: source.panesByID,
                into: &panes
            )
            return BessieProjectTab(id: UUID(), name: tab.label, panes: panes)
        }

        let capturedPanes = source.capturedPaneIDs.compactMap { source.panesByID[$0] }
        let workingDirectory = Self.authoritativeWorkingDirectory(
            panes: capturedPanes,
            expectedCount: source.capturedPaneIDs.count
        )
        let name = source.workspace.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return BessieProject(
            id: UUID(),
            name: name.isEmpty ? "Untitled project" : name,
            targetConnectionID: targetConnectionID,
            workingDirectory: workingDirectory,
            tabs: tabs,
            createdAt: now,
            updatedAt: now
        )
    }

    private static func source(from projection: HerdrSessionProjection?) throws -> CaptureSource {
        guard let projection else { throw BessieProjectCaptureError.missingProjection }
        guard let workspace = projection.focusedWorkspace else {
            throw BessieProjectCaptureError.missingFocusedWorkspace
        }
        let tabs = projection.tabs.filter { $0.workspaceID == workspace.id }
        guard !tabs.isEmpty,
              tabs.count == workspace.tabCount,
              Set(tabs.map(\.id)).count == workspace.tabCount else {
            throw BessieProjectCaptureError.missingTabs
        }
        var panesByID: [String: PaneProjection] = [:]
        for pane in projection.panes {
            guard panesByID.updateValue(pane, forKey: pane.id) == nil else {
                throw BessieProjectCaptureError.missingPane(paneID: pane.id)
            }
        }
        var layouts: [String: TabLayoutProjection] = [:]
        var capturedPaneIDs: Set<String> = []
        for tab in tabs {
            guard let layout = projection.layouts[tab.id] else {
                throw BessieProjectCaptureError.missingLayout(tabID: tab.id)
            }
            let layoutPaneIDs = layout.root.paneIDs
            guard layout.workspaceID == workspace.id,
                  layoutPaneIDs.count == tab.paneCount,
                  Set(layoutPaneIDs).count == tab.paneCount else {
                throw BessieProjectCaptureError.missingLayout(tabID: tab.id)
            }
            for paneID in layoutPaneIDs {
                guard let pane = panesByID[paneID],
                      pane.workspaceID == workspace.id,
                      pane.tabID == tab.id else {
                    throw BessieProjectCaptureError.missingPane(paneID: paneID)
                }
                capturedPaneIDs.insert(paneID)
            }
            layouts[tab.id] = layout
        }
        let workspacePaneIDs = Set(projection.panes.lazy.filter { $0.workspaceID == workspace.id }.map(\.id))
        guard workspacePaneIDs.count == workspace.paneCount,
              capturedPaneIDs.count == workspace.paneCount,
              capturedPaneIDs == workspacePaneIDs else {
            throw BessieProjectCaptureError.missingLayout(tabID: tabs.first!.id)
        }
        return CaptureSource(
            workspace: workspace,
            tabs: tabs,
            layouts: layouts,
            panesByID: panesByID,
            capturedPaneIDs: capturedPaneIDs
        )
    }

    private static func appendSplits(
        from layout: RecursivePaneLayout,
        existingPaneID: UUID,
        panesByID: [String: PaneProjection],
        into panes: inout [BessieProjectPane]
    ) throws {
        guard case .split(let branch) = layout else { return }
        let secondLeaf = firstLeaf(in: branch.second)
        guard let secondPane = panesByID[secondLeaf.paneID] else {
            throw BessieProjectCaptureError.missingPane(paneID: secondLeaf.paneID)
        }
        let secondID = UUID()
        panes.append(.init(
            id: secondID,
            label: secondPane.label,
            command: nil,
            placement: .split(fromPaneID: existingPaneID, direction: branch.direction, ratio: branch.ratio)
        ))
        try appendSplits(from: branch.first, existingPaneID: existingPaneID, panesByID: panesByID, into: &panes)
        try appendSplits(from: branch.second, existingPaneID: secondID, panesByID: panesByID, into: &panes)
    }

    private static func firstLeaf(in layout: RecursivePaneLayout) -> PaneLayoutLeaf {
        switch layout {
        case .pane(let leaf): leaf
        case .split(let branch): firstLeaf(in: branch.first)
        }
    }

    private static func authoritativeWorkingDirectory(
        panes: [PaneProjection],
        expectedCount: Int
    ) -> String {
        guard panes.count == expectedCount, expectedCount > 0 else { return "" }
        let paths = panes.compactMap(\.cwd)
        guard paths.count == expectedCount,
              Set(paths).count == 1,
              let path = paths.first,
              NSString(string: path).isAbsolutePath
        else { return "" }
        return path
    }
}

private struct CaptureSource {
    let workspace: WorkspaceProjection
    let tabs: [TabProjection]
    let layouts: [String: TabLayoutProjection]
    let panesByID: [String: PaneProjection]
    let capturedPaneIDs: Set<String>
}
