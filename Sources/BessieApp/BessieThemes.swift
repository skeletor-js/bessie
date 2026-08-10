import AppKit
import BessieCore
import GhosttyTerminal
import SwiftUI

struct BessieTerminalPalette: Equatable, Sendable {
    let foreground: String
    let background: String
    let cursor: String
    let cursorText: String
    let selectionForeground: String
    let selectionBackground: String
    let ansi: [String]

    var configuration: TerminalConfiguration {
        TerminalConfiguration { builder in
            builder.withForeground(foreground)
            builder.withBackground(background)
            builder.withCursorColor(cursor)
            builder.withCursorText(cursorText)
            builder.withSelectionForeground(selectionForeground)
            builder.withSelectionBackground(selectionBackground)
            for (index, color) in ansi.enumerated() {
                builder.withPalette(index, color: color)
            }
        }
    }

    var theme: TerminalTheme {
        let configuration = configuration
        return TerminalTheme(light: configuration, dark: configuration)
    }
}

struct BessieThemeDefinition {
    let id: BessieThemeID
    let displayName: String
    let scheme: ColorScheme
    let palette: BessiePalette
    let terminal: BessieTerminalPalette
    let preview: [Color]

    var resolvedTerminalTheme: BessieResolvedTerminalTheme {
        BessieResolvedTerminalTheme(
            concreteID: id,
            scheme: scheme == .light ? .light : .dark,
            theme: terminal.theme
        )
    }
}

struct BessieResolvedTerminalTheme: Equatable, Sendable {
    let concreteID: BessieThemeID
    let scheme: TerminalColorScheme
    let theme: TerminalTheme
    let compatibility: GhosttyCompatibilityValues?

    init(
        concreteID: BessieThemeID,
        scheme: TerminalColorScheme,
        theme: TerminalTheme,
        compatibility: GhosttyCompatibilityValues? = nil
    ) {
        self.concreteID = concreteID
        self.scheme = scheme
        self.theme = theme
        self.compatibility = compatibility
    }

    func applyingCompatibility(_ profile: GhosttyCompatibilityProfile?) -> BessieResolvedTerminalTheme {
        return BessieResolvedTerminalTheme(
            concreteID: concreteID,
            scheme: scheme,
            theme: theme,
            compatibility: profile?.effective
        )
    }
}

enum CatppuccinDerivativeTarget: Equatable, Sendable {
    case palette(CatppuccinColorName)
    case composited(foreground: CatppuccinColorName, alpha: Double, background: CatppuccinColorName)

    func hex(for flavor: CatppuccinFlavor) -> String {
        switch self {
        case let .palette(name):
            return CatppuccinPalette.v1_8_0[flavor][name]!.hex
        case let .composited(foreground, alpha, background):
            let foregroundHex = CatppuccinPalette.v1_8_0[flavor][foreground]!.hex
            let backgroundHex = CatppuccinPalette.v1_8_0[flavor][background]!.hex
            let foregroundChannels = Self.channels(foregroundHex)
            let backgroundChannels = Self.channels(backgroundHex)
            let channels = zip(foregroundChannels, backgroundChannels).map {
                Int((Double($0) * alpha + Double($1) * (1 - alpha)).rounded())
            }
            return String(format: "#%02x%02x%02x", channels[0], channels[1], channels[2])
        }
    }

    private static func channels(_ hex: String) -> [Int] {
        let value = String(hex.dropFirst())
        return stride(from: 0, to: 6, by: 2).map { index in
            Int(value[value.index(value.startIndex, offsetBy: index)..<value.index(value.startIndex, offsetBy: index + 2)], radix: 16)!
        }
    }
}

enum CatppuccinAccessibilityDerivative: String, CaseIterable, Hashable, Sendable {
    case latteOnBlue
    case latteLink
    case latteActiveBorder
    case latteDiffAdded
    case latteDiffRemoved
    case latteDiffHunk

    var source: CatppuccinColorName {
        switch self {
        case .latteOnBlue: .base
        case .latteLink: .blue
        case .latteActiveBorder: .lavender
        case .latteDiffAdded: .green
        case .latteDiffRemoved: .red
        case .latteDiffHunk: .peach
        }
    }

    var target: CatppuccinDerivativeTarget {
        switch self {
        case .latteOnBlue: .palette(.blue)
        case .latteLink: .palette(.base)
        case .latteActiveBorder: .composited(foreground: .overlay2, alpha: 0.25, background: .surface0)
        case .latteDiffAdded, .latteDiffRemoved, .latteDiffHunk: .palette(.crust)
        }
    }

    var requiredContrast: Double { self == .latteActiveBorder ? 3 : 4.5 }

