import BessieCore
import SwiftUI

enum HerdPickerKind: Equatable {
    case all, local, ssh
}

struct HerdPickerRow: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let kind: HerdPickerKind
    let scope: ConnectionScope
    let isSelected: Bool
    let isFresh: Bool
    let canRetry: Bool
}

enum HerdPickerPresentation {
    static let panelCornerRadius: CGFloat = 4
    static let rowHeight: CGFloat = 31
    static let captureRows = [
        HerdPickerRow(
            id: "all", title: "All herds", detail: "", kind: .all,
            scope: .all, isSelected: true, isFresh: true, canRetry: false
        ),
        HerdPickerRow(
            id: "local", title: "local", detail: "", kind: .local,
            scope: .connection(id: "local-bessie"), isSelected: false, isFresh: true, canRetry: false
        ),
        HerdPickerRow(
            id: "ci-box", title: "ci-box", detail: "", kind: .ssh,
            scope: .connection(id: "capture-ci-box"), isSelected: false, isFresh: false, canRetry: false
        ),
    ]
    static func panelHeight(rowCount: Int) -> CGFloat {
        min(BessieAccessibilityContract.pickerMaximumHeight, CGFloat(rowCount) * (rowHeight + 2) + 46)
    }

    static func rows(
        connections: [BessieConnectionDefinition],
        health: [ConnectionHealth],
        selection: ConnectionScope
    ) -> [HerdPickerRow] {
        let healthByID = Dictionary(uniqueKeysWithValues: health.map { ($0.connectionID, $0) })
        let all = HerdPickerRow(
            id: "all", title: "All herds", detail: "", kind: .all,
            scope: .all, isSelected: selection == .all, isFresh: true, canRetry: false
        )
        return [all] + connections.map { connection in
            let state = healthByID[connection.id]
            return HerdPickerRow(
                id: connection.id,
                title: connection.kind == .local ? "local" : ConnectionDisplayLabel(connection: connection).short,
                detail: state.map { "\($0.isUsable ? "Healthy" : $0.phase) · \($0.detail)" }
                    ?? "Waiting for connection status",
                kind: connection.kind == .local ? .local : .ssh,
                scope: .connection(id: connection.id),
                isSelected: selection == .connection(id: connection.id),
                isFresh: state?.isUsable == true,
                canRetry: state?.canRetry == true
            )
        }
    }

    static func hierarchyRows(
        connections: [BessieConnectionDefinition],
        health: [ConnectionHealth],
        selectedConnectionID: String?
    ) -> [HerdPickerRow] {
        rows(
            connections: connections,
            health: health,
            selection: selectedConnectionID.map { .connection(id: $0) } ?? .all
        ).filter { $0.scope != .all }
    }
}

struct HerdPicker: View {
    let rows: [HerdPickerRow]
    let label: String
    let select: (ConnectionScope) -> Void
    let retry: (String) -> Void
    let addHerd: () -> Void
    @State private var presented = false
    @FocusState private var triggerFocused: Bool
    @FocusState private var focusedRow: String?

    var body: some View {
        Button { presented.toggle() } label: {
            HStack(spacing: 7) {
                BessieIconView(icon: .hardDrives)
                    .frame(width: 20)
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
        .accessibilityLabel("Herd picker, \(label)")
        .accessibilityValue(presented ? "Expanded" : "Collapsed")
        .accessibilityHint(presented ? "Choose a fresh herd or retry an unavailable herd" : "Opens the herd list")
        .onAppear {
            if ProcessInfo.processInfo.environment["BESSIE_DESIGN_ARTBOARD"] == "03" {
                presented = true
            }
        }
        .overlay(alignment: .topLeading) {
            if presented {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(rows) { row in
                        pickerRow(row).focused($focusedRow, equals: row.id)
                    }
                    Divider().overlay(BessieDesign.border).padding(.vertical, 3)
                    Button {
                        presented = false
                        addHerd()
                    } label: {
                        HStack(spacing: 8) { BessieIconView(icon: .plus, size: 14); Text("Add a host…") }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 9)
                            .frame(height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens connection settings")
                }
            }
            .padding(4)
            .frame(width: 228, height: HerdPickerPresentation.panelHeight(rowCount: rows.count))
            .background(BessieDesign.panel)
            .clipShape(RoundedRectangle(cornerRadius: HerdPickerPresentation.panelCornerRadius))
            .overlay { RoundedRectangle(cornerRadius: HerdPickerPresentation.panelCornerRadius).stroke(BessieDesign.border) }
            .offset(y: 36)
            .zIndex(300)
            .onAppear { focusedRow = rows.first?.id }
            }
        }
        .zIndex(presented ? 300 : 0)
        .onChange(of: presented) { _, shown in if !shown { triggerFocused = true } }
        .onExitCommand { presented = false }
    }

    private func pickerRow(_ row: HerdPickerRow) -> some View {
        HStack(spacing: 5) {
            Button {
                presented = false
                select(row.scope)
            } label: {
                HStack(spacing: 8) {
                if row.kind != .all { BessieIconView(icon: icon(row.kind), size: 14).frame(width: 16) }
                Text(row.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                Spacer(minLength: 6)
                if row.isSelected { BessieIconView(icon: .check, size: 13) }
                }
                .padding(.leading, 9)
                .padding(.trailing, row.canRetry ? 2 : 9)
                .frame(maxWidth: .infinity, minHeight: HerdPickerPresentation.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(row.title), \(row.detail)\(row.isSelected ? ", selected" : "")")
            if row.canRetry {
                Button("Retry") { retry(row.id) }
                    .buttonStyle(BessieQuietButtonStyle())
                    .accessibilityLabel("Retry \(row.title)")
                    .padding(.trailing, 5)
            }
        }
    }

    private func icon(_ kind: HerdPickerKind) -> BessieIcon {
        switch kind { case .all: .hardDrives; case .local: .desktop; case .ssh: .cloud }
    }
}
