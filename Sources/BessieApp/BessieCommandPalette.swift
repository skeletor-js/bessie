import AppKit
import BessieCore
import os.log
import SwiftUI

enum BessieCommandPaletteOpenability {
    static func allowsOpen(
        onboardingCompleted: Bool,
        mainWindowIsKey: Bool,
        hasAttachedSheet: Bool
    ) -> Bool {
        onboardingCompleted && mainWindowIsKey && !hasAttachedSheet
    }
}

@MainActor
final class BessieCommandPaletteAvailability: ObservableObject {
    @Published var canToggle = false
}

enum BessieCommandPaletteRecoveryNotice: Equatable {
    case waiting
    case failed(String)

    var message: String {
        switch self {
        case .waiting:
            "Waiting for fresh Herdr state…"
        case .failed(let message):
            message
        }
    }
}

@MainActor
final class BessieCommandPaletteModel: ObservableObject {
    @Published var query = ""
    @Published var selection = 0
    @Published private(set) var index = CommandPaletteIndex(
        allEntities: [], sections: [], activeConnectionID: nil
    )
    @Published private(set) var results: [CommandPaletteEntity] = []
    @Published private(set) var sections: [CommandPaletteSection] = []
    @Published private(set) var recoveryNotice: BessieCommandPaletteRecoveryNotice?
    @Published private(set) var isSearchMounted = false
    @Published private(set) var isSearchFocused = false
    private(set) var isOpen = false

    private let log = OSLog(subsystem: "work.superbud.Bessie", category: .pointsOfInterest)
    private let recoveryDelayNanoseconds: UInt64
    private var dispatchGate = CommandPaletteDispatchGate()
    private var recoveryTask: Task<Void, Never>?
    private var pendingActivation: (entity: CommandPaletteEntity, alternate: Bool)?
    private var lastPointerLocation: NSPoint?
    private var onDispatch: (CommandPaletteRouteIntent) -> Bool = { _ in false }
    private var onSuccessfulDispatch: (CommandPaletteEntityID) -> Void = { _ in }
    private var onDismiss: (Bool) -> Void = { _ in }

    var isBrowse: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasFreshConnections: Bool {
        index.allEntities.contains { $0.kind == .connection && $0.freshness == .fresh }
    }
    var selectedEntity: CommandPaletteEntity? {
        results.indices.contains(selection) ? results[selection] : nil
    }
    var selectedScrollID: String? {
        guard let selectedEntity else { return nil }
        guard isBrowse else { return rowID(for: selectedEntity, section: nil) }
        var offset = 0
        for section in sections {
            let end = offset + section.entities.count
            if selection >= offset, selection < end {
                return rowID(for: section.entities[selection - offset], section: section.kind)
            }
            offset = end
        }
        return nil
    }

    init(recoveryDelayNanoseconds: UInt64 = 2_000_000_000) {
        self.recoveryDelayNanoseconds = recoveryDelayNanoseconds
    }

    func configure(
        onDispatch: @escaping (CommandPaletteRouteIntent) -> Bool,
        onSuccessfulDispatch: @escaping (CommandPaletteEntityID) -> Void,
        onDismiss: @escaping (Bool) -> Void
    ) {
        self.onDispatch = onDispatch
        self.onSuccessfulDispatch = onSuccessfulDispatch
        self.onDismiss = onDismiss
    }

    func open(input: CommandPaletteIndexInput, initialQuery: String = "") {
        os_signpost(.begin, log: log, name: "Palette Open")
        recoveryTask?.cancel()
        recoveryTask = nil
        pendingActivation = nil
        recoveryNotice = nil
        dispatchGate = CommandPaletteDispatchGate()
        lastPointerLocation = NSEvent.mouseLocation
        isSearchMounted = false
        isSearchFocused = false
        isOpen = true
        query = initialQuery
        rebuild(input: input)
    }

    func rebuild(input: CommandPaletteIndexInput) {
        guard isOpen else { return }
        os_signpost(.begin, log: log, name: "Command Palette Index")
        let nextIndex = CommandPaletteIndexBuilder().build(input)
        os_signpost(.end, log: log, name: "Command Palette Index", "entities=%d", nextIndex.allEntities.count)
        index = nextIndex
        updateResults(preservingSelection: true)
        resolvePendingActivationIfPossible()
    }

