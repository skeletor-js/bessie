import BessieCore
import SwiftUI

indirect enum ProjectLayoutNode: Equatable {
    case pane(BessieProjectPane)
    case split(paneID: UUID, direction: SplitDirection, ratio: Double, first: ProjectLayoutNode, second: ProjectLayoutNode)

    static func build(from panes: [BessieProjectPane]) -> ProjectLayoutNode? {
        guard let root = panes.first(where: { if case .root = $0.placement { return true }; return false }) else {
            return nil
        }
        var node: ProjectLayoutNode = .pane(root)
        for pane in panes {
            guard case .split(let parentID, let direction, let ratio) = pane.placement else { continue }
            node = node.replacing(parentID) { parent in
                .split(paneID: pane.id, direction: direction, ratio: ratio, first: .pane(parent), second: .pane(pane))
            }
        }
        return node
    }

    private func replacing(_ paneID: UUID, replacement: (BessieProjectPane) -> ProjectLayoutNode) -> ProjectLayoutNode {
        switch self {
        case .pane(let pane):
            return pane.id == paneID ? replacement(pane) : self
        case .split(let splitPaneID, let direction, let ratio, let first, let second):
            return .split(
                paneID: splitPaneID,
                direction: direction,
                ratio: ratio,
                first: first.replacing(paneID, replacement: replacement),
                second: second.replacing(paneID, replacement: replacement)
            )
        }
    }
}

struct ProjectLayoutPreview: View {
    let project: BessieProject?
    let tab: BessieProjectTab
    var selectedPaneID: UUID?
    var onSelectPane: (UUID) -> Void = { _ in }
    var onChangeRatio: (UUID, Double) -> Void = { _, _ in }
    var onAddPane: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            if let node = ProjectLayoutNode.build(from: tab.panes) {
                ProjectLayoutNodeView(
                    project: project, node: node,
                    paneNumbers: Dictionary(uniqueKeysWithValues: tab.panes.enumerated().map { ($0.element.id, $0.offset + 1) }),
                    selectedPaneID: selectedPaneID,
                    onSelectPane: onSelectPane, onChangeRatio: onChangeRatio
                )
                    .padding(9)
                Button(action: onAddPane) {
                    HStack(spacing: 7) { BessieIconView(icon: .plus, size: 13); Text("Add a pane") }
                        .font(.system(size: 11.5))
                        .foregroundStyle(BessieDesign.faint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay { RoundedRectangle(cornerRadius: BessieDesign.controlRadius).stroke(BessieDesign.borderStrong, style: StrokeStyle(dash: [5])) }
                }
                .buttonStyle(.plain)
                .frame(minHeight: 72)
                .padding(9)
            } else {
                Text("Layout unavailable")
                    .font(.system(size: 11))
                    .foregroundStyle(BessieDesign.codeSubtle)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity)
        .background(BessieDesign.background)
        .overlay { Rectangle().stroke(BessieDesign.border, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Layout preview for \(tab.name)")
    }

}

private struct ProjectLayoutNodeView: View {
    let project: BessieProject?
    let node: ProjectLayoutNode
    let paneNumbers: [UUID: Int]
    let selectedPaneID: UUID?
    let onSelectPane: (UUID) -> Void
    let onChangeRatio: (UUID, Double) -> Void

    var body: some View {
        switch node {
        case .pane(let pane):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text("\(paneNumbers[pane.id] ?? 1)").font(.system(size: 11, weight: .semibold, design: .monospaced))
                    Text(pane.label ?? "Shell").font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer()
                    paneMark(for: pane)
                }
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
            .accessibilityValue(selectedPaneID == pane.id ? "Selected" : "Not selected")
            .accessibilityHint("Select this pane for editing")
            .contentShape(Rectangle())
            .onTapGesture { onSelectPane(pane.id) }
            .focusable()
            .onKeyPress(phases: .down) { press in
                guard press.key == .return || press.key == .space else { return .ignored }
                onSelectPane(pane.id)
                return .handled
            }
            .accessibilityAction { onSelectPane(pane.id) }
        case .split(let paneID, let direction, let ratio, let first, let second):
            GeometryReader { proxy in
                if direction == .right {
                    HStack(spacing: 0) {
                        ProjectLayoutNodeView(project: project, node: first, paneNumbers: paneNumbers, selectedPaneID: selectedPaneID, onSelectPane: onSelectPane, onChangeRatio: onChangeRatio)
                            .frame(width: max(0, (proxy.size.width - BessieDesign.paneGap) * ratio))
                        splitHandle(paneID: paneID, ratio: ratio, extent: proxy.size.width, direction: direction)
                        ProjectLayoutNodeView(project: project, node: second, paneNumbers: paneNumbers, selectedPaneID: selectedPaneID, onSelectPane: onSelectPane, onChangeRatio: onChangeRatio)
                    }
                } else {
                    VStack(spacing: 0) {
                        ProjectLayoutNodeView(project: project, node: first, paneNumbers: paneNumbers, selectedPaneID: selectedPaneID, onSelectPane: onSelectPane, onChangeRatio: onChangeRatio)
                            .frame(height: max(0, (proxy.size.height - BessieDesign.paneGap) * ratio))
                        splitHandle(paneID: paneID, ratio: ratio, extent: proxy.size.height, direction: direction)
                        ProjectLayoutNodeView(project: project, node: second, paneNumbers: paneNumbers, selectedPaneID: selectedPaneID, onSelectPane: onSelectPane, onChangeRatio: onChangeRatio)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func paneMark(for pane: BessieProjectPane) -> some View {
        let command = pane.command?.lowercased() ?? ""
        if ["claude", "codex", "grok", "amp"].contains(where: command.contains) {
            BessieProviderMark(provider: command, size: 12)
        } else {
            BessieIconView(icon: .terminalWindow, size: 12)
                .foregroundStyle(BessieDesign.faint)
                .accessibilityLabel("Shell")
        }
    }

    private func splitHandle(paneID: UUID, ratio: Double, extent: CGFloat, direction: SplitDirection) -> some View {
        Rectangle()
            .fill(BessieDesign.borderStrong)
            .frame(
                width: direction == .right ? BessieDesign.paneGap : nil,
                height: direction == .down ? BessieDesign.paneGap : nil
            )
            .contentShape(Rectangle().inset(by: -4))
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let translation = direction == .right ? value.translation.width : value.translation.height
                guard extent > 0 else { return }
                onChangeRatio(paneID, min(0.9, max(0.1, ratio + Double(translation / extent))))
            })
            .accessibilityLabel("Split divider")
            .accessibilityValue("\(Int(ratio * 100)) percent")
            .accessibilityHint("Drag or adjust to resize both panes")
            .accessibilityAdjustableAction { adjustment in
                switch adjustment {
                case .increment: onChangeRatio(paneID, min(0.9, ratio + 0.05))
                case .decrement: onChangeRatio(paneID, max(0.1, ratio - 0.05))
                @unknown default: break
                }
            }
    }
}
