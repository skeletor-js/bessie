import AppKit
import BessieCore
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
    let strong: Color
    let text: Color
    let subtle: Color
    let faint: Color
    let border: Color
    let borderStrong: Color
    let hover: Color
    let selected: Color
    let accent: Color
    let accentSoft: Color
    let accentForeground: Color
    let blocked: Color
    let running: Color
    let done: Color
    let idle: Color
}

enum BessieDesign {
    static func palette(for scheme: ColorScheme) -> BessiePalette {
        switch scheme {
        case .dark:
            return BessiePalette(
                desk: Color(red: 0.027, green: 0.027, blue: 0.027),
                window: Color(red: 0.020, green: 0.020, blue: 0.020),
                background: Color(red: 0.055, green: 0.055, blue: 0.055),
                rail: Color(red: 0.039, green: 0.039, blue: 0.039),
                panel: Color(red: 0.086, green: 0.086, blue: 0.086),
                inset: Color(red: 0.067, green: 0.067, blue: 0.067),
                code: Color(red: 0.031, green: 0.031, blue: 0.031),
                strong: Color(white: 0.961), text: Color(white: 0.714), subtle: Color(white: 0.541), faint: Color(white: 0.373),
                border: Color.white.opacity(0.10), borderStrong: Color.white.opacity(0.19), hover: Color.white.opacity(0.055), selected: Color.white.opacity(0.10),
                accent: .white, accentSoft: Color.white.opacity(0.12), accentForeground: .black,
                blocked: .white, running: Color(white: 0.604), done: Color(white: 0.863), idle: Color(white: 0.373)
            )
        case .light:
            return BessiePalette(
                desk: Color(red: 0.86, green: 0.84, blue: 0.79),
                window: Color(red: 0.94, green: 0.92, blue: 0.87),
                background: Color(red: 0.975, green: 0.965, blue: 0.93),
                rail: Color(red: 0.91, green: 0.89, blue: 0.84),
                panel: Color(red: 0.995, green: 0.985, blue: 0.95),
                inset: Color(red: 0.90, green: 0.88, blue: 0.83),
                code: Color(red: 0.12, green: 0.115, blue: 0.105),
                strong: Color(red: 0.075, green: 0.07, blue: 0.06), text: Color(white: 0.24), subtle: Color(white: 0.38), faint: Color(white: 0.53),
                border: Color.black.opacity(0.13), borderStrong: Color.black.opacity(0.24), hover: Color.black.opacity(0.045), selected: Color.black.opacity(0.09),
                accent: Color(red: 0.075, green: 0.07, blue: 0.06), accentSoft: Color.black.opacity(0.12), accentForeground: .white,
                blocked: Color(white: 0.06), running: Color(white: 0.34), done: Color(white: 0.18), idle: Color(white: 0.53)
            )
        @unknown default:
            return palette(for: .dark)
        }
    }

    private static func adaptive(_ keyPath: KeyPath<BessiePalette, Color>) -> Color {
        let dark = NSColor(palette(for: .dark)[keyPath: keyPath])
        let light = NSColor(palette(for: .light)[keyPath: keyPath])
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    static let desk = adaptive(\.desk)
    static let window = adaptive(\.window)
    static let background = adaptive(\.background)
    static let rail = adaptive(\.rail)
    static let panel = adaptive(\.panel)
    static let inset = adaptive(\.inset)
    static let code = adaptive(\.code)
    static let strong = adaptive(\.strong)
    static let text = adaptive(\.text)
    static let subtle = adaptive(\.subtle)
    static let faint = adaptive(\.faint)
    static let border = adaptive(\.border)
    static let borderStrong = adaptive(\.borderStrong)
    static let hover = adaptive(\.hover)
    static let selected = adaptive(\.selected)
    static let accent = adaptive(\.accent)
    static let accentSoft = adaptive(\.accentSoft)
    static let accentForeground = adaptive(\.accentForeground)
    static let blocked = adaptive(\.blocked)
    static let running = adaptive(\.running)
    static let done = adaptive(\.done)
    static let idle = adaptive(\.idle)

    static let titlebarHeight: CGFloat = 30
    static let railWidth: CGFloat = 244
    static let topbarHeight: CGFloat = 46
    static let rowHeight: CGFloat = 30
    static let cardGap: CGFloat = 9
    static let paneGap: CGFloat = 7
    static let cardRadius: CGFloat = 4
    static let paneRadius: CGFloat = 3
    static let controlRadius: CGFloat = 3
}

struct BessieDensityMetrics: Equatable {
    let rowHeight: CGFloat
    let cardGap: CGFloat
    let railWidth: CGFloat
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
                 railWidth: BessieDesign.railWidth, topbarHeight: BessieDesign.topbarHeight, settingsRowPadding: 13,
                 herdCardHeaderHeight: 38, herdCardFooterHeight: 42, herdCardPadding: 12,
                 attentionGap: 11, attentionPadding: 15, paneHeaderHeight: 27, tabStripHeight: 36)
        case .compact:
            Self(rowHeight: 26, cardGap: 6, railWidth: 220, topbarHeight: 38, settingsRowPadding: 8,
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
        switch self {
        case .system: nil
        case .dark: .dark
        case .light: .light
        }
    }
}

