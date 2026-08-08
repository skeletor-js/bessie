import AppKit
import SwiftUI
import XCTest
@testable import BessieApp
@testable import BessieCore

final class BessieVisualFoundationTests: XCTestCase {
    func testBindingGeometryIsExactInBothDensities() {
        for density in [BessieDensity.comfortable, .compact] {
            let metrics = BessieDensityMetrics.metrics(for: density)
            XCTAssertEqual(metrics.railWidth, 244)
            XCTAssertEqual(metrics.collapsedRailWidth, 52)
        }
        XCTAssertEqual(BessieDesign.cardGap, 9)
        XCTAssertEqual(BessieDesign.paneGap, 7)
        XCTAssertEqual(BessieDesign.titlebarHeight, 30)
        XCTAssertEqual(BessieDesign.topbarHeight, 46)
        XCTAssertEqual(BessieDesign.surfaceRadius, 4)
        XCTAssertEqual(BessieDesign.controlRadius, 3)
    }

    func testBindingMotionDurationsAreExact() {
        XCTAssertEqual(BessieDesign.hoverDuration, 0.12)
        XCTAssertEqual(BessieDesign.popoverDuration, 0.15)
        XCTAssertEqual(BessieDesign.panelDuration, 0.28)
    }

    func testSemanticDesignFacadeExposesIntentSpecificThemeRoles() {
        XCTAssertEqual(BessieDesign.activeBorder.role, .activeBorder)
        XCTAssertEqual(BessieDesign.destructive.role, .destructive)
        XCTAssertEqual(BessieDesign.link.role, .link)
        XCTAssertEqual(BessieDesign.controlTint.role, .controlTint)
        XCTAssertEqual(BessieDesign.insertionPoint.role, .insertionPoint)
    }

    func testNativeSemanticCallersOwnSelectionControlAndDestructiveIntent() throws {
        let design = try appSource("BessieDesignSystem.swift")
        let app = try appSource("BessieApp.swift")
        let settings = try appSource("BessieSettings.swift")
        let palette = try appSource("BessieCommandPalette.swift")
        let onboarding = try appSource("OnboardingView.swift")
        let product = try appSource("ProductSurfaces.swift")
        let runtime = try appSource("RuntimeSettingsView.swift")

        for source in [design, app, settings, product] {
            XCTAssertFalse(source.contains(".tint(BessieDesign.strong)"))
        }
        XCTAssertTrue(design.contains(".tint(BessieDesign.insertionPoint)"))
        XCTAssertFalse(design.contains("static let red = BessieSemanticColor(.red)"))
        XCTAssertFalse(app.contains(".foregroundStyle(.secondary)"))
        XCTAssertTrue(palette.contains(".background(selected ? BessieDesign.selected : BessieSemanticColor.clear)"))
        XCTAssertTrue(onboarding.contains("selected ? BessieDesign.activeBorder : BessieDesign.border"))
        XCTAssertFalse(product.contains("BessieDesign.selected.opacity"))
        XCTAssertTrue(product.contains(".background(BessieDesign.accentSoft)"))
        XCTAssertTrue(product.contains("selected ? BessieDesign.activeBorder"))
        XCTAssertTrue(product.contains("destructive ? BessieDesign.destructive : BessieDesign.text"))
        XCTAssertTrue(product.contains("hovering ? BessieDesign.hover : BessieSemanticColor.clear"))
        XCTAssertTrue(product.contains("focused ? BessieDesign.activeBorder : BessieSemanticColor.clear"))
        XCTAssertTrue(runtime.contains(".foregroundStyle(BessieDesign.destructive)"))
        XCTAssertFalse(runtime.contains(".foregroundStyle(.red)"))
        XCTAssertTrue(settings.contains("configuration.isOn ? BessieDesign.controlTint : BessieDesign.inset"))
    }

