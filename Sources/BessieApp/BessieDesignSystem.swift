import AppKit
import BessieCore
import QuartzCore
import SwiftUI

enum BessieResources {
    static func url(forResource name: String, withExtension extensionName: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: extensionName)
            ?? Bundle.module.url(forResource: name, withExtension: extensionName)
    }
}

struct BessiePalette {
    let desk: Color
    let window: Color
    let background: Color
    let rail: Color
    let panel: Color
    let inset: Color
    let code: Color
    let codeText: Color
    let codeSubtle: Color
    let strong: Color
    let text: Color
    let subtle: Color
    let faint: Color
    let border: Color
    let borderStrong: Color
    let activeBorder: Color
    let hover: Color
    let selected: Color
    let accent: Color
    let accentSoft: Color
    let accentForeground: Color
    let destructive: Color
    let link: Color
    let controlTint: Color
    let insertionPoint: Color
    let blocked: Color
    let running: Color
    let done: Color
    let idle: Color
    let diffAdded: Color
    let diffAddedPlate: Color
    let diffRemoved: Color
    let diffRemovedPlate: Color
    let diffHunk: Color
    let diffHunkPlate: Color
}

// SwiftUI invokes ShapeStyle resolution on the main actor, but the macOS 14
// protocol declaration is not actor-annotated in Swift 6.
@MainActor
struct BessieSemanticColor: @preconcurrency ShapeStyle, View, Sendable {
    nonisolated let role: Role
    nonisolated private let opacityValue: Double

    nonisolated init(_ role: Role, opacity: Double = 1) {
        self.role = role
        opacityValue = opacity
    }

    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        let definition = BessieThemeRegistry.definition(
            for: environment.bessieConcreteThemeID,
            systemScheme: environment.colorScheme
        )
        return role.color(in: definition.palette).opacity(opacityValue)
    }

    var body: some View {
        Rectangle().fill(self)
    }

    nonisolated func opacity(_ opacity: Double) -> BessieSemanticColor {
        BessieSemanticColor(role, opacity: opacityValue * opacity)
    }

    var currentColor: Color {
        role.color(in: BessieThemeRuntime.palette()).opacity(opacityValue)
    }

    static let clear = BessieSemanticColor(.clear)

    enum Role: Hashable, Sendable {
        case desk, window, background, rail, panel, inset
        case code, codeText, codeSubtle, strong, text, subtle, faint
        case border, borderStrong, activeBorder, hover, selected
        case accent, accentSoft, accentForeground
        case destructive, link, controlTint, insertionPoint
        case blocked, running, done, idle
        case diffAdded, diffAddedPlate, diffRemoved, diffRemovedPlate, diffHunk, diffHunkPlate
        case clear

        @MainActor
        func color(in palette: BessiePalette) -> Color {
            switch self {
            case .desk: palette.desk
            case .window: palette.window
            case .background: palette.background
            case .rail: palette.rail
            case .panel: palette.panel
            case .inset: palette.inset
            case .code: palette.code
            case .codeText: palette.codeText
            case .codeSubtle: palette.codeSubtle
            case .strong: palette.strong
            case .text: palette.text
            case .subtle: palette.subtle
            case .faint: palette.faint
            case .border: palette.border
            case .borderStrong: palette.borderStrong
            case .activeBorder: palette.activeBorder
            case .hover: palette.hover
            case .selected: palette.selected
            case .accent: palette.accent
            case .accentSoft: palette.accentSoft
            case .accentForeground: palette.accentForeground
            case .destructive: palette.destructive
            case .link: palette.link
            case .controlTint: palette.controlTint
            case .insertionPoint: palette.insertionPoint
            case .blocked: palette.blocked
            case .running: palette.running
            case .done: palette.done
            case .idle: palette.idle
            case .diffAdded: palette.diffAdded
            case .diffAddedPlate: palette.diffAddedPlate
            case .diffRemoved: palette.diffRemoved
            case .diffRemovedPlate: palette.diffRemovedPlate
            case .diffHunk: palette.diffHunk
            case .diffHunkPlate: palette.diffHunkPlate
            case .clear: .clear
            }
        }
    }
}

enum BessieDesign {
    private static func gray(_ value: UInt8) -> Color {
        Color(.sRGB, white: Double(value) / 255, opacity: 1)
    }

