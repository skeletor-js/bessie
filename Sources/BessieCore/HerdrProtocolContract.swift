import Foundation

public struct HerdrWorkspaceCreationResult: Equatable, Sendable {
    public let workspaceID: String
    public let tabID: String
    public let rootPaneID: String

    public init(workspaceID: String, tabID: String, rootPaneID: String) {
        self.workspaceID = workspaceID
        self.tabID = tabID
        self.rootPaneID = rootPaneID
    }

    public init(result: JSONValue) throws {
        let payload: WorkspaceCreationPayload = try decodeResult(result, type: "workspace_created")
        workspaceID = try requiredID(payload.workspace.workspaceID, field: "workspace.workspace_id")
        tabID = try requiredID(payload.tab.tabID, field: "tab.tab_id")
        rootPaneID = try requiredID(payload.rootPane.paneID, field: "root_pane.pane_id")
    }
}

public struct HerdrTabCreationResult: Equatable, Sendable {
    public let tabID: String
    public let rootPaneID: String

    public init(tabID: String, rootPaneID: String) {
        self.tabID = tabID
        self.rootPaneID = rootPaneID
    }

    public init(result: JSONValue) throws {
        let payload: TabCreationPayload = try decodeResult(result, type: "tab_created")
        tabID = try requiredID(payload.tab.tabID, field: "tab.tab_id")
        rootPaneID = try requiredID(payload.rootPane.paneID, field: "root_pane.pane_id")
    }
}

public struct HerdrTabInfoResult: Equatable, Sendable {
    public let tabID: String

    public init(result: JSONValue) throws {
        let payload: TabInfoPayload = try decodeResult(result, type: "tab_info")
        tabID = try requiredID(payload.tab.tabID, field: "tab.tab_id")
    }
}

public struct HerdrPaneCreationResult: Equatable, Sendable {
    public let paneID: String

    public init(paneID: String) {
        self.paneID = paneID
    }

    public init(result: JSONValue) throws {
        let payload: PaneCreationPayload = try decodeResult(result, type: "pane_info")
        paneID = try requiredID(payload.pane.paneID, field: "pane.pane_id")
    }
}

public struct HerdrPaneContractFacts: Equatable, Sendable {
    public let paneID: String
    public let cwd: String?
    public let foregroundCWD: String?

    public init(value: JSONValue) throws {
        let payload: PaneFactsPayload
        do {
            payload = try value.decode()
        } catch {
            throw HerdrClientError.unexpectedResponse("invalid pane facts: \(error.localizedDescription)")
        }
        paneID = try requiredID(payload.paneID, field: "pane_id")
        cwd = payload.cwd
        foregroundCWD = payload.foregroundCWD
    }
}

public struct HerdrStartupCommandPolicy: Equatable, Sendable {
    public let pollInterval: TimeInterval
    public let readinessTimeout: TimeInterval
    public let echoTimeout: TimeInterval
    public let stableEchoReadCount: Int

    public init(
        pollInterval: TimeInterval = 0.05,
        readinessTimeout: TimeInterval = 5,
        echoTimeout: TimeInterval = 5,
        stableEchoReadCount: Int = 2
    ) {
        precondition(pollInterval > 0)
        precondition(readinessTimeout >= 0 && echoTimeout >= 0)
        precondition(stableEchoReadCount > 0)
        self.pollInterval = pollInterval
        self.readinessTimeout = readinessTimeout
        self.echoTimeout = echoTimeout
        self.stableEchoReadCount = stableEchoReadCount
    }
}

public enum HerdrStartupCommandFailure: Error, Equatable, Sendable {
    case invalidCommand
    case readinessTimedOut(paneID: String)
    case echoTimedOut(paneID: String)
    case cancelled(paneID: String)
}

public enum HerdrStartupCommandProgress: Equatable, Sendable {
    case readinessConfirmed
    case submittingText
    case textSubmitted
    case echoConfirmed
    case submittingEnter
    case enterSubmitted
}

public struct HerdrStartupCommandSubmitter: Sendable {
    private let api: any HerdrMutationAPI
    private let policy: HerdrStartupCommandPolicy
    private let now: @Sendable () -> Date
    private let wait: @Sendable (TimeInterval) -> Void
    private let isCancelled: @Sendable () -> Bool

    public init(
        api: any HerdrMutationAPI,
        policy: HerdrStartupCommandPolicy = HerdrStartupCommandPolicy(),
        now: @escaping @Sendable () -> Date = Date.init,
        wait: @escaping @Sendable (TimeInterval) -> Void = Thread.sleep(forTimeInterval:),
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) {
        self.api = api
        self.policy = policy
        self.now = now
        self.wait = wait
        self.isCancelled = isCancelled
    }

    public func submit(
        command: String,
        toPaneID paneID: String,
        onProgress: (HerdrStartupCommandProgress) -> Void = { _ in }
    ) throws {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !command.contains("\n"), !command.contains("\r") else {
            throw HerdrStartupCommandFailure.invalidCommand
        }

        let baseline = try waitForReadyPane(paneID: paneID)
        onProgress(.readinessConfirmed)
        try checkCancellation(paneID: paneID)
        onProgress(.submittingText)
        try sendInput(paneID: paneID, text: command, keys: [])
        onProgress(.textSubmitted)
        try waitForNewStableEcho(command, baseline: baseline, paneID: paneID)
        onProgress(.echoConfirmed)
        try checkCancellation(paneID: paneID)
        onProgress(.submittingEnter)
        try sendInput(paneID: paneID, text: "", keys: ["Enter"])
        onProgress(.enterSubmitted)
    }