    func testNativeSemanticCallersOwnCaretLinkProgressAndDiffRoles() throws {
        let settings = try appSource("BessieSettings.swift")
        let palette = try appSource("BessieCommandPalette.swift")
        let onboarding = try appSource("OnboardingView.swift")
        let product = try appSource("ProductSurfaces.swift")
        let markdown = try appSource("MarkdownFileEditor.swift")
        let follow = try appSource("FollowFilesSurface.swift")

        XCTAssertTrue(settings.contains(".tint(BessieDesign.controlTint)"))
        XCTAssertTrue(settings.contains(".tint(BessieDesign.insertionPoint)"))
        XCTAssertTrue(palette.contains(".tint(BessieDesign.insertionPoint)"))
        XCTAssertTrue(onboarding.contains(".tint(BessieDesign.insertionPoint)"))
        XCTAssertTrue(product.contains(".tint(BessieDesign.controlTint)"))
        XCTAssertTrue(product.contains(".tint(BessieDesign.insertionPoint)"))
        XCTAssertGreaterThanOrEqual(product.components(separatedBy: ".tint(BessieDesign.running)").count - 1, 4)
        XCTAssertGreaterThanOrEqual(follow.components(separatedBy: ".tint(BessieDesign.running)").count - 1, 2)
        XCTAssertTrue(markdown.contains(".tint(BessieDesign.link)"))
        XCTAssertTrue(markdown.contains(".tint(BessieDesign.controlTint)"))
        XCTAssertTrue(markdown.contains(".tint(BessieDesign.insertionPoint)"))
        XCTAssertTrue(markdown.contains(".tint(BessieDesign.running)"))

        XCTAssertTrue(follow.contains("return BessieDesign.diffHunk"))
        XCTAssertTrue(follow.contains("return BessieDesign.diffHunkPlate"))
        XCTAssertTrue(follow.contains("return BessieDesign.diffAdded"))
        XCTAssertTrue(follow.contains("return BessieDesign.diffAddedPlate"))
        XCTAssertTrue(follow.contains("return BessieDesign.diffRemoved"))
        XCTAssertTrue(follow.contains("return BessieDesign.diffRemovedPlate"))
    }

    func testAccessibilityEnvironmentsDoNotSelectAlternateSemanticColorBranches() {
        XCTAssertEqual(BessieDesign.selected.role, .selected)
        XCTAssertEqual(BessieDesign.blocked.role, .blocked)
        XCTAssertEqual(BessieDesign.destructive.role, .destructive)
        XCTAssertEqual(BessieStatusPresentation.needsYou.accessibilityLabel, "Needs you, filled circle")
        XCTAssertEqual(BessieStateGeometry.needsYouFilledCircle.rawValue, "needsYouFilledCircle")
    }

    func testOnboardingWindowTitlesMatchTheBinding() {
        XCTAssertEqual(BessieOnboardingWindowChrome.splashTitle, "bessie")
        XCTAssertEqual(BessieOnboardingWindowChrome.welcomeTitle, "welcome to bessie")
    }

    func testStateGeometryVocabularyIsComplete() {
        XCTAssertEqual(Set(BessieStateGeometry.allCases), [
            .needsYouFilledCircle, .workingSpinnerRing, .settledHollowRing, .unknownHollowDiamond,
        ])
        XCTAssertEqual(BessieStatusPresentation.needsYou.accessibilityLabel, "Needs you, filled circle")
        XCTAssertEqual(BessieStatusPresentation.working.accessibilityLabel, "Working, ring")
        XCTAssertEqual(BessieStatusPresentation.settled.accessibilityLabel, "Settled, hollow ring")
        XCTAssertEqual(BessieStatusPresentation.unknown.accessibilityLabel, "Unknown, hollow diamond")
    }

    @MainActor
    func testProviderMarksHaveStableSpokenNames() {
        XCTAssertEqual(BessieProviderMark.spokenLabel(for: "claude"), "Claude agent")
        XCTAssertEqual(BessieProviderMark.spokenLabel(for: "Codex CLI"), "Codex agent")
        XCTAssertEqual(BessieProviderMark.spokenLabel(for: "grok"), "Grok agent")
        XCTAssertEqual(BessieProviderMark.spokenLabel(for: "amp"), "Amp agent")
        XCTAssertEqual(BessieProviderMark.spokenLabel(for: nil), "Unknown agent")
        XCTAssertEqual(BessieProviderMark.spokenLabel(for: "cursor"), "Cursor agent")
        XCTAssertEqual(BessieProviderMark.spokenLabel(for: "pi"), "Pi agent")
        XCTAssertEqual(BessieProviderMark.spokenLabel(for: "unknown-bot"), "Unknown agent")
    }