    static func palette(for scheme: ColorScheme) -> BessiePalette {
        switch scheme {
        case .dark:
            return BessiePalette(
                desk: gray(7),
                window: gray(5),
                background: gray(14),
                rail: gray(10),
                panel: gray(22),
                inset: gray(17),
                code: gray(8),
                codeText: gray(245), codeSubtle: gray(166),
                strong: gray(245), text: gray(182), subtle: gray(138), faint: gray(95),
                border: Color.white.opacity(0.10), borderStrong: Color.white.opacity(0.19), activeBorder: Color.white.opacity(0.19), hover: Color.white.opacity(0.055), selected: Color.white.opacity(0.10),
                accent: .white, accentSoft: Color.white.opacity(0.12), accentForeground: .black,
                destructive: .red, link: gray(245), controlTint: gray(245), insertionPoint: gray(245),
                blocked: .white, running: Color(white: 0.604), done: Color(white: 0.863), idle: Color(white: 0.373),
                diffAdded: Color(red: 0.45, green: 0.82, blue: 0.52),
                diffAddedPlate: Color(red: 0.18, green: 0.42, blue: 0.22).opacity(0.28),
                diffRemoved: Color(red: 0.95, green: 0.48, blue: 0.48),
                diffRemovedPlate: Color(red: 0.45, green: 0.16, blue: 0.16).opacity(0.28),
                diffHunk: Color(red: 0.45, green: 0.72, blue: 0.95),
                diffHunkPlate: Color(red: 0.15, green: 0.28, blue: 0.42).opacity(0.35)
            )
        case .light:
            return BessiePalette(
                desk: gray(232),
                window: gray(237),
                background: gray(250),
                rail: gray(245),
                panel: .white,
                inset: gray(242),
                code: gray(251),
                codeText: gray(12), codeSubtle: gray(107),
                strong: gray(12), text: gray(58), subtle: gray(107), faint: gray(154),
                border: Color(red: 12 / 255, green: 12 / 255, blue: 12 / 255).opacity(0.12),
                borderStrong: Color(red: 12 / 255, green: 12 / 255, blue: 12 / 255).opacity(0.20),
                activeBorder: Color(red: 12 / 255, green: 12 / 255, blue: 12 / 255).opacity(0.20),
                hover: Color(red: 12 / 255, green: 12 / 255, blue: 12 / 255).opacity(0.05),
                selected: Color(red: 12 / 255, green: 12 / 255, blue: 12 / 255).opacity(0.07),
                accent: gray(12), accentSoft: Color(red: 12 / 255, green: 12 / 255, blue: 12 / 255).opacity(0.10), accentForeground: .white,
                destructive: .red, link: gray(12), controlTint: gray(12), insertionPoint: gray(12),
                blocked: Color(white: 0.047), running: Color(white: 0.416), done: Color(white: 0.165), idle: Color(white: 0.541),
                diffAdded: Color(red: 0.15, green: 0.48, blue: 0.22),
                diffAddedPlate: Color(red: 0.78, green: 0.94, blue: 0.80).opacity(0.55),
                diffRemoved: Color(red: 0.72, green: 0.16, blue: 0.18),
                diffRemovedPlate: Color(red: 0.98, green: 0.82, blue: 0.82).opacity(0.55),
                diffHunk: Color(red: 0.10, green: 0.34, blue: 0.68),
                diffHunkPlate: Color(red: 0.82, green: 0.89, blue: 0.98).opacity(0.65)
            )
        @unknown default:
            return palette(for: .dark)
        }
    }

    static let desk = BessieSemanticColor(.desk)
    static let window = BessieSemanticColor(.window)
    static let background = BessieSemanticColor(.background)
    static let rail = BessieSemanticColor(.rail)
    static let panel = BessieSemanticColor(.panel)
    static let inset = BessieSemanticColor(.inset)
    static let code = BessieSemanticColor(.code)
    static let codeText = BessieSemanticColor(.codeText)
    static let codeSubtle = BessieSemanticColor(.codeSubtle)
    static let strong = BessieSemanticColor(.strong)
    static let text = BessieSemanticColor(.text)
    static let subtle = BessieSemanticColor(.subtle)
    static let faint = BessieSemanticColor(.faint)
    static let border = BessieSemanticColor(.border)
    static let borderStrong = BessieSemanticColor(.borderStrong)
    static let activeBorder = BessieSemanticColor(.activeBorder)
    static let hover = BessieSemanticColor(.hover)
    static let selected = BessieSemanticColor(.selected)
    static let accent = BessieSemanticColor(.accent)
    static let accentSoft = BessieSemanticColor(.accentSoft)
    static let accentForeground = BessieSemanticColor(.accentForeground)
    static let destructive = BessieSemanticColor(.destructive)
    static let link = BessieSemanticColor(.link)
    static let controlTint = BessieSemanticColor(.controlTint)
    static let insertionPoint = BessieSemanticColor(.insertionPoint)
    static let blocked = BessieSemanticColor(.blocked)
    static let running = BessieSemanticColor(.running)
    static let done = BessieSemanticColor(.done)
    static let idle = BessieSemanticColor(.idle)
    static let diffAdded = BessieSemanticColor(.diffAdded)
    static let diffAddedPlate = BessieSemanticColor(.diffAddedPlate)
    static let diffRemoved = BessieSemanticColor(.diffRemoved)
    static let diffRemovedPlate = BessieSemanticColor(.diffRemovedPlate)
    static let diffHunk = BessieSemanticColor(.diffHunk)
    static let diffHunkPlate = BessieSemanticColor(.diffHunkPlate)

    static let titlebarHeight: CGFloat = 30
    static let railWidth: CGFloat = 244
    static let collapsedRailWidth: CGFloat = 52
    static let topbarHeight: CGFloat = 46
    static let rowHeight: CGFloat = 30
    static let cardGap: CGFloat = 9
    static let paneGap: CGFloat = 7
    static let surfaceRadius: CGFloat = 4
    static let controlRadius: CGFloat = 3
    static let popoverInnerRadius: CGFloat = 4

    static let motionFastDuration: TimeInterval = 0.16
    static let motionExplanatoryDuration: TimeInterval = 0.20
    static let motionStrongEaseOut = Animation.timingCurve(0.23, 1, 0.32, 1, duration: motionFastDuration)
    static let motionExplanatoryEaseOut = Animation.timingCurve(0.23, 1, 0.32, 1, duration: motionExplanatoryDuration)