    var measuredContrast: Double {
        switch self {
        case .latteOnBlue: 4.501312632826
        case .latteLink: 4.505819186617
        case .latteActiveBorder: 3.010447412869
        case .latteDiffAdded: 4.544364425300
        case .latteDiffRemoved: 4.512243615966
        case .latteDiffHunk: 4.514935942774
        }
    }

    var hex: String {
        switch self {
        case .latteOnBlue: "#f3f5f9"
        case .latteLink: "#1d64ef"
        case .latteActiveBorder: "#4c5bcc"
        case .latteDiffAdded: "#2d711e"
        case .latteDiffRemoved: "#c60e36"
        case .latteDiffHunk: "#aa4307"
        }
    }
}

struct CatppuccinSemanticValue: Equatable, Sendable {
    let source: CatppuccinColorName
    let alpha: Double
    let derivative: CatppuccinAccessibilityDerivative?
    let hex: String
}

struct CatppuccinSemanticMapping {
    let values: [BessieSemanticColor.Role: CatppuccinSemanticValue]
    let palette: BessiePalette
}

struct CatppuccinDerivativeCandidate: Equatable, Sendable {
    let name: String
    let contrast: Double
    let lightnessDelta: Double
    let hueDelta: Double
    let chromaRetention: Double
}

enum CatppuccinDerivativeDisposition: Equatable, Sendable {
    case targetMet
    case strongestBoundedFallback
}

struct CatppuccinDerivativeSelection: Equatable, Sendable {
    let candidate: CatppuccinDerivativeCandidate
    let disposition: CatppuccinDerivativeDisposition
}

enum CatppuccinDerivativePolicy {
    static func select(
        from candidates: [CatppuccinDerivativeCandidate],
        requiredContrast: Double,
        maximumHueDelta: Double = 5,
        minimumChromaRetention: Double = 0.60
    ) -> CatppuccinDerivativeSelection? {
        let bounded = candidates.filter {
            $0.hueDelta <= maximumHueDelta && $0.chromaRetention >= minimumChromaRetention
        }
        if let candidate = bounded
            .filter({ $0.contrast >= requiredContrast })
            .min(by: { $0.lightnessDelta < $1.lightnessDelta }) {
            return CatppuccinDerivativeSelection(candidate: candidate, disposition: .targetMet)
        }
        guard let candidate = bounded.max(by: { $0.contrast < $1.contrast }) else { return nil }
        return CatppuccinDerivativeSelection(candidate: candidate, disposition: .strongestBoundedFallback)
    }
}

enum BessieThemeRegistry {
    static let selectableIDs = BessieThemeID.allCases

