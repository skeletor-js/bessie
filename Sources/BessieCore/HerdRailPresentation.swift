import Foundation

public struct HerdRailPresentedRow: Identifiable, Equatable, Sendable {
    public let base: HerdRailPaneRow
    public let isPinned: Bool
    public let snooze: BessiePaneSnooze?

    public var id: HerdPaneIdentity { base.id }
    public var incarnation: BessiePaneIncarnation {
        BessiePaneIncarnation(
            connectionID: base.id.connectionID,
            paneID: base.id.paneID,
            terminalID: base.terminalID
        )
    }
    public var isSnoozed: Bool { snooze != nil }
    public var wakeAt: Date? { snooze?.wakeAt }

    public init(base: HerdRailPaneRow, isPinned: Bool, snooze: BessiePaneSnooze?) {
        self.base = base
        self.isPinned = isPinned
        self.snooze = snooze
    }

    public func compactWakeLabel(now: Date) -> String? {
        switch snooze {
        case nil: return nil
        case .indefinite?: return "∞"
        case .until(let deadline, _)?:
            return Self.relativeLabel(seconds: max(0, deadline.timeIntervalSince(now)))
        }
    }

    public func accessibleWakeLabel(now: Date) -> String? {
        switch snooze {
        case nil: return nil
        case .indefinite?: return "Snoozed until further notice"
        case .until(let deadline, _)?:
            let seconds = max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
            if seconds < 60 { return "Wakes in \(seconds) seconds" }
            let minutes = Int(ceil(Double(seconds) / 60))
            if minutes < 60 { return "Wakes in \(minutes) minutes" }
            let hours = Int(ceil(Double(minutes) / 60))
            return "Wakes in \(hours) hours"
        }
    }

    private static func relativeLabel(seconds: TimeInterval) -> String {
        if seconds < 60 { return "in \(max(1, Int(ceil(seconds))))s" }
        let minutes = Int(ceil(seconds / 60))
        if minutes < 60 { return "in \(minutes)m" }
        return "in \(Int(ceil(Double(minutes) / 60)))h"
    }
}

public struct HerdRailPresentation: Equatable, Sendable {
    public let pinnedRows: [HerdRailPresentedRow]
    public let ordinaryRows: [HerdRailGroup: [HerdRailPresentedRow]]
    public let shellRows: [HerdRailPresentedRow]
    public let snoozedRows: [HerdRailPresentedRow]
    public let awakeAttentionCount: Int
    public let navigationRows: [HerdRailPresentedRow]

    public init(base: HerdRailProjection, ledger: BessiePanePresentationLedger, now: Date = Date()) {
        var pinned: [HerdRailPresentedRow] = []
        var ordinary = Dictionary(uniqueKeysWithValues: HerdRailGroup.allCases.map { ($0, [HerdRailPresentedRow]()) })
        var shells: [HerdRailPresentedRow] = []
        var snoozed: [HerdRailPresentedRow] = []
        var attention = 0

        for baseRow in base.rows {
            let incarnation = BessiePaneIncarnation(
                connectionID: baseRow.id.connectionID,
                paneID: baseRow.id.paneID,
                terminalID: baseRow.terminalID
            )
            let preference = ledger.preference(for: incarnation, now: now)
            let activeSnooze = preference?.snooze.flatMap { $0.isActive(at: now) ? $0 : nil }
            let row = HerdRailPresentedRow(
                base: baseRow,
                isPinned: preference?.pinned == true,
                snooze: activeSnooze
            )

            if row.isPinned {
                pinned.append(row)
            } else if row.isSnoozed {
                snoozed.append(row)
            } else if baseRow.group == .shells {
                shells.append(row)
            } else {
                ordinary[baseRow.group, default: []].append(row)
            }

            if !row.isSnoozed {
                if baseRow.rawState == .blocked { attention += 1 }
            }
        }

        pinnedRows = pinned
        ordinaryRows = ordinary
        shellRows = shells
        snoozedRows = snoozed
        awakeAttentionCount = attention
        navigationRows = pinned.filter { !$0.isSnoozed }
            + HerdRailGroup.allCases.prefix(4).flatMap { ordinary[$0, default: []] }
            + shells
    }

    public func rows(in group: HerdRailGroup) -> [HerdRailPresentedRow] {
        group == .shells ? shellRows : ordinaryRows[group, default: []]
    }

    public var allRows: [HerdRailPresentedRow] {
        pinnedRows
            + HerdRailGroup.allCases.prefix(4).flatMap { rows(in: $0) }
            + shellRows
            + snoozedRows
    }

    public var traversal: HerdPaneTraversal { HerdPaneTraversal(navigationRows.map(\.id)) }
    public var snoozedIncarnations: Set<BessiePaneIncarnation> {
        Set((pinnedRows + snoozedRows).filter(\.isSnoozed).map(\.incarnation))
    }
}