    static let systemTypeDesign: Font.Design = .default
    static let monoTypeDesign: Font.Design = .monospaced

    // Compatibility names for cross-owned surfaces. New Bessie-owned chrome uses
    // the shape vocabulary above; native window geometry remains untouched.
    static let cardRadius = surfaceRadius
    static let paneRadius: CGFloat = 3
}

enum BessieStateGeometry: String, CaseIterable {
    case needsYouFilledCircle
    case workingSpinnerRing
    case doneCheckmarkRing
    case idleHorizontalLine
    case unknownHollowDiamond
}

enum BessieStatusPresentation: Equatable {
    case needsYou, working, done, idle, unknown

    init(state: AgentSemanticState) {
        switch state {
        case .blocked: self = .needsYou
        case .working: self = .working
        case .done: self = .done
        case .idle: self = .idle
        case .unknown: self = .unknown
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .needsYou: "Needs you, filled circle"
        case .working: "Working, ring"
        case .done: "Done, checkmark ring"
        case .idle: "Idle, horizontal line"
        case .unknown: "Unknown, hollow diamond"
        }
    }
}

enum BessieStatusGeometry {
    static let needsYouDiameter: CGFloat = 8
    static let needsYouHaloWidth: CGFloat = 3
    static let needsYouHaloOpacity = 0.22
    static let workingDiameter: CGFloat = 10
    static let workingLineWidth: CGFloat = 1.6
    static let workingRotationDuration: TimeInterval = 0.8
    static let doneDiameter: CGFloat = 10
    static let idleWidth: CGFloat = 10
    static let idleHeight: CGFloat = 2
    static let unknownDiameter: CGFloat = 8
    static let unknownLineWidth: CGFloat = 1.5
}

struct BessieStatusGlyph: View {
    let state: AgentSemanticState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch BessieStatusPresentation(state: state) {
            case .needsYou:
                Circle()
                    .fill(BessieDesign.blocked)
                    .frame(width: BessieStatusGeometry.needsYouDiameter, height: BessieStatusGeometry.needsYouDiameter)
                    .overlay {
                        Circle().stroke(BessieDesign.blocked.opacity(BessieStatusGeometry.needsYouHaloOpacity), lineWidth: BessieStatusGeometry.needsYouHaloWidth)
                    }
            case .working:
                // Spin via Core Animation in a tiny NSView. A continuous SwiftUI
                // transform/TimelineView forces whole-window NSHostingView commits
                // and starves live libghostty input (~40% CPU). CA keeps the spin
                // on the compositor without invalidating the SwiftUI tree.
                BessieWorkingSpinner(
                    diameter: BessieStatusGeometry.workingDiameter,
                    lineWidth: BessieStatusGeometry.workingLineWidth,
                    duration: BessieStatusGeometry.workingRotationDuration,
                    reduceMotion: reduceMotion
                )
                .frame(width: BessieStatusGeometry.workingDiameter, height: BessieStatusGeometry.workingDiameter)
            case .done:
                Image(systemName: "checkmark.circle")
                    .font(.system(size: BessieStatusGeometry.doneDiameter, weight: .medium))
                    .foregroundStyle(BessieDesign.borderStrong)
            case .idle:
                Capsule()
                    .fill(BessieDesign.borderStrong)
                    .frame(width: BessieStatusGeometry.idleWidth, height: BessieStatusGeometry.idleHeight)
            case .unknown:
                Rectangle()
                    .stroke(BessieDesign.borderStrong, lineWidth: BessieStatusGeometry.unknownLineWidth)
                    .frame(width: BessieStatusGeometry.unknownDiameter / sqrt(2), height: BessieStatusGeometry.unknownDiameter / sqrt(2))
                    .rotationEffect(.degrees(45))
            }
        }
        .frame(width: 14, height: 14)
        .accessibilityLabel(BessieStatusPresentation(state: state).accessibilityLabel)
    }
}

/// Working-status ring driven by Core Animation so chrome can spin without
/// forcing SwiftUI display-cadence commits of the shared window hosting view.
struct BessieWorkingSpinner: NSViewRepresentable {
    var diameter: CGFloat
    var lineWidth: CGFloat
    var duration: TimeInterval
    var reduceMotion: Bool

    func makeNSView(context: Context) -> BessieWorkingSpinnerNSView {
        let view = BessieWorkingSpinnerNSView()
        view.configure(diameter: diameter, lineWidth: lineWidth, duration: duration, reduceMotion: reduceMotion)
        return view
    }

    func updateNSView(_ view: BessieWorkingSpinnerNSView, context: Context) {
        view.configure(diameter: diameter, lineWidth: lineWidth, duration: duration, reduceMotion: reduceMotion)
    }
}

final class BessieWorkingSpinnerNSView: NSView {
    static let animationKey = "bessie.working.spin"

    /// Rotated container keeps path rebuilds off the animated transform.
    private let contentLayer = CALayer()
    private let trackLayer = CAShapeLayer()
    private let arcLayer = CAShapeLayer()
    private var diameter: CGFloat = BessieStatusGeometry.workingDiameter
    private var lineWidth: CGFloat = BessieStatusGeometry.workingLineWidth
    private var duration: TimeInterval = BessieStatusGeometry.workingRotationDuration
    private var reduceMotion = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        trackLayer.fillColor = NSColor.clear.cgColor
        trackLayer.lineCap = .round
        arcLayer.fillColor = NSColor.clear.cgColor
        arcLayer.lineCap = .round
        // Match the old SwiftUI trim arc, parked at 12 o'clock when static.
        contentLayer.addSublayer(trackLayer)
        contentLayer.addSublayer(arcLayer)
        layer?.addSublayer(contentLayer)
        contentLayer.transform = CATransform3DMakeRotation(-.pi / 2, 0, 0, 1)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    override func layout() {
        super.layout()
        rebuildPaths()
    }

