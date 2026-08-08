import AppKit
import BessieCore
import GhosttyTerminal
import SwiftUI
import XCTest
@testable import BessieApp

final class BessieThemeTests: XCTestCase {
    func testCuratedCatalogHasExactStableOrderAndNames() {
        XCTAssertEqual(BessieThemeRegistry.selectableIDs, [
            .system, .dark, .light, .catppuccinLatte, .catppuccinFrappe,
            .catppuccinMacchiato, .catppuccinMocha,
        ])
        XCTAssertEqual(BessieThemeRegistry.definitions.count, 6)
        XCTAssertEqual(BessieThemeRegistry.selectableIDs.map(\.title), [
            "System", "Bessie Dark", "Bessie Light", "Catppuccin Latte",
            "Catppuccin Frappé", "Catppuccin Macchiato", "Catppuccin Mocha",
        ])
        XCTAssertFalse(BessieThemeRegistry.selectableIDs.contains { $0.rawValue.lowercased().contains("tokyo") })
        XCTAssertFalse(BessieThemeRegistry.selectableIDs.contains { $0.rawValue.lowercased().contains("dracula") })
    }

    func testCanonicalCatppuccinV180PaletteHasEveryExactOpaqueSRGBColor() throws {
        let expected: [CatppuccinFlavor: [CatppuccinColorName: String]] = [
            .latte: expectedCatppuccinColors("dc8a78 dd7878 ea76cb 8839ef d20f39 e64553 fe640b df8e1d 40a02b 179299 04a5e5 209fb5 1e66f5 7287fd 4c4f69 5c5f77 6c6f85 7c7f93 8c8fa1 9ca0b0 acb0be bcc0cc ccd0da eff1f5 e6e9ef dce0e8"),
            .frappe: expectedCatppuccinColors("f2d5cf eebebe f4b8e4 ca9ee6 e78284 ea999c ef9f76 e5c890 a6d189 81c8be 99d1db 85c1dc 8caaee babbf1 c6d0f5 b5bfe2 a5adce 949cbb 838ba7 737994 626880 51576d 414559 303446 292c3c 232634"),
            .macchiato: expectedCatppuccinColors("f4dbd6 f0c6c6 f5bde6 c6a0f6 ed8796 ee99a0 f5a97f eed49f a6da95 8bd5ca 91d7e3 7dc4e4 8aadf4 b7bdf8 cad3f5 b8c0e0 a5adcb 939ab7 8087a2 6e738d 5b6078 494d64 363a4f 24273a 1e2030 181926"),
            .mocha: expectedCatppuccinColors("f5e0dc f2cdcd f5c2e7 cba6f7 f38ba8 eba0ac fab387 f9e2af a6e3a1 94e2d5 89dceb 74c7ec 89b4fa b4befe cdd6f4 bac2de a6adc8 9399b2 7f849c 6c7086 585b70 45475a 313244 1e1e2e 181825 11111b"),
        ]

        XCTAssertEqual(CatppuccinFlavor.allCases, [.latte, .frappe, .macchiato, .mocha])
        XCTAssertEqual(CatppuccinColorName.allCases.count, 26)
        XCTAssertEqual(Set(CatppuccinColorName.allCases.map(\.rawValue)).count, 26)
        XCTAssertEqual(Set(expected.keys), Set(CatppuccinFlavor.allCases))

        for flavor in CatppuccinFlavor.allCases {
            let palette = CatppuccinPalette.v1_8_0[flavor]
            XCTAssertEqual(Set(palette.colors.keys), Set(CatppuccinColorName.allCases), flavor.rawValue)
            XCTAssertEqual(palette.colors.count, 26, flavor.rawValue)
            for name in CatppuccinColorName.allCases {
                let color = try XCTUnwrap(palette[name], "\(flavor.rawValue).\(name.rawValue)")
                XCTAssertEqual(color.hex, expected[flavor]?[name], "\(flavor.rawValue).\(name.rawValue)")
                XCTAssertEqual(color.alpha, 255, "\(flavor.rawValue).\(name.rawValue)")
                XCTAssertEqual(color.red, UInt8(color.hex.dropFirst(1).prefix(2), radix: 16)!)
                XCTAssertEqual(color.green, UInt8(color.hex.dropFirst(3).prefix(2), radix: 16)!)
                XCTAssertEqual(color.blue, UInt8(color.hex.dropFirst(5).prefix(2), radix: 16)!)
            }
        }
    }

