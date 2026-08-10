import AppKit
import BessieCore
import SwiftUI

struct HerdrPrefixModePresentation: Equatable {
    static let isAnimated = false

    let text: String
    let accessibilityValue: String

    init?(mode: HerdrPrefixMode) {
        switch mode {
        case .idle:
            return nil
        case .armed:
            text = "PREFIX"
            accessibilityValue = "Prefix command armed"
        case .resize:
            text = "RESIZE"
            accessibilityValue = "Pane resize mode"
        }
    }
}

struct HerdrPrefixModeIndicator: View {
    let mode: HerdrPrefixMode

    var body: some View {
        if let presentation = HerdrPrefixModePresentation(mode: mode) {
            Text(presentation.text)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(BessieDesign.controlTint)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(BessieDesign.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))
                .accessibilityElement()
                .accessibilityLabel("Herdr keyboard mode")
                .accessibilityValue(presentation.accessibilityValue)
        }
    }
}

enum BessiePrefixFocusRestoration {
    static func canRestore(
        origin: BessiePrefixInputOwner,
        window: NSWindow,
        connectionID: String,
        connectionGeneration: UUID?,
        paneID: String,
        controllerID: ObjectIdentifier,
        terminalID: String
    ) -> Bool {
        origin.windowID == ObjectIdentifier(window)
            && origin.connectionID == connectionID
            && origin.connectionGeneration == connectionGeneration
            && origin.paneID == paneID
            && origin.terminalControllerID == controllerID
            && origin.terminalID == terminalID
    }
}

struct HerdrKeyboardReferenceRow: Identifiable, Equatable {
    let sequence: String
    let title: String
    let availability: String
    let detail: String

    var id: String { "\(sequence)-\(title)" }
    var accessibilityLabel: String { "\(sequence), \(title), \(availability). \(detail)" }
}

struct HerdrKeyboardReferenceModel: Equatable {
    let prefixRows: [HerdrKeyboardReferenceRow]
    let nativeRows: [HerdrKeyboardReferenceRow]
    let boundaryNotice = "Custom Herdr bindings and plugins are not reflected here. Real copy mode at Ctrl-B [ is unavailable through protocol 19."

    init(
        prefixDefinitions: [HerdrPrefixCommandDefinition] = HerdrPrefixCommandCatalog.definitions,
        nativeDefinitions: [BessieCommandDefinition] = BessieKeyboardShortcutRouter.commands
    ) {
        prefixRows = prefixDefinitions.map { definition in
            let availability: String
            let detail: String
            switch definition.availability {
            case .supported:
                availability = "Herdr default"
                detail = "Runs through Herdr's public protocol."
            case .graphicalEquivalent:
                availability = "Bessie graphical equivalent"
                detail = "Runs the matching Bessie application action."
            case .unavailable(let reason):
                availability = "unavailable"
                detail = reason
            }
            return HerdrKeyboardReferenceRow(
                sequence: definition.displaySequence,
                title: definition.title,
                availability: availability,
                detail: detail
            )
        }
        nativeRows = nativeDefinitions.compactMap { definition in
            guard let shortcut = definition.shortcut, !shortcut.hasPrefix("Ctrl-B") else { return nil }
            return HerdrKeyboardReferenceRow(
                sequence: shortcut,
                title: definition.title,
                availability: "Bessie native shortcut",
                detail: definition.detail
            )
        }
    }
}

struct HerdrKeyboardReferenceSheet: View {
    let close: () -> Void
    private let model = HerdrKeyboardReferenceModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Keyboard reference")
                        .font(.system(size: 20, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Herdr 0.8 defaults and Bessie application shortcuts")
                        .font(.system(size: 12))
                        .foregroundStyle(BessieDesign.subtle)
                }
                Spacer()
                Button("Close", action: close)
                    .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    referenceGroup("Herdr prefix commands", rows: model.prefixRows)
                    referenceGroup("Native Mac shortcuts", rows: model.nativeRows)
                    Text(model.boundaryNotice)
                        .font(.system(size: 11))
                        .foregroundStyle(BessieDesign.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(model.boundaryNotice)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 360, idealHeight: 560)
        .background(BessieDesign.background)
        .onExitCommand(perform: close)
        .onAppear {
            NSAccessibility.post(
                element: NSApplication.shared,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: "Keyboard reference",
                    .priority: NSAccessibilityPriorityLevel.medium.rawValue,
                ]
            )
        }
    }

    private func referenceGroup(_ title: String, rows: [HerdrKeyboardReferenceRow]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BessieDesign.strong)
                .accessibilityAddTraits(.isHeader)
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.sequence)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(BessieDesign.controlTint)
                        .frame(width: 118, alignment: .leading)
                    Text(row.title)
                        .font(.system(size: 11))
                    Spacer(minLength: 8)
                    Text(row.availability)
                        .font(.system(size: 10))
                        .foregroundStyle(BessieDesign.subtle)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.accessibilityLabel)
            }
        }
    }
}
