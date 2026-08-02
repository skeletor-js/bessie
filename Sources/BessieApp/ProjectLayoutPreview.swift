import BessieCore
import SwiftUI

indirect enum ProjectLayoutNode: Equatable {
    case pane(BessieProjectPane)
    case split(direction: SplitDirection, ratio: Double, first: ProjectLayoutNode, second: ProjectLayoutNode)

    static func build(from panes: [BessieProjectPane]) -> ProjectLayoutNode? {
        guard let root = panes.first(where: { if case .root = $0.placement { return true }; return false }) else {
            return nil
        }
        var node: ProjectLayoutNode = .pane(root)
        for pane in panes {
            guard case .split(let parentID, let direction, let ratio) = pane.placement else { continue }
            node = node.replacing(parentID) { parent in
                .split(direction: direction, ratio: ratio, first: .pane(parent), second: .pane(pane))
            }
        }
        return node
    }

    private func replacing(_ paneID: UUID, replacement: (BessieProjectPane) -> ProjectLayoutNode) -> ProjectLayoutNode {
        switch self {
        case .pane(let pane):
            return pane.id == paneID ? replacement(pane) : self
        case .split(let direction, let ratio, let first, let second):
            return .split(
                direction: direction,
                ratio: ratio,
                first: first.replacing(paneID, replacement: replacement),
                second: second.replacing(paneID, replacement: replacement)
            )
        }
    }
}

struct ProjectLayoutPreview: View {
    let tab: BessieProjectTab
    var selectedPaneID: UUID?

    var body: some View {
        Group {
            if let node = ProjectLayoutNode.build(from: tab.panes) {
                ProjectLayoutNodeView(node: node, selectedPaneID: selectedPaneID)
                    .padding(7)
            } else {
                Text("Layout unavailable")
                    .font(.system(size: 11))
                    .foregroundStyle(BessieDesign.subtle)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity)
        .background(BessieDesign.code)
        .overlay { Rectangle().stroke(BessieDesign.border, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Layout preview for \(tab.name)")
    }
}

private struct ProjectLayoutNodeView: View {
    let node: ProjectLayoutNode
    let selectedPaneID: UUID?

    var body: some View {
        switch node {
        case .pane(let pane):
            VStack(alignment: .leading, spacing: 4) {
                Text(pane.label ?? "Shell")
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                Text(pane.commandDisplay(fallback: "shell"))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(BessieDesign.subtle)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(selectedPaneID == pane.id ? BessieDesign.selected : BessieDesign.panel)
            .overlay {
                Rectangle().stroke(
                    selectedPaneID == pane.id ? BessieDesign.borderStrong : BessieDesign.border,
                    lineWidth: selectedPaneID == pane.id ? 1.5 : 1
                )
            }
            .accessibilityLabel("Pane \(pane.label ?? "Shell")")
        case .split(let direction, let ratio, let first, let second):
            GeometryReader { proxy in
                if direction == .right {
                    HStack(spacing: BessieDesign.paneGap) {
                        ProjectLayoutNodeView(node: first, selectedPaneID: selectedPaneID)
                            .frame(width: max(0, (proxy.size.width - BessieDesign.paneGap) * ratio))
                        ProjectLayoutNodeView(node: second, selectedPaneID: selectedPaneID)
                    }
                } else {
                    VStack(spacing: BessieDesign.paneGap) {
                        ProjectLayoutNodeView(node: first, selectedPaneID: selectedPaneID)
                            .frame(height: max(0, (proxy.size.height - BessieDesign.paneGap) * ratio))
                        ProjectLayoutNodeView(node: second, selectedPaneID: selectedPaneID)
                    }
                }
            }
        }
    }
}