    @MainActor
    func testBessieDarkAndLightPalettesRetainExactRGBAFingerprints() throws {
        let dark = try XCTUnwrap(BessieThemeRegistry.definitions[.dark]?.palette)
        assertPalette(dark, equals: [
            "desk": [7/255, 7/255, 7/255, 1], "window": [5/255, 5/255, 5/255, 1],
            "background": [14/255, 14/255, 14/255, 1], "rail": [10/255, 10/255, 10/255, 1],
            "panel": [22/255, 22/255, 22/255, 1], "inset": [17/255, 17/255, 17/255, 1],
            "code": [8/255, 8/255, 8/255, 1], "codeText": [245/255, 245/255, 245/255, 1],
            "codeSubtle": [166/255, 166/255, 166/255, 1], "strong": [245/255, 245/255, 245/255, 1],
            "text": [182/255, 182/255, 182/255, 1], "subtle": [138/255, 138/255, 138/255, 1],
            "faint": [95/255, 95/255, 95/255, 1], "border": [1, 1, 1, 0.10],
            "borderStrong": [1, 1, 1, 0.19], "hover": [1, 1, 1, 0.055], "selected": [1, 1, 1, 0.10],
            "accent": [1, 1, 1, 1], "accentSoft": [1, 1, 1, 0.12], "accentForeground": [0, 0, 0, 1],
            "blocked": [1, 1, 1, 1], "running": [0.604, 0.604, 0.604, 1], "done": [0.863, 0.863, 0.863, 1],
            "idle": [0.373, 0.373, 0.373, 1], "diffAdded": [0.45, 0.82, 0.52, 1],
            "diffAddedPlate": [0.18, 0.42, 0.22, 0.28], "diffRemoved": [0.95, 0.48, 0.48, 1],
            "diffRemovedPlate": [0.45, 0.16, 0.16, 0.28], "diffHunk": [0.45, 0.72, 0.95, 1],
            "diffHunkPlate": [0.15, 0.28, 0.42, 0.35],
            "activeBorder": [1, 1, 1, 0.19], "destructive": [1, 56/255, 60/255, 1],
            "link": [245/255, 245/255, 245/255, 1], "controlTint": [245/255, 245/255, 245/255, 1],
            "insertionPoint": [245/255, 245/255, 245/255, 1],
        ])

        let light = try XCTUnwrap(BessieThemeRegistry.definitions[.light]?.palette)
        assertPalette(light, equals: [
            "desk": [232/255, 232/255, 232/255, 1], "window": [237/255, 237/255, 237/255, 1],
            "background": [250/255, 250/255, 250/255, 1], "rail": [245/255, 245/255, 245/255, 1],
            "panel": [1, 1, 1, 1], "inset": [242/255, 242/255, 242/255, 1],
            "code": [251/255, 251/255, 251/255, 1], "codeText": [12/255, 12/255, 12/255, 1],
            "codeSubtle": [107/255, 107/255, 107/255, 1], "strong": [12/255, 12/255, 12/255, 1],
            "text": [58/255, 58/255, 58/255, 1], "subtle": [107/255, 107/255, 107/255, 1],
            "faint": [154/255, 154/255, 154/255, 1], "border": [12/255, 12/255, 12/255, 0.12],
            "borderStrong": [12/255, 12/255, 12/255, 0.20], "hover": [12/255, 12/255, 12/255, 0.05],
            "selected": [12/255, 12/255, 12/255, 0.07], "accent": [12/255, 12/255, 12/255, 1],
            "accentSoft": [12/255, 12/255, 12/255, 0.10], "accentForeground": [1, 1, 1, 1],
            "blocked": [0.047, 0.047, 0.047, 1], "running": [0.416, 0.416, 0.416, 1],
            "done": [0.165, 0.165, 0.165, 1], "idle": [0.541, 0.541, 0.541, 1],
            "diffAdded": [0.15, 0.48, 0.22, 1], "diffAddedPlate": [0.78, 0.94, 0.80, 0.55],
            "diffRemoved": [0.72, 0.16, 0.18, 1], "diffRemovedPlate": [0.98, 0.82, 0.82, 0.55],
            "diffHunk": [0.10, 0.34, 0.68, 1], "diffHunkPlate": [0.82, 0.89, 0.98, 0.65],
            "activeBorder": [12/255, 12/255, 12/255, 0.20], "destructive": [1, 56/255, 60/255, 1],
            "link": [12/255, 12/255, 12/255, 1], "controlTint": [12/255, 12/255, 12/255, 1],
            "insertionPoint": [12/255, 12/255, 12/255, 1],
        ])
    }

    func testSystemResolutionRemainsLimitedToBessieDarkAndLight() {
        XCTAssertNil(BessieThemeRegistry.definitions[.system])
        XCTAssertEqual(BessieThemeRegistry.concreteID(for: .system, systemScheme: .dark), .dark)
        XCTAssertEqual(BessieThemeRegistry.concreteID(for: .system, systemScheme: .light), .light)
    }

    @MainActor
    func testCatppuccinSemanticMappingsUseCanonicalSourcesAndAuthoredTreatments() throws {
        let expectations: [(BessieSemanticColor.Role, CatppuccinColorName, Double)] = [
            (.desk, .crust, 1), (.window, .mantle, 1), (.background, .base, 1),
            (.rail, .mantle, 1), (.panel, .surface0, 1), (.inset, .mantle, 1),
            (.code, .crust, 1), (.codeText, .text, 1), (.codeSubtle, .subtext0, 1),
            (.strong, .text, 1), (.text, .subtext1, 1), (.subtle, .subtext0, 1),
            (.faint, .overlay1, 1), (.border, .overlay0, 0.20),
            (.borderStrong, .overlay0, 0.40), (.hover, .overlay2, 0.10),
            (.selected, .overlay2, 0.25), (.activeBorder, .lavender, 1),
            (.accent, .blue, 1), (.accentSoft, .blue, 0.15),
            (.accentForeground, .base, 1), (.link, .blue, 1), (.controlTint, .blue, 1),
            (.insertionPoint, .rosewater, 1), (.destructive, .red, 1),
            (.blocked, .red, 1), (.running, .blue, 1), (.done, .green, 1),
            (.idle, .overlay0, 1), (.diffAdded, .green, 1),
            (.diffAddedPlate, .green, 0.20), (.diffRemoved, .red, 1),
            (.diffRemovedPlate, .red, 0.20), (.diffHunk, .peach, 1),
            (.diffHunkPlate, .peach, 0.20),
        ]

        for flavor in CatppuccinFlavor.allCases {
            let mapping = BessieThemeRegistry.catppuccinMapping(for: flavor)
            XCTAssertEqual(mapping.values.count, expectations.count, flavor.rawValue)
            for (role, source, alpha) in expectations {
                let value = try XCTUnwrap(mapping.values[role], "\(flavor.rawValue).\(role)")
                XCTAssertEqual(value.source, source, "\(flavor.rawValue).\(role)")
                XCTAssertEqual(value.alpha, alpha, accuracy: 0.000_001, "\(flavor.rawValue).\(role)")
                let canonical = try XCTUnwrap(CatppuccinPalette.v1_8_0[flavor][source])
                if value.derivative == nil {
                    XCTAssertEqual(value.hex, canonical.hex, "\(flavor.rawValue).\(role)")
                }
                assertColor(role.color(in: mapping.palette), hex: value.hex, alpha: alpha)
            }
        }
    }