    static let definitions: [BessieThemeID: BessieThemeDefinition] = [
        .dark: definition(
            id: .dark,
            name: "Bessie Dark",
            scheme: .dark,
            palette: BessieDesign.palette(for: .dark),
            terminal: terminal(
                foreground: "#F5F5F5", background: "#080808", cursor: "#FFFFFF", cursorText: "#080808",
                selectionForeground: "#FFFFFF", selectionBackground: "#454545",
                ansi: ["#171717", "#D75F5F", "#5FAF5F", "#D7AF5F", "#5F87D7", "#AF87D7", "#5FAFAF", "#D0D0D0", "#626262", "#FF8787", "#87D787", "#FFD787", "#87AFFF", "#D7AFFF", "#87D7D7", "#FFFFFF"]
            )
        ),
        .light: definition(
            id: .light,
            name: "Bessie Light",
            scheme: .light,
            palette: BessieDesign.palette(for: .light),
            terminal: terminal(
                foreground: "#0C0C0C", background: "#FBFBFB", cursor: "#0C0C0C", cursorText: "#FBFBFB",
                selectionForeground: "#0C0C0C", selectionBackground: "#CFCFCF",
                ansi: ["#1C1C1C", "#A80000", "#007A19", "#8A6500", "#0057B8", "#7A3E9D", "#007777", "#C4C4C4", "#686868", "#D00000", "#008A24", "#A67800", "#006FE6", "#9854BF", "#008F8F", "#F2F2F2"]
            )
        ),
        .catppuccinLatte: definition(
            id: .catppuccinLatte,
            name: "Catppuccin Latte",
            scheme: .light,
            palette: catppuccinMapping(for: .latte).palette,
            terminal: terminal(
                foreground: "#4c4f69", background: "#eff1f5", cursor: "#dc8a78", cursorText: "#eff1f5",
                selectionForeground: "#4c4f69", selectionBackground: "#d8dae1",
                ansi: ["#5c5f77", "#d20f39", "#40a02b", "#df8e1d", "#1e66f5", "#ea76cb", "#179299", "#acb0be", "#6c6f85", "#d20f39", "#40a02b", "#df8e1d", "#1e66f5", "#ea76cb", "#179299", "#bcc0cc"]
            )
        ),
        .catppuccinFrappe: definition(
            id: .catppuccinFrappe,
            name: "Catppuccin Frappé",
            scheme: .dark,
            palette: catppuccinMapping(for: .frappe).palette,
            terminal: terminal(
                foreground: "#c6d0f5", background: "#303446", cursor: "#f2d5cf", cursorText: "#232634",
                selectionForeground: "#c6d0f5", selectionBackground: "#44495d",
                ansi: ["#51576d", "#e78284", "#a6d189", "#e5c890", "#8caaee", "#f4b8e4", "#81c8be", "#a5adce", "#626880", "#e78284", "#a6d189", "#e5c890", "#8caaee", "#f4b8e4", "#81c8be", "#b5bfe2"]
            )
        ),
        .catppuccinMacchiato: definition(
            id: .catppuccinMacchiato,
            name: "Catppuccin Macchiato",
            scheme: .dark,
            palette: catppuccinMapping(for: .macchiato).palette,
            terminal: terminal(
                foreground: "#cad3f5", background: "#24273a", cursor: "#f4dbd6", cursorText: "#181926",
                selectionForeground: "#cad3f5", selectionBackground: "#3a3e53",
                ansi: ["#494d64", "#ed8796", "#a6da95", "#eed49f", "#8aadf4", "#f5bde6", "#8bd5ca", "#a5adcb", "#5b6078", "#ed8796", "#a6da95", "#eed49f", "#8aadf4", "#f5bde6", "#8bd5ca", "#b8c0e0"]
            )
        ),
        .catppuccinMocha: definition(
            id: .catppuccinMocha,
            name: "Catppuccin Mocha",
            scheme: .dark,
            palette: catppuccinMapping(for: .mocha).palette,
            terminal: terminal(
                foreground: "#cdd6f4", background: "#1e1e2e", cursor: "#f5e0dc", cursorText: "#11111b",
                selectionForeground: "#cdd6f4", selectionBackground: "#353749",
                ansi: ["#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8", "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#bac2de"]
            )
        ),
    ]

    static func definition(for id: BessieThemeID, systemScheme: ColorScheme) -> BessieThemeDefinition {
        definitions[concreteID(for: id, systemScheme: systemScheme)] ?? definitions[.dark]!
    }

    static func concreteID(for id: BessieThemeID, systemScheme: ColorScheme) -> BessieThemeID {
        id == .system ? (systemScheme == .light ? .light : .dark) : id
    }

    static func scheme(for id: BessieThemeID, systemScheme: ColorScheme) -> ColorScheme {
        definition(for: id, systemScheme: systemScheme).scheme
    }

    static func preferredColorScheme(for id: BessieThemeID) -> ColorScheme? {
        id == .system ? nil : definition(for: id, systemScheme: .dark).scheme
    }

    static func quickToggleTarget(for id: BessieThemeID, systemScheme: ColorScheme) -> BessieThemeID {
        scheme(for: id, systemScheme: systemScheme) == .dark ? .light : .dark
    }

    private static func definition(
        id: BessieThemeID,
        name: String,
        scheme: ColorScheme,
        palette: BessiePalette,
        terminal: BessieTerminalPalette
    ) -> BessieThemeDefinition {
        BessieThemeDefinition(
            id: id,
            displayName: name,
            scheme: scheme,
            palette: palette,
            terminal: terminal,
            preview: [palette.background, palette.accent, palette.text]
        )
    }

    private static func terminal(
        foreground: String,
        background: String,
        cursor: String,
        cursorText: String,
        selectionForeground: String,
        selectionBackground: String,
        ansi: [String]
    ) -> BessieTerminalPalette {
        BessieTerminalPalette(
            foreground: foreground,
            background: background,
            cursor: cursor,
            cursorText: cursorText,
            selectionForeground: selectionForeground,
            selectionBackground: selectionBackground,
            ansi: ansi
        )
    }