struct BessieCowCrop: Equatable {
    let ink: Double
    let scale: CGFloat
    let position: UnitPoint

    static let connect = BessieCowCrop(ink: 0.05, scale: 900, position: UnitPoint(x: 0.50, y: 0.0))
    static let herd = BessieCowCrop(ink: 0.06, scale: 780, position: UnitPoint(x: 0.04, y: 0.22))
    static let workspaces = BessieCowCrop(ink: 0.055, scale: 700, position: UnitPoint(x: 0.72, y: 0.08))
    static let workspace = BessieCowCrop(ink: 0.045, scale: 900, position: UnitPoint(x: 0.18, y: 0.68))
    static let attention = BessieCowCrop(ink: 0.06, scale: 480, position: UnitPoint(x: 0.80, y: 0.30))
    static let agent = BessieCowCrop(ink: 0.03, scale: 660, position: UnitPoint(x: 0.08, y: 0.82))
    static let settings = BessieCowCrop(ink: 0.03, scale: 900, position: UnitPoint(x: 0.10, y: 0.50))
    static let newProcess = BessieCowCrop(ink: 0.04, scale: 700, position: UnitPoint(x: 0.65, y: 0.55))
}

struct BessieCowprintTexture: View {
    let base: Color
    let crop: BessieCowCrop
    var intensityScale = 1.0

    @EnvironmentObject private var settings: BessieSettingsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let tileImage: Image? = {
        guard let url = BessieResources.url(forResource: "CowprintTile", withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        return Image(nsImage: image)
    }()

    var body: some View {
        if !settings.preferences.cowprintEnabled {
            base
        } else {
            animatedTexture
        }
    }

    private var animatedTexture: some View {
        let paused = reduceMotion || !settings.preferences.cowPrintMotion
        return TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: paused)) { timeline in
            GeometryReader { proxy in
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))

                    let referenceIntensity = max(0.001, settings.preferences.cowPrintIntensity)
                    let preferenceFactor = min(2.4, referenceIntensity / 0.05)
                    context.opacity = min(0.16, max(0, crop.ink * preferenceFactor * intensityScale))

                    let tile = max(220, crop.scale)
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let drift = paused ? 0 : sin(time * 0.155) * 7
                    let originX = -tile * crop.position.x + drift
                    let originY = -tile * crop.position.y - drift * 0.35
                    let startX = originX - tile
                    let startY = originY - tile
                    let columns = Int(ceil((size.width - startX) / tile)) + 1
                    let rows = Int(ceil((size.height - startY) / tile)) + 1

                    if let image = Self.tileImage {
                        for row in 0..<max(1, rows) {
                            for column in 0..<max(1, columns) {
                                let rect = CGRect(
                                    x: startX + CGFloat(column) * tile,
                                    y: startY + CGFloat(row) * tile,
                                    width: tile,
                                    height: tile
                                )
                                context.draw(image, in: rect)
                            }
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .accessibilityHidden(true)
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
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "questionmark.square.dashed")
            }
        }
        .frame(width: width, height: width / 1.45)
        .accessibilityLabel("Bessie")
    }
}

struct BessieBrandMark: View {
    var body: some View {
        HStack(spacing: 8) {
            BessieLogoMark(width: 19)
            Text("Bessie")
                .font(.system(size: 14, weight: .semibold))
                .tracking(-0.14)
        }
        .foregroundStyle(BessieDesign.strong)
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
            .contentShape(Rectangle())
            .overlay { BessieWindowDragRegion() }
            .accessibilityHint("Double-click to zoom the window")

            HStack(spacing: 5) { actions }
        }
        .font(.system(size: 13))
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(height: density.topbarHeight)
        .background(BessieDesign.background)
        .overlay(alignment: .bottom) { Rectangle().fill(BessieDesign.border).frame(height: 1) }
    }
}

private struct BessieWindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragRegionView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragRegionView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }
}

struct BessiePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
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
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .foregroundStyle(configuration.isPressed ? BessieDesign.strong : BessieDesign.text)
            .background(configuration.isPressed ? BessieDesign.selected : BessieDesign.panel)
            .overlay {
                RoundedRectangle(cornerRadius: BessieDesign.controlRadius)
                    .stroke(BessieDesign.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))
    }
}

struct BessieQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .frame(height: 26)
            .foregroundStyle(configuration.isPressed ? BessieDesign.strong : BessieDesign.subtle)
            .background(configuration.isPressed ? BessieDesign.selected : Color.clear)
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
            Text("\(connectionCount) CONNECTION\(connectionCount == 1 ? "" : "S") · HERDR 0.7.5")
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
        .background(BessieDesign.window)
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

struct BessieSurfaceCard: ViewModifier {
    let base: Color
    let crop: BessieCowCrop?
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                if let crop {
                    BessieCowprintTexture(base: base, crop: crop)
                } else {
                    base
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .stroke(BessieDesign.border, lineWidth: 1)
            }
    }
}

extension View {
    func bessieSurface(base: Color, crop: BessieCowCrop? = nil, radius: CGFloat = BessieDesign.cardRadius) -> some View {
        modifier(BessieSurfaceCard(base: base, crop: crop, radius: radius))
    }

    func bessieInput() -> some View {
        modifier(BessieInputModifier())
    }
}