    func testAllAgentMarkSVGsArePackaged() throws {
        XCTAssertEqual(
            BessieProviderMark.packagedResourceNames,
            [
                "AgentClaude", "AgentCodex", "AgentGrok", "AgentAmp", "AgentGeneric",
                "AgentHermes", "AgentGemini", "AgentOpenCode", "AgentCopilot",
                "AgentPi", "AgentOmp", "AgentCursor", "AgentDevin", "AgentAgy",
                "AgentCline", "AgentMastraCode", "AgentKimi", "AgentKiro", "AgentDroid",
                "AgentKilo", "AgentQodercli", "AgentMaki", "AgentOpenClaw",
            ]
        )
        XCTAssertEqual(BessieProviderMark.resourceName(for: "claude-code"), "AgentClaude")
        XCTAssertEqual(BessieProviderMark.resourceName(for: "openai-codex"), "AgentCodex")
        XCTAssertEqual(BessieProviderMark.resourceName(for: "xai-grok"), "AgentGrok")
        XCTAssertEqual(BessieProviderMark.resourceName(for: "sourcegraph-amp"), "AgentAmp")
        XCTAssertEqual(BessieProviderMark.resourceName(for: "hermes"), "AgentHermes")
        XCTAssertEqual(BessieProviderMark.spokenLabel(for: "hermes"), "Hermes agent")
        XCTAssertEqual(BessieProviderMark.resourceName(for: "gemini"), "AgentGemini")
        XCTAssertEqual(BessieProviderMark.resourceName(for: "opencode"), "AgentOpenCode")
        XCTAssertEqual(BessieProviderMark.resourceName(for: "copilot"), "AgentCopilot")
        // Token matching: "pi" must not steal "copilot".
        XCTAssertEqual(BessieProviderMark.resourceName(for: "copilot"), "AgentCopilot")
        XCTAssertEqual(BessieProviderMark.resourceName(for: "pi"), "AgentPi")
        XCTAssertEqual(BessieProviderMark.resourceName(for: "omp"), "AgentOmp")
        XCTAssertEqual(BessieProviderMark.resourceName(for: "cursor"), "AgentCursor")
        XCTAssertEqual(BessieProviderMark.resourceName(for: "devin"), "AgentDevin")
        XCTAssertEqual(BessieProviderMark.resourceName(for: "agy"), "AgentAgy")
        XCTAssertEqual(BessieProviderMark.resourceName(for: "antigravity"), "AgentAgy")
        XCTAssertEqual(BessieProviderMark.resourceName(for: "cline"), "AgentCline")
        XCTAssertEqual(BessieProviderMark.resourceName(for: "mastracode"), "AgentMastraCode")
        XCTAssertEqual(BessieProviderMark.resourceName(for: "kimi"), "AgentKimi")
        XCTAssertEqual(BessieProviderMark.resourceName(for: "kiro"), "AgentKiro")
        XCTAssertEqual(BessieProviderMark.resourceName(for: "droid"), "AgentDroid")
        XCTAssertEqual(BessieProviderMark.resourceName(for: "kilo"), "AgentKilo")
        XCTAssertEqual(BessieProviderMark.resourceName(for: "qodercli"), "AgentQodercli")
        XCTAssertEqual(BessieProviderMark.resourceName(for: "maki"), "AgentMaki")
        XCTAssertEqual(BessieProviderMark.resourceName(for: "openclaw"), "AgentOpenClaw")

        for name in BessieProviderMark.packagedResourceNames {
            let url = try XCTUnwrap(BessieResources.url(forResource: name, withExtension: "svg"), name)
            let source = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(source.contains("<svg"), name)
            XCTAssertTrue(source.contains("<title>"), name)
            XCTAssertTrue(
                source.contains("<path")
                    || source.contains("<circle")
                    || source.contains("<rect")
                    || source.contains("<polygon")
                    || source.contains("<image"),
                name
            )
        }
    }

