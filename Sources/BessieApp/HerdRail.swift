import AppKit
import BessieCore
import SwiftUI

struct HerdRailUpdatePresentation: Equatable {
    let version: String

    init?(phase: BessieUpdatePhase, canRestartToUpdate: Bool) {
        guard canRestartToUpdate,
              case let .readyToRestart(version) = phase
        else { return nil }
        self.version = version.shortVersion
    }

    let title = "Restart to Update"
    let symbolName = "arrow.clockwise"
    var expandedAccessibilityLabel: String { title }
    var collapsedAccessibilityLabel: String { "Restart to Update Bessie \(version)" }
    var help: String { collapsedAccessibilityLabel }
}

enum HerdRailFooterPresentation {
    enum Item: Hashable {
        case restartToUpdate
        case settingsDivider
        case settings
    }

    static func items(update: HerdRailUpdatePresentation?) -> [Item] {
        update == nil
            ? [.settingsDivider, .settings]
            : [.restartToUpdate, .settingsDivider, .settings]
    }
}

struct HerdRailUpdateActivation {
    private(set) var isConsumed = false

    mutating func invoke(_ action: () -> Void) -> Bool {
        guard !isConsumed else { return false }
        isConsumed = true
        action()
        return true
    }

    mutating func reset() {
        isConsumed = false
    }
}

struct HerdRail: View {
    private enum FocusTarget: Hashable {
        case row(HerdPaneIdentity)
        case shellsHeader
        case snoozedHeader
    }

    let presentation: HerdRailPresentation
    let healthMessages: [String]
    let selectedPane: HerdPaneIdentity?
    let hierarchy: WorkspaceHierarchyRail
    let update: HerdRailUpdatePresentation?
    @Binding var collapsed: Bool
    @Binding var appearance: BessieAppearance
    let restartToUpdate: () -> Void
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
    let setPinned: (BessiePaneIncarnation, Bool) -> Void
    let setSnooze: (BessiePaneIncarnation, BessiePaneSnoozePreset) -> Void
    let wakePane: (BessiePaneIncarnation) -> Void

