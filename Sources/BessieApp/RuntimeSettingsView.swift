import AppKit
import BessieCore
import SwiftUI

struct RuntimeSettingsView: View {
    @EnvironmentObject private var model: BessieSettingsModel
    @State private var customPath = ""
    @State private var pendingKind: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BessieSectionLabel("HERDR RUNTIME")
            Picker("Runtime", selection: selection) {
                Text("Included").tag("bundled")
                Text("System (advanced)").tag("system")
                Text("Custom (advanced)").tag("custom")
            }
            .pickerStyle(.segmented)
            if selection.wrappedValue == "custom" {
                HStack {
                    TextField("/absolute/path/to/herdr", text: $customPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Use path") {
                        model.selectRuntime(.custom(URL(fileURLWithPath: customPath)))
                        if model.runtimePersistenceError == nil { pendingKind = nil }
                    }
                        .disabled(!customPath.hasPrefix("/"))
                }
            }
            Text("Included is recommended. An external choice is never replaced automatically if it is missing or incompatible.")
                .font(.system(size: 11)).foregroundStyle(BessieDesign.subtle)
            if let error = model.runtimePersistenceError {
                Text("The runtime choice was not changed: \(error)").font(.system(size: 11)).foregroundStyle(.red)
            }
            Button("Run Setup Again") { model.runSetupAgain() }
                .buttonStyle(BessieSecondaryButtonStyle())
        }
        .onAppear {
            if case .custom(let url) = model.runtimeSelection { customPath = url.path }
        }
    }

    private var selection: Binding<String> {
        Binding(get: {
            if let pendingKind { return pendingKind }
            return switch model.runtimeSelection { case .bundled: "bundled"; case .system: "system"; case .custom: "custom" }
        }, set: { value in
            if value == "bundled" { pendingKind = nil; model.selectRuntime(.bundled) }
            else if value == "system" { pendingKind = nil; model.selectRuntime(.system) }
            else { pendingKind = "custom" }
        })
    }
}