    func testExactPhosphorIconResourceMappingIsComplete() throws {
        XCTAssertEqual(BessieIcon.allCases.count, 30)
        XCTAssertEqual(BessieIcon.magnifyingGlass.resourceName, "PhosphorMagnifyingGlassThin")
        XCTAssertEqual(BessieIcon.terminalWindow.resourceName, "PhosphorTerminalWindowThin")
        XCTAssertEqual(BessieIcon.sun.resourceName, "PhosphorSunThin")
        XCTAssertEqual(BessieIcon.cow.resourceName, "PhosphorCowFill")

        for icon in BessieIcon.allCases {
            let url = try XCTUnwrap(BessieResources.url(forResource: icon.resourceName, withExtension: "svg"), icon.resourceName)
            let source = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(source.contains("viewBox=\"0 0 24 24\""), icon.resourceName)
            let path = try XCTUnwrap(source.range(of: #"<path d="[^"]+""#, options: .regularExpression), icon.resourceName)
            XCTAssertFalse(source[path].isEmpty, icon.resourceName)
        }
    }

    func testCanonicalStatusGeometryMatchesBinding() {
        XCTAssertEqual(BessieStatusGeometry.needsYouDiameter, 8)
        XCTAssertEqual(BessieStatusGeometry.needsYouHaloWidth, 3)
        XCTAssertEqual(BessieStatusGeometry.needsYouHaloOpacity, 0.22)
        XCTAssertEqual(BessieStatusGeometry.workingDiameter, 10)
        XCTAssertEqual(BessieStatusGeometry.workingLineWidth, 1.6)
        XCTAssertEqual(BessieStatusGeometry.workingRotationDuration, 0.8)
        XCTAssertEqual(BessieStatusGeometry.settledDiameter, 9)
        XCTAssertEqual(BessieStatusGeometry.settledLineWidth, 1.5)
        XCTAssertEqual(BessieStatusGeometry.unknownDiameter, 8)
        XCTAssertEqual(BessieStatusGeometry.unknownLineWidth, 1.5)
        XCTAssertEqual(BessieStatusPresentation(state: .done), .settled)
        XCTAssertEqual(BessieStatusPresentation(state: .idle), .settled)
    }

    @MainActor
    func testWorkingSpinnerUsesCoreAnimationAndRespectsReduceMotion() {
        let spinner = BessieWorkingSpinnerNSView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: BessieStatusGeometry.workingDiameter,
                height: BessieStatusGeometry.workingDiameter
            )
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 40, height: 40),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = spinner

        spinner.configure(
            diameter: BessieStatusGeometry.workingDiameter,
            lineWidth: BessieStatusGeometry.workingLineWidth,
            duration: BessieStatusGeometry.workingRotationDuration,
            reduceMotion: false
        )
        XCTAssertTrue(spinner.isSpinning, "Working ring should spin via Core Animation when motion is allowed")

        spinner.configure(
            diameter: BessieStatusGeometry.workingDiameter,
            lineWidth: BessieStatusGeometry.workingLineWidth,
            duration: BessieStatusGeometry.workingRotationDuration,
            reduceMotion: true
        )
        XCTAssertFalse(spinner.isSpinning, "Reduce Motion must freeze the working ring")
    }

    func testAccessibilityAndMinimumWindowContracts() {
        XCTAssertEqual(BessieAccessibilityContract.minimumContentWidth, 1080)
        XCTAssertEqual(BessieAccessibilityContract.minimumContentHeight, 680)
        XCTAssertEqual(
            BessieAccessibilityContract.minimumContentSize,
            NSSize(width: 1080, height: 680)
        )
        XCTAssertEqual(BessieAccessibilityContract.pickerMaximumHeight, 420)
        XCTAssertTrue(BessieAccessibilityContract.permitsSpatialMotion(reduceMotion: false))
        XCTAssertFalse(BessieAccessibilityContract.permitsSpatialMotion(reduceMotion: true))
        XCTAssertFalse(BessieAccessibilityContract.usesOpaqueMaterial(reduceTransparency: false, increasedContrast: false))
        XCTAssertTrue(BessieAccessibilityContract.usesOpaqueMaterial(reduceTransparency: true, increasedContrast: false))
        XCTAssertTrue(BessieAccessibilityContract.usesOpaqueMaterial(reduceTransparency: false, increasedContrast: true))
    }

