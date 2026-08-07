import Foundation

public struct BessiePaneIncarnation: Hashable, Codable, Equatable, Sendable {
    public let connectionID: String
    public let paneID: String
    public let terminalID: String

    public init(connectionID: String, paneID: String, terminalID: String) {
        self.connectionID = connectionID
        self.paneID = paneID
        self.terminalID = terminalID
    }
}

public enum BessieTimedSnoozeProvenance: String, Codable, CaseIterable, Equatable, Sendable {
    case thirtyMinutes
    case oneHour
    case threeHours
    case twelveHours
    case twentyFourHours
    case tomorrow
}

public enum BessiePaneSnooze: Equatable, Sendable {
    case indefinite
    case until(Date, provenance: BessieTimedSnoozeProvenance)

    public var wakeAt: Date? {
        switch self {
        case .indefinite: nil
        case .until(let date, _): date
        }
    }

    public var provenance: BessieTimedSnoozeProvenance? {
        switch self {
        case .indefinite: nil
        case .until(_, let provenance): provenance
        }
    }

    public func isActive(at now: Date) -> Bool {
        switch self {
        case .indefinite: true
        case .until(let date, _): date > now
        }
    }
}

extension BessiePaneSnooze: Codable {
    private enum Kind: String, Codable { case indefinite, until }
    private enum CodingKeys: String, CodingKey {
        case kind
        case wakeAt = "wake_at"
        case provenance
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .kind) {
        case .indefinite:
            guard !values.contains(.wakeAt), !values.contains(.provenance) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .kind,
                    in: values,
                    debugDescription: "Indefinite snooze cannot include a deadline or provenance."
                )
            }
            self = .indefinite
        case .until:
            self = .until(
                try values.decode(Date.self, forKey: .wakeAt),
                provenance: try values.decode(BessieTimedSnoozeProvenance.self, forKey: .provenance)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .indefinite:
            try values.encode(Kind.indefinite, forKey: .kind)
        case .until(let date, let provenance):
            try values.encode(Kind.until, forKey: .kind)
            try values.encode(date, forKey: .wakeAt)
            try values.encode(provenance, forKey: .provenance)
        }
    }
}

public enum BessiePaneSnoozePreset: String, Codable, CaseIterable, Equatable, Sendable {
    case untilFurtherNotice = "until_further_notice"
    case thirtyMinutes = "thirty_minutes"
    case oneHour = "one_hour"
    case threeHours = "three_hours"
    case twelveHours = "twelve_hours"
    case twentyFourHours = "twenty_four_hours"
    case tomorrow

    public var provenance: BessieTimedSnoozeProvenance? {
        switch self {
        case .untilFurtherNotice: nil
        case .thirtyMinutes: .thirtyMinutes
        case .oneHour: .oneHour
        case .threeHours: .threeHours
        case .twelveHours: .twelveHours
        case .twentyFourHours: .twentyFourHours
        case .tomorrow: .tomorrow
        }
    }

    public func deadline(now: Date, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        switch self {
        case .untilFurtherNotice: return nil
        case .thirtyMinutes: return now.addingTimeInterval(1_800)
        case .oneHour: return now.addingTimeInterval(3_600)
        case .threeHours: return now.addingTimeInterval(10_800)
        case .twelveHours: return now.addingTimeInterval(43_200)
        case .twentyFourHours: return now.addingTimeInterval(86_400)
        case .tomorrow:
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: nextDay)
        }
    }

    public func snooze(now: Date, calendar: Calendar = .autoupdatingCurrent) -> BessiePaneSnooze {
        guard let provenance, let deadline = deadline(now: now, calendar: calendar) else {
            return .indefinite
        }
        return .until(deadline, provenance: provenance)
    }
}

public struct BessiePanePresentationPreference: Codable, Equatable, Sendable {
    public let connectionID: String
    public let paneID: String
    public let terminalID: String
    public var pinned: Bool
    public var snooze: BessiePaneSnooze?

    public init(
        connectionID: String,
        paneID: String,
        terminalID: String,
        pinned: Bool = false,
        snooze: BessiePaneSnooze? = nil
    ) {
        self.connectionID = connectionID
        self.paneID = paneID
        self.terminalID = terminalID
        self.pinned = pinned
        self.snooze = snooze
    }

    public var incarnation: BessiePaneIncarnation {
        BessiePaneIncarnation(connectionID: connectionID, paneID: paneID, terminalID: terminalID)
    }

    enum CodingKeys: String, CodingKey {
        case connectionID = "connection_id"
        case paneID = "pane_id"
        case terminalID = "terminal_id"
        case pinned, snooze
    }
}

public enum BessiePanePresentationError: Error, Equatable, LocalizedError, Sendable {
    case identifierTooLong
    case invalidIdentifier
    case tooManyRecords
    case revisionOverflow

    public var errorDescription: String? {
        switch self {
        case .identifierTooLong: "A pane presentation identifier exceeds 256 UTF-8 bytes."
        case .invalidIdentifier: "A pane presentation identifier is empty."
        case .tooManyRecords: "Pane presentation preferences exceed the 4,096-record limit."
        case .revisionOverflow: "Pane presentation revision cannot advance further."
        }
    }
}

public struct BessiePanePresentationLedger: Equatable, Sendable {
    public static let maximumRecords = 4_096
    public static let maximumIdentifierBytes = 256

    public private(set) var revision: UInt64
    public private(set) var records: [BessiePanePresentationPreference]

