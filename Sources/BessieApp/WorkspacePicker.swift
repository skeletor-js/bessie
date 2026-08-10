import BessieCore
import SwiftUI

struct WorkspacePickerRow: Identifiable, Equatable {
    let id: TopologyWorkspaceID
    let title: String
    let detail: String
    let isSelected: Bool
}

enum WorkspacePickerPresentation {
    static let creationAction = HerdrAction.workspaceCreate(cwd: nil, label: nil, focus: true)
    static let defaultLabel = "All workspaces"
    static let panelCornerRadius: CGFloat = 4
    static let rowHeight: CGFloat = 31
    static func panelHeight(rowCount: Int) -> CGFloat {
        min(BessieAccessibilityContract.pickerMaximumHeight, CGFloat(max(1, rowCount) + 1) * (rowHeight + 2) + 46)
    }

    static func rows(
        topology: ScopedTopologyProjection,
        selectedConnectionID: String?,
        selectedWorkspaceID: String?
    ) -> [WorkspacePickerRow] {
        topology.workspaces.map { item in
            let connectionLabel = item.connection.kind == .local
                ? "local"
                : ConnectionDisplayLabel(connection: item.connection).short
            return WorkspacePickerRow(
                id: item.id,
                title: item.summary.label,
                detail: "\(connectionLabel) · \(BessieSidebarSessionSummary.text(tabCount: item.summary.tabCount, paneCount: item.summary.paneCount))",
                isSelected: item.id.connectionID == selectedConnectionID
                    && item.id.workspaceID == selectedWorkspaceID
            )
        }
    }
}

struct WorkspacePicker: View {
    let rows: [WorkspacePickerRow]
    let label: String
    let showAll: () -> Void
    let open: (TopologyWorkspaceID) -> Void
    let create: () -> Void
    @State private var presented = false
    @FocusState private var triggerFocused: Bool
    @FocusState private var focusedRow: String?

    var body: some View {
        Button { presented.toggle() } label: {
            HStack(spacing: 7) {
                BessieIconView(icon: .squaresFour).frame(width: 20)
                Text(label).lineLimit(1)
                Spacer(minLength: 4)
                BessieIconView(icon: presented ? .caretUp : .caretDown, size: 11)
            }
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, minHeight: 31)
            .background(presented ? BessieDesign.selected : BessieSemanticColor.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($triggerFocused)
        .accessibilityLabel("Workspace picker, \(label)")
        .accessibilityValue(presented ? "Expanded" : "Collapsed")
        .accessibilityHint(presented ? "Choose a fresh workspace or create one" : "Opens the workspace list")
        .onAppear {
            if ProcessInfo.processInfo.environment["BESSIE_DESIGN_ARTBOARD"] == "04" {
                presented = true
            }
        }
        .overlay(alignment: .topLeading) {
          if presented {
            ScrollView {
              VStack(spacing: 2) {
                Button {
                    presented = false
                    showAll()
                } label: {
                    HStack(spacing: 8) {
                        Text(WorkspacePickerPresentation.defaultLabel).font(.system(size: 12.5, weight: .medium))
                        Spacer(minLength: 6)
                        if !rows.contains(where: \.isSelected) {
                            BessieIconView(icon: .check, size: 13)
                        }
                    }
                    .padding(.horizontal, 9)
                    .frame(minHeight: WorkspacePickerPresentation.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focused($focusedRow, equals: "all")
                .accessibilityLabel("All workspaces\(rows.contains(where: \.isSelected) ? "" : ", selected")")

                if rows.isEmpty {
                    Text("No fresh workspaces in this herd")
                        .font(.system(size: 10.5))
                        .foregroundStyle(BessieDesign.subtle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9)
                } else {
                    ForEach(rows) { row in
                        Button {
                            presented = false
                            open(row.id)
                        } label: {
                            HStack(spacing: 8) {
                                BessieIconView(icon: row.isSelected ? .folderOpen : .folder, size: 14).frame(width: 16)
                                Text(row.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                                Spacer(minLength: 6)
                                if row.isSelected { BessieIconView(icon: .check, size: 13) }
                            }
                            .padding(.horizontal, 9)
                            .frame(minHeight: WorkspacePickerPresentation.rowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .focused($focusedRow, equals: focusID(row.id))
                        .accessibilityLabel("\(row.title), \(row.detail)\(row.isSelected ? ", selected" : "")")
                    }
                }
                Divider().overlay(BessieDesign.border).padding(.vertical, 3)
                Button {
                    presented = false
                    create()
                } label: {
                    HStack(spacing: 8) { BessieIconView(icon: .plus, size: 14); Text("New workspace") }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Creates an ordinary Herdr workspace")
              }
            }
            .padding(4)
            .frame(width: 228, height: WorkspacePickerPresentation.panelHeight(rowCount: rows.count))
            .background(BessieDesign.panel)
            .clipShape(RoundedRectangle(cornerRadius: WorkspacePickerPresentation.panelCornerRadius))
            .overlay { RoundedRectangle(cornerRadius: WorkspacePickerPresentation.panelCornerRadius).stroke(BessieDesign.border) }
            .offset(y: 36)
            .zIndex(300)
            .onAppear { focusedRow = "all" }
          }
        }
        .zIndex(presented ? 300 : 0)
        .onChange(of: presented) { _, shown in if !shown { triggerFocused = true } }
        .onExitCommand { presented = false }
    }

    private func focusID(_ id: TopologyWorkspaceID) -> String {
        "\(id.connectionID)::\(id.workspaceID)"
    }
}