    @MainActor
    func testKeyboardCoordinatorProtectsIMEAndTextEditingNotTerminalFocus() {
        // IME composition always wins.
        XCTAssertFalse(BessieKeyboardShortcutCoordinator.shouldRoute(
            .showCommandPalette,
            hasMarkedText: true,
            firstResponderIsEditableText: false
        ))
        // Product/topology chords work with or without terminal focus when not typing.
        XCTAssertTrue(BessieKeyboardShortcutCoordinator.shouldRoute(
            .nextPane,
            hasMarkedText: false,
            firstResponderIsEditableText: false
        ))
        XCTAssertTrue(BessieKeyboardShortcutCoordinator.shouldRoute(
            .splitPane(.right),
            hasMarkedText: false,
            firstResponderIsEditableText: false
        ))
        XCTAssertTrue(BessieKeyboardShortcutCoordinator.shouldRoute(
            .showCommandPalette,
            hasMarkedText: false,
            firstResponderIsEditableText: false
        ))
        // Editable text keeps topology chords; global palette/zen still route.
        XCTAssertFalse(BessieKeyboardShortcutCoordinator.shouldRoute(
            .nextPane,
            hasMarkedText: false,
            firstResponderIsEditableText: true
        ))
        XCTAssertFalse(BessieKeyboardShortcutCoordinator.shouldRoute(
            .projectsPicker,
            hasMarkedText: false,
            firstResponderIsEditableText: true
        ))
        XCTAssertTrue(BessieKeyboardShortcutCoordinator.shouldRoute(
            .showCommandPalette,
            hasMarkedText: false,
            firstResponderIsEditableText: true
        ))
        XCTAssertTrue(BessieKeyboardShortcutCoordinator.shouldRoute(
            .toggleZen,
            hasMarkedText: false,
            firstResponderIsEditableText: true
        ))
    }

    @MainActor
    func testOnboardingSurfaceIsAlwaysFullyOpaque() {
        XCTAssertEqual(BessieOnboardingSurface.opacity(reduceTransparency: false), 1)
        XCTAssertEqual(BessieOnboardingSurface.opacity(reduceTransparency: true), 1)
    }

    @MainActor
    func testCoalsAndPaperUseExactAchromaticSurfaceTokens() {
        assertGray(BessieDesign.palette(for: .dark).window, equals: 5)
        assertGray(BessieDesign.palette(for: .dark).background, equals: 14)
        assertGray(BessieDesign.palette(for: .dark).rail, equals: 10)
        assertGray(BessieDesign.palette(for: .dark).panel, equals: 22)
        assertGray(BessieDesign.palette(for: .dark).inset, equals: 17)

        assertGray(BessieDesign.palette(for: .light).window, equals: 237)
        assertGray(BessieDesign.palette(for: .light).background, equals: 250)
        assertGray(BessieDesign.palette(for: .light).rail, equals: 245)
        assertGray(BessieDesign.palette(for: .light).panel, equals: 255)
        assertGray(BessieDesign.palette(for: .light).inset, equals: 242)
    }

    @MainActor
    func testCodePlateMatchesEachBindingAppearance() {
        for scheme in [ColorScheme.dark, .light] {
            let palette = BessieDesign.palette(for: scheme)
            assertGray(palette.code, equals: scheme == .dark ? 8 : 251)
            assertGray(palette.codeText, equals: scheme == .dark ? 245 : 12)
        }
    }