    func configure(diameter: CGFloat, lineWidth: CGFloat, duration: TimeInterval, reduceMotion: Bool) {
        let geometryChanged =
            self.diameter != diameter
            || self.lineWidth != lineWidth
        let durationChanged = self.duration != duration
        self.diameter = diameter
        self.lineWidth = lineWidth
        self.duration = duration
        self.reduceMotion = reduceMotion
        if geometryChanged {
            rebuildPaths()
        }
        applyColors()
        updateAnimation(forceRestart: durationChanged)
    }

    var isSpinning: Bool {
        contentLayer.animation(forKey: Self.animationKey) != nil
    }

    var spinTimingFunctionControlPoints: [CGPoint]? {
        guard let timingFunction = (contentLayer.animation(forKey: Self.animationKey) as? CABasicAnimation)?.timingFunction else {
            return nil
        }
        return [1, 2].map { index in
            var values = [Float](repeating: 0, count: 2)
            timingFunction.getControlPoint(at: index, values: &values)
            return CGPoint(x: CGFloat(values[0]), y: CGFloat(values[1]))
        }
    }

    private func rebuildPaths() {
        let side = min(bounds.width, bounds.height)
        let size = side > 0 ? side : diameter
        let inset = lineWidth / 2
        let rect = CGRect(x: inset, y: inset, width: max(0, size - lineWidth), height: max(0, size - lineWidth))
        let path = CGPath(ellipseIn: rect, transform: nil)
        let frame = CGRect(origin: .zero, size: CGSize(width: size, height: size))
        // Anchor at center so rotation spins in place.
        contentLayer.bounds = frame
        contentLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        if contentLayer.anchorPoint != CGPoint(x: 0.5, y: 0.5) {
            contentLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        }
        trackLayer.frame = frame
        arcLayer.frame = frame
        trackLayer.path = path
        trackLayer.lineWidth = lineWidth
        arcLayer.path = path
        arcLayer.lineWidth = lineWidth
        // Match the SwiftUI trim(from:0, to:0.28) arc.
        arcLayer.strokeStart = 0
        arcLayer.strokeEnd = 0.28
    }

    private func applyColors() {
        let appearance = effectiveAppearance
        appearance.performAsCurrentDrawingAppearance {
            trackLayer.strokeColor = NSColor(BessieDesign.accentSoft.currentColor).cgColor
            arcLayer.strokeColor = NSColor(BessieDesign.accent.currentColor).cgColor
        }
    }

    private func updateAnimation(forceRestart: Bool = false) {
        let shouldSpin = !reduceMotion && window != nil && !isHiddenOrHasHiddenAncestor
        let existing = contentLayer.animation(forKey: Self.animationKey) as? CABasicAnimation
        if shouldSpin {
            if let existing, !forceRestart, existing.duration == duration {
                return
            }
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = -Double.pi / 2
            spin.toValue = -Double.pi / 2 + (2 * Double.pi)
            spin.duration = max(0.05, duration)
            spin.timingFunction = CAMediaTimingFunction(name: .linear)
            spin.repeatCount = .infinity
            spin.isRemovedOnCompletion = false
            contentLayer.removeAnimation(forKey: Self.animationKey)
            contentLayer.add(spin, forKey: Self.animationKey)
        } else {
            if existing != nil {
                contentLayer.removeAnimation(forKey: Self.animationKey)
            }
            // Park the arc at the canonical 12 o'clock static pose.
            contentLayer.transform = CATransform3DMakeRotation(-.pi / 2, 0, 0, 1)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAnimation()
    }

    override func viewDidHide() {
        super.viewDidHide()
        updateAnimation()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        updateAnimation()
    }
}

struct AgentStateGlyph: View {
    let state: AgentSemanticState
    var size: Double = 9

    var body: some View {
        BessieStatusGlyph(state: state)
        .frame(width: size, height: size)
    }
}

/// Testable system-accessibility and minimum-layout policy shared by the
/// redesigned surfaces. These are desktop constraints, not breakpoints.
enum BessieAccessibilityContract {
    static let minimumContentWidth: CGFloat = 1080
    static let minimumContentHeight: CGFloat = 680
    static let minimumContentSize = NSSize(
        width: minimumContentWidth,
        height: minimumContentHeight
    )
    static let pickerMaximumHeight: CGFloat = 420

    static func permitsSpatialMotion(reduceMotion: Bool) -> Bool { !reduceMotion }
    static func usesOpaqueMaterial(reduceTransparency: Bool, increasedContrast: Bool) -> Bool {
        reduceTransparency || increasedContrast
    }
}

/// Onboarding is an opaque application surface, never a material card. This
/// remains 1.0 with Reduce Transparency both enabled and disabled.
struct BessieOnboardingSurface: View {
    let base: BessieSemanticColor
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    static func opacity(reduceTransparency: Bool) -> Double { 1 }

