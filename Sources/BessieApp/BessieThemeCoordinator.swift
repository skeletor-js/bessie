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
    @Published private(set) var compatibilityProfile: GhosttyCompatibilityProfile?
    @Published private(set) var compatibilityError: String?

    private let settings: BessieSettingsModel
    private let terminalRegistry: TerminalControllerRegistry
    private let applyTerminalTheme: (BessieResolvedTerminalTheme) -> TerminalThemeTransaction.Result
    private let compatibilityParser: GhosttyCompatibilityParser
    private var systemScheme: ColorScheme

    init(
        settings: BessieSettingsModel,
        terminalRegistry: TerminalControllerRegistry,
        initialSystemScheme: ColorScheme = .dark,
        compatibilityParser: GhosttyCompatibilityParser = .init(),
        applyTerminalTheme: ((BessieResolvedTerminalTheme) -> TerminalThemeTransaction.Result)? = nil
    ) {
        self.settings = settings
        self.terminalRegistry = terminalRegistry
        self.applyTerminalTheme = applyTerminalTheme ?? { [weak terminalRegistry] in
            terminalRegistry?.applyTheme($0) ?? .rejectedAndRestored
        }
        self.compatibilityParser = compatibilityParser
        systemScheme = initialSystemScheme
        let definition = BessieThemeRegistry.definition(
            for: settings.preferences.appearance,
            systemScheme: initialSystemScheme
        )
        effectiveConcreteID = definition.id

        var initialProfile: GhosttyCompatibilityProfile?
        var initialError: String?
        if settings.preferences.ghosttyCompatibilityEnabled,
           let path = settings.preferences.ghosttyCompatibilitySelectedPath {
            do {
                let candidate = try compatibilityParser.parse(URL(fileURLWithPath: path))
                if candidate.isValid {
                    initialProfile = candidate
                } else {
                    initialError = Self.invalidConfigurationMessage
                }
            } catch {
                initialError = Self.loadFailureMessage
            }
        }
        compatibilityProfile = initialProfile
        compatibilityError = initialError
        terminalRegistry.setInitialTheme(definition.resolvedTerminalTheme.applyingCompatibility(initialProfile))
        commitChrome(definition: definition, selection: settings.preferences.appearance)
    }

    @discardableResult
    func requestSelection(_ selection: BessieThemeID) -> Bool {
        let definition = BessieThemeRegistry.definition(for: selection, systemScheme: systemScheme)
        let result = applyTerminalTheme(resolvedTerminalTheme(for: definition))
        guard result.succeeded else {
            selectionError = failureMessage(result, restored: "The terminal rejected this built-in theme. Bessie kept the previous theme.")
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
        let result = applyTerminalTheme(resolvedTerminalTheme(for: definition))
        guard result.succeeded else {
            selectionError = failureMessage(result, restored: "The terminal could not follow the Mac appearance. Bessie kept the previous theme.")
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

    var compatibilitySummary: String? {
        guard settings.preferences.ghosttyCompatibilityEnabled, let compatibilityProfile else { return nil }
        let counts = Dictionary(grouping: compatibilityProfile.assignments, by: \.classification).mapValues(\.count)
        return "Applied \(counts[.applied, default: 0]) settings; \(counts[.overridden, default: 0]) overridden, \(counts[.ignored, default: 0]) ignored, and \(counts[.unsupported, default: 0]) unsupported."
    }

    @discardableResult
    func selectCompatibilityConfiguration(_ url: URL) -> Bool {
        guard let candidate = loadValidProfile(url) else { return false }
        if settings.preferences.ghosttyCompatibilityEnabled {
            let definition = currentDefinition()
            let previousTheme = resolvedTerminalTheme(for: definition)
            let result = applyTerminalTheme(definition.resolvedTerminalTheme.applyingCompatibility(candidate))
            guard result.succeeded else {
                compatibilityError = failureMessage(result, restored: "The terminal rejected the compatible presentation settings. Bessie kept the previous settings.")
                return false
            }
            guard settings.commitGhosttyCompatibility(enabled: true, selectedPath: candidate.rootURL.path) else {
                compatibilityError = persistenceFailureMessage(rollbackTheme: previousTheme)
                return false
            }
            compatibilityProfile = candidate
        } else {
            guard settings.commitGhosttyCompatibility(enabled: false, selectedPath: candidate.rootURL.path) else {
                compatibilityError = "Bessie couldn't save the selected Ghostty configuration. The previous selection remains active."
                return false
            }
        }
        compatibilityError = nil
        return true
    }

    @discardableResult
    func setCompatibilityEnabled(_ enabled: Bool) -> Bool {
        guard enabled != settings.preferences.ghosttyCompatibilityEnabled else { return true }
        let definition = currentDefinition()
        if enabled {
            guard let path = settings.preferences.ghosttyCompatibilitySelectedPath,
                  let candidate = loadValidProfile(URL(fileURLWithPath: path))
            else {
                if settings.preferences.ghosttyCompatibilitySelectedPath == nil {
                    compatibilityError = "Choose a Ghostty configuration file before enabling compatibility."
                }
                return false
            }
            let result = applyTerminalTheme(definition.resolvedTerminalTheme.applyingCompatibility(candidate))
            guard result.succeeded else {
                compatibilityError = failureMessage(result, restored: "The terminal rejected the compatible presentation settings. Bessie kept the previous settings.")
                return false
            }
            guard settings.commitGhosttyCompatibility(enabled: true, selectedPath: candidate.rootURL.path) else {
                compatibilityError = persistenceFailureMessage(rollbackTheme: definition.resolvedTerminalTheme)
                return false
            }
            compatibilityProfile = candidate
        } else {
            let previousTheme = resolvedTerminalTheme(for: definition)
            let result = applyTerminalTheme(definition.resolvedTerminalTheme)
            guard result.succeeded else {
                compatibilityError = failureMessage(result, restored: "The terminal could not restore Bessie's built-in theme. Compatibility remains enabled.")
                return false
            }
            guard settings.commitGhosttyCompatibility(
                enabled: false,
                selectedPath: settings.preferences.ghosttyCompatibilitySelectedPath
            ) else {
                compatibilityError = persistenceFailureMessage(rollbackTheme: previousTheme)
                return false
            }
            compatibilityProfile = nil
        }
        compatibilityError = nil
        return true
    }

    @discardableResult
    func reloadCompatibilityConfiguration() -> Bool {
        guard settings.preferences.ghosttyCompatibilityEnabled,
              let path = settings.preferences.ghosttyCompatibilitySelectedPath,
              let candidate = loadValidProfile(URL(fileURLWithPath: path))
        else { return false }
        let definition = currentDefinition()
        let result = applyTerminalTheme(definition.resolvedTerminalTheme.applyingCompatibility(candidate))
        guard result.succeeded else {
            compatibilityError = failureMessage(result, restored: "The terminal rejected the reloaded presentation settings. Bessie kept the last-known-good settings.")
            return false
        }
        compatibilityProfile = candidate
        compatibilityError = nil
        return true
    }

    @discardableResult
    func resetPreferencesToDefaults() -> Bool {
        let defaults = BessiePreferences()
        if settings.preferences.ghosttyCompatibilityEnabled, !setCompatibilityEnabled(false) { return false }
        guard requestSelection(defaults.appearance) else { return false }
        settings.preferences = defaults
        compatibilityProfile = nil
        compatibilityError = nil
        return true
    }

    private func resolvedTerminalTheme(for definition: BessieThemeDefinition) -> BessieResolvedTerminalTheme {
        definition.resolvedTerminalTheme.applyingCompatibility(
            settings.preferences.ghosttyCompatibilityEnabled ? compatibilityProfile : nil
        )
    }

    private func currentDefinition() -> BessieThemeDefinition {
        BessieThemeRegistry.definition(for: settings.preferences.appearance, systemScheme: systemScheme)
    }

    private func loadValidProfile(_ url: URL) -> GhosttyCompatibilityProfile? {
        do {
            let candidate = try compatibilityParser.parse(url)
            guard candidate.isValid else {
                compatibilityError = Self.invalidConfigurationMessage
                return nil
            }
            return candidate
        } catch {
            compatibilityError = Self.loadFailureMessage
            return nil
        }
    }

    private func commitChrome(definition: BessieThemeDefinition, selection: BessieThemeID) {
        BessieThemeRuntime.publish(definition.id)
        BessieSettingsModel.applyAppAppearance(
            selection: selection,
            effectiveScheme: definition.scheme,
            palette: definition.palette
        )
    }

    private func failureMessage(_ result: TerminalThemeTransaction.Result, restored: String) -> String {
        result == .rollbackFailed
            ? "Bessie couldn't restore every terminal surface after the update failed. Terminal appearance may be inconsistent until Bessie is restarted."
            : restored
    }

    private func persistenceFailureMessage(rollbackTheme: BessieResolvedTerminalTheme) -> String {
        let rollback = applyTerminalTheme(rollbackTheme)
        return rollback.succeeded
            ? "Bessie couldn't save the compatibility change. The previous terminal settings were restored."
            : failureMessage(.rollbackFailed, restored: "")
    }

    private static let invalidConfigurationMessage = "The Ghostty configuration contains invalid syntax or values. Bessie kept the last-known-good terminal presentation."
    private static let loadFailureMessage = "Bessie couldn't read the Ghostty configuration safely. The last-known-good terminal presentation remains active."
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
