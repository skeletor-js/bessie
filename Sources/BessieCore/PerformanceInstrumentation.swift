import Foundation

/// Payload-free timing points. Callers may attach only an opaque numeric sequence ID.
public enum BessiePerformanceMilestone: String, CaseIterable, Codable, Sendable {
    case processStart = "process_start"
    case appStart = "app_start"
    case firstWindowContent = "first_window_content"
    case startupMainThreadProbeScheduled = "startup_main_thread_probe_scheduled"
    case startupMainThreadProbeCompleted = "startup_main_thread_probe_completed"
    case runtimeValidation = "runtime_validation"
    case connectionStart = "connection_start"
    case remoteBridgeStart = "remote_bridge_start"
    case remoteTunnelReady = "remote_tunnel_ready"
    case snapshotInstalled = "snapshot_installed"
    case shellReady = "shell_ready"
    case terminalControllerReady = "terminal_controller_ready"
    case firstCompleteFrame = "first_complete_frame"
    case terminalInputReceived = "terminal_input_received"
    case terminalInputEnqueued = "terminal_input_enqueued"
    case terminalWriteCompleted = "terminal_write_completed"
    case terminalFrameReceived = "terminal_frame_received"
    case terminalFrameFed = "terminal_frame_fed"
    case terminalFrameRendered = "terminal_frame_rendered"
    case terminalSwitchRequested = "terminal_switch_requested"
    case terminalSwitchSurfaceAttached = "terminal_switch_surface_attached"
    case terminalResizeRequested = "terminal_resize_requested"
    case terminalResizeConverged = "terminal_resize_converged"
    case terminalContinuousInputStarted = "terminal_continuous_input_started"
    case terminalContinuousInputVisible = "terminal_continuous_input_visible"
    case terminalContinuousOutputStarted = "terminal_continuous_output_started"
    case terminalContinuousOutputVisible = "terminal_continuous_output_visible"
    case terminalOutputMegabyteStarted = "terminal_output_megabyte_started"
    case terminalOutputMegabyteVisible = "terminal_output_megabyte_visible"
    case terminalOutputLinesStarted = "terminal_output_lines_started"
    case terminalOutputLinesVisible = "terminal_output_lines_visible"
}

public enum BessiePerformanceEvidenceKind: String, Codable, Sendable {
    case deterministicSimulation = "deterministic_simulation"
    case packagedLocalMeasurement = "packaged_local_measurement"
    case packagedRemoteMeasurement = "packaged_remote_measurement"
    case unavailable
}

public enum BessieBudgetVerdict: String, Codable, Sendable {
    case passed
    case failed
    case unavailable
    case notEvaluated = "not_evaluated"
}

public enum BessieStartupScenario: String, Sendable {
    case warm
    case cold
    case unavailable
}

public struct BessiePerformanceMark: Codable, Equatable, Sendable {
    public let milestone: BessiePerformanceMilestone
    public let sequence: UInt64?
    public let elapsedMilliseconds: Double

    enum CodingKeys: String, CodingKey {
        case milestone
        case sequence
        case elapsedMilliseconds = "elapsed_ms"
    }
}

public struct BessiePerformanceSpan: Codable, Equatable, Sendable {
    public let startMilestone: BessiePerformanceMilestone
    public let endMilestone: BessiePerformanceMilestone
    public let sequence: UInt64?
    public let durationMilliseconds: Double?
    public let budgetVerdict: BessieBudgetVerdict

    enum CodingKeys: String, CodingKey {
        case startMilestone = "start_milestone"
        case endMilestone = "end_milestone"
        case sequence
        case durationMilliseconds = "duration_ms"
        case budgetVerdict = "budget_verdict"
    }
}

public struct BessiePerformanceBudgetResult: Codable, Equatable, Sendable {
    public let metric: String
    public let observedMilliseconds: Double?
    public let budgetVerdict: BessieBudgetVerdict

    enum CodingKeys: String, CodingKey {
        case metric
        case observedMilliseconds = "observed_ms"
        case budgetVerdict = "budget_verdict"
    }
}

public struct BessiePerformanceEvidence: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let evidenceKind: BessiePerformanceEvidenceKind
    public let milestones: [BessiePerformanceMark]
    public let spans: [BessiePerformanceSpan]
    public let budgets: [BessiePerformanceBudgetResult]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case evidenceKind = "evidence_kind"
        case milestones
        case spans
        case budgets
    }
}

