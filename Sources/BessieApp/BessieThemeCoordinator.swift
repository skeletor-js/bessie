import AppKit
import BessieCore
import SwiftUI

private struct BessieConcreteThemeIDKey: EnvironmentKey {
    static let defaultValue = BessieThemeID.dark
}

extension EnvironmentValues {
    var bessieConcreteThemeID: BessieThemeID {
        get { self[BessieConcreteThemeIDKey.self] }
        set { self[BessieConcreteThemeIDKey.self] = newValue }
    }
}

@MainActor
final class BessieThemeCoordinator: ObservableObject {
    @Published private(set) var effectiveConcreteID: BessieThemeID
    @Published var selectionError: String?

    private let settings: BessieSettingsModel
    private let terminalRegistry: TerminalControllerRegistry
    private let applyTerminalTheme: (BessieResolvedTerminalTheme) -> Bool
    private var systemScheme: ColorScheme

    init(
        settings: BessieSettingsModel,
        terminalRegistry: TerminalControllerRegistry,
        initialSystemScheme: ColorScheme = .dark,
        applyTerminalTheme: ((BessieResolvedTerminalTheme) -> Bool)? = nil
    ) {
        self.settings = settings
        self.terminalRegistry = terminalRegistry
        self.applyTerminalTheme = applyTerminalTheme ?? { [weak terminalRegistry] in
            terminalRegistry?.applyTheme($0) == true
        }
        systemScheme = initialSystemScheme
        let definition = BessieThemeRegistry.definition(
            for: settings.preferences.appearance,
            systemScheme: initialSystemScheme
        )
        effectiveConcreteID = definition.id
        terminalRegistry.setInitialTheme(definition.resolvedTerminalTheme)
        commitChrome(definition: definition, selection: settings.preferences.appearance)
    }

    @discardableResult
    func requestSelection(_ selection: BessieThemeID) -> Bool {
        let definition = BessieThemeRegistry.definition(for: selection, systemScheme: systemScheme)
        guard applyTerminalTheme(definition.resolvedTerminalTheme) else {
            selectionError = "The terminal rejected this built-in theme. Bessie kept the previous theme."
            return false
        }
        settings.commitThemeSelection(selection)
        effectiveConcreteID = definition.id
        selectionError = nil
        commitChrome(definition: definition, selection: selection)
        return true
    }

    func effectiveAppearanceChanged(_ scheme: ColorScheme) {
        systemScheme = scheme
        guard settings.preferences.appearance == .system else {
            let definition = BessieThemeRegistry.definition(
                for: settings.preferences.appearance,
                systemScheme: scheme
            )
            commitChrome(definition: definition, selection: settings.preferences.appearance)
            return
        }
        let definition = BessieThemeRegistry.definition(for: .system, systemScheme: scheme)
        guard definition.id != effectiveConcreteID else { return }
        guard applyTerminalTheme(definition.resolvedTerminalTheme) else {
            selectionError = "The terminal could not follow the Mac appearance. Bessie kept the previous theme."
            return
        }
        effectiveConcreteID = definition.id
        selectionError = nil
        commitChrome(definition: definition, selection: .system)
    }

    func binding() -> Binding<BessieThemeID> {
        Binding(
            get: { [settings] in settings.preferences.appearance },
            set: { [weak self] in _ = self?.requestSelection($0) }
        )
    }

    @discardableResult
    func resetPreferencesToDefaults() -> Bool {
        let defaults = BessiePreferences()
        guard requestSelection(defaults.appearance) else { return false }
        settings.preferences = defaults
        return true
    }

    private func commitChrome(definition: BessieThemeDefinition, selection: BessieThemeID) {
        BessieThemeRuntime.publish(definition.id)
        BessieSettingsModel.applyAppAppearance(
            selection: selection,
            effectiveScheme: definition.scheme,
            palette: definition.palette
        )
    }
}

struct BessieThemeAppearanceIngress: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: BessieThemeCoordinator

    func body(content: Content) -> some View {
        content
            .environment(\.bessieConcreteThemeID, coordinator.effectiveConcreteID)
            .onAppear { coordinator.effectiveAppearanceChanged(colorScheme) }
            .onChange(of: colorScheme) { _, scheme in coordinator.effectiveAppearanceChanged(scheme) }
            .alert("Theme couldn't be applied", isPresented: Binding(
                get: { coordinator.selectionError != nil },
                set: { if !$0 { coordinator.selectionError = nil } }
            )) {
                Button("OK") { coordinator.selectionError = nil }
            } message: {
                Text(coordinator.selectionError ?? "Bessie kept the previous theme.")
            }
    }
}