    @MainActor
    func testCowprintUsesFixedAppearanceSpecificInk() {
        XCTAssertEqual(BessieCowprintBackdrop.inkOpacity(for: .dark), 0.11)
        XCTAssertEqual(BessieCowprintBackdrop.inkOpacity(for: .light), 0.16)
        XCTAssertEqual(BessieCowprintBackdrop.tileSize, 640)
    }

    @MainActor
    func testBindingSurfaceCardsUseFixedOpaqueTints() {
        XCTAssertTrue(BessieMaterialBackground.usesFixedOpaqueTint)
    }

    func testRegularShellKeepsOutsideInsetAndDistinctPanelGap() {
        let comfortable = BessieDensityMetrics.metrics(for: .comfortable)
        let compact = BessieDensityMetrics.metrics(for: .compact)

        XCTAssertEqual(comfortable.shellOutsideInset, comfortable.cardGap)
        XCTAssertEqual(comfortable.shellBottomInset, 7)
        XCTAssertGreaterThan(compact.shellOutsideInset, compact.cardGap)
        XCTAssertGreaterThanOrEqual(comfortable.shellPanelGap, comfortable.cardGap)
        XCTAssertGreaterThanOrEqual(compact.shellPanelGap, compact.cardGap)
    }

    func testZenControlsUseVisiblePlainLanguageLabels() {
        XCTAssertEqual(BessieZenPresentationContract.awarenessRailWidth, 52)
        XCTAssertEqual(BessieZenPresentationContract.terminalHeaderHeight, 34)
        XCTAssertEqual(BessieZenPresentationContract.gutter, 9)
        XCTAssertEqual(BessieZenPresentationContract.windowTitle, "zen")
        XCTAssertEqual(BessieZenControlLabels.expand, "Expand")
        XCTAssertNil(BessieZenPresentationContract.elsewhereLabel(count: 0))
        XCTAssertEqual(BessieZenPresentationContract.elsewhereLabel(count: 2), "2 elsewhere")
    }

    @MainActor
    func testCanonicalWorkspaceAndPaletteGeometry() {
        XCTAssertEqual(BessieWorkspacePresentationContract.inCardChromeHeight, 0)
        XCTAssertEqual(BessieCommandPalette.width, 560)
        XCTAssertEqual(BessieCommandPalette.scrimOpacity, 0.28)
        XCTAssertEqual(BessieCommandPalette.inputFontSize, 16)
        XCTAssertEqual(BessieCommandPalette.topInsetFraction, 0.14)
        XCTAssertEqual(BessieCommandPalette.maximumListHeightFraction, 0.48)
    }

    @MainActor
    func testPaletteFooterUsesSelectionCapabilitiesAndAllFiveKinds() {
        let disconnectedHerd = CommandPaletteEntity(
            id: .init(kind: .connection, components: ["remote"]),
            kind: .connection,
            title: "Remote",
            detail: "Connection lost",
            freshness: .disconnected,
            route: .connection("remote")
        )
        let command = CommandPaletteEntity(
            id: .init(kind: .command, components: ["settings"]),
            kind: .command,
            title: "Settings",
            detail: "Command",
            route: .command(.showSettings)
        )

        XCTAssertEqual(BessieCommandPalette.footerLegend, "panes · workspaces · projects · herds · commands")
        XCTAssertEqual(BessieCommandPalette.activationVerb(for: disconnectedHerd), "retry")
        XCTAssertEqual(BessieCommandPalette.activationVerb(for: command), "run")
        XCTAssertEqual(BessieCommandPalette.retryHealthDetail(base: "Connecting", attemptCount: 1), "Retrying")
        XCTAssertEqual(
            BessieCommandPalette.retryHealthDetail(base: "Disconnected", attemptCount: 1),
            "Disconnected · Retry failed"
        )
        XCTAssertEqual(
            BessieCommandPalette.retryHealthDetail(base: "Disconnected", attemptCount: 2),
            "Disconnected · Retry failed again"
        )
        XCTAssertNil(command.alternateRoute)
    }

