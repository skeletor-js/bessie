import BessieCore
import SwiftUI

struct HerdRail: View {
    let projection: HerdRailProjection
    let healthMessages: [String]
    let selectedPane: HerdPaneIdentity?
    let hierarchy: WorkspaceHierarchyRail
    @Binding var collapsed: Bool
    @Binding var appearance: BessieAppearance
    let openSearch: () -> Void
    let selectDestination: (ProductDestination) -> Void
    let openPane: (RoutedPaneTarget) -> Void
    let enterZen: (RoutedPaneTarget) -> Void
    let performPaneAction: (RoutedPaneTarget, HerdrAction) -> Void
    let requestSplit: (RoutedPaneTarget, SplitDirection) -> Void
    let paneMoveChoices: (RoutedPaneTarget) -> PaneMoveChoices?
    let requestMoveToNewTab: (RoutedPaneTarget, String) -> Void
    let canTakeOverPane: (RoutedPaneTarget) -> Bool
    let takeOverPane: (RoutedPaneTarget) -> Void
    let renamePane: (RoutedPaneTarget) -> Void
    let closePane: (RoutedPaneTarget) -> Void

    @State private var shellsExpanded = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 2) {
                    hierarchy
                    ForEach(Array(HerdRailGroup.allCases.prefix(4)), id: \.self) { group in
                        stateSection(group)
                    }
                    if projection.count(in: .shells) > 0 {
                        if collapsed {
                            if let shell = projection.rows(in: .shells).first {
                                Button { openPane(shell.target) } label: {
                                    BessieIconView(icon: .terminalWindow, size: 15)
                                        .frame(width: 40, height: 28)
                                }
                                .buttonStyle(.plain)
                                .help("Shells")
                                .accessibilityLabel("Open Shells")
                            }
                        } else {
                            shellsSection
                        }
                    }
                    if !healthMessages.isEmpty && !collapsed {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("HEALTH").font(.system(size: 9, weight: .semibold, design: .monospaced))
                            ForEach(healthMessages, id: \.self) { Text($0).font(.caption).foregroundStyle(BessieDesign.subtle) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                }.padding(.horizontal, collapsed ? 4 : 8).padding(.vertical, 6)
            }
            footer
        }
        .frame(width: collapsed ? BessieDesign.collapsedRailWidth : BessieDesign.railWidth)
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
            if value.translation.width <= -40 { collapsed = true }
            if value.translation.width >= 40 { collapsed = false }
        })
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Herd rail")
    }

    private var header: some View {
        Group {
            if collapsed {
                VStack(spacing: 2) {
                    Button { collapsed = false } label: {
                        BessiePhosphorCow(size: 19).frame(width: 30, height: 30)
                    }
                        .buttonStyle(.plain).help("Expand herd rail")
                        .accessibilityLabel("Expand herd rail").accessibilityValue("Collapsed")
                    Button(action: openSearch) { BessieIconView(icon: .magnifyingGlass).frame(width: 30, height: 30) }
                        .buttonStyle(.plain).help("Search").accessibilityLabel("Search")
                    railDivider
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 6) {
                    Button { collapsed.toggle() } label: { BessiePhosphorCow(size: 19) }
                        .buttonStyle(.plain).help("Collapse herd rail")
                        .accessibilityLabel("Collapse herd rail").accessibilityValue("Expanded")
                    Text("Bessie").font(.headline)
                    Spacer()
                    Button(action: openSearch) { BessieIconView(icon: .magnifyingGlass).frame(width: 28, height: 28) }
                        .buttonStyle(.plain).help("Search").accessibilityLabel("Search")
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.top, 12).padding(.bottom, 8)
    }

    @ViewBuilder private func stateSection(_ group: HerdRailGroup) -> some View {
        let rows = projection.rows(in: group)
        if !collapsed { sectionHeader(group.rawValue, count: rows.count) }
        ForEach(rows) { paneRow($0) }
    }

    private var shellsSection: some View {
        VStack(spacing: 2) {
            Button { shellsExpanded.toggle() } label: {
                sectionHeaderContent("Shells", count: projection.count(in: .shells), disclosure: true)
            }.buttonStyle(.plain).help(shellsExpanded ? "Collapse Shells" : "Expand Shells")
                .accessibilityLabel(shellsExpanded ? "Collapse Shells" : "Expand Shells")
                .accessibilityValue(shellsExpanded ? "Expanded" : "Collapsed")
            if shellsExpanded { ForEach(projection.rows(in: .shells)) { paneRow($0) } }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        sectionHeaderContent(title, count: count, disclosure: false)
            .accessibilityLabel("\(title), \(count)")
    }

    private func sectionHeaderContent(_ title: String, count: Int, disclosure: Bool) -> some View {
        HStack(spacing: 7) {
            if disclosure { BessieIconView(icon: shellsExpanded ? .caretDown : .caretRight, size: 11) }
            if disclosure { BessieIconView(icon: .terminalWindow, size: 13) }
            Text(title); Spacer(); Text("\(count)").monospacedDigit()
        }
        .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(BessieDesign.subtle)
        .padding(.horizontal, 0)
        .frame(maxWidth: .infinity, minHeight: 27, alignment: .leading)
    }

    private func paneRow(_ row: HerdRailPaneRow) -> some View {
        let selected = row.id == selectedPane
        return Button { openPane(row.target) } label: {
            Group {
                if collapsed {
                    HerdRailStateMark(group: row.group, agentKind: row.agentKind)
                        .frame(width: 40, height: 28)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            BessieStatusGlyph(state: row.rawState)
                            Text(row.title)
                                .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 6) {
                            Text(row.location)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(BessieDesign.faint)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            BessieProviderMark(provider: row.agentKind)
                        }
                    }
                    .padding(.leading, 9)
                    .padding(.trailing, 8)
                    .padding(.top, 5)
                    .padding(.bottom, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(row.group == .needsYou ? BessieDesign.blocked.opacity(0.08) : (selected ? BessieDesign.selected : BessieSemanticColor.clear))
            .overlay {
                if row.group == .needsYou {
                    RoundedRectangle(cornerRadius: BessieDesign.controlRadius)
                        .stroke(BessieDesign.blocked.opacity(0.45), lineWidth: 1)
                }
            }
            .overlay(alignment: .leading) {
                if selected {
                    Rectangle().fill(BessieDesign.accent).frame(width: 2.5)
                        .padding(.vertical, 6).offset(x: collapsed ? -4 : -8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))
        }
        .buttonStyle(.plain).help(row.accessibilityDescription)
        .accessibilityLabel(row.accessibilityDescription)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .contextMenu {
            PaneContextMenuContent(
                paneID: row.target.paneID,
                primaryTitle: "Open pane",
                primaryAction: { openPane(row.target) },
                zenTitle: "Open in Zen",
                enterZen: { enterZen(row.target) },
                action: { performPaneAction(row.target, $0) },
                requestSplit: { requestSplit(row.target, $0) },
                moveChoices: paneMoveChoices(row.target),
                requestMoveToNewTab: { requestMoveToNewTab(row.target, $0) },
                canTakeOver: canTakeOverPane(row.target),
                requestTakeover: { takeOverPane(row.target) },
                rename: { renamePane(row.target) },
                close: { closePane(row.target) }
            )
        }
        .padding(.bottom, row.group == .needsYou ? 6 : 0)
    }

    private var footer: some View {
        Group {
            if collapsed {
                footerControls.frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 2) {
                    footerControls
                    Text("Settings")
                    Spacer()
                    if BessieAppearanceToggle.isVisible(for: appearance) {
                        appearanceMenu
                    }
                }
                .padding(.horizontal, 10)
            }
        }
        .padding(.vertical, 7)
        .overlay(alignment: .top) { Rectangle().fill(BessieDesign.border).frame(height: 1) }
    }

    private var footerControls: some View {
        Button { selectDestination(.settings) } label: { BessieIconView(icon: .gear).frame(width: 30, height: 30) }
            .buttonStyle(.plain).help("Settings").accessibilityLabel("Settings")
    }

    private var appearanceMenu: some View {
        Button {
            appearance = BessieAppearanceToggle.target(
                current: appearance,
                effectiveSystemIsDark: colorScheme == .dark
            )
        } label: {
            Group {
                if effectiveDarkAppearance {
                    BessieIconView(icon: .sun, size: 15)
                } else {
                    Image(systemName: "moon")
                        .font(.system(size: 13, weight: .regular))
                }
            }
            .foregroundStyle(BessieDesign.strong)
            .frame(width: 28, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Switch to \(appearanceToggleTarget.title)")
        .accessibilityLabel("Switch to \(appearanceToggleTarget.title)")
        .accessibilityValue(effectiveDarkAppearance ? "Dark mode" : "Light mode")
        .contextMenu {
            ForEach(BessieThemeRegistry.selectableIDs, id: \.self) { id in
                Button(id.title) { appearance = id }
            }
        }
    }

    private var effectiveDarkAppearance: Bool {
        BessieThemeRegistry.scheme(for: appearance, systemScheme: colorScheme) == .dark
    }

    private var appearanceToggleTarget: BessieThemeID {
        BessieThemeRegistry.quickToggleTarget(for: appearance, systemScheme: colorScheme)
    }

    private var railDivider: some View {
        Rectangle().fill(BessieDesign.border).frame(width: collapsed ? 24 : nil, height: 1).padding(.vertical, 6)
    }
}

private struct HerdRailStateMark: View {
    let group: HerdRailGroup
    let agentKind: String?
    var body: some View {
        HStack(spacing: 5) {
            BessieStatusGlyph(state: state)
            if group == .shells {
                BessieIconView(icon: .terminalWindow, size: 13)
            } else {
                BessieProviderMark(provider: agentKind)
            }
        }
        .frame(width: 26)
    }

    private var state: AgentSemanticState {
        switch group {
        case .needsYou: .blocked
        case .working: .working
        case .settled: .done
        case .unknown, .shells: .unknown
        }
    }
}