    var body: some View {
        Rectangle()
            .fill(base)
            .opacity(Self.opacity(reduceTransparency: reduceTransparency))
    }
}

struct BessieDensityMetrics: Equatable {
    let rowHeight: CGFloat
    let cardGap: CGFloat
    let shellOutsideInset: CGFloat
    let shellBottomInset: CGFloat
    let shellPanelGap: CGFloat
    let railWidth: CGFloat
    let collapsedRailWidth: CGFloat
    let topbarHeight: CGFloat
    let settingsRowPadding: CGFloat
    let herdCardHeaderHeight: CGFloat
    let herdCardFooterHeight: CGFloat
    let herdCardPadding: CGFloat
    let attentionGap: CGFloat
    let attentionPadding: CGFloat
    let paneHeaderHeight: CGFloat
    let tabStripHeight: CGFloat

    static func metrics(for density: BessieDensity) -> Self {
        switch density {
        case .comfortable:
            Self(rowHeight: BessieDesign.rowHeight, cardGap: BessieDesign.cardGap,
                 shellOutsideInset: 9, shellBottomInset: 7, shellPanelGap: 9,
                 railWidth: BessieDesign.railWidth, collapsedRailWidth: BessieDesign.collapsedRailWidth,
                 topbarHeight: BessieDesign.topbarHeight, settingsRowPadding: 13,
                 herdCardHeaderHeight: 38, herdCardFooterHeight: 42, herdCardPadding: 12,
                 attentionGap: 11, attentionPadding: 15, paneHeaderHeight: 27, tabStripHeight: 36)
        case .compact:
            Self(rowHeight: 26, cardGap: 6, shellOutsideInset: 8, shellBottomInset: 8, shellPanelGap: 7,
                 railWidth: BessieDesign.railWidth, collapsedRailWidth: BessieDesign.collapsedRailWidth,
                 topbarHeight: 39, settingsRowPadding: 8,
                 herdCardHeaderHeight: 32, herdCardFooterHeight: 36, herdCardPadding: 9,
                 attentionGap: 7, attentionPadding: 10, paneHeaderHeight: 23, tabStripHeight: 30)
        }
    }
}

private struct BessieDensityKey: EnvironmentKey {
    static let defaultValue = BessieDensityMetrics.metrics(for: .comfortable)
}

extension EnvironmentValues {
    var bessieDensity: BessieDensityMetrics {
        get { self[BessieDensityKey.self] }
        set { self[BessieDensityKey.self] = newValue }
    }
}

extension BessieAppearance {
    var preferredColorScheme: ColorScheme? {
        BessieThemeRegistry.preferredColorScheme(for: self)
    }
}

struct BessieWindowRoot<Content: View>: View {
    @EnvironmentObject private var settings: BessieSettingsModel
    @State private var onboardingTitle: String?
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            BessieCowprintBackdrop(enabled: settings.preferences.cowprintEnabled)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            content
                .mask {
                    if onboardingTitle == nil {
                        Color.white
                    } else {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: BessieDesign.titlebarHeight)
                            Color.white
                        }
                        .ignoresSafeArea(edges: .top)
                    }
                }
            if let onboardingTitle {
                BessieOnboardingWindowTitle(
                    title: onboardingTitle
                )
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onPreferenceChange(BessieOnboardingWindowTitleKey.self) { onboardingTitle = $0 }
    }
}

enum BessieOnboardingWindowChrome {
    static let splashTitle = "bessie"
    static let welcomeTitle = "welcome to bessie"
}

private struct BessieOnboardingWindowTitleKey: PreferenceKey {
    static let defaultValue: String? = nil

    static func reduce(value: inout String?, nextValue: () -> String?) {
        value = nextValue() ?? value
    }
}

extension View {
    func bessieOnboardingWindowTitle(_ title: String) -> some View {
        preference(key: BessieOnboardingWindowTitleKey.self, value: title)
    }
}

private struct BessieOnboardingWindowTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(BessieDesign.faint)
            .frame(maxWidth: .infinity)
            .frame(height: BessieDesign.titlebarHeight)
            .background(BessieWindowTitleProbe(title: title))
            .accessibilityHidden(true)
    }
}

private struct BessieWindowTitleProbe: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        updateWindow(for: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        updateWindow(for: view)
    }

    private func updateWindow(for view: NSView) {
        if let window = view.window {
            window.title = title
            return
        }
        let title = title
        DispatchQueue.main.async { [weak view] in
            view?.window?.title = title
        }
    }
}

struct BessieCowprintBackdrop: View {
    let enabled: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bessieConcreteThemeID) private var concreteThemeID

    static let darkInkOpacity = 0.11
    static let lightInkOpacity = 0.16
    static let tileSize: CGFloat = 640

    static func inkOpacity(for scheme: ColorScheme) -> Double {
        scheme == .light ? lightInkOpacity : darkInkOpacity
    }

    private static let tileImage: Image? = {
        guard let url = BessieResources.url(forResource: "CowprintTile", withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        return Image(nsImage: image).renderingMode(.template)
    }()

    var body: some View {
        Canvas(
            opaque: true,
            colorMode: .nonLinear,
            rendersAsynchronously: ProcessInfo.processInfo.environment["BESSIE_DESIGN_ARTBOARD"] == nil
        ) { context, size in
            let palette = BessieThemeRegistry.definition(
                for: concreteThemeID,
                systemScheme: colorScheme
            ).palette
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.window))
            guard enabled else { return }

            context.opacity = Self.inkOpacity(for: colorScheme)
            let tile = Self.tileSize
            let startX: CGFloat = 0
            let startY: CGFloat = 0
            let columns = max(1, Int(ceil((size.width - startX) / tile)) + 1)
            let rows = max(1, Int(ceil((size.height - startY) / tile)) + 1)

            if let image = Self.tileImage {
                var resolved = context.resolve(image)
                resolved.shading = .color(palette.accent)
                for row in 0..<rows {
                    for column in 0..<columns {
                        let tileRect = CGRect(
                            x: startX + CGFloat(column) * tile,
                            y: startY + CGFloat(row) * tile,
                            width: tile,
                            height: tile
                        )
                        context.draw(resolved, in: tileRect)
                    }
                }
            }
        }
    }
}