    private func waitForReadyPane(paneID: String) throws -> String {
        let deadline = now().addingTimeInterval(policy.readinessTimeout)
        while true {
            try checkCancellation(paneID: paneID)
            let text = try readPane(paneID: paneID)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
            guard waitForNextPoll(until: deadline) else {
                throw HerdrStartupCommandFailure.readinessTimedOut(paneID: paneID)
            }
        }
    }

    private func waitForNewStableEcho(_ command: String, baseline: String, paneID: String) throws {
        let baselineCount = Self.echoCount(command, in: baseline)
        let deadline = now().addingTimeInterval(policy.echoTimeout)
        var consecutiveMatches = 0

        while true {
            try checkCancellation(paneID: paneID)
            let text = try readPane(paneID: paneID)
            if Self.echoCount(command, in: text) > baselineCount {
                consecutiveMatches += 1
                if consecutiveMatches >= policy.stableEchoReadCount { return }
            } else {
                consecutiveMatches = 0
            }
            guard waitForNextPoll(until: deadline) else {
                throw HerdrStartupCommandFailure.echoTimedOut(paneID: paneID)
            }
        }
    }

    private func readPane(paneID: String) throws -> String {
        let result = try api.request(method: "pane.read", params: [
            "pane_id": .string(paneID),
            "source": .string("visible"),
            "lines": .number(20),
            "format": .string("text"),
            "strip_ansi": .bool(true),
        ])
        let payload: PaneReadPayload = try decodeResult(result, type: "pane_read")
        guard payload.read.paneID == paneID else {
            throw HerdrClientError.unexpectedResponse(
                "pane.read returned \(payload.read.paneID) for \(paneID)"
            )
        }
        return payload.read.text
    }

    private func sendInput(paneID: String, text: String, keys: [String]) throws {
        let result = try api.request(method: "pane.send_input", params: [
            "pane_id": .string(paneID),
            "text": .string(text),
            "keys": .array(keys.map(JSONValue.string)),
        ])
        guard case .object(let object) = result, object["type"] == .string("ok") else {
            throw HerdrClientError.unexpectedResponse("expected ok from pane.send_input")
        }
    }

    private func waitForNextPoll(until deadline: Date) -> Bool {
        let remaining = deadline.timeIntervalSince(now())
        guard remaining > 0 else { return false }
        wait(min(policy.pollInterval, remaining))
        return true
    }

    private func checkCancellation(paneID: String) throws {
        if isCancelled() {
            throw HerdrStartupCommandFailure.cancelled(paneID: paneID)
        }
    }

    private static func echoCount(_ command: String, in text: String) -> Int {
        let rendered = text.filter { $0 != "\r" && $0 != "\n" }
        guard !command.isEmpty else { return 0 }
        var count = 0
        var searchStart = rendered.startIndex
        while searchStart < rendered.endIndex,
              let range = rendered.range(of: command, range: searchStart..<rendered.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }
}

private struct WorkspaceCreationPayload: Decodable {
    let workspace: WorkspaceIdentityPayload
    let tab: TabIdentityPayload
    let rootPane: PaneIdentityPayload

    enum CodingKeys: String, CodingKey {
        case workspace, tab
        case rootPane = "root_pane"
    }
}

private struct TabCreationPayload: Decodable {
    let tab: TabIdentityPayload
    let rootPane: PaneIdentityPayload

    enum CodingKeys: String, CodingKey {
        case tab
        case rootPane = "root_pane"
    }
}

private struct TabInfoPayload: Decodable {
    let tab: TabIdentityPayload
}

private struct PaneCreationPayload: Decodable {
    let pane: PaneIdentityPayload
}

private struct WorkspaceIdentityPayload: Decodable {
    let workspaceID: String
    enum CodingKeys: String, CodingKey { case workspaceID = "workspace_id" }
}

private struct TabIdentityPayload: Decodable {
    let tabID: String
    enum CodingKeys: String, CodingKey { case tabID = "tab_id" }
}

private struct PaneIdentityPayload: Decodable {
    let paneID: String
    enum CodingKeys: String, CodingKey { case paneID = "pane_id" }
}

private struct PaneFactsPayload: Decodable {
    let paneID: String
    let cwd: String?
    let foregroundCWD: String?

    enum CodingKeys: String, CodingKey {
        case paneID = "pane_id"
        case cwd
        case foregroundCWD = "foreground_cwd"
    }
}

private struct PaneReadPayload: Decodable {
    struct Read: Decodable {
        let paneID: String
        let text: String
        enum CodingKeys: String, CodingKey { case paneID = "pane_id", text }
    }
    let read: Read
}

private func decodeResult<T: Decodable>(_ result: JSONValue, type: String) throws -> T {
    guard case .object(let object) = result, object["type"] == .string(type) else {
        throw HerdrClientError.unexpectedResponse("expected \(type)")
    }
    do {
        return try result.decode()
    } catch {
        throw HerdrClientError.unexpectedResponse("invalid \(type): \(error.localizedDescription)")
    }
}

private func requiredID(_ value: String, field: String) throws -> String {
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw HerdrClientError.unexpectedResponse("missing \(field)")
    }
    return value
}
