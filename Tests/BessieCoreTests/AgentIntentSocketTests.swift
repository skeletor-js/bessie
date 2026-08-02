#if os(macOS)
import Darwin
import Foundation
import Testing
@testable import BessieCore

@Suite("Agent intent socket")
struct AgentIntentSocketTests {
    @Test("round trips one request and preserves correlation id")
    func roundTrip() throws {
        let path = temporarySocketPath()
        let server = BessieIntentSocketServer(path: path) { request in
            .success(id: request.id, value: .object(["running": .bool(true)]))
        }
        try server.start()
        defer { server.stop() }

        let result = BessieIntentClient(path: path).call(BessieIntentRequest(
            id: "correlation-1", intent: "app.status", params: [:]
        ))

        #expect(result.id == "correlation-1")
        #expect(result.ok)
        #expect(fileMode(path) == 0o600)
    }

    @Test("malformed JSON returns structured invalid params")
    func malformedRequest() throws {
        let path = temporarySocketPath()
        let server = BessieIntentSocketServer(path: path) { _ in
            Issue.record("Malformed input must not reach the executor")
            return .failure(id: "unexpected", code: .invalidParams, message: "unexpected")
        }
        try server.start()
        defer { server.stop() }
        let connection = try UnixSocketNDJSONConnection(path: path)
        try connection.sendLine(Data(#"{"id":"bad-1""#.utf8))

        let result = try JSONDecoder().decode(BessieIntentResult.self, from: connection.readLine())
        #expect(result.id.isEmpty)
        #expect(result.error?.code == .invalidParams)
    }

    @Test("connection failure maps to bessie not running")
    func offline() {
        let result = BessieIntentClient(path: temporarySocketPath()).call(BessieIntentRequest(
            id: "offline-1", intent: "app.status", params: [:]
        ))
        #expect(result.id == "offline-1")
        #expect(result.error?.code == .bessieNotRunning)
    }

    @Test("a second server cannot take over a live socket")
    func competingServer() throws {
        let path = temporarySocketPath()
        let first = BessieIntentSocketServer(path: path) { .success(id: $0.id, value: .null) }
        let second = BessieIntentSocketServer(path: path) { .success(id: $0.id, value: .null) }
        try first.start()
        defer { first.stop() }

        #expect(throws: BessieIntentSocketError.alreadyRunning(path)) { try second.start() }
        #expect(BessieIntentClient(path: path).call(BessieIntentRequest(
            id: "owner", intent: "app.status", params: [:]
        )).ok)
    }

    private func temporarySocketPath() -> String {
        "/tmp/bessie-\(UUID().uuidString.prefix(12)).sock"
    }

    private func fileMode(_ path: String) -> mode_t? {
        var value = stat()
        guard stat(path, &value) == 0 else { return nil }
        return value.st_mode & 0o777
    }
}
#endif