struct BessieLogoMark: View {
    var width: CGFloat = 20

    private static let image: NSImage? = {
        guard let url = BessieResources.url(forResource: "BessieLogo", withExtension: "svg") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "questionmark.square.dashed")
            }
        }
        .foregroundStyle(BessieDesign.strong)
        .frame(width: width, height: width / 1.45)
        .accessibilityLabel("Bessie")
    }
}

struct BessieAssetIcon: View {
    let resource: String
    let size: CGFloat

    private var image: NSImage? {
        guard let url = BessieResources.url(forResource: resource, withExtension: "svg"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        image.isTemplate = true
        return image
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
    }
}

enum BessieIcon: String, CaseIterable {
    case magnifyingGlass, hardDrives, caretDown, caretUp, caretRight, stack, squaresFour
    case terminalWindow, gear, dotsThree, plus, cornersOut, check, desktop, cloud
    case folderOpen, folder, browser, squareSplitHorizontal, squareSplitVertical, x, play
    case minus, bell, listBullets, paintBrush, wrench, power, sun, cow

    var resourceName: String {
        switch self {
        case .magnifyingGlass: "PhosphorMagnifyingGlassThin"
        case .hardDrives: "PhosphorHardDrivesThin"
        case .caretDown: "PhosphorCaretDownThin"
        case .caretUp: "PhosphorCaretUpThin"
        case .caretRight: "PhosphorCaretRightThin"
        case .stack: "PhosphorStackThin"
        case .squaresFour: "PhosphorSquaresFourThin"
        case .terminalWindow: "PhosphorTerminalWindowThin"
        case .gear: "PhosphorGearThin"
        case .dotsThree: "PhosphorDotsThreeThin"
        case .plus: "PhosphorPlusThin"
        case .cornersOut: "PhosphorCornersOutThin"
        case .check: "PhosphorCheckThin"
        case .desktop: "PhosphorDesktopThin"
        case .cloud: "PhosphorCloudThin"
        case .folderOpen: "PhosphorFolderOpenThin"
        case .folder: "PhosphorFolderThin"
        case .browser: "PhosphorBrowserThin"
        case .squareSplitHorizontal: "PhosphorSquareSplitHorizontalThin"
        case .squareSplitVertical: "PhosphorSquareSplitVerticalThin"
        case .x: "PhosphorXThin"
        case .play: "PhosphorPlayThin"
        case .minus: "PhosphorMinusThin"
        case .bell: "PhosphorBellThin"
        case .listBullets: "PhosphorListBulletsThin"
        case .paintBrush: "PhosphorPaintBrushThin"
        case .wrench: "PhosphorWrenchThin"
        case .power: "PhosphorPowerThin"
        case .sun: "PhosphorSunThin"
        case .cow: "PhosphorCowFill"
        }
    }
}

struct BessieIconView: View {
    let icon: BessieIcon
    var size: CGFloat = 16

    var body: some View {
        BessieAssetIcon(resource: icon.resourceName, size: size)
            .background {
                if BessieResources.url(forResource: icon.resourceName, withExtension: "svg") == nil {
                    ZStack {
                        Rectangle().fill(.red)
                        Text("!").font(.system(size: max(7, size * 0.7), weight: .bold)).foregroundStyle(.white)
                    }
                }
            }
    }
}

struct BessiePhosphorSun: View {
    var body: some View { BessieIconView(icon: .sun, size: 16) }
}

struct BessiePhosphorCow: View {
    var size: CGFloat = 19
    var body: some View { BessieLogoMark(width: size) }
}

struct BessieProviderMark: View {
    let provider: String?
    var size: CGFloat = 13

    static func spokenLabel(for provider: String?) -> String {
        switch resourceName(for: provider) {
        case "AgentClaude": return "Claude agent"
        case "AgentCodex": return "Codex agent"
        case "AgentGrok": return "Grok agent"
        case "AgentAmp": return "Amp agent"
        case "AgentHermes": return "Hermes agent"
        case "AgentGemini": return "Gemini agent"
        case "AgentOpenCode": return "OpenCode agent"
        case "AgentCopilot": return "Copilot agent"
        case "AgentPi": return "Pi agent"
        case "AgentOmp": return "OMP agent"
        case "AgentCursor": return "Cursor agent"
        case "AgentDevin": return "Devin agent"
        case "AgentAgy": return "Antigravity agent"
        case "AgentCline": return "Cline agent"
        case "AgentMastraCode": return "Mastra agent"
        case "AgentKimi": return "Kimi agent"
        case "AgentKiro": return "Kiro agent"
        case "AgentDroid": return "Droid agent"
        case "AgentKilo": return "Kilo agent"
        case "AgentQodercli": return "Qoder CLI agent"
        case "AgentMaki": return "Maki agent"
        case "AgentOpenClaw": return "OpenClaw agent"
        default: return "Unknown agent"
        }
    }

