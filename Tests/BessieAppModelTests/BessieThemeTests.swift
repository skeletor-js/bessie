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

        XCTAssertFalse(result)
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

        XCTAssertFalse(result)
        XCTAssertEqual(secondCalls, 0)
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

        XCTAssertTrue(registry.applyTheme(latte))
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
            applyTerminalTheme: { _ in false }
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
            applyTerminalTheme: { _ in false }
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
            applyTerminalTheme: { _ in terminalApplyCount += 1; return true }
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
