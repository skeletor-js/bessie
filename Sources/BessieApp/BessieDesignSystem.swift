import AppKit
import SwiftUI

enum BessieResources {
    static func url(forResource name: String, withExtension extensionName: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: extensionName)
            ?? Bundle.module.url(forResource: name, withExtension: extensionName)
    }
}

/// Native rendering of the retained Bessie design system. Values mirror the
/// shipped cowprint/dark/sharp/flat token set rather than macOS adaptive defaults.
enum BessieDesign {
    static let desk = Color(red: 0.027, green: 0.027, blue: 0.027)
    static let window = Color(red: 0.020, green: 0.020, blue: 0.020)
    static let background = Color(red: 0.055, green: 0.055, blue: 0.055)
    static let rail = Color(red: 0.039, green: 0.039, blue: 0.039)
    static let panel = Color(red: 0.086, green: 0.086, blue: 0.086)
    static let inset = Color(red: 0.067, green: 0.067, blue: 0.067)
    static let code = Color(red: 0.031, green: 0.031, blue: 0.031)

    static let strong = Color(white: 0.961)
    static let text = Color(white: 0.714)
    static let subtle = Color(white: 0.541)
    static let faint = Color(white: 0.373)
    static let border = Color.white.opacity(0.10)
    static let borderStrong = Color.white.opacity(0.19)
    static let hover = Color.white.opacity(0.055)
    static let selected = Color.white.opacity(0.10)
    static let accent = Color.white
    static let accentSoft = Color.white.opacity(0.12)
    static let accentForeground = Color.black

    // The cowprint palette communicates state through luminance, never hue.
    static let blocked = Color.white
    static let running = Color(white: 0.604)
    static let done = Color(white: 0.863)
    static let idle = Color(white: 0.373)

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
        let paused = reduceMotion || !settings.preferences.cowPrintMotion
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: paused)) { timeline in
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

    init(crumbs: [String] = [], title: String, @ViewBuilder actions: () -> Actions) {
        self.crumbs = crumbs
        self.title = title
        self.actions = actions()
    }

    var body: some View {
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
            HStack(spacing: 5) { actions }
        }
        .font(.system(size: 13))
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(height: BessieDesign.topbarHeight)
        .background(BessieDesign.background)
        .overlay(alignment: .bottom) { Rectangle().fill(BessieDesign.border).frame(height: 1) }
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