    @MainActor
    func testCatppuccinInteractionRolesRemainSemanticallyDistinct() {
        for flavor in CatppuccinFlavor.allCases {
            let values = BessieThemeRegistry.catppuccinMapping(for: flavor).values
            XCTAssertNotEqual(values[.border], values[.borderStrong])
            XCTAssertNotEqual(values[.border], values[.hover])
            XCTAssertNotEqual(values[.hover], values[.selected])
            XCTAssertNotEqual(values[.selected], values[.accentSoft])
            XCTAssertNotEqual(values[.selected], values[.activeBorder])
        }
    }

    @MainActor
    func testLatteAccessibilityDerivativesAreNamedBoundedAndMeasuredOnActualTargets() throws {
        let mapping = BessieThemeRegistry.catppuccinMapping(for: .latte)
        let expected: [(BessieSemanticColor.Role, CatppuccinAccessibilityDerivative)] = [
            (.accentForeground, .latteOnBlue), (.link, .latteLink),
            (.activeBorder, .latteActiveBorder), (.diffAdded, .latteDiffAdded),
            (.diffRemoved, .latteDiffRemoved), (.diffHunk, .latteDiffHunk),
        ]
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: expected.map { ($0.1, $0.1.hex) }), [
            .latteOnBlue: "#f3f5f9", .latteLink: "#1d64ef",
            .latteActiveBorder: "#4c5bcc", .latteDiffAdded: "#2d711e",
            .latteDiffRemoved: "#c60e36", .latteDiffHunk: "#aa4307",
        ])
        XCTAssertEqual(Set(mapping.values.values.compactMap(\.derivative)), Set(expected.map { $0.1 }))

        for (role, derivative) in expected {
            let value = try XCTUnwrap(mapping.values[role])
            XCTAssertEqual(value.derivative, derivative)
            XCTAssertEqual(value.source, derivative.source)
            let target = derivative.target.hex(for: .latte)
            let measured = contrast(value.hex, target)
            XCTAssertGreaterThanOrEqual(measured, derivative.requiredContrast, derivative.rawValue)
            XCTAssertEqual(measured, derivative.measuredContrast, accuracy: 0.000_001, derivative.rawValue)

            let sourceLCH = oklch(try XCTUnwrap(CatppuccinPalette.v1_8_0[.latte][derivative.source]).hex)
            let derivedLCH = oklch(value.hex)
            let hueDelta = min(abs(sourceLCH.h - derivedLCH.h), 360 - abs(sourceLCH.h - derivedLCH.h))
            XCTAssertLessThanOrEqual(hueDelta, 5, derivative.rawValue)
            XCTAssertGreaterThanOrEqual(derivedLCH.c, sourceLCH.c * 0.60, derivative.rawValue)
        }

        XCTAssertEqual(CatppuccinPalette.v1_8_0[.latte][.blue]?.hex, "#1e66f5")
        XCTAssertEqual(CatppuccinPalette.v1_8_0[.latte][.lavender]?.hex, "#7287fd")
        XCTAssertEqual(CatppuccinPalette.v1_8_0[.latte][.green]?.hex, "#40a02b")
        XCTAssertEqual(CatppuccinPalette.v1_8_0[.latte][.red]?.hex, "#d20f39")
        XCTAssertEqual(CatppuccinPalette.v1_8_0[.latte][.peach]?.hex, "#fe640b")
        XCTAssertEqual(CatppuccinPalette.v1_8_0[.latte][.base]?.hex, "#eff1f5")
    }

    @MainActor
    func testCatppuccinReadableRolesClearContrastOnTheirActualOpaqueTargets() throws {
        for flavor in CatppuccinFlavor.allCases {
            let values = BessieThemeRegistry.catppuccinMapping(for: flavor).values
            func hex(_ role: BessieSemanticColor.Role) throws -> String {
                try XCTUnwrap(values[role], "\(flavor.rawValue).\(role)").hex
            }

            for surface in [BessieSemanticColor.Role.window, .background, .panel] {
                XCTAssertGreaterThanOrEqual(contrast(try hex(.strong), try hex(surface)), 4.5, "\(flavor.rawValue).strong/\(surface)")
            }
            XCTAssertGreaterThanOrEqual(contrast(try hex(.accentForeground), try hex(.accent)), 4.5, "\(flavor.rawValue).accentForeground")
            XCTAssertGreaterThanOrEqual(contrast(try hex(.link), try hex(.background)), 4.5, "\(flavor.rawValue).link")
            let selectedPanel = CatppuccinDerivativeTarget.composited(
                foreground: .overlay2,
                alpha: 0.25,
                background: .surface0
            ).hex(for: flavor)
            XCTAssertGreaterThanOrEqual(contrast(try hex(.activeBorder), selectedPanel), 3, "\(flavor.rawValue).activeBorder")
            for role in [BessieSemanticColor.Role.diffAdded, .diffRemoved, .diffHunk] {
                XCTAssertGreaterThanOrEqual(contrast(try hex(role), try hex(.code)), 4.5, "\(flavor.rawValue).\(role)")
            }
        }
    }

    func testBoundedDerivativePolicyPrefersSmallestPassingChangeAndHasExplicitFallback() throws {
        let candidates = [
            CatppuccinDerivativeCandidate(name: "small passing", contrast: 4.6, lightnessDelta: 0.08, hueDelta: 1, chromaRetention: 0.8),
            CatppuccinDerivativeCandidate(name: "large passing", contrast: 5.1, lightnessDelta: 0.20, hueDelta: 1, chromaRetention: 0.8),
            CatppuccinDerivativeCandidate(name: "unbounded", contrast: 12, lightnessDelta: 0.30, hueDelta: 6, chromaRetention: 0.9),
        ]
        let passing = try XCTUnwrap(CatppuccinDerivativePolicy.select(from: candidates, requiredContrast: 4.5))
        XCTAssertEqual(passing.candidate.name, "small passing")
        XCTAssertEqual(passing.disposition, .targetMet)

        let impossible = try XCTUnwrap(CatppuccinDerivativePolicy.select(from: candidates, requiredContrast: 7))
        XCTAssertEqual(impossible.candidate.name, "large passing")
        XCTAssertEqual(impossible.disposition, .strongestBoundedFallback)
        XCTAssertNil(CatppuccinDerivativePolicy.select(
            from: [CatppuccinDerivativeCandidate(name: "unbounded", contrast: 12, lightnessDelta: 0.3, hueDelta: 5.1, chromaRetention: 0.59)],
            requiredContrast: 4.5
        ))
    }

    @MainActor
    func testEveryConcreteThemeHasCompleteValidTerminalColorsAndAccessiblePrimaryContrast() throws {
        for id in BessieThemeRegistry.selectableIDs where id != .system {
            let definition = try XCTUnwrap(BessieThemeRegistry.definitions[id])
            let terminal = definition.terminal
            XCTAssertEqual(terminal.ansi.count, 16, id.rawValue)
            for value in [
                terminal.foreground, terminal.background, terminal.cursor, terminal.cursorText,
                terminal.selectionForeground, terminal.selectionBackground,
            ] + terminal.ansi {
                XCTAssertNotNil(value.range(of: #"^#[0-9a-fA-F]{6}$"#, options: .regularExpression), "\(id.rawValue): \(value)")
            }
            XCTAssertGreaterThanOrEqual(contrast(terminal.foreground, terminal.background), 4.5, id.rawValue)
            for surface in [definition.palette.window, definition.palette.background, definition.palette.panel] {
                XCTAssertGreaterThanOrEqual(contrast(definition.palette.strong, surface), 4.5, id.rawValue)
            }
            XCTAssertGreaterThanOrEqual(contrast(definition.palette.accentForeground, definition.palette.accent), 3, id.rawValue)

            let controller = TerminalController(theme: terminal.theme) { _ in }
            let rendered = controller.renderedConfig.lowercased()
            XCTAssertTrue(rendered.contains("foreground = \(terminal.foreground.lowercased())"), id.rawValue)
            XCTAssertTrue(rendered.contains("background = \(terminal.background.lowercased())"), id.rawValue)
            for (index, color) in terminal.ansi.enumerated() {
                XCTAssertTrue(rendered.contains("palette = \(index)=\(color.lowercased())"), "\(id.rawValue) palette \(index)")
            }
        }
    }

    func testOfficialCatppuccinGhosttyValuesArePinnedExactly() throws {
        let latte = try XCTUnwrap(BessieThemeRegistry.definitions[.catppuccinLatte]?.terminal)
        XCTAssertEqual(latte.ansi, ["#5c5f77", "#d20f39", "#40a02b", "#df8e1d", "#1e66f5", "#ea76cb", "#179299", "#acb0be", "#6c6f85", "#d20f39", "#40a02b", "#df8e1d", "#1e66f5", "#ea76cb", "#179299", "#bcc0cc"])
        XCTAssertEqual([latte.background, latte.foreground, latte.cursor, latte.cursorText, latte.selectionBackground, latte.selectionForeground], ["#eff1f5", "#4c4f69", "#dc8a78", "#eff1f5", "#d8dae1", "#4c4f69"])

        let frappe = try XCTUnwrap(BessieThemeRegistry.definitions[.catppuccinFrappe]?.terminal)
        XCTAssertEqual(frappe.ansi, ["#51576d", "#e78284", "#a6d189", "#e5c890", "#8caaee", "#f4b8e4", "#81c8be", "#a5adce", "#626880", "#e78284", "#a6d189", "#e5c890", "#8caaee", "#f4b8e4", "#81c8be", "#b5bfe2"])
        XCTAssertEqual([frappe.background, frappe.foreground, frappe.cursor, frappe.cursorText, frappe.selectionBackground, frappe.selectionForeground], ["#303446", "#c6d0f5", "#f2d5cf", "#232634", "#44495d", "#c6d0f5"])

        let macchiato = try XCTUnwrap(BessieThemeRegistry.definitions[.catppuccinMacchiato]?.terminal)
        XCTAssertEqual(macchiato.ansi, ["#494d64", "#ed8796", "#a6da95", "#eed49f", "#8aadf4", "#f5bde6", "#8bd5ca", "#a5adcb", "#5b6078", "#ed8796", "#a6da95", "#eed49f", "#8aadf4", "#f5bde6", "#8bd5ca", "#b8c0e0"])
        XCTAssertEqual([macchiato.background, macchiato.foreground, macchiato.cursor, macchiato.cursorText, macchiato.selectionBackground, macchiato.selectionForeground], ["#24273a", "#cad3f5", "#f4dbd6", "#181926", "#3a3e53", "#cad3f5"])

        let mocha = try XCTUnwrap(BessieThemeRegistry.definitions[.catppuccinMocha]?.terminal)
        XCTAssertEqual(mocha.ansi, ["#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8", "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#bac2de"])
        XCTAssertEqual([mocha.background, mocha.foreground, mocha.cursor, mocha.cursorText, mocha.selectionBackground, mocha.selectionForeground], ["#1e1e2e", "#cdd6f4", "#f5e0dc", "#11111b", "#353749", "#cdd6f4"])
    }

    @MainActor
    func testThemeTransactionRollsBackEarlierTargetsAfterMidFanOutRejection() {
        let previous = BessieThemeRegistry.definitions[.dark]!.resolvedTerminalTheme
        let candidate = BessieThemeRegistry.definitions[.catppuccinMocha]!.resolvedTerminalTheme
        var first = previous
        var second = previous
        var third = previous

        let result = TerminalThemeTransaction.apply(candidate: candidate, previous: previous, targets: [
            .init { first = $0; return true },
            .init { theme in
                if theme == candidate { return false }
                second = theme
                return true
            },
            .init { third = $0; return true },
        ])

        XCTAssertEqual(result, .rejectedAndRestored)
        XCTAssertEqual(first, previous)
        XCTAssertEqual(second, previous)
        XCTAssertEqual(third, previous)
    }

    @MainActor
    func testThemeTransactionStopsAtFirstRejectedTarget() {
        let previous = BessieThemeRegistry.definitions[.dark]!.resolvedTerminalTheme
        let candidate = BessieThemeRegistry.definitions[.catppuccinLatte]!.resolvedTerminalTheme
        var secondCalls = 0

        let result = TerminalThemeTransaction.apply(candidate: candidate, previous: previous, targets: [
            .init { _ in false },
            .init { _ in secondCalls += 1; return true },
        ])

        XCTAssertEqual(result, .rollbackFailed)
        XCTAssertEqual(secondCalls, 0)
    }

    @MainActor
    func testThemeTransactionReportsRollbackFailureInsteadOfClaimingRestoration() {
        let previous = BessieThemeRegistry.definitions[.dark]!.resolvedTerminalTheme
        let candidate = BessieThemeRegistry.definitions[.catppuccinLatte]!.resolvedTerminalTheme
        var firstCalls: [BessieResolvedTerminalTheme] = []

        let result = TerminalThemeTransaction.apply(candidate: candidate, previous: previous, targets: [
            .init { theme in
                firstCalls.append(theme)
                return theme == candidate
            },
            .init { theme in theme == previous },
        ])

        XCTAssertEqual(result, .rollbackFailed)
        XCTAssertEqual(firstCalls, [candidate, previous])
    }

    @MainActor
    func testLiveControllerThemeChangePreservesIdentityAndTerminalOverrides() throws {
        let controller = PaneTerminalController(
            paneID: "theme-live-update",
            endpoint: HerdrTerminalEndpoint(
                connectionID: "test",
                executablePath: "/usr/bin/false",
                socketPath: "/tmp/missing"
            )
        )
        let identity = ObjectIdentifier(controller)
        let candidate = BessieThemeRegistry.definitions[.catppuccinLatte]!.resolvedTerminalTheme

        controller.updateFontSize(17)
        XCTAssertTrue(controller.updateTheme(candidate))

        XCTAssertEqual(ObjectIdentifier(controller), identity)
        XCTAssertEqual(controller.ghosttyController.theme, candidate.theme)
        XCTAssertEqual(controller.ghosttyController.effectiveColorScheme, .light)
        let rendered = controller.ghosttyController.renderedConfig
        XCTAssertTrue(rendered.contains("font-size = 17"))
        XCTAssertTrue(rendered.contains("mouse-reporting = false"))
        XCTAssertTrue(rendered.contains("macos-option-as-alt = left"))
        XCTAssertTrue(rendered.lowercased().contains("background = #eff1f5"))
        for (index, color) in BessieThemeRegistry.definitions[.catppuccinLatte]!.terminal.ansi.enumerated() {
            XCTAssertTrue(rendered.lowercased().contains("palette = \(index)=\(color)"))
        }
        XCTAssertNil(controller.themeConfigurationError)
    }

    @MainActor
    func testThemeChangeMovesHostDefaultsButPreservesApplicationRGBFrame() throws {
        let dark = BessieThemeRegistry.definitions[.dark]!.resolvedTerminalTheme
        let light = BessieThemeRegistry.definitions[.light]!.resolvedTerminalTheme
        let controller = PaneTerminalController(
            paneID: "semantic-color-pair",
            endpoint: HerdrTerminalEndpoint(
                connectionID: "test",
                executablePath: "/usr/bin/false",
                socketPath: "/tmp/missing"
            ),
            theme: dark
        )
        let host = TerminalSurfaceHostView(frame: NSRect(x: 0, y: 0, width: 640, height: 320))
        let window = NSWindow(
            contentRect: host.bounds,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        host.attach(controller: controller, fontSize: 13, requestFocus: {}, responderChanged: { _ in })
        host.layoutSubtreeIfNeeded()
        defer {
            host.detach()
            window.orderOut(nil)
            controller.release()
        }
        let ansi = Data("\u{1b}[39;49mhost-default \u{1b}[38;2;255;248;220;48;2;16;16;20mapp-pair\u{1b}[39;49m host-again".utf8)

        controller.session.receive(ansi)
        for _ in 0..<10 where controller.session.readViewportText()?.contains("app-pair") != true {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertTrue(
            controller.session.readViewportText()?.contains("host-default app-pair host-again") == true,
            controller.session.readViewportText() ?? "nil viewport"
        )
        XCTAssertTrue(controller.ghosttyController.renderedConfig.lowercased().contains("foreground = #f5f5f5"))
        XCTAssertTrue(controller.ghosttyController.renderedConfig.lowercased().contains("background = #080808"))

        XCTAssertTrue(controller.updateTheme(light))

        XCTAssertTrue(
            controller.session.readViewportText()?.contains("host-default app-pair host-again") == true,
            controller.session.readViewportText() ?? "nil viewport"
        )
        XCTAssertTrue(controller.ghosttyController.renderedConfig.lowercased().contains("foreground = #0c0c0c"))
        XCTAssertTrue(controller.ghosttyController.renderedConfig.lowercased().contains("background = #fbfbfb"))
    }

    @MainActor
    func testRejectedLiveControllerCandidateRestoresWorkingThemeAndStatus() {
        let controller = PaneTerminalController(
            paneID: "theme-live-rejection",
            endpoint: HerdrTerminalEndpoint(
                connectionID: "test",
                executablePath: "/usr/bin/false",
                socketPath: "/tmp/missing"
            )
        )
        let previousTheme = controller.ghosttyController.theme
        let previousScheme = controller.ghosttyController.effectiveColorScheme
        let previousStatus = controller.status
        let invalidConfiguration = TerminalConfiguration { builder in
            builder.withBackground("not-a-color")
        }
        let invalid = BessieResolvedTerminalTheme(
            concreteID: .catppuccinMocha,
            scheme: .dark,
            theme: TerminalTheme(light: invalidConfiguration, dark: invalidConfiguration)
        )

        XCTAssertFalse(controller.updateTheme(invalid))
        XCTAssertEqual(controller.ghosttyController.theme, previousTheme)
        XCTAssertEqual(controller.ghosttyController.effectiveColorScheme, previousScheme)
        XCTAssertEqual(controller.status, previousStatus)
        XCTAssertNil(controller.themeConfigurationError)
    }

    @MainActor
    func testRegistryUpdatesVisibleWarmAndFutureControllersWithoutReplacingIdentity() throws {
        let registry = TerminalControllerRegistry(warmCapacity: 3)
        let endpoint = HerdrTerminalEndpoint(
            connectionID: "test",
            executablePath: "/usr/bin/false",
            socketPath: "/tmp/missing"
        )
        registry.reconcile(
            presentedPaneIDs: ["visible-a", "visible-b"],
            availablePaneIDs: ["visible-a", "visible-b", "warm", "future"],
            prewarmPaneIDs: ["warm"],
            endpoint: endpoint
        )
        let original = registry.controllers.mapValues(ObjectIdentifier.init)
        let latte = BessieThemeRegistry.definitions[.catppuccinLatte]!.resolvedTerminalTheme

        XCTAssertEqual(registry.applyTheme(latte), .applied)
        for (paneID, controller) in registry.controllers {
            XCTAssertEqual(ObjectIdentifier(controller), original[paneID])
            XCTAssertEqual(controller.ghosttyController.theme, latte.theme)
            XCTAssertEqual(controller.ghosttyController.effectiveColorScheme, .light)
        }

        registry.reconcile(
            presentedPaneIDs: ["visible-a", "visible-b", "future"],
            availablePaneIDs: ["visible-a", "visible-b", "warm", "future"],
            prewarmPaneIDs: ["warm"],
            endpoint: endpoint
        )
        let future = try XCTUnwrap(registry.controllers["future"])
        XCTAssertEqual(future.ghosttyController.theme, latte.theme)
        XCTAssertEqual(future.ghosttyController.effectiveColorScheme, .light)
        registry.releaseAll()
    }

    @MainActor
    func testRejectedSelectionLeavesPreferenceAndEffectiveAppThemeUnchanged() throws {
        defer { BessieThemeRuntime.publish(.dark) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = BessieSettingsModel(
            presentationURL: root.appendingPathComponent("presentation.json"),
            connectionsURL: root.appendingPathComponent("connections.json"),
            runtimeSelectionURL: root.appendingPathComponent("runtime.json")
        )
        let registry = TerminalControllerRegistry()
        let coordinator = BessieThemeCoordinator(
            settings: settings,
            terminalRegistry: registry,
            applyTerminalTheme: { _ in .rejectedAndRestored }
        )

        XCTAssertFalse(coordinator.requestSelection(.catppuccinMocha))
        XCTAssertEqual(settings.preferences.appearance, .dark)
        XCTAssertEqual(coordinator.effectiveConcreteID, .dark)
        XCTAssertNotNil(coordinator.selectionError)
    }

    @MainActor
    func testRejectedDefaultResetLeavesEveryPreferenceUnchanged() throws {
        defer { BessieThemeRuntime.publish(.dark) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let original = BessiePreferences(
            appearance: .catppuccinMocha,
            density: .compact,
            appIcon: .light,
            cowprintEnabled: false,
            terminalFontSize: 19,
            paneGap: 12
        )
        let presentationURL = root.appendingPathComponent("presentation.json")
        try BessiePresentationStore(url: presentationURL).save(BessiePresentationState(preferences: original))
        let settings = BessieSettingsModel(
            presentationURL: presentationURL,
            connectionsURL: root.appendingPathComponent("connections.json"),
            runtimeSelectionURL: root.appendingPathComponent("runtime.json")
        )
        let coordinator = BessieThemeCoordinator(
            settings: settings,
            terminalRegistry: TerminalControllerRegistry(),
            applyTerminalTheme: { _ in .rejectedAndRestored }
        )

        XCTAssertFalse(coordinator.resetPreferencesToDefaults())
        XCTAssertEqual(settings.preferences, original)
    }

    @MainActor
    func testSystemAppearanceChangesConcreteTerminalFingerprintWithoutChangingPersistedSelection() throws {
        defer { BessieThemeRuntime.publish(.dark) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let presentationURL = root.appendingPathComponent("presentation.json")
        try BessiePresentationStore(url: presentationURL).save(BessiePresentationState(
            preferences: BessiePreferences(appearance: .system)
        ))
        let settings = BessieSettingsModel(
            presentationURL: presentationURL,
            connectionsURL: root.appendingPathComponent("connections.json"),
            runtimeSelectionURL: root.appendingPathComponent("runtime.json")
        )
        let registry = TerminalControllerRegistry()
        let coordinator = BessieThemeCoordinator(
            settings: settings,
            terminalRegistry: registry,
            initialSystemScheme: .dark
        )

        coordinator.effectiveAppearanceChanged(.light)

        XCTAssertEqual(settings.preferences.appearance, .system)
        XCTAssertEqual(coordinator.effectiveConcreteID, .light)
        XCTAssertEqual(registry.effectiveTheme.concreteID, .light)
    }

    @MainActor
    func testFixedThemeIgnoresSystemAppearanceChanges() throws {
        defer { BessieThemeRuntime.publish(.dark) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let presentationURL = root.appendingPathComponent("presentation.json")
        try BessiePresentationStore(url: presentationURL).save(BessiePresentationState(
            preferences: BessiePreferences(appearance: .catppuccinMacchiato)
        ))
        let settings = BessieSettingsModel(
            presentationURL: presentationURL,
            connectionsURL: root.appendingPathComponent("connections.json"),
            runtimeSelectionURL: root.appendingPathComponent("runtime.json")
        )
        let registry = TerminalControllerRegistry()
        var terminalApplyCount = 0
        let coordinator = BessieThemeCoordinator(
            settings: settings,
            terminalRegistry: registry,
            initialSystemScheme: .dark,
            applyTerminalTheme: { _ in terminalApplyCount += 1; return .applied }
        )

        coordinator.effectiveAppearanceChanged(.light)

        XCTAssertEqual(settings.preferences.appearance, .catppuccinMacchiato)
        XCTAssertEqual(coordinator.effectiveConcreteID, .catppuccinMacchiato)
        XCTAssertEqual(terminalApplyCount, 0)
    }

    @MainActor
    func testDarkToDarkPublicationChangesTheConcreteChromePalette() throws {
        defer { BessieThemeRuntime.publish(.dark) }
        BessieThemeRuntime.publish(.catppuccinFrappe)
        let frappe = try XCTUnwrap(NSColor(BessieDesign.background.currentColor).usingColorSpace(.sRGB))

        BessieThemeRuntime.publish(.catppuccinMocha)
        let mocha = try XCTUnwrap(NSColor(BessieDesign.background.currentColor).usingColorSpace(.sRGB))

        XCTAssertNotEqual(
            [frappe.redComponent, frappe.greenComponent, frappe.blueComponent],
            [mocha.redComponent, mocha.greenComponent, mocha.blueComponent]
        )
    }

    @MainActor
    func testMountedChromeTracksEveryDarkCatppuccinSelectionWithoutRecreatingFocusedTerminal() throws {
        defer { BessieThemeRuntime.publish(.dark) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let presentationURL = root.appendingPathComponent("presentation.json")
        try BessiePresentationStore(url: presentationURL).save(BessiePresentationState(
            preferences: BessiePreferences(appearance: .catppuccinFrappe)
        ))
        let settings = BessieSettingsModel(
            presentationURL: presentationURL,
            connectionsURL: root.appendingPathComponent("connections.json"),
            runtimeSelectionURL: root.appendingPathComponent("runtime.json")
        )
        let registry = TerminalControllerRegistry()
        let coordinator = BessieThemeCoordinator(
            settings: settings,
            terminalRegistry: registry,
            initialSystemScheme: .dark
        )
        registry.reconcile(
            presentedPaneIDs: ["mounted-theme"],
            availablePaneIDs: ["mounted-theme"],
            endpoint: HerdrTerminalEndpoint(
                connectionID: "test",
                executablePath: "/usr/bin/false",
                socketPath: "/tmp/missing"
            )
        )
        let controller = try XCTUnwrap(registry.controllers["mounted-theme"])
        let controllerIdentity = ObjectIdentifier(controller)

        let chrome = NSHostingView(rootView: MountedThemeChromeProbe()
            .modifier(BessieThemeAppearanceIngress())
            .environmentObject(coordinator))
        chrome.frame = NSRect(x: 0, y: 0, width: 160, height: 100)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 100))
        content.addSubview(chrome)
        controller.terminalView.frame = NSRect(x: 170, y: 0, width: 50, height: 100)
        content.addSubview(controller.terminalView)
        let window = NSWindow(
            contentRect: content.bounds,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.makeFirstResponder(controller.terminalView))
        drainMountedThemeUpdates(chrome)
        defer {
            window.orderOut(nil)
            controller.terminalView.removeFromSuperview()
            registry.releaseAll()
        }

        var observedBackgrounds: [[CGFloat]] = []
        for themeID in [
            BessieThemeID.catppuccinFrappe,
            .catppuccinMacchiato,
            .catppuccinMocha,
            .catppuccinFrappe,
            .catppuccinMacchiato,
            .catppuccinMocha,
        ] {
            XCTAssertTrue(coordinator.requestSelection(themeID), themeID.rawValue)
            drainMountedThemeUpdates(chrome)

            let definition = try XCTUnwrap(BessieThemeRegistry.definitions[themeID])
            let actual = try mountedBackgroundColor(chrome)
            let components = [actual.redComponent, actual.greenComponent, actual.blueComponent]
            if let previous = observedBackgrounds.last {
                let delta = zip(components, previous).reduce(CGFloat.zero) { result, pair in
                    result + abs(pair.0 - pair.1)
                }
                XCTAssertGreaterThan(delta, 0.04, themeID.rawValue)
            }
            observedBackgrounds.append(components)

            XCTAssertEqual(settings.preferences.appearance, themeID)
            XCTAssertEqual(coordinator.effectiveConcreteID, themeID)
            XCTAssertEqual(try BessiePresentationStore(url: presentationURL).load().preferences.appearance, themeID)
            XCTAssertEqual(registry.effectiveTheme.concreteID, themeID)
            XCTAssertEqual(ObjectIdentifier(controller), controllerIdentity)
            XCTAssertTrue(window.firstResponder === controller.terminalView)
            XCTAssertTrue(controller.ghosttyController.renderedConfig.lowercased().contains(
                "background = \(definition.terminal.background)"
            ))
        }
        XCTAssertEqual(Set(observedBackgrounds.map { $0.map(String.init(describing:)).joined(separator: ",") }).count, 3)
    }

    @MainActor
    func testThemeChromeDoesNotPaintTheStatusItemWindow() throws {
        let statusItem = NSStatusBar.system.statusItem(withLength: 30)
        let statusWindow = try XCTUnwrap(statusItem.button?.window)
        let originalStatusBackground = statusWindow.backgroundColor
        let originalAppearance = NSApp.appearance
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        defer {
            statusWindow.backgroundColor = originalStatusBackground
            NSStatusBar.system.removeStatusItem(statusItem)
            window.close()
            NSApp.appearance = originalAppearance
        }

        let definition = BessieThemeRegistry.definition(for: .dark, systemScheme: .dark)
        BessieSettingsModel.applyAppAppearance(
            selection: .dark,
            effectiveScheme: .dark,
            palette: definition.palette
        )

        XCTAssertEqual(statusWindow.backgroundColor, originalStatusBackground)
        XCTAssertEqual(window.backgroundColor, NSColor(definition.palette.window))
    }

    @MainActor
    func testUnexpectedFutureControllerThemeRejectionStaysRecoverableAndUnpresented() {
        let invalidConfiguration = TerminalConfiguration { builder in
            builder.withBackground("not-a-color")
        }
        let invalid = BessieResolvedTerminalTheme(
            concreteID: .catppuccinMocha,
            scheme: .dark,
            theme: TerminalTheme(light: invalidConfiguration, dark: invalidConfiguration)
        )
        let controller = PaneTerminalController(
            paneID: "theme-rejection",
            endpoint: HerdrTerminalEndpoint(connectionID: "test", executablePath: "/usr/bin/false", socketPath: "/tmp/missing"),
            theme: invalid
        )

        XCTAssertNotNil(controller.themeConfigurationError)
        XCTAssertFalse(controller.hasReadyFrame)
        XCTAssertFalse(controller.isSurfacePresented)
    }

    private func expectedCatppuccinColors(_ hexValues: String) -> [CatppuccinColorName: String] {
        let values = hexValues.split(separator: " ").map { "#" + $0 }
        XCTAssertEqual(values.count, CatppuccinColorName.allCases.count)
        return Dictionary(uniqueKeysWithValues: zip(CatppuccinColorName.allCases, values))
    }

    @MainActor
    private func assertPalette(
        _ palette: BessiePalette,
        equals expected: [String: [Double]],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let colors: [String: Color] = [
            "desk": palette.desk, "window": palette.window, "background": palette.background,
            "rail": palette.rail, "panel": palette.panel, "inset": palette.inset,
            "code": palette.code, "codeText": palette.codeText, "codeSubtle": palette.codeSubtle,
            "strong": palette.strong, "text": palette.text, "subtle": palette.subtle, "faint": palette.faint,
            "border": palette.border, "borderStrong": palette.borderStrong, "hover": palette.hover,
            "selected": palette.selected, "accent": palette.accent, "accentSoft": palette.accentSoft,
            "accentForeground": palette.accentForeground, "blocked": palette.blocked, "running": palette.running,
            "done": palette.done, "idle": palette.idle, "diffAdded": palette.diffAdded,
            "diffAddedPlate": palette.diffAddedPlate, "diffRemoved": palette.diffRemoved,
            "diffRemovedPlate": palette.diffRemovedPlate, "diffHunk": palette.diffHunk,
            "diffHunkPlate": palette.diffHunkPlate, "activeBorder": palette.activeBorder,
            "destructive": palette.destructive, "link": palette.link,
            "controlTint": palette.controlTint, "insertionPoint": palette.insertionPoint,
        ]
        XCTAssertEqual(Set(colors.keys), Set(expected.keys), file: file, line: line)
        for (role, color) in colors {
            guard let converted = NSColor(color).usingColorSpace(.sRGB), let expectedRGBA = expected[role] else {
                XCTFail("Missing sRGB fingerprint for \(role)", file: file, line: line)
                continue
            }
            let actual = [converted.redComponent, converted.greenComponent, converted.blueComponent, converted.alphaComponent].map(Double.init)
            XCTAssertEqual(actual.count, expectedRGBA.count, role, file: file, line: line)
            for (component, expectedComponent) in zip(actual, expectedRGBA) {
                XCTAssertEqual(component, expectedComponent, accuracy: 0.000_001, role, file: file, line: line)
            }
        }
    }

    private func contrast(_ foreground: String, _ background: String) -> Double {
        let lhs = luminance(hex: foreground)
        let rhs = luminance(hex: background)
        return (max(lhs, rhs) + 0.05) / (min(lhs, rhs) + 0.05)
    }

    @MainActor
    private func contrast(_ foreground: Color, _ background: Color) -> Double {
        let lhs = luminance(color: foreground)
        let rhs = luminance(color: background)
        return (max(lhs, rhs) + 0.05) / (min(lhs, rhs) + 0.05)
    }

    private func luminance(hex: String) -> Double {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
        return luminance(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }

    @MainActor
    private func luminance(color: Color) -> Double {
        let color = NSColor(color).usingColorSpace(.sRGB)!
        return luminance(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent)
    }

    private func luminance(red: Double, green: Double, blue: Double) -> Double {
        func linear(_ component: Double) -> Double {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    private func oklch(_ hex: String) -> (l: Double, c: Double, h: Double) {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
        func linear(_ byte: UInt64) -> Double {
            let component = Double(byte) / 255
            return component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        let red = linear((value >> 16) & 0xff)
        let green = linear((value >> 8) & 0xff)
        let blue = linear(value & 0xff)
        let l = cbrt(0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue)
        let m = cbrt(0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue)
        let s = cbrt(0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue)
        let lightness = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s
        let b = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s
        let hue = atan2(b, a) * 180 / .pi
        return (lightness, hypot(a, b), hue < 0 ? hue + 360 : hue)
    }

    @MainActor
    private func assertColor(_ color: Color, hex: String, alpha: Double, file: StaticString = #filePath, line: UInt = #line) {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
        guard let converted = NSColor(color).usingColorSpace(.sRGB) else {
            XCTFail("Could not resolve semantic color", file: file, line: line)
            return
        }
        XCTAssertEqual(Double(converted.redComponent), Double((value >> 16) & 0xff) / 255, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(Double(converted.greenComponent), Double((value >> 8) & 0xff) / 255, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(Double(converted.blueComponent), Double(value & 0xff) / 255, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(Double(converted.alphaComponent), alpha, accuracy: 0.000_001, file: file, line: line)
    }

    @MainActor
    private func drainMountedThemeUpdates(_ view: NSView) {
        for _ in 0..<5 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
        }
    }

    @MainActor
    private func mountedBackgroundColor(_ view: NSView) throws -> NSColor {
        let representation = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        return try XCTUnwrap(representation.colorAt(x: 4, y: 4)?.usingColorSpace(.sRGB))
    }
}

private struct MountedThemeChromeProbe: View {
    var body: some View {
        ZStack {
            BessieDesign.background
            RoundedRectangle(cornerRadius: BessieDesign.surfaceRadius)
                .fill(BessieDesign.panel)
                .overlay {
                    Text("Mounted chrome")
                        .foregroundStyle(BessieDesign.text)
                }
                .padding(20)
        }
        .environment(\.colorScheme, .dark)
        .frame(width: 160, height: 100)
    }
}