    /// SVG resource stem under `Sources/BessieApp/Resources/`.
    /// Herdr-native agent kinds map to dedicated marks; unknown agents use `AgentGeneric.svg`.
    static func resourceName(for provider: String?) -> String {
        guard let provider, !provider.isEmpty else { return "AgentGeneric" }
        let normalized = provider.lowercased()
        let tokens = Set(
            normalized
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { !$0.isEmpty }
        )

        // Exact Herdr kind / common tokens first (avoids substring traps like "pi" in "copilot").
        let exact: [(Set<String>, String)] = [
            (["claude"], "AgentClaude"),
            (["codex"], "AgentCodex"),
            (["grok", "xai"], "AgentGrok"),
            (["amp", "sourcegraph"], "AgentAmp"),
            (["hermes", "nous", "nousresearch"], "AgentHermes"),
            (["gemini", "google"], "AgentGemini"),
            (["opencode", "oc"], "AgentOpenCode"),
            (["copilot", "github"], "AgentCopilot"),
            (["pi"], "AgentPi"),
            (["omp"], "AgentOmp"),
            (["cursor"], "AgentCursor"),
            (["devin"], "AgentDevin"),
            (["agy", "antigravity"], "AgentAgy"),
            (["cline"], "AgentCline"),
            (["mastracode", "mastra"], "AgentMastraCode"),
            (["kimi"], "AgentKimi"),
            (["kiro"], "AgentKiro"),
            (["droid", "factory"], "AgentDroid"),
            (["kilo", "kilocode"], "AgentKilo"),
            (["qodercli", "qoder"], "AgentQodercli"),
            (["maki"], "AgentMaki"),
            (["openclaw"], "AgentOpenClaw"),
            (["openai"], "AgentCodex"),
        ]
        for (keys, resource) in exact {
            if !tokens.isDisjoint(with: keys) || keys.contains(normalized) {
                return resource
            }
        }

        // Fuzzy fallbacks for free-form labels ("Claude Code", "OpenAI Codex", …).
        if normalized.contains("claude") { return "AgentClaude" }
        if normalized.contains("codex") { return "AgentCodex" }
        if normalized.contains("openai") { return "AgentCodex" }
        if normalized.contains("grok") || normalized.contains("xai") { return "AgentGrok" }
        if normalized.contains("sourcegraph") || normalized.contains(" amp") || normalized.hasPrefix("amp") {
            return "AgentAmp"
        }
        if normalized.contains("hermes") || normalized.contains("nous") { return "AgentHermes" }
        if normalized.contains("gemini") || normalized.contains("google") { return "AgentGemini" }
        if normalized.contains("opencode") { return "AgentOpenCode" }
        if normalized.contains("copilot") || normalized.contains("github") { return "AgentCopilot" }
        if normalized.contains("cursor") { return "AgentCursor" }
        if normalized.contains("devin") { return "AgentDevin" }
        if normalized.contains("antigravity") { return "AgentAgy" }
        if normalized.contains("cline") { return "AgentCline" }
        if normalized.contains("mastra") { return "AgentMastraCode" }
        if normalized.contains("kimi") { return "AgentKimi" }
        if normalized.contains("kiro") { return "AgentKiro" }
        if normalized.contains("droid") || normalized.contains("factory") { return "AgentDroid" }
        if normalized.contains("kilo") { return "AgentKilo" }
        if normalized.contains("qoder") { return "AgentQodercli" }
        if normalized.contains("maki") { return "AgentMaki" }
        if normalized.contains("openclaw") { return "AgentOpenClaw" }
        if normalized.contains("omp") { return "AgentOmp" }
        // "pi" only as a whole token (already handled above); avoid "copilot" false positive.
        return "AgentGeneric"
    }

    /// All packaged agent mark SVG stems that must ship with the app.
    static let packagedResourceNames = [
        "AgentClaude", "AgentCodex", "AgentGrok", "AgentAmp", "AgentGeneric",
        "AgentHermes", "AgentGemini", "AgentOpenCode", "AgentCopilot",
        "AgentPi", "AgentOmp", "AgentCursor", "AgentDevin", "AgentAgy",
        "AgentCline", "AgentMastraCode", "AgentKimi", "AgentKiro", "AgentDroid",
        "AgentKilo", "AgentQodercli", "AgentMaki", "AgentOpenClaw",
    ]

    private var resource: String { Self.resourceName(for: provider) }

    var body: some View {
        BessieAssetIcon(resource: resource, size: size)
            .foregroundStyle(BessieDesign.subtle)
            .accessibilityLabel(Self.spokenLabel(for: provider))
    }
}

struct BessieBrandMark: View {
    var body: some View {
        BessiePhosphorCow(size: 19)
        .foregroundStyle(BessieDesign.strong)
        .accessibilityLabel("Bessie")
    }
}

struct BessieTopBar<Actions: View>: View {
    let crumbs: [String]
    let title: String
    @ViewBuilder let actions: Actions
    @Environment(\.bessieDensity) private var density

