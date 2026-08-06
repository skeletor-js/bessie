import Foundation
import XCTest
@testable import BessieCore

final class PerformanceInstrumentationTests: XCTestCase {
    func testRecorderPreservesLifecycleOrderingAndSequenceCorrelation() {
        let clock = SteppingClock(values: [0, 0.020, 0.050, 0.055, 0.060])
        let recorder = BessiePerformanceRecorder(now: clock.now)

        recorder.mark(.processStart)
        recorder.mark(.firstWindowContent)
        recorder.mark(.terminalInputReceived, sequence: 42)
        recorder.mark(.terminalInputEnqueued, sequence: 42)
        recorder.mark(.terminalWriteCompleted, sequence: 42)

        XCTAssertEqual(recorder.duration(from: .processStart, to: .firstWindowContent), 20, accuracy: 0.001)
        XCTAssertEqual(
            recorder.duration(from: .terminalInputReceived, to: .terminalWriteCompleted, sequence: 42),
            10,
            accuracy: 0.001
        )
        XCTAssertEqual(
            recorder.evidence().milestones.map(\.milestone),
            [.processStart, .firstWindowContent, .terminalInputReceived, .terminalInputEnqueued, .terminalWriteCompleted]
        )
        XCTAssertEqual(Set(BessiePerformanceMilestone.allCases.map(\.rawValue)), Set([
            "process_start", "app_start", "first_window_content", "startup_main_thread_probe_scheduled",
            "startup_main_thread_probe_completed", "runtime_validation", "connection_start", "remote_bridge_start",
            "remote_tunnel_ready", "snapshot_installed",
            "shell_ready", "terminal_controller_ready", "first_complete_frame", "terminal_input_received",
            "terminal_input_enqueued", "terminal_write_completed", "terminal_frame_received",
            "terminal_frame_fed", "terminal_frame_rendered", "terminal_switch_requested",
            "terminal_switch_surface_attached", "terminal_resize_requested", "terminal_resize_converged",
            "terminal_continuous_input_started", "terminal_continuous_input_visible", "terminal_output_megabyte_started",
            "terminal_continuous_output_started", "terminal_continuous_output_visible",
            "terminal_output_megabyte_visible", "terminal_output_lines_started", "terminal_output_lines_visible",
        ]))
    }

    func testProcessStartCanBeAnchoredBeforeRecorderInitialization() {
        let recorder = BessiePerformanceRecorder(now: SteppingClock(values: [10]).now)

        recorder.markProcessStart(atSystemUptime: 9.25)
        recorder.mark(.firstWindowContent)

        XCTAssertEqual(
            recorder.duration(from: .processStart, to: .firstWindowContent),
            750,
            accuracy: 0.001
        )
    }

    func testAggregationUsesDeterministicNearestRankPercentiles() {
        let summary = BessiePerformanceSummary(samplesMilliseconds: [50, 10, 40, 20, 30])

        XCTAssertEqual(summary.count, 5)
        XCTAssertEqual(summary.p50Milliseconds, 30)
        XCTAssertEqual(summary.p95Milliseconds, 50)
        XCTAssertEqual(summary.p99Milliseconds, 50)
    }

    func testPaneSwitchTimingIsPayloadFreeAndSequenceCorrelated() throws {
        let recorder = BessiePerformanceRecorder(now: SteppingClock(values: [1, 1.012]).now)
        recorder.mark(.terminalSwitchRequested, sequence: 7)
        recorder.mark(.terminalSwitchSurfaceAttached, sequence: 7)

        let span = recorder.evidence().spans.first {
            $0.startMilestone == .terminalSwitchRequested
                && $0.endMilestone == .terminalSwitchSurfaceAttached
                && $0.sequence == 7
        }
        XCTAssertEqual(try XCTUnwrap(span?.durationMilliseconds), 12, accuracy: 0.001)
        XCTAssertEqual(span?.budgetVerdict, .notEvaluated)
    }

    func testReleaseBudgetsMatchTheApprovedHardeningPlan() {
        XCTAssertEqual(BessieReleaseBudget.firstWindowContentP95.maximumMilliseconds, 750)
        XCTAssertEqual(BessieReleaseBudget.warmShellReadyP95.maximumMilliseconds, 1_500)
        XCTAssertEqual(BessieReleaseBudget.coldShellReadyP95.maximumMilliseconds, 3_000)
        XCTAssertEqual(BessieReleaseBudget.printableEchoP50.maximumMilliseconds, 25)
        XCTAssertEqual(BessieReleaseBudget.printableEchoP95.maximumMilliseconds, 50)
        XCTAssertEqual(BessieReleaseBudget.printableEchoP99.maximumMilliseconds, 100)
        XCTAssertEqual(BessieReleaseBudget.frameReceiveToFeedP95.maximumMilliseconds, 8)
        XCTAssertEqual(BessieReleaseBudget.startupMainThreadStallMaximum.maximumMilliseconds, 100)
        XCTAssertEqual(BessieReleaseBudget.resizeConvergenceMaximum.maximumMilliseconds, 250)
    }