    @State private var shellsExpanded = true
    @State private var snoozedExpanded = true
    @State private var hoveredRows: Set<HerdPaneIdentity> = []
    @State private var renderNow = Date()
    @State private var pendingRelocation: (BessiePaneIncarnation, String)?
    @State private var updateActivation = HerdRailUpdateActivation()
    @State private var updateHovered = false
    @FocusState private var focusTarget: FocusTarget?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 2) {
                    hierarchy
                    if !presentation.pinnedRows.isEmpty {
                        presentedSection("Pinned", rows: presentation.pinnedRows)
                    }
                    ForEach(HerdRailGroup.statusCases, id: \.self) { group in
                        stateSection(group)
                    }
                    if !presentation.shellRows.isEmpty {
                        if collapsed {
                            collapsedSummary(
                                icon: .terminalWindow,
                                title: "Shells",
                                count: presentation.shellRows.count,
                                expand: { shellsExpanded = true }
                            )
                        } else {
                            shellsSection
                        }
                    }
                    if !presentation.snoozedRows.isEmpty {
                        if collapsed {
                            collapsedSnoozedSummary
                        } else {
                            snoozedSection
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
        .task(id: countdownSignature) { await runCountdownCadence() }
        .onChange(of: presentation) { _, _ in restorePendingRelocationFocus() }
        .onChange(of: update) { _, _ in updateActivation.reset() }
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
        let rows = presentation.rows(in: group)
        if group != .unknown || !rows.isEmpty {
            if !collapsed { sectionHeader(group.rawValue, count: rows.count) }
            ForEach(rows) { paneRow($0) }
        }
    }

    @ViewBuilder private func presentedSection(_ title: String, rows: [HerdRailPresentedRow]) -> some View {
        if !collapsed { sectionHeader(title, count: rows.count) }
        ForEach(rows) { paneRow($0) }
    }

    private var shellsSection: some View {
        VStack(spacing: 2) {
            Button { shellsExpanded.toggle() } label: {
                sectionHeaderContent("Shells", count: presentation.shellRows.count, disclosure: shellsExpanded)
            }.buttonStyle(.plain).help(shellsExpanded ? "Collapse Shells" : "Expand Shells")
                .focused($focusTarget, equals: .shellsHeader)
                .accessibilityLabel(shellsExpanded ? "Collapse Shells" : "Expand Shells")
                .accessibilityValue(shellsExpanded ? "Expanded" : "Collapsed")
            if shellsExpanded { ForEach(presentation.shellRows) { paneRow($0) } }
        }
    }

    private var snoozedSection: some View {
        VStack(spacing: 2) {
            Button { snoozedExpanded.toggle() } label: {
                sectionHeaderContent("Snoozed", count: presentation.snoozedRows.count, disclosure: snoozedExpanded)
            }
            .buttonStyle(.plain)
            .focused($focusTarget, equals: .snoozedHeader)
            .help(snoozedExpanded ? "Collapse Snoozed" : "Expand Snoozed")
            .accessibilityLabel(snoozedExpanded ? "Collapse Snoozed" : "Expand Snoozed")
            .accessibilityValue(snoozedExpanded ? "Expanded" : "Collapsed")
            if snoozedExpanded { ForEach(presentation.snoozedRows) { paneRow($0) } }
        }
    }

    private func collapsedSummary(
        icon: BessieIcon,
        title: String,
        count: Int,
        expand: @escaping () -> Void
    ) -> some View {
        Button {
            expand()
            collapsed = false
            focusAfterExpansion(presentation.shellRows.first?.id, fallback: .shellsHeader)
        } label: {
            VStack(spacing: 0) {
                BessieIconView(icon: icon, size: 14)
                Text("\(count)").font(.system(size: 8, design: .monospaced)).monospacedDigit()
            }.frame(width: 40, height: 32)
        }
        .buttonStyle(.plain)
        .help("\(title), \(count). Expand rail")
        .accessibilityLabel("\(title), \(count). Expand rail")
    }

    private var collapsedSnoozedSummary: some View {
        Button {
            snoozedExpanded = true
            collapsed = false
            focusAfterExpansion(presentation.snoozedRows.first?.id, fallback: .snoozedHeader)
        } label: {
            VStack(spacing: 0) {
                Text("Zzz").font(.system(size: 9, weight: .semibold, design: .rounded))
                Text("\(presentation.snoozedRows.count)").font(.system(size: 8, design: .monospaced)).monospacedDigit()
            }.frame(width: 40, height: 32)
        }
        .buttonStyle(.plain)
        .help("Snoozed, \(presentation.snoozedRows.count). Expand rail")
        .accessibilityLabel("Snoozed, \(presentation.snoozedRows.count). Expand rail")
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        sectionHeaderContent(title, count: count, disclosure: nil)
            .accessibilityLabel("\(title), \(count)")
    }

    private func sectionHeaderContent(_ title: String, count: Int, disclosure: Bool?) -> some View {
        HStack(spacing: 7) {
            if let disclosure { BessieIconView(icon: disclosure ? .caretDown : .caretRight, size: 11) }
            if title == "Shells" { BessieIconView(icon: .terminalWindow, size: 13) }
            if title == "Snoozed" { Text("Zzz").font(.system(size: 8, weight: .semibold, design: .rounded)) }
            Text(title.uppercased()); Spacer(); Text("\(count)").monospacedDigit()
        }
        .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(BessieDesign.subtle)
        .padding(.horizontal, 0)
        .frame(maxWidth: .infinity, minHeight: 27, alignment: .leading)
    }

    private func paneRow(_ row: HerdRailPresentedRow) -> some View {
        let base = row.base
        let selected = row.id == selectedPane
        return Button { openPane(base.target) } label: {
            Group {
                if collapsed {
                    HStack(spacing: 2) {
                        HerdRailStateMark(group: base.group, agentKind: base.agentKind)
                        if row.isSnoozed { Text("Zzz").font(.system(size: 7, weight: .semibold, design: .rounded)) }
                    }.frame(width: 40, height: 28)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            BessieStatusGlyph(state: base.rawState)
                            Text(base.title)
                                .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if row.isPinned { Image(systemName: "pin.fill").font(.system(size: 9)) }
                            if row.isSnoozed { Text("Zzz").font(.system(size: 9, weight: .semibold, design: .rounded)) }
                        }
                        HStack(spacing: 6) {
                            Text([base.secondaryIdentity, base.location].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(BessieDesign.faint)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if let wake = row.compactWakeLabel(now: renderNow) { Text(wake).monospacedDigit() }
                            BessieProviderMark(provider: base.agentKind)
                        }
                    }
                    .padding(.leading, 9)
                    .padding(.trailing, 8)
                    .padding(.top, 5)
                    .padding(.bottom, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(base.group == .needsYou && !row.isSnoozed ? BessieDesign.blocked.opacity(0.08) : (selected ? BessieDesign.selected : BessieSemanticColor.clear))
            .overlay {
                if base.group == .needsYou && !row.isSnoozed {
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
        .buttonStyle(.plain).help(accessibilityLabel(row))
        .opacity(row.isSnoozed && !hoveredRows.contains(row.id) && !isFocused(row.id) ? 0.52 : 1)
        .accessibilityLabel(accessibilityLabel(row))
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .focused($focusTarget, equals: .row(row.id))
        .onHover { hovering in
            if hovering { hoveredRows.insert(row.id) } else { hoveredRows.remove(row.id) }
        }
        .contextMenu {
            paneActionMenu(row)
        }
        .padding(.bottom, base.group == .needsYou ? 6 : 0)
    }

    @ViewBuilder private func presentationMenu(_ row: HerdRailPresentedRow) -> some View {
        Button(row.isPinned ? "Unpin" : "Pin") {
            beginExplicitRelocation(row, announcement: row.isPinned ? "Pane unpinned" : "Pane pinned")
            setPinned(row.incarnation, !row.isPinned)
        }
        Menu("Snooze") {
            ForEach(BessiePaneSnoozePreset.allCases, id: \.self) { preset in
                Button {
                    beginExplicitRelocation(row, announcement: "Pane snoozed")
                    setSnooze(row.incarnation, preset)
                } label: {
                    if row.snooze?.provenance == preset.provenance
                        && (preset != .untilFurtherNotice || row.snooze == .indefinite) {
                        Label(snoozeTitle(preset), systemImage: "checkmark")
                    } else {
                        Text(snoozeTitle(preset))
                    }
                }
            }
        }
        if row.isSnoozed {
            Button("Wake now") {
                beginExplicitRelocation(row, announcement: "Pane awake")
                wakePane(row.incarnation)
            }
        }
    }

    @ViewBuilder private func paneActionMenu(_ row: HerdRailPresentedRow) -> some View {
        presentationMenu(row)
        Divider()
        PaneContextMenuContent(
            paneID: row.base.target.paneID,
            primaryTitle: "Open pane",
            primaryAction: { openPane(row.base.target) },
            zenTitle: "Open in Zen",
            enterZen: { enterZen(row.base.target) },
            action: { performPaneAction(row.base.target, $0) },
            requestSplit: { requestSplit(row.base.target, $0) },
            moveChoices: paneMoveChoices(row.base.target),
            requestMoveToNewTab: { requestMoveToNewTab(row.base.target, $0) },
            canTakeOver: canTakeOverPane(row.base.target),
            requestTakeover: { takeOverPane(row.base.target) },
            rename: { renamePane(row.base.target) },
            close: { closePane(row.base.target) }
        )
    }

    private func isFocused(_ identity: HerdPaneIdentity) -> Bool {
        focusTarget == .row(identity)
    }

    private func focusAfterExpansion(_ identity: HerdPaneIdentity?, fallback: FocusTarget) {
        DispatchQueue.main.async {
            focusTarget = identity.map(FocusTarget.row) ?? fallback
        }
    }

    private func beginExplicitRelocation(_ row: HerdRailPresentedRow, announcement: String) {
        pendingRelocation = (row.incarnation, announcement)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if pendingRelocation?.0 == row.incarnation { restorePendingRelocationFocus() }
        }
    }

    private func restorePendingRelocationFocus() {
        guard let pendingRelocation else { return }
        self.pendingRelocation = nil
        let row = presentation.allRows.first { $0.incarnation == pendingRelocation.0 }
        if let row, row.isSnoozed, !row.isPinned, !snoozedExpanded {
            focusTarget = .snoozedHeader
        } else if let row {
            focusTarget = .row(row.id)
        }
        NSAccessibility.post(
            element: NSApp,
            notification: .announcementRequested,
            userInfo: [.announcement: pendingRelocation.1, .priority: NSAccessibilityPriorityLevel.medium.rawValue]
        )
    }

    private func snoozeTitle(_ preset: BessiePaneSnoozePreset) -> String {
        switch preset {
        case .untilFurtherNotice: return "Until further notice"
        case .thirtyMinutes: return "30 minutes"
        case .oneHour: return "1 hour"
        case .threeHours: return "3 hours"
        case .twelveHours: return "12 hours"
        case .twentyFourHours: return "24 hours"
        case .tomorrow:
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            let deadline = preset.deadline(now: renderNow) ?? renderNow
            return "Tomorrow at \(formatter.string(from: deadline))"
        }
    }

    private func accessibilityLabel(_ row: HerdRailPresentedRow) -> String {
        [
            row.base.accessibilityDescription,
            row.isPinned ? "Pinned" : nil,
            row.accessibleWakeLabel(now: renderNow),
        ].compactMap { $0 }.joined(separator: ", ")
    }

    private var timedDeadlines: [Date] {
        presentation.allRows.compactMap(\.wakeAt).sorted()
    }

    private var countdownSignature: String {
        timedDeadlines.map { String($0.timeIntervalSinceReferenceDate) }.joined(separator: "|")
    }

    @MainActor
    private func runCountdownCadence() async {
        while !Task.isCancelled {
            let now = Date()
            guard let deadline = timedDeadlines.first(where: { $0 > now }) else {
                renderNow = now
                return
            }
            let interval: TimeInterval = deadline.timeIntervalSince(now) <= 60 ? 1 : 60
            let elapsed = now.timeIntervalSinceReferenceDate
            let delay = max(0.05, interval - elapsed.truncatingRemainder(dividingBy: interval))
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            renderNow = Date()
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            ForEach(HerdRailFooterPresentation.items(update: update), id: \.self) { item in
                switch item {
                case .restartToUpdate:
                    if let update { restartToUpdateRow(update) }
                case .settingsDivider:
                    Rectangle().fill(BessieDesign.border).frame(height: 1)
                case .settings:
                    settingsFooter
                }
            }
        }
    }

    private func restartToUpdateRow(_ update: HerdRailUpdatePresentation) -> some View {
        Button {
            _ = updateActivation.invoke(restartToUpdate)
        } label: {
            if collapsed {
                Image(systemName: update.symbolName)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 40, height: 38)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: update.symbolName)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(update.title)
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(update.version)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(BessieDesign.subtle)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(BessieDesign.text)
        .frame(maxWidth: .infinity)
        .background(updateHovered ? BessieDesign.hover : BessieDesign.accentSoft)
        .help(update.help)
        .accessibilityLabel(collapsed ? update.collapsedAccessibilityLabel : update.expandedAccessibilityLabel)
        .disabled(updateActivation.isConsumed)
        .accessibilityIdentifier("restart-to-update")
        .onHover { updateHovered = $0 }
    }

    private var settingsFooter: some View {
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
        case .done: .done
        case .idle: .idle
        case .unknown, .shells: .unknown
        }
    }
}