    static func catppuccinMapping(for flavor: CatppuccinFlavor) -> CatppuccinSemanticMapping {
        func value(
            _ source: CatppuccinColorName,
            alpha: Double = 1,
            derivative: CatppuccinAccessibilityDerivative? = nil
        ) -> CatppuccinSemanticValue {
            precondition(derivative == nil || flavor == .latte)
            precondition(derivative == nil || derivative?.source == source)
            return CatppuccinSemanticValue(
                source: source,
                alpha: alpha,
                derivative: derivative,
                hex: derivative?.hex ?? CatppuccinPalette.v1_8_0[flavor][source]!.hex
            )
        }

        let latte = flavor == .latte
        let values: [BessieSemanticColor.Role: CatppuccinSemanticValue] = [
            .desk: value(.crust), .window: value(.mantle), .background: value(.base),
            .rail: value(.mantle), .panel: value(.surface0), .inset: value(.mantle),
            .code: value(.crust), .codeText: value(.text), .codeSubtle: value(.subtext0),
            .strong: value(.text), .text: value(.subtext1), .subtle: value(.subtext0),
            .faint: value(.overlay1), .border: value(.overlay0, alpha: 0.20),
            .borderStrong: value(.overlay0, alpha: 0.40),
            .activeBorder: value(.lavender, derivative: latte ? .latteActiveBorder : nil),
            .hover: value(.overlay2, alpha: 0.10), .selected: value(.overlay2, alpha: 0.25),
            .accent: value(.blue), .accentSoft: value(.blue, alpha: 0.15),
            .accentForeground: value(.base, derivative: latte ? .latteOnBlue : nil),
            .link: value(.blue, derivative: latte ? .latteLink : nil),
            .controlTint: value(.blue), .insertionPoint: value(.rosewater),
            .destructive: value(.red), .blocked: value(.red), .running: value(.blue),
            .done: value(.green), .idle: value(.overlay0),
            .diffAdded: value(.green, derivative: latte ? .latteDiffAdded : nil),
            .diffAddedPlate: value(.green, alpha: 0.20),
            .diffRemoved: value(.red, derivative: latte ? .latteDiffRemoved : nil),
            .diffRemovedPlate: value(.red, alpha: 0.20),
            .diffHunk: value(.peach, derivative: latte ? .latteDiffHunk : nil),
            .diffHunkPlate: value(.peach, alpha: 0.20),
        ]
        func mapped(_ role: BessieSemanticColor.Role) -> Color {
            let semantic = values[role]!
            return color(semantic.hex, opacity: semantic.alpha)
        }

        return CatppuccinSemanticMapping(
            values: values,
            palette: BessiePalette(
                desk: mapped(.desk), window: mapped(.window), background: mapped(.background),
                rail: mapped(.rail), panel: mapped(.panel), inset: mapped(.inset),
                code: mapped(.code), codeText: mapped(.codeText), codeSubtle: mapped(.codeSubtle),
                strong: mapped(.strong), text: mapped(.text), subtle: mapped(.subtle), faint: mapped(.faint),
                border: mapped(.border), borderStrong: mapped(.borderStrong), activeBorder: mapped(.activeBorder),
                hover: mapped(.hover), selected: mapped(.selected), accent: mapped(.accent),
                accentSoft: mapped(.accentSoft), accentForeground: mapped(.accentForeground),
                destructive: mapped(.destructive), link: mapped(.link), controlTint: mapped(.controlTint),
                insertionPoint: mapped(.insertionPoint), blocked: mapped(.blocked), running: mapped(.running),
                done: mapped(.done), idle: mapped(.idle), diffAdded: mapped(.diffAdded),
                diffAddedPlate: mapped(.diffAddedPlate), diffRemoved: mapped(.diffRemoved),
                diffRemovedPlate: mapped(.diffRemovedPlate), diffHunk: mapped(.diffHunk),
                diffHunkPlate: mapped(.diffHunkPlate)
            )
        )
    }

    private static func color(_ hex: String, opacity: Double = 1) -> Color {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
        return Color(
            .sRGB,
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255,
            opacity: opacity
        )
    }
}

extension BessieThemeID {
    var captureName: String {
        switch self {
        case .dark: "bessie-dark"
        case .light: "bessie-light"
        case .catppuccinLatte: "catppuccin-latte"
        case .catppuccinFrappe: "catppuccin-frappe"
        case .catppuccinMacchiato: "catppuccin-macchiato"
        case .catppuccinMocha: "catppuccin-mocha"
        case .system: "system"
        }
    }
}

final class BessieThemeSelectionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var concreteID: BessieThemeID = .dark

    func set(_ concreteID: BessieThemeID) {
        lock.lock()
        self.concreteID = concreteID
        lock.unlock()
    }

    func get() -> BessieThemeID {
        lock.lock()
        defer { lock.unlock() }
        return concreteID
    }
}

enum BessieThemeRuntime {
    private static let selection = BessieThemeSelectionBox()

    @MainActor
    static func publish(_ concreteID: BessieThemeID) {
        precondition(concreteID != .system)
        selection.set(concreteID)
    }

    static func palette() -> BessiePalette {
        BessieThemeRegistry.definition(for: selection.get(), systemScheme: .dark).palette
    }
}