    func testMaximumBudgetsUseMeasuredMainThreadAndResizeSpans() throws {
        let recorder = BessiePerformanceRecorder(
            now: SteppingClock(values: [0, 0.080, 1, 1.220]).now
        )
        recorder.mark(.startupMainThreadProbeScheduled, sequence: 1)
        recorder.mark(.startupMainThreadProbeCompleted, sequence: 1)
        recorder.mark(.terminalResizeRequested, sequence: 2)
        recorder.mark(.terminalResizeConverged, sequence: 2)

        let budgets = Dictionary(uniqueKeysWithValues: recorder.evidence().budgets.map { ($0.metric, $0) })
        XCTAssertEqual(
            try XCTUnwrap(budgets[BessieReleaseBudget.startupMainThreadStallMaximum.metric]?.observedMilliseconds),
            80,
            accuracy: 0.001
        )
        XCTAssertEqual(
            budgets[BessieReleaseBudget.startupMainThreadStallMaximum.metric]?.budgetVerdict,
            .passed
        )
        XCTAssertEqual(
            try XCTUnwrap(budgets[BessieReleaseBudget.resizeConvergenceMaximum.metric]?.observedMilliseconds),
            220,
            accuracy: 0.001
        )
        XCTAssertEqual(
            budgets[BessieReleaseBudget.resizeConvergenceMaximum.metric]?.budgetVerdict,
            .passed
        )
    }

    func testEvaluationFailsAnyExceededBudgetAndRetainsMetricIdentity() {
        let passing = BessieBudgetEvaluation(
            budget: .printableEchoP95,
            observedMilliseconds: 49.9,
            evidenceKind: .deterministicSimulation
        )
        let failing = BessieBudgetEvaluation(
            budget: .printableEchoP95,
            observedMilliseconds: 50.1,
            evidenceKind: .packagedLocalMeasurement
        )

        XCTAssertTrue(passing.passed)
        XCTAssertFalse(failing.passed)
        XCTAssertEqual(failing.budget.metric, "printable_key_to_visible_echo_p95")
        XCTAssertEqual(failing.evidenceKind.rawValue, "packaged_local_measurement")
    }

    func testRecorderBoundsSequenceHistoryWithoutDiscardingCurrentSequence() {
        let clock = SteppingClock(values: [0, 0.001, 0.002, 0.003, 0.004, 0.005])
        let recorder = BessiePerformanceRecorder(maximumRetainedSequences: 2, now: clock.now)

        recorder.mark(.terminalInputReceived, sequence: 1)
        recorder.mark(.terminalWriteCompleted, sequence: 1)
        recorder.mark(.terminalInputReceived, sequence: 2)
        recorder.mark(.terminalWriteCompleted, sequence: 2)
        recorder.mark(.terminalInputReceived, sequence: 3)
        recorder.mark(.terminalWriteCompleted, sequence: 3)

        XCTAssertTrue(recorder.duration(from: .terminalInputReceived, to: .terminalWriteCompleted, sequence: 1).isNaN)
        XCTAssertEqual(recorder.duration(from: .terminalInputReceived, to: .terminalWriteCompleted, sequence: 2), 1, accuracy: 0.001)
        XCTAssertEqual(recorder.duration(from: .terminalInputReceived, to: .terminalWriteCompleted, sequence: 3), 1, accuracy: 0.001)
        XCTAssertEqual(Set(recorder.evidence().milestones.compactMap(\.sequence)), [2, 3])
    }

    func testTerminalProbeRetainsLongRunningFrameAndInputEvidence() {
        let recorder = BessiePerformanceRecorder.configured(environment: [
            "BESSIE_TERMINAL_PERFORMANCE_PROBE": "1",
        ])

        for sequence in 1...2_100 {
            recorder.mark(.terminalFrameReceived, sequence: UInt64(sequence))
        }

        XCTAssertTrue(recorder.evidence().milestones.contains { $0.sequence == 1 })
    }

    func testRenderedSpanRemainsTruthfullyUnavailable() {
        let recorder = BessiePerformanceRecorder(now: SteppingClock(values: [0]).now)
        recorder.mark(.terminalInputReceived, sequence: 9)
        recorder.markUnavailable(from: .terminalInputReceived, to: .terminalFrameRendered, sequence: 9)

        let span = recorder.evidence().spans.first
        XCTAssertEqual(span?.startMilestone, .terminalInputReceived)
        XCTAssertEqual(span?.endMilestone, .terminalFrameRendered)
        XCTAssertEqual(span?.sequence, 9)
        XCTAssertNil(span?.durationMilliseconds)
        XCTAssertEqual(span?.budgetVerdict, .unavailable)
        XCTAssertTrue(recorder.duration(from: .terminalInputReceived, to: .terminalFrameRendered, sequence: 9).isNaN)
    }