    public init(
        revision: UInt64 = 0,
        records: [BessiePanePresentationPreference] = [],
        now: Date = Date()
    ) throws {
        guard records.count <= Self.maximumRecords else { throw BessiePanePresentationError.tooManyRecords }
        self.revision = revision
        self.records = try Self.normalized(records, now: now)
    }

    public func preference(for incarnation: BessiePaneIncarnation, now: Date = Date()) -> BessiePanePresentationPreference? {
        records.first { $0.incarnation == incarnation }.flatMap { record -> BessiePanePresentationPreference? in
            var record = record
            if let snooze = record.snooze, !snooze.isActive(at: now) { record.snooze = nil }
            return record.pinned || record.snooze != nil ? record : nil
        }
    }

    @discardableResult
    public mutating func setPinned(_ pinned: Bool, for incarnation: BessiePaneIncarnation) throws -> Bool {
        try mutate(incarnation) { $0.pinned = pinned }
    }

    @discardableResult
    public mutating func setSnooze(
        _ snooze: BessiePaneSnooze,
        for incarnation: BessiePaneIncarnation,
        now: Date = Date()
    ) throws -> Bool {
        guard snooze.isActive(at: now) else { return try wake(incarnation, now: now) }
        return try mutate(incarnation) { $0.snooze = snooze }
    }

    @discardableResult
    public mutating func wake(_ incarnation: BessiePaneIncarnation, now: Date = Date()) throws -> Bool {
        try mutate(incarnation) { $0.snooze = nil }
    }

    @discardableResult
    public mutating func reconcile(now: Date = Date()) throws -> Bool {
        let normalized = try Self.normalized(records, now: now)
        guard normalized != records else { return false }
        records = normalized
        try advanceRevision()
        return true
    }

    public mutating func recordLoadNormalization() throws {
        try advanceRevision()
    }

    @discardableResult
    public mutating func remove(_ incarnation: BessiePaneIncarnation) throws -> Bool {
        guard let index = records.firstIndex(where: { $0.incarnation == incarnation }) else { return false }
        records.remove(at: index)
        try advanceRevision()
        return true
    }

    @discardableResult
    public mutating func reconcileFullSnapshot(
        connectionID: String,
        incarnations: Set<BessiePaneIncarnation>
    ) throws -> Bool {
        let retained = records.filter { $0.connectionID != connectionID || incarnations.contains($0.incarnation) }
        guard retained != records else { return false }
        records = retained
        try advanceRevision()
        return true
    }

    private mutating func mutate(
        _ incarnation: BessiePaneIncarnation,
        body: (inout BessiePanePresentationPreference) -> Void
    ) throws -> Bool {
        try Self.validate(incarnation)
        let index = records.firstIndex { $0.incarnation == incarnation }
        var record = index.map { records[$0] } ?? BessiePanePresentationPreference(
            connectionID: incarnation.connectionID,
            paneID: incarnation.paneID,
            terminalID: incarnation.terminalID
        )
        let previous = record
        body(&record)
        guard record != previous else { return false }
        if record.pinned || record.snooze != nil {
            if let index { records[index] = record } else {
                guard records.count < Self.maximumRecords else { throw BessiePanePresentationError.tooManyRecords }
                records.append(record)
            }
        } else if let index {
            records.remove(at: index)
        }
        records.sort(by: Self.precedes)
        try advanceRevision()
        return true
    }

    private mutating func advanceRevision() throws {
        guard revision < UInt64.max else { throw BessiePanePresentationError.revisionOverflow }
        revision += 1
    }

    private static func normalized(
        _ records: [BessiePanePresentationPreference],
        now: Date
    ) throws -> [BessiePanePresentationPreference] {
        var byIncarnation: [BessiePaneIncarnation: BessiePanePresentationPreference] = [:]
        for var record in records {
            try validate(record.incarnation)
            if let snooze = record.snooze, !snooze.isActive(at: now) { record.snooze = nil }
            if record.pinned || record.snooze != nil { byIncarnation[record.incarnation] = record }
            else { byIncarnation.removeValue(forKey: record.incarnation) }
        }
        return byIncarnation.values.sorted(by: precedes)
    }

    private static func validate(_ incarnation: BessiePaneIncarnation) throws {
        let identifiers = [incarnation.connectionID, incarnation.paneID, incarnation.terminalID]
        guard identifiers.allSatisfy({ !$0.isEmpty }) else { throw BessiePanePresentationError.invalidIdentifier }
        guard identifiers.allSatisfy({ $0.utf8.count <= maximumIdentifierBytes }) else {
            throw BessiePanePresentationError.identifierTooLong
        }
    }

    private static func precedes(
        _ lhs: BessiePanePresentationPreference,
        _ rhs: BessiePanePresentationPreference
    ) -> Bool {
        if lhs.connectionID != rhs.connectionID { return lhs.connectionID < rhs.connectionID }
        if lhs.paneID != rhs.paneID { return lhs.paneID < rhs.paneID }
        return lhs.terminalID < rhs.terminalID
    }
}

public struct BessiePaneSnoozeSchedule: Equatable, Sendable {
    public let nextDeadline: Date?
    public let needsWatchdog: Bool

    public init(records: [BessiePanePresentationPreference], now: Date = Date()) {
        let deadlines = records.compactMap { record -> Date? in
            guard case .until(let deadline, _) = record.snooze, deadline > now else { return nil }
            return deadline
        }
        nextDeadline = deadlines.min()
        needsWatchdog = !deadlines.isEmpty
    }
}