    func queryDidChange() {
        guard isOpen else { return }
        if pendingActivation != nil {
            cancelRecovery()
        } else if recoveryNotice != nil {
            recoveryNotice = nil
        }
        os_signpost(.event, log: log, name: "Command Palette Query", "length=%d", query.count)
        updateResults(preservingSelection: true)
    }

    func bufferPrintableCharacters(_ characters: String) {
        guard isOpen, !characters.isEmpty else { return }
        query.append(contentsOf: characters)
        queryDidChange()
    }

    func markSearchMounted() {
        guard isOpen else { return }
        isSearchMounted = true
        os_signpost(.end, log: log, name: "Palette Open", "results=%d", results.count)
    }

    func markSearchFocused(_ focused: Bool) {
        isSearchFocused = isOpen && focused
    }

    func moveSelection(by delta: Int) {
        selection = CommandPaletteKeyboard.movedSelection(
            current: selection,
            delta: delta,
            count: results.count
        )
    }

    func rowID(
        for entity: CommandPaletteEntity,
        section: CommandPaletteSection.Kind?
    ) -> String {
        "\(section?.rawValue ?? "query")::\(entity.id.description)"
    }

    func resultIndex(
        for entity: CommandPaletteEntity,
        section targetSection: CommandPaletteSection.Kind?
    ) -> Int? {
        guard let targetSection else {
            return results.firstIndex { $0.id == entity.id }
        }
        var offset = 0
        for section in sections {
            if section.kind == targetSection,
               let index = section.entities.firstIndex(where: { $0.id == entity.id }) {
                return offset + index
            }
            offset += section.entities.count
        }
        return nil
    }

    func isSelected(
        _ entity: CommandPaletteEntity,
        section: CommandPaletteSection.Kind?
    ) -> Bool {
        resultIndex(for: entity, section: section) == selection
    }

    func hover(
        _ entity: CommandPaletteEntity,
        section: CommandPaletteSection.Kind?
    ) {
        let pointer = NSEvent.mouseLocation
        defer { lastPointerLocation = pointer }
        guard lastPointerLocation != pointer,
              let index = resultIndex(for: entity, section: section)
        else { return }
        selection = index
    }

    func activate(entity: CommandPaletteEntity? = nil, alternate: Bool) {
        guard isOpen else { return }
        let entity = entity ?? selectedEntity
        guard let entity, dispatchGate.begin(entity, alternate: alternate) != nil else { return }
        pendingActivation = (entity, alternate)
        resolvePendingActivationIfPossible()
    }

    func dismiss() {
        guard isOpen else { return }
        cancelRecovery()
        isSearchFocused = false
        isOpen = false
        onDismiss(true)
    }

    private func updateResults(preservingSelection: Bool) {
        let selectedID = preservingSelection ? selectedEntity?.id : nil
        if isBrowse {
            sections = index.sections
            results = sections.flatMap(\.entities)
        } else {
            sections = []
            os_signpost(.begin, log: log, name: "Palette Query")
            results = index.results(query: query)
            os_signpost(.end, log: log, name: "Palette Query", "results=%d", results.count)
        }
        if let selectedID, let preserved = results.firstIndex(where: { $0.id == selectedID }) {
            selection = preserved
        } else {
            selection = 0
        }
    }

    private func resolvePendingActivationIfPossible() {
        guard let pendingActivation else { return }
        switch CommandPaletteTargetResolver.resolve(
            pendingActivation.entity,
            currentEntities: index.allEntities,
            alternate: pendingActivation.alternate
        ) {
        case .dispatch(let route):
            finishDispatch(route, entityID: pendingActivation.entity.id)
        case .connectionUnavailable:
            failRecovery("That target's herd is disconnected. Retry the herd, then search again.")
        case .refreshRequired:
            beginRecoveryWaitIfNeeded()
        }
    }

    private func finishDispatch(_ route: CommandPaletteRouteIntent, entityID: CommandPaletteEntityID) {
        guard dispatchGate.commit(route) != nil else { return }
        recoveryTask?.cancel()
        recoveryTask = nil
        pendingActivation = nil
        recoveryNotice = nil
        let succeeded = onDispatch(route)
        if succeeded { onSuccessfulDispatch(entityID) }
        isSearchFocused = false
        isOpen = false
        onDismiss(!succeeded)
    }