    func testExportSchemaIsPayloadFreeAndRedactsByConstruction() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bessie-performance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("evidence.json")
        let recorder = BessiePerformanceRecorder(
            evidenceKind: .packagedLocalMeasurement,
            exportURL: output,
            now: SteppingClock(values: [1, 1.004]).now
        )

        recorder.mark(.terminalFrameReceived, sequence: 17)
        recorder.mark(.terminalFrameFed, sequence: 17)
        try recorder.flushEvidence()

        let data = try Data(contentsOf: output)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schema_version", "evidence_kind", "milestones", "spans", "budgets"])
        let text = String(decoding: data, as: UTF8.self)
        for forbidden in ["terminal_content", "command", "cwd", "hostname", "username", "socket", "config", "environment", "secret"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(forbidden), forbidden)
        }
        XCTAssertTrue(text.contains("packaged_local_measurement"))
        XCTAssertTrue(text.contains("terminal_frame_received"))
        XCTAssertTrue(text.contains("terminal_frame_fed"))
    }

    func testExplicitFlushAvoidsExportWorkInsideMeasuredMarks() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bessie-performance-flush-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("evidence.json")
        let recorder = BessiePerformanceRecorder(
            evidenceKind: .packagedLocalMeasurement,
            exportURL: output,
            exportsAfterEveryMark: false,
            now: SteppingClock(values: [1, 1.004]).now
        )

        recorder.mark(.terminalFrameReceived, sequence: 17)
        recorder.mark(.terminalFrameFed, sequence: 17)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))

        try recorder.flushEvidence()

        let evidence = try JSONDecoder().decode(
            BessiePerformanceEvidence.self,
            from: Data(contentsOf: output)
        )
        XCTAssertEqual(evidence.milestones.map(\.milestone), [.terminalFrameReceived, .terminalFrameFed])
    }

    func testBudgetAggregationSeparatesPassFailAndUnavailableEvidence() {
        let clockValues = (0..<20).flatMap { index -> [TimeInterval] in
            let start = Double(index)
            return [start, start + (index >= 18 ? 0.009 : 0.007)]
        }
        let recorder = BessiePerformanceRecorder(now: SteppingClock(values: clockValues).now)
        for sequence in 1...20 {
            recorder.mark(.terminalFrameReceived, sequence: UInt64(sequence))
            recorder.mark(.terminalFrameFed, sequence: UInt64(sequence))
        }

        let budgets = Dictionary(uniqueKeysWithValues: recorder.evidence().budgets.map { ($0.metric, $0) })
        XCTAssertEqual(budgets[BessieReleaseBudget.frameReceiveToFeedP95.metric]?.budgetVerdict, .failed)
        guard let observed = budgets[BessieReleaseBudget.frameReceiveToFeedP95.metric]?.observedMilliseconds else {
            return XCTFail("Expected a frame receive-to-feed aggregate")
        }
        XCTAssertEqual(observed, 9, accuracy: 0.001)
        XCTAssertEqual(budgets[BessieReleaseBudget.printableEchoP95.metric]?.budgetVerdict, .unavailable)
        XCTAssertNil(budgets[BessieReleaseBudget.printableEchoP95.metric]?.observedMilliseconds)
    }

    func testLiveEchoCorrelationEvaluatesAllPrintablePercentileBudgets() throws {
        var values: [TimeInterval] = []
        for index in 0..<20 {
            let start = Double(index)
            values.append(start)
            values.append(start + Double(index + 1) / 1_000)
        }
        let recorder = BessiePerformanceRecorder(now: SteppingClock(values: values).now)
        for sequence in 1...20 {
            recorder.mark(.terminalInputReceived, sequence: UInt64(sequence))
            recorder.mark(.terminalFrameRendered, sequence: UInt64(sequence))
        }

        let evidence = recorder.evidence()
        let budgets = Dictionary(uniqueKeysWithValues: evidence.budgets.map { ($0.metric, $0) })
        XCTAssertEqual(
            try XCTUnwrap(budgets[BessieReleaseBudget.printableEchoP50.metric]?.observedMilliseconds),
            10,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(budgets[BessieReleaseBudget.printableEchoP95.metric]?.observedMilliseconds),
            19,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(budgets[BessieReleaseBudget.printableEchoP99.metric]?.observedMilliseconds),
            20,
            accuracy: 0.001
        )
        XCTAssertEqual(
            evidence.spans.filter {
                $0.startMilestone == .terminalInputReceived && $0.endMilestone == .terminalFrameRendered
            }.count,
            20
        )
    }
}

private final class SteppingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [TimeInterval]

    init(values: [TimeInterval]) { self.values = values }

    func now() -> TimeInterval {
        lock.withLock { values.removeFirst() }
    }
}