    init(crumbs: [String] = [], title: String, @ViewBuilder actions: () -> Actions) {
        self.crumbs = crumbs
        self.title = title
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: 7) {
            HStack(spacing: 7) {
                ForEach(Array(crumbs.enumerated()), id: \.offset) { index, crumb in
                    if index > 0 { Text("/").foregroundStyle(BessieDesign.faint) }
                    Text(crumb).foregroundStyle(BessieDesign.subtle)
                }
                if !crumbs.isEmpty { Text("/").foregroundStyle(BessieDesign.faint) }
                Text(title)
                    .fontWeight(.medium)
                    .foregroundStyle(BessieDesign.strong)
                    .lineLimit(1)
                Spacer(minLength: 12)
            }

            HStack(spacing: 5) { actions }
        }
        .font(.system(size: 13))
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity)
        .frame(height: density.topbarHeight)
        .overlay(alignment: .bottom) { Rectangle().fill(BessieDesign.border).frame(height: 1) }
    }
}

/// Transparent AppKit region for window drag + double-click full screen.
/// Covers the stoplight title strip even with `.hiddenTitleBar`.
struct BessieWindowChromeRegion: NSViewRepresentable {
    enum Action {
        case toggleFullScreen
        case zoom
    }

    var action: Action = .toggleFullScreen

    func makeNSView(context: Context) -> NSView {
        let view = ChromeRegionView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ChromeRegionView)?.action = action
    }

    private final class ChromeRegionView: NSView {
        var action: Action = .toggleFullScreen

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        override var mouseDownCanMoveWindow: Bool { false }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard bounds.contains(point),
                  window?.styleMask.contains(.fullScreen) != true
            else { return nil }
            let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            if buttons.compactMap({ window?.standardWindowButton($0) }).contains(where: { button in
                convert(button.bounds, from: button).contains(point)
            }) {
                return nil
            }
            return self
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount >= 2 {
                switch action {
                case .toggleFullScreen:
                    window.toggleFullScreen(nil)
                case .zoom:
                    window.performZoom(nil)
                }
                return
            }
            window.performDrag(with: event)
        }
    }
}

// Keep old name as alias used elsewhere if any
private typealias BessieWindowDragRegion = BessieWindowChromeRegion

struct BessiePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 11)
            .frame(height: 28)
            .foregroundStyle(BessieDesign.accentForeground)
            .background(configuration.isPressed ? BessieDesign.done : BessieDesign.accent)
            .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))
    }
}

struct BessieSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 11)
            .frame(height: 28)
            .foregroundStyle(configuration.isPressed ? BessieDesign.strong : BessieDesign.text)
            .background(configuration.isPressed ? BessieDesign.selected : BessieDesign.panel)
            .overlay {
                RoundedRectangle(cornerRadius: BessieDesign.controlRadius)
                    .stroke(BessieDesign.borderStrong, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))
    }
}

struct BessieQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 8)
            .frame(height: 26)
            .foregroundStyle(configuration.isPressed ? BessieDesign.strong : BessieDesign.subtle)
            .background(configuration.isPressed ? BessieDesign.selected : BessieSemanticColor.clear)
            .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))
    }
}

struct BessieStatusLine: View {
    let workspaceCount: Int
    let attentionCount: Int
    let connectionCount: Int

    var body: some View {
        HStack(spacing: 16) {
            Text("BESSIE 0.1.0").foregroundStyle(BessieDesign.strong)
            Text("\(connectionCount) CONNECTION\(connectionCount == 1 ? "" : "S")")
            Text("\(workspaceCount) WORKSPACE\(workspaceCount == 1 ? "" : "S")")
            Spacer(minLength: 8)
            if attentionCount > 0 {
                Text("\(attentionCount) IN ATTENTION").foregroundStyle(BessieDesign.strong)
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(BessieDesign.subtle)
        .padding(.horizontal, 13)
        .frame(height: 26)
        .background(BessieDesign.window.opacity(0.35))
        .overlay(alignment: .top) { Rectangle().fill(BessieDesign.border).frame(height: 1) }
    }
}

struct BessieSectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.55)
            .foregroundStyle(BessieDesign.faint)
    }
}

struct BessieLabeledInput<Control: View>: View {
    let label: String
    let hint: String?
    @ViewBuilder let control: Control

    init(label: String, hint: String? = nil, @ViewBuilder control: () -> Control) {
        self.label = label
        self.hint = hint
        self.control = control()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(BessieDesign.strong)
            control
            if let hint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(BessieDesign.faint)
            }
        }
    }
}

private struct BessieInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(BessieDesign.codeText)
            .tint(BessieDesign.insertionPoint)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(BessieDesign.code)
            .overlay {
                RoundedRectangle(cornerRadius: BessieDesign.controlRadius)
                    .stroke(BessieDesign.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))
    }
}

struct BessieMaterialBackground: View {
    let base: BessieSemanticColor
    let radius: CGFloat
    static let usesFixedOpaqueTint = true

    var body: some View {
        RoundedRectangle(cornerRadius: radius).fill(base)
    }
}

struct BessieSurfaceCard: ViewModifier {
    let base: BessieSemanticColor
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                BessieMaterialBackground(base: base, radius: radius)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .stroke(BessieDesign.border, lineWidth: 1)
            }
    }
}

extension View {
    func bessieSurface(base: BessieSemanticColor, radius: CGFloat = BessieDesign.surfaceRadius) -> some View {
        modifier(BessieSurfaceCard(base: base, radius: radius))
    }

    func bessieInput() -> some View {
        modifier(BessieInputModifier())
    }
}
