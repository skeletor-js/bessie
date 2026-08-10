import BessieCore
import GhosttyTerminal
import SwiftUI
import XCTest
@testable import BessieApp

@MainActor
final class GhosttyCompatibilityIntegrationTests: XCTestCase {
    func testProfileUsesOnlyTypedAllowlistedCommandsBeforeMandatoryOverlayAndPaneFontSize() throws {
        let profile = GhosttyCompatibilityProfile(
            rootURL: URL(fileURLWithPath: "/tmp/config"),
            resolvedFiles: [URL(fileURLWithPath: "/tmp/config")],
            assignments: [],
            effective: .init(
                fontFamilies: ["Berkeley Mono", "Symbols Nerd Font"],
                fontFamilyWasReset: true,
                fontThicken: true,
                fontThickenStrength: 128,
                cursorStyle: .underline,
                cursorStyleBlink: false
            )
        )
        let builtIn = try XCTUnwrap(BessieThemeRegistry.definitions[.dark])
        let adjusted = builtIn.resolvedTerminalTheme.applyingCompatibility(profile)
        let controller = PaneTerminalController(
            paneID: "compatibility-order",
            endpoint: .init(connectionID: "test", executablePath: "/usr/bin/false", socketPath: "/tmp/missing"),
            theme: adjusted
        )
        defer { controller.release() }
        controller.updateFontSize(17)

        let rendered = controller.ghosttyController.renderedConfig
        let reset = try XCTUnwrap(rendered.range(of: "font-family = \n"))
        let family = try XCTUnwrap(rendered.range(of: "font-family = Berkeley Mono"))
        let overlay = try XCTUnwrap(rendered.range(of: "mouse-reporting = false"))
        let fontSize = try XCTUnwrap(rendered.range(of: "font-size = 17"))
        let theme = try XCTUnwrap(rendered.range(of: "foreground = #F5F5F5", options: .caseInsensitive))
        XCTAssertLessThan(reset.lowerBound, family.lowerBound)
        XCTAssertLessThan(family.lowerBound, overlay.lowerBound)
        XCTAssertLessThan(overlay.lowerBound, fontSize.lowerBound)
        XCTAssertLessThan(fontSize.lowerBound, theme.lowerBound)
        for expected in [
            "font-family = Symbols Nerd Font", "font-thicken = true", "font-thicken-strength = 128",
            "cursor-style = underline", "cursor-style-blink = false", "background-opacity = 1",
            "macos-option-as-alt = left", "mouse-hide-while-typing = true",
        ] {
            XCTAssertTrue(rendered.contains(expected), rendered)
        }
        for forbidden in ["command =", "keybind =", "window-", "font-style =", "config-file ="] {
            XCTAssertFalse(rendered.contains(forbidden), rendered)
        }
        XCTAssertEqual(adjusted.theme, builtIn.resolvedTerminalTheme.theme)
    }

    func testEnableThenDisableExplicitlyRestoresBessieTerminalDefaultsOnSameController() throws {
        let builtIn = try XCTUnwrap(BessieThemeRegistry.definitions[.dark]).resolvedTerminalTheme
        let enabled = builtIn.applyingCompatibility(.init(
            rootURL: URL(fileURLWithPath: "/tmp/config"),
            resolvedFiles: [URL(fileURLWithPath: "/tmp/config")],
            assignments: [],
            effective: .init(
                fontFamilies: ["Berkeley Mono"],
                fontThicken: false,
                fontThickenStrength: 128,
                cursorStyle: .underline,
                cursorStyleBlink: false
            )
        ))

        XCTAssertEqual(builtIn.applyingCompatibility(nil), builtIn)

        let controller = PaneTerminalController(
            paneID: "compatibility-disabled",
            endpoint: .init(connectionID: "test", executablePath: "/usr/bin/false", socketPath: "/tmp/missing"),
            theme: enabled
        )
        defer { controller.release() }

        XCTAssertTrue(controller.ghosttyController.renderedConfig.contains("font-family = Berkeley Mono"))
        XCTAssertTrue(controller.ghosttyController.renderedConfig.contains("cursor-style = underline"))
        XCTAssertTrue(controller.updateTheme(builtIn))
        let expectedBaseline = "font-family = \n" + """
        font-thicken = true
        font-thicken-strength = 255
        cursor-style = block
        cursor-style-blink = true
        background-opacity = 1
        mouse-reporting = false
        macos-option-as-alt = left
        mouse-hide-while-typing = true
        font-size = 13
        """
        XCTAssertEqual(controller.ghosttyController.terminalConfiguration.rendered, expectedBaseline)
    }