    private func beginRecoveryWaitIfNeeded() {
        guard recoveryTask == nil else { return }
        recoveryNotice = .waiting
        let delay = recoveryDelayNanoseconds
        recoveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled, self.pendingActivation != nil else { return }
            self.failRecovery("That palette target is no longer available in the current Herdr state.")
        }
    }

    private func failRecovery(_ message: String) {
        recoveryTask?.cancel()
        recoveryTask = nil
        pendingActivation = nil
        dispatchGate.cancelActivation()
        recoveryNotice = .failed(message)
    }

    private func cancelRecovery() {
        recoveryTask?.cancel()
        recoveryTask = nil
        pendingActivation = nil
        dispatchGate.cancelActivation()
        recoveryNotice = nil
    }
}

struct BessieCommandPalette: View {
    @ObservedObject var model: BessieCommandPaletteModel
    @Environment(\.bessieDensity) private var density
    @FocusState private var searchFocused: Bool
    let maxListHeight: CGFloat

    static let width: CGFloat = 560
    static let scrimOpacity = 0.28
    static let inputFontSize: CGFloat = 16
    static let topInsetFraction = 0.14
    static let maximumListHeightFraction = 0.48
    static let footerLegend = "panes · workspaces · projects · herds · commands"

    static func activationVerb(for entity: CommandPaletteEntity) -> String {
        if entity.kind == .command { return "run" }
        if entity.kind == .connection && entity.freshness == .disconnected { return "retry" }
        return "open"
    }

    static func retryHealthDetail(base: String, attemptCount: Int) -> String {
        guard attemptCount > 0 else { return base }
        let transientPhases = ["checking", "connecting", "reconnecting", "retrying", "starting", "syncing"]
        if transientPhases.contains(where: { base.localizedCaseInsensitiveContains($0) }) {
            return "Retrying"
        }
        return attemptCount == 1 ? "\(base) · Retry failed" : "\(base) · Retry failed again"
    }

    private var horizontalPadding: CGFloat { density.rowHeight >= BessieDesign.rowHeight ? 9 : 7 }
    private var verticalPadding: CGFloat { density.rowHeight >= BessieDesign.rowHeight ? 5 : 3 }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Rectangle().fill(BessieDesign.border).frame(height: 1)
            resultList
                .frame(maxHeight: min(520, maxListHeight))
            Rectangle().fill(BessieDesign.border).frame(height: 1)
            footer
        }
        .frame(width: Self.width)
        .bessieSurface(base: BessieDesign.panel)
        .overlay { Rectangle().stroke(BessieDesign.borderStrong, lineWidth: 1) }
        .background(BessieWindowSnapshotProbe(role: "sheet"))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command palette")
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(named: "Dismiss") { model.dismiss() }
        .task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            searchFocused = true
            await Task.yield()
            guard !Task.isCancelled else { return }
            model.markSearchMounted()
            announceInitialState()
        }
        .onChange(of: model.query) { _, _ in model.queryDidChange() }
        .onChange(of: searchFocused) { _, focused in
            model.markSearchFocused(focused)
        }
        .onChange(of: announcement) { _, message in
            guard let message else { return }
            AccessibilityNotification.Announcement(message).post()
        }
    }

    private var searchField: some View {
        HStack(spacing: 11) {
            BessieIconView(icon: .magnifyingGlass, size: 17)
                .foregroundStyle(BessieDesign.subtle)
            TextField("Search commands", text: $model.query)
                .tint(BessieDesign.insertionPoint)
                .textFieldStyle(.plain)
                .font(.system(size: Self.inputFontSize))
                .focused($searchFocused)
                .accessibilityLabel("Search commands, panes, workspaces, Projects, and herds")
            Text("esc")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(BessieDesign.subtle)
                .padding(.horizontal, 6)
                .frame(height: 20)
                .background(BessieDesign.inset)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .padding(.horizontal, horizontalPadding + 7)
        .padding(.vertical, verticalPadding + 6)
    }

    @ViewBuilder private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if !model.hasFreshConnections {
                        noticeRow(
                            icon: .hardDrives,
                            message: "No herds connected. Commands and herd retry routes remain available."
                        )
                    }
                    if let recoveryNotice = model.recoveryNotice {
                        noticeRow(icon: .magnifyingGlass, message: recoveryNotice.message)
                    }
                    if !model.isBrowse && model.results.isEmpty {
                        noticeRow(
                            icon: .magnifyingGlass,
                            message: "No matching panes, workspaces, Projects, herds, or commands"
                        )
                    } else if model.isBrowse {
                        ForEach(model.sections) { section in
                            Text(section.title)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(BessieDesign.faint)
                                .textCase(.uppercase)
                                .tracking(0.5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, horizontalPadding + 6)
                                .padding(.top, verticalPadding + 5)
                                .padding(.bottom, 3)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(section.entities) { item in row(item, section: section.kind) }
                        }
                    } else {
                        ForEach(model.results) { item in row(item, section: nil) }
                    }
                }
                .padding(6)
            }
            .onChange(of: model.selection) { _, _ in
                guard let id = model.selectedScrollID else { return }
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    private func row(
        _ item: CommandPaletteEntity,
        section: CommandPaletteSection.Kind?
    ) -> some View {
        BessieCommandPaletteRow(
            item: item,
            selected: model.isSelected(item, section: section),
            density: density,
            action: { model.activate(entity: item, alternate: false) }
        )
        .id(model.rowID(for: item, section: section))
        .onHover { hovering in
            if hovering { model.hover(item, section: section) }
        }
    }

    private func noticeRow(icon: BessieIcon, message: String) -> some View {
        HStack(spacing: 10) {
            BessieIconView(icon: icon, size: 16).foregroundStyle(BessieDesign.faint)
            Text(message)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(BessieDesign.subtle)
            Spacer()
        }
        .padding(.horizontal, horizontalPadding + 6)
        .frame(minHeight: density.rowHeight + 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            if let selected = model.selectedEntity {
                Text("↑↓ move")
                Text("↵ \(Self.activationVerb(for: selected))")
                if selected.alternateRoute != nil { Text("⌘↩ alternate") }
                Spacer()
            } else {
                Spacer()
            }
            Text(Self.footerLegend)
        }
        .font(.system(size: 11))
        .foregroundStyle(BessieDesign.faint)
        .padding(.horizontal, horizontalPadding + 7)
        .padding(.vertical, verticalPadding + 3)
    }

    private var announcement: String? {
        if let recoveryNotice = model.recoveryNotice { return recoveryNotice.message }
        if !model.isBrowse && model.results.isEmpty {
            return "No matching panes, workspaces, Projects, herds, or commands"
        }
        if !model.hasFreshConnections {
            return "No herds connected. Commands and herd retry routes remain available."
        }
        return nil
    }

    private func announceInitialState() {
        guard let announcement else { return }
        AccessibilityNotification.Announcement(announcement).post()
    }
}