public final class BessiePerformanceRecorder: @unchecked Sendable {
    public typealias Clock = @Sendable () -> TimeInterval

    private struct Key: Hashable {
        let milestone: BessiePerformanceMilestone
        let sequence: UInt64?
    }

    private struct StoredMark {
        let key: Key
        let timestamp: TimeInterval
    }

    private struct SpanKey: Hashable {
        let start: BessiePerformanceMilestone
        let end: BessiePerformanceMilestone
        let sequence: UInt64?
    }

    private let lock = NSLock()
    private let now: Clock
    private let maximumRetainedSequences: Int
    private let evidenceKind: BessiePerformanceEvidenceKind
    private let startupScenario: BessieStartupScenario
    private let exportURL: URL?
    private let exportsAfterEveryMark: Bool
    private let exportQueue = DispatchQueue(label: "bessie.performance.evidence")
    private let exportStateLock = NSLock()
    private var exportDirty = false
    private var exportScheduled = false
    private var marks: [Key: TimeInterval] = [:]
    private var orderedMarks: [StoredMark] = []
    private var unavailableSpans: Set<SpanKey> = []
    private var retainedSequenceOrder: [UInt64] = []
    private var retainedSequences: Set<UInt64> = []
    private var sequenceCounter: UInt64 = 0

    public init(
        maximumRetainedSequences: Int = 2_048,
        evidenceKind: BessiePerformanceEvidenceKind = .deterministicSimulation,
        startupScenario: BessieStartupScenario = .unavailable,
        exportURL: URL? = nil,
        exportsAfterEveryMark: Bool = true,
        now: @escaping Clock = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.maximumRetainedSequences = max(1, maximumRetainedSequences)
        self.evidenceKind = evidenceKind
        self.startupScenario = startupScenario
        self.exportURL = exportURL
        self.exportsAfterEveryMark = exportsAfterEveryMark
        self.now = now
    }

