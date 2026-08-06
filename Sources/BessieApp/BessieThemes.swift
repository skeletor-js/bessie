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
            palette: palette(
                desk: "#dce0e8", window: "#e6e9ef", background: "#eff1f5", rail: "#e6e9ef", panel: "#ffffff", inset: "#dce0e8",
                code: "#e6e9ef", codeText: "#4c4f69", codeSubtle: "#6c6f85", strong: "#3c3f59", text: "#4c4f69", subtle: "#6c6f85", faint: "#8c8fa1",
                border: "#7c7f93", borderOpacity: 0.22, borderStrong: "#6c6f85", borderStrongOpacity: 0.34, hover: "#7c7f93", hoverOpacity: 0.10, selected: "#1e66f5", selectedOpacity: 0.13,
                accent: "#1e66f5", accentSoft: "#1e66f5", accentSoftOpacity: 0.14, accentForeground: "#ffffff",
                blocked: "#d20f39", running: "#1e66f5", done: "#40a02b", idle: "#8c8fa1",
                diffAdded: "#287d16", diffAddedPlate: "#40a02b", diffRemoved: "#b80c32", diffRemovedPlate: "#d20f39", diffHunk: "#1e66f5", diffHunkPlate: "#1e66f5"
            ),
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
            palette: palette(
                desk: "#232634", window: "#292c3c", background: "#303446", rail: "#292c3c", panel: "#414559", inset: "#292c3c",
                code: "#232634", codeText: "#c6d0f5", codeSubtle: "#a5adce", strong: "#f2d5cf", text: "#c6d0f5", subtle: "#a5adce", faint: "#838ba7",
                border: "#a5adce", borderOpacity: 0.16, borderStrong: "#b5bfe2", borderStrongOpacity: 0.28, hover: "#c6d0f5", hoverOpacity: 0.07, selected: "#8caaee", selectedOpacity: 0.17,
                accent: "#8caaee", accentSoft: "#8caaee", accentSoftOpacity: 0.16, accentForeground: "#232634",
                blocked: "#e78284", running: "#8caaee", done: "#a6d189", idle: "#737994",
                diffAdded: "#a6d189", diffAddedPlate: "#a6d189", diffRemoved: "#e78284", diffRemovedPlate: "#e78284", diffHunk: "#8caaee", diffHunkPlate: "#8caaee"
            ),
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
            palette: palette(
                desk: "#181926", window: "#1e2030", background: "#24273a", rail: "#1e2030", panel: "#363a4f", inset: "#1e2030",
                code: "#181926", codeText: "#cad3f5", codeSubtle: "#a5adcb", strong: "#f4dbd6", text: "#cad3f5", subtle: "#a5adcb", faint: "#8087a2",
                border: "#a5adcb", borderOpacity: 0.16, borderStrong: "#b8c0e0", borderStrongOpacity: 0.28, hover: "#cad3f5", hoverOpacity: 0.07, selected: "#8aadf4", selectedOpacity: 0.17,
                accent: "#8aadf4", accentSoft: "#8aadf4", accentSoftOpacity: 0.16, accentForeground: "#181926",
                blocked: "#ed8796", running: "#8aadf4", done: "#a6da95", idle: "#6e738d",
                diffAdded: "#a6da95", diffAddedPlate: "#a6da95", diffRemoved: "#ed8796", diffRemovedPlate: "#ed8796", diffHunk: "#8aadf4", diffHunkPlate: "#8aadf4"
            ),
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
            palette: palette(
                desk: "#11111b", window: "#181825", background: "#1e1e2e", rail: "#181825", panel: "#313244", inset: "#181825",
                code: "#11111b", codeText: "#cdd6f4", codeSubtle: "#a6adc8", strong: "#f5e0dc", text: "#cdd6f4", subtle: "#a6adc8", faint: "#7f849c",
                border: "#a6adc8", borderOpacity: 0.16, borderStrong: "#bac2de", borderStrongOpacity: 0.28, hover: "#cdd6f4", hoverOpacity: 0.07, selected: "#89b4fa", selectedOpacity: 0.17,
                accent: "#89b4fa", accentSoft: "#89b4fa", accentSoftOpacity: 0.16, accentForeground: "#11111b",
                blocked: "#f38ba8", running: "#89b4fa", done: "#a6e3a1", idle: "#6c7086",
                diffAdded: "#a6e3a1", diffAddedPlate: "#a6e3a1", diffRemoved: "#f38ba8", diffRemovedPlate: "#f38ba8", diffHunk: "#89b4fa", diffHunkPlate: "#89b4fa"
            ),
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

    private static func palette(
        desk: String, window: String, background: String, rail: String, panel: String, inset: String,
        code: String, codeText: String, codeSubtle: String, strong: String, text: String, subtle: String, faint: String,
        border: String, borderOpacity: Double, borderStrong: String, borderStrongOpacity: Double,
        hover: String, hoverOpacity: Double, selected: String, selectedOpacity: Double,
        accent: String, accentSoft: String, accentSoftOpacity: Double, accentForeground: String,
        blocked: String, running: String, done: String, idle: String,
        diffAdded: String, diffAddedPlate: String, diffRemoved: String, diffRemovedPlate: String,
        diffHunk: String, diffHunkPlate: String
    ) -> BessiePalette {
        BessiePalette(
            desk: color(desk), window: color(window), background: color(background), rail: color(rail), panel: color(panel), inset: color(inset),
            code: color(code), codeText: color(codeText), codeSubtle: color(codeSubtle),
            strong: color(strong), text: color(text), subtle: color(subtle), faint: color(faint),
            border: color(border, opacity: borderOpacity), borderStrong: color(borderStrong, opacity: borderStrongOpacity),
            hover: color(hover, opacity: hoverOpacity), selected: color(selected, opacity: selectedOpacity),
            accent: color(accent), accentSoft: color(accentSoft, opacity: accentSoftOpacity), accentForeground: color(accentForeground),
            blocked: color(blocked), running: color(running), done: color(done), idle: color(idle),
            diffAdded: color(diffAdded), diffAddedPlate: color(diffAddedPlate, opacity: 0.20),
            diffRemoved: color(diffRemoved), diffRemovedPlate: color(diffRemovedPlate, opacity: 0.20),
            diffHunk: color(diffHunk), diffHunkPlate: color(diffHunkPlate, opacity: 0.20)
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