    func testCommandPaletteOpenabilityRequiresCompletedOnboardingKeyMainWindowAndNoSheet() {
        XCTAssertTrue(BessieCommandPaletteOpenability.allowsOpen(
            onboardingCompleted: true,
            mainWindowIsKey: true,
            hasAttachedSheet: false
        ))
        XCTAssertFalse(BessieCommandPaletteOpenability.allowsOpen(
            onboardingCompleted: false,
            mainWindowIsKey: true,
            hasAttachedSheet: false
        ))
        XCTAssertFalse(BessieCommandPaletteOpenability.allowsOpen(
            onboardingCompleted: true,
            mainWindowIsKey: false,
            hasAttachedSheet: false
        ))
        XCTAssertFalse(BessieCommandPaletteOpenability.allowsOpen(
            onboardingCompleted: true,
            mainWindowIsKey: true,
            hasAttachedSheet: true
        ))
    }

    func testLogoContrastExceedsAccessibleTextContrastInBothAppearances() {
        XCTAssertGreaterThan(contrastRatio(foreground: 245.0 / 255, background: 5.0 / 255), 4.5)
        XCTAssertGreaterThan(contrastRatio(foreground: 12.0 / 255, background: 237.0 / 255), 4.5)
    }

    func testShapeVocabularyKeepsPopoverInsideSharedSurfaceGeometry() {
        XCTAssertEqual(BessieDesign.surfaceRadius, BessieDesign.popoverInnerRadius)
        XCTAssertLessThan(BessieDesign.controlRadius, BessieDesign.surfaceRadius)
        XCTAssertLessThan(BessieDesign.paneRadius, BessieDesign.surfaceRadius)
    }

    @MainActor
    func testStaticCowprintRenderIsDeterministicInBothAppearances() throws {
        let dark = try renderProof(scheme: .dark)
        let repeatedDark = try renderProof(scheme: .dark)
        let light = try renderProof(scheme: .light)
        let repeatedLight = try renderProof(scheme: .light)

        XCTAssertGreaterThan(dark.count, 20_000)
        XCTAssertGreaterThan(light.count, 20_000)
        XCTAssertEqual(dark, repeatedDark)
        XCTAssertEqual(light, repeatedLight)
        XCTAssertNotEqual(dark, light)

        if let evidenceDirectory = ProcessInfo.processInfo.environment["BESSIE_VISUAL_EVIDENCE_DIR"] {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: evidenceDirectory),
                withIntermediateDirectories: true
            )
            try dark.write(to: URL(fileURLWithPath: evidenceDirectory).appendingPathComponent("cowprint-static-dark.png"))
            try light.write(to: URL(fileURLWithPath: evidenceDirectory).appendingPathComponent("cowprint-static-light.png"))
        }
    }

    private func appSource(_ name: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/BessieApp/\(name)"),
            encoding: .utf8
        )
    }

    private func contrastRatio(foreground: Double, background: Double) -> Double {
        let lighter = max(relativeLuminance(foreground), relativeLuminance(background))
        let darker = min(relativeLuminance(foreground), relativeLuminance(background))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ component: Double) -> Double {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }

    @MainActor
    private func assertGray(_ color: Color, equals byte: Int, file: StaticString = #filePath, line: UInt = #line) {
        guard let converted = NSColor(color).usingColorSpace(.sRGB) else {
            XCTFail("Could not convert design color to sRGB", file: file, line: line)
            return
        }
        let expected = CGFloat(byte) / 255
        XCTAssertEqual(converted.redComponent, expected, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(converted.greenComponent, expected, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(converted.blueComponent, expected, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(converted.alphaComponent, 1, accuracy: 0.001, file: file, line: line)
    }

    @MainActor
    private func renderProof(scheme: ColorScheme) throws -> Data {
        let view = ZStack(alignment: .topLeading) {
            BessieCowprintBackdrop(enabled: true)
            HStack(spacing: 12) {
                BessieLogoMark(width: 72)
                Text("Bessie")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(BessieDesign.strong)
            }
            .padding(28)
        }
        .environment(\.colorScheme, scheme)
        .environment(\.bessieConcreteThemeID, scheme == .light ? .light : .dark)
        .frame(width: 640, height: 400)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            XCTFail("Could not render visual-foundation proof")
            return Data()
        }
        return png
    }
}