    func testCoordinatorLoadsPersistedProfileAndInvalidReloadPreservesLastKnownGoodVisuals() throws {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config")
        try "font-family = Berkeley Mono".write(to: config, atomically: true, encoding: .utf8)
        let presentationURL = root.appendingPathComponent("presentation.json")
        try BessiePresentationStore(url: presentationURL).save(.init(preferences: .init(
            appearance: .dark,
            ghosttyCompatibilityEnabled: true,
            ghosttyCompatibilitySelectedPath: config.path
        )))
        let settings = makeSettings(root: root, presentationURL: presentationURL)
        let registry = TerminalControllerRegistry()
        var applied: [BessieResolvedTerminalTheme] = []
        let coordinator = BessieThemeCoordinator(
            settings: settings,
            terminalRegistry: registry,
            applyTerminalTheme: { applied.append($0); return .applied }
        )

        XCTAssertEqual(coordinator.compatibilityProfile?.effective.fontFamilies, ["Berkeley Mono"])
        XCTAssertEqual(registry.effectiveTheme.compatibility?.fontFamilies, ["Berkeley Mono"])
        XCTAssertNil(coordinator.compatibilityError)

        try "font-thicken-strength = 999".write(to: config, atomically: true, encoding: .utf8)
        XCTAssertFalse(coordinator.reloadCompatibilityConfiguration())
        XCTAssertEqual(coordinator.compatibilityProfile?.effective.fontFamilies, ["Berkeley Mono"])
        XCTAssertTrue(settings.preferences.ghosttyCompatibilityEnabled)
        XCTAssertTrue(applied.isEmpty)
        XCTAssertNotNil(coordinator.compatibilityError)
    }

    func testSelectionEnableDisableCommitsOnlyAfterSuccessfulTerminalTransaction() throws {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config")
        try "cursor-style = bar".write(to: config, atomically: true, encoding: .utf8)
        let settings = makeSettings(root: root)
        let registry = TerminalControllerRegistry()
        var accept = false
        var attempts = 0
        let coordinator = BessieThemeCoordinator(
            settings: settings,
            terminalRegistry: registry,
            applyTerminalTheme: { _ in attempts += 1; return accept ? .applied : .rejectedAndRestored }
        )

        XCTAssertTrue(coordinator.selectCompatibilityConfiguration(config))
        XCTAssertEqual(settings.preferences.ghosttyCompatibilitySelectedPath, config.path)
        XCTAssertFalse(settings.preferences.ghosttyCompatibilityEnabled)

        XCTAssertFalse(coordinator.setCompatibilityEnabled(true))
        XCTAssertFalse(settings.preferences.ghosttyCompatibilityEnabled)
        XCTAssertEqual(attempts, 1)

        accept = true
        XCTAssertTrue(coordinator.setCompatibilityEnabled(true))
        XCTAssertTrue(settings.preferences.ghosttyCompatibilityEnabled)
        XCTAssertEqual(coordinator.compatibilityProfile?.effective.cursorStyle, .bar)

        XCTAssertTrue(coordinator.setCompatibilityEnabled(false))
        XCTAssertFalse(settings.preferences.ghosttyCompatibilityEnabled)
        XCTAssertNil(coordinator.compatibilityProfile)
        XCTAssertEqual(attempts, 3)
    }

    func testPersistenceFailureRollsBackAppliedThemeAndKeepsPreferencesDisabled() throws {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config")
        try "cursor-style = bar".write(to: config, atomically: true, encoding: .utf8)
        let presentationURL = root.appendingPathComponent("presentation.json")
        let settings = makeSettings(root: root, presentationURL: presentationURL)
        let registry = TerminalControllerRegistry()
        var applied: [BessieResolvedTerminalTheme] = []
        let coordinator = BessieThemeCoordinator(
            settings: settings,
            terminalRegistry: registry,
            applyTerminalTheme: { applied.append($0); return .applied }
        )
        XCTAssertTrue(coordinator.selectCompatibilityConfiguration(config))
        try FileManager.default.removeItem(at: presentationURL)
        try FileManager.default.createDirectory(at: presentationURL, withIntermediateDirectories: false)

        XCTAssertFalse(coordinator.setCompatibilityEnabled(true))
        XCTAssertFalse(settings.preferences.ghosttyCompatibilityEnabled)
        XCTAssertNil(coordinator.compatibilityProfile)
        XCTAssertEqual(applied.count, 2)
        XCTAssertNotNil(applied[0].compatibility)
        XCTAssertNil(applied[1].compatibility)
        XCTAssertTrue(coordinator.compatibilityError?.contains("couldn't save") == true)
    }

    func testRollbackFailureIsReportedWithoutClaimingPreviousSettingsWereRestored() throws {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config")
        try "cursor-style = bar".write(to: config, atomically: true, encoding: .utf8)
        let presentationURL = root.appendingPathComponent("presentation.json")
        let settings = makeSettings(root: root, presentationURL: presentationURL)
        let registry = TerminalControllerRegistry()
        var attempts = 0
        let coordinator = BessieThemeCoordinator(
            settings: settings,
            terminalRegistry: registry,
            applyTerminalTheme: { _ in
                attempts += 1
                return attempts == 1 ? .applied : .rollbackFailed
            }
        )
        XCTAssertTrue(coordinator.selectCompatibilityConfiguration(config))
        try FileManager.default.removeItem(at: presentationURL)
        try FileManager.default.createDirectory(at: presentationURL, withIntermediateDirectories: false)

        XCTAssertFalse(coordinator.setCompatibilityEnabled(true))
        XCTAssertFalse(settings.preferences.ghosttyCompatibilityEnabled)
        XCTAssertTrue(coordinator.compatibilityError?.contains("may be inconsistent") == true)
        XCTAssertFalse(coordinator.compatibilityError?.contains("restored") == true)
    }

    private func makeFixtureDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeSettings(root: URL, presentationURL: URL? = nil) -> BessieSettingsModel {
        BessieSettingsModel(
            presentationURL: presentationURL ?? root.appendingPathComponent("presentation.json"),
            connectionsURL: root.appendingPathComponent("connections.json"),
            runtimeSelectionURL: root.appendingPathComponent("runtime.json")
        )
    }
}