private struct BessieCommandPaletteRow: View {
    let item: CommandPaletteEntity
    let selected: Bool
    let density: BessieDensityMetrics
    let action: () -> Void

    private var horizontalPadding: CGFloat { density.rowHeight >= BessieDesign.rowHeight ? 11 : 9 }

    private var icon: BessieIcon {
        switch item.kind {
        case .pane: .terminalWindow
        case .workspace: .squaresFour
        case .project: .stack
        case .connection: .hardDrives
        case .command: .terminalWindow
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                if let state = item.semanticState, item.kind != .connection {
                    BessieStatusGlyph(state: state)
                } else {
                    BessieIconView(icon: icon, size: 15)
                        .foregroundStyle(selected ? BessieDesign.accent : BessieDesign.subtle)
                }
                HStack(spacing: 0) {
                    Text(item.title).foregroundStyle(BessieDesign.strong)
                    if !item.detail.isEmpty {
                        Text(" · \(item.detail)").foregroundStyle(BessieDesign.subtle)
                    }
                }
                .font(.system(size: 13))
                .lineLimit(1)
                Spacer(minLength: 12)
                Text([item.location, item.shortcut].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(BessieDesign.faint)
                    .lineLimit(1)
                if item.kind == .pane, let provider = item.provider {
                    BessieProviderMark(provider: provider)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: density.rowHeight)
            .background(selected ? BessieDesign.selected : BessieSemanticColor.clear)
            .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint(accessibilityHint)
    }

    private var accessibilityHint: String {
        let verb: String
        if item.kind == .command { verb = "Run" }
        else if item.kind == .connection && item.freshness == .disconnected { verb = "Retry herd" }
        else { verb = "Open" }
        return item.alternateRoute == nil ? verb : "\(verb), or press Command Return for the advertised alternate route"
    }

    private var accessibilityLabel: String {
        let status = item.semanticState.map { ", \(HerdPresentationStatus(state: $0).rawValue)" } ?? ""
        let location = item.location.map { ", \($0)" } ?? ""
        let health = item.kind == .connection ? ", \(item.detail)" : ""
        let kind = item.kind == .connection ? "Herd" : item.kind.rawValue.capitalized
        return "\(kind): \(item.title)\(status)\(health)\(location)"
    }
}