    /// The production app uses this factory so disk output is impossible without the dedicated path variable.
    public static func configured(environment: [String: String] = ProcessInfo.processInfo.environment) -> BessiePerformanceRecorder {
        let path = environment["BESSIE_PERFORMANCE_EVIDENCE_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let exportURL = path.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        let kind = BessiePerformanceEvidenceKind(rawValue: environment["BESSIE_PERFORMANCE_EVIDENCE_KIND"] ?? "")
            ?? (exportURL == nil ? .unavailable : .packagedLocalMeasurement)
        let scenario = BessieStartupScenario(rawValue: environment["BESSIE_PERFORMANCE_STARTUP_SCENARIO"] ?? "")
            ?? .unavailable
        let isTerminalProbe = environment["BESSIE_TERMINAL_PERFORMANCE_PROBE"] == "1"
        return BessiePerformanceRecorder(
            maximumRetainedSequences: isTerminalProbe ? 32_768 : 2_048,
            evidenceKind: kind,
            startupScenario: scenario,
            exportURL: exportURL,
            // The terminal benchmark explicitly flushes after collecting all samples.
            exportsAfterEveryMark: !isTerminalProbe
        )
    }

    public func nextSequence() -> UInt64 {
        lock.withLock {
            sequenceCounter &+= 1
            if sequenceCounter == 0 { sequenceCounter = 1 }
            return sequenceCounter
        }
    }

    public func mark(_ milestone: BessiePerformanceMilestone, sequence: UInt64? = nil) {
        record(milestone, sequence: sequence, timestamp: now())
    }

    /// Anchors launch evidence at the OS-reported process launch time instead of
    /// the later first Swift access to the recorder.
    public func markProcessStart(atSystemUptime timestamp: TimeInterval) {
        guard timestamp.isFinite, timestamp >= 0 else { return }
        record(.processStart, sequence: nil, timestamp: timestamp)
    }

    private func record(
        _ milestone: BessiePerformanceMilestone,
        sequence: UInt64?,
        timestamp: TimeInterval
    ) {
        let recorded = lock.withLock { () -> Bool in
            retain(sequence)
            let key = Key(milestone: milestone, sequence: sequence)
            guard marks[key] == nil else { return false }
            marks[key] = timestamp
            orderedMarks.append(StoredMark(key: key, timestamp: timestamp))
            return true
        }
        if recorded { scheduleExportIfNeeded() }
    }

    public func markUnavailable(
        from start: BessiePerformanceMilestone,
        to end: BessiePerformanceMilestone,
        sequence: UInt64? = nil
    ) {
        let inserted = lock.withLock { () -> Bool in
            retain(sequence)
            return unavailableSpans.insert(SpanKey(start: start, end: end, sequence: sequence)).inserted
        }
        if inserted { scheduleExportIfNeeded() }
    }

    /// Returns milliseconds, or NaN when either timing point has not been recorded.
    public func duration(
        from start: BessiePerformanceMilestone,
        to end: BessiePerformanceMilestone,
        sequence: UInt64? = nil
    ) -> Double {
        lock.withLock {
            durationLocked(from: start, to: end, sequence: sequence) ?? .nan
        }
    }

    public func evidence() -> BessiePerformanceEvidence {
        lock.withLock { evidenceLocked() }
    }

    /// Test/evidence harnesses can force a final atomic snapshot before reading the opt-in path.
    public func flushEvidence() throws {
        guard exportURL != nil else { return }
        let document = evidence()
        try exportQueue.sync { try persist(document) }
    }

    private func retain(_ sequence: UInt64?) {
        guard let sequence, retainedSequences.insert(sequence).inserted else { return }
        retainedSequenceOrder.append(sequence)
        guard retainedSequenceOrder.count > maximumRetainedSequences else { return }
        let expired = retainedSequenceOrder.removeFirst()
        retainedSequences.remove(expired)
        marks = marks.filter { $0.key.sequence != expired }
        orderedMarks.removeAll { $0.key.sequence == expired }
        unavailableSpans = Set(unavailableSpans.filter { $0.sequence != expired })
    }

    private func durationLocked(
        from start: BessiePerformanceMilestone,
        to end: BessiePerformanceMilestone,
        sequence: UInt64?
    ) -> Double? {
        guard let startTime = marks[Key(milestone: start, sequence: sequence)],
              let endTime = marks[Key(milestone: end, sequence: sequence)],
              endTime >= startTime
        else { return nil }
        return (endTime - startTime) * 1_000
    }

    private func evidenceLocked() -> BessiePerformanceEvidence {
        let baseline = marks[Key(milestone: .processStart, sequence: nil)] ?? orderedMarks.first?.timestamp ?? 0
        let exportedMarks = orderedMarks.map {
            BessiePerformanceMark(
                milestone: $0.key.milestone,
                sequence: $0.key.sequence,
                elapsedMilliseconds: max(0, ($0.timestamp - baseline) * 1_000)
            )
        }
        let spans = measuredSpansLocked() + unavailableSpans
            .sorted(by: Self.sortSpans)
            .map {
                BessiePerformanceSpan(
                    startMilestone: $0.start,
                    endMilestone: $0.end,
                    sequence: $0.sequence,
                    durationMilliseconds: nil,
                    budgetVerdict: .unavailable
                )
            }
        return BessiePerformanceEvidence(
            schemaVersion: 1,
            evidenceKind: evidenceKind,
            milestones: exportedMarks,
            spans: spans,
            budgets: budgetResultsLocked()
        )
    }

    private func measuredSpansLocked() -> [BessiePerformanceSpan] {
        let definitions: [(BessiePerformanceMilestone, BessiePerformanceMilestone)] = [
            (.processStart, .appStart),
            (.processStart, .firstWindowContent),
            (.startupMainThreadProbeScheduled, .startupMainThreadProbeCompleted),
            (.connectionStart, .runtimeValidation),
            (.connectionStart, .snapshotInstalled),
            (.connectionStart, .shellReady),
            (.terminalControllerReady, .firstCompleteFrame),
            (.terminalInputReceived, .terminalInputEnqueued),
            (.terminalInputReceived, .terminalWriteCompleted),
            (.terminalFrameReceived, .terminalFrameFed),
            (.terminalSwitchRequested, .terminalSwitchSurfaceAttached),
            (.terminalResizeRequested, .terminalResizeConverged),
            (.terminalContinuousInputStarted, .terminalContinuousInputVisible),
            (.terminalContinuousOutputStarted, .terminalContinuousOutputVisible),
            (.terminalInputReceived, .terminalFrameRendered),
            (.terminalOutputMegabyteStarted, .terminalOutputMegabyteVisible),
            (.terminalOutputLinesStarted, .terminalOutputLinesVisible),
        ]
        var results: [BessiePerformanceSpan] = []
        for (start, end) in definitions {
            let sequences = Set(marks.keys.filter { $0.milestone == start }.map(\.sequence))
            for sequence in sequences.sorted(by: Self.sortSequences) {
                guard let duration = durationLocked(from: start, to: end, sequence: sequence) else { continue }
                results.append(BessiePerformanceSpan(
                    startMilestone: start,
                    endMilestone: end,
                    sequence: sequence,
                    durationMilliseconds: duration,
                    // Percentile budgets are evaluated only after the minimum sample count.
                    budgetVerdict: .notEvaluated
                ))
            }
        }
        return results
    }

    private func budgetResultsLocked() -> [BessiePerformanceBudgetResult] {
        BessieReleaseBudget.all.map { budget in
            let observed: Double?
            switch budget.metric {
            case BessieReleaseBudget.firstWindowContentP95.metric:
                observed = percentileLocked(from: .processStart, to: .firstWindowContent, percentile: 0.95)
            case BessieReleaseBudget.warmShellReadyP95.metric where startupScenario == .warm:
                observed = percentileLocked(from: .connectionStart, to: .shellReady, percentile: 0.95)
            case BessieReleaseBudget.coldShellReadyP95.metric where startupScenario == .cold:
                observed = percentileLocked(from: .connectionStart, to: .shellReady, percentile: 0.95)
            case BessieReleaseBudget.frameReceiveToFeedP95.metric:
                observed = percentileLocked(from: .terminalFrameReceived, to: .terminalFrameFed, percentile: 0.95)
            case BessieReleaseBudget.printableEchoP50.metric:
                observed = percentileLocked(from: .terminalInputReceived, to: .terminalFrameRendered, percentile: 0.50)
            case BessieReleaseBudget.printableEchoP95.metric:
                observed = percentileLocked(from: .terminalInputReceived, to: .terminalFrameRendered, percentile: 0.95)
            case BessieReleaseBudget.printableEchoP99.metric:
                observed = percentileLocked(from: .terminalInputReceived, to: .terminalFrameRendered, percentile: 0.99)
            case BessieReleaseBudget.startupMainThreadStallMaximum.metric:
                observed = maximumLocked(
                    from: .startupMainThreadProbeScheduled,
                    to: .startupMainThreadProbeCompleted
                )
            case BessieReleaseBudget.resizeConvergenceMaximum.metric:
                observed = maximumLocked(from: .terminalResizeRequested, to: .terminalResizeConverged)
            default:
                observed = nil
            }
            return BessiePerformanceBudgetResult(
                metric: budget.metric,
                observedMilliseconds: observed,
                budgetVerdict: observed.map { $0 <= budget.maximumMilliseconds ? .passed : .failed } ?? .unavailable
            )
        }
    }

    private func percentileLocked(
        from start: BessiePerformanceMilestone,
        to end: BessiePerformanceMilestone,
        percentile: Double,
        minimumSampleCount: Int = 20
    ) -> Double? {
        let samples = marks.keys
            .filter { $0.milestone == start }
            .compactMap { durationLocked(from: start, to: end, sequence: $0.sequence) }
            .sorted()
        guard samples.count >= minimumSampleCount else { return nil }
        let rank = max(1, Int(ceil(percentile * Double(samples.count))))
        return samples[rank - 1]
    }

    private func maximumLocked(
        from start: BessiePerformanceMilestone,
        to end: BessiePerformanceMilestone,
        minimumSampleCount: Int = 1
    ) -> Double? {
        let samples = marks.keys
            .filter { $0.milestone == start }
            .compactMap { durationLocked(from: start, to: end, sequence: $0.sequence) }
        guard samples.count >= minimumSampleCount else { return nil }
        return samples.max()
    }

    private func scheduleExportIfNeeded() {
        guard exportURL != nil, exportsAfterEveryMark else { return }
        let shouldSchedule = exportStateLock.withLock { () -> Bool in
            exportDirty = true
            guard !exportScheduled else { return false }
            exportScheduled = true
            return true
        }
        guard shouldSchedule else { return }
        exportQueue.async { [weak self] in self?.drainExports() }
    }

    private func drainExports() {
        while true {
            let shouldExport = exportStateLock.withLock { () -> Bool in
                guard exportDirty else {
                    exportScheduled = false
                    return false
                }
                exportDirty = false
                return true
            }
            guard shouldExport else { return }
            try? persist(evidence())
        }
    }

    private func persist(_ document: BessiePerformanceEvidence) throws {
        guard let exportURL else { return }
        try FileManager.default.createDirectory(
            at: exportURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: exportURL, options: .atomic)
    }

    private static func sortSequences(_ lhs: UInt64?, _ rhs: UInt64?) -> Bool {
        switch (lhs, rhs) {
        case (nil, .some): true
        case (.some, nil): false
        case (.some(let lhs), .some(let rhs)): lhs < rhs
        case (nil, nil): false
        }
    }

    private static func sortSpans(_ lhs: SpanKey, _ rhs: SpanKey) -> Bool {
        if lhs.start.rawValue != rhs.start.rawValue { return lhs.start.rawValue < rhs.start.rawValue }
        if lhs.end.rawValue != rhs.end.rawValue { return lhs.end.rawValue < rhs.end.rawValue }
        return sortSequences(lhs.sequence, rhs.sequence)
    }
}

public struct BessiePerformanceSummary: Codable, Equatable, Sendable {
    public let count: Int
    public let p50Milliseconds: Double?
    public let p95Milliseconds: Double?
    public let p99Milliseconds: Double?

    public init(samplesMilliseconds: [Double]) {
        let sorted = samplesMilliseconds.filter { $0.isFinite && $0 >= 0 }.sorted()
        count = sorted.count
        p50Milliseconds = Self.percentile(0.50, sorted: sorted)
        p95Milliseconds = Self.percentile(0.95, sorted: sorted)
        p99Milliseconds = Self.percentile(0.99, sorted: sorted)
    }

    private static func percentile(_ percentile: Double, sorted: [Double]) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let rank = max(1, Int(ceil(percentile * Double(sorted.count))))
        return sorted[rank - 1]
    }
}

public struct BessieReleaseBudget: Codable, Equatable, Sendable {
    public let metric: String
    public let maximumMilliseconds: Double

    private init(_ metric: String, _ maximumMilliseconds: Double) {
        self.metric = metric
        self.maximumMilliseconds = maximumMilliseconds
    }

    public static let firstWindowContentP95 = Self("first_window_content_p95", 750)
    public static let warmShellReadyP95 = Self("warm_shell_ready_p95", 1_500)
    public static let coldShellReadyP95 = Self("cold_shell_ready_p95", 3_000)
    public static let printableEchoP50 = Self("printable_key_to_visible_echo_p50", 25)
    public static let printableEchoP95 = Self("printable_key_to_visible_echo_p95", 50)
    public static let printableEchoP99 = Self("printable_key_to_visible_echo_p99", 100)
    public static let frameReceiveToFeedP95 = Self("frame_receive_to_libghostty_feed_p95", 8)
    public static let startupMainThreadStallMaximum = Self("startup_main_thread_stall_max", 100)
    public static let resizeConvergenceMaximum = Self("resize_convergence_max", 250)

    public static let all: [Self] = [
        .firstWindowContentP95, .warmShellReadyP95, .coldShellReadyP95,
        .printableEchoP50, .printableEchoP95, .printableEchoP99,
        .frameReceiveToFeedP95, .startupMainThreadStallMaximum, .resizeConvergenceMaximum,
    ]
}

public struct BessieBudgetEvaluation: Codable, Equatable, Sendable {
    public let budget: BessieReleaseBudget
    public let observedMilliseconds: Double
    public let evidenceKind: BessiePerformanceEvidenceKind

    public init(
        budget: BessieReleaseBudget,
        observedMilliseconds: Double,
        evidenceKind: BessiePerformanceEvidenceKind
    ) {
        self.budget = budget
        self.observedMilliseconds = observedMilliseconds
        self.evidenceKind = evidenceKind
    }

    public var passed: Bool {
        observedMilliseconds.isFinite && observedMilliseconds >= 0
            && observedMilliseconds <= budget.maximumMilliseconds
    }
}
