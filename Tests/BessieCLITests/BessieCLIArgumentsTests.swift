import BessieCore
import Foundation
import Testing
@testable import BessieCLI

@Suite("Bessie CLI arguments")
struct BessieCLIArgumentsTests {
    @Test func validForms() throws {
        #expect(try BessieCLICommand.parse(["intents"]) == .intents)
        #expect(try BessieCLICommand.parse(["status"]) == .call(intent: "app.status", params: [:], confirmToken: nil))
        #expect(try BessieCLICommand.parse(["call", "pane.focus"]) == .call(intent: "pane.focus", params: [:], confirmToken: nil))
    }

    @Test func missingIntent() {
        #expect(throws: BessieCLIParseError.self) { try BessieCLICommand.parse(["call"]) }
    }

    @Test func rejectsNonObjectJSON() {
        #expect(throws: BessieCLIParseError.self) { try BessieCLICommand.parse(["call", "pane.focus", "--json", "[]"]) }
    }

    @Test func rejectsInvalidJSON() {
        #expect(throws: BessieCLIParseError.self) { try BessieCLICommand.parse(["call", "pane.focus", "--json", "{"]) }
    }

    @Test func parsesConfirmationToken() throws {
        let command = try BessieCLICommand.parse([
            "call", "workspace.close", "--json", #"{"workspace_id":"w1"}"#, "--confirm", "same-token",
        ])
        #expect(command == .call(
            intent: "workspace.close",
            params: ["workspace_id": .string("w1")],
            confirmToken: "same-token"
        ))
    }

    @Test func offlineStatusIsAnHonestFailure() throws {
        let runner = BessieCLIRunner(call: { request in
            .failure(id: request.id, code: .bessieNotRunning, message: "Bessie is not running.")
        })
        let outcome = try runner.run(arguments: ["status"])
        #expect(!outcome.result.ok)
        #expect(outcome.result.error?.code == .bessieNotRunning)
        #expect(outcome.exitCode != 0)
    }

    @Test func offlineIntentsUsesStaticRegistryNames() throws {
        let runner = BessieCLIRunner(call: { request in
            .failure(id: request.id, code: .bessieNotRunning, message: "Bessie is not running.")
        })
        let outcome = try runner.run(arguments: ["intents"])
        let data = try JSONEncoder().encode(outcome.result.value)
        let catalog = try JSONDecoder().decode(BessieIntentCatalog.self, from: data)
        #expect(outcome.result.ok)
        #expect(Set(catalog.intents.map(\.id.rawValue)) == Set(BessieIntentRegistry.catalog.intents.map(\.id.rawValue)))
    }

    @Test func requestsReceiveUniqueIDs() throws {
        var ids: [String] = []
        let runner = BessieCLIRunner(call: { request in
            ids.append(request.id)
            return .success(id: request.id, value: .null)
        })
        _ = try runner.run(arguments: ["status"])
        _ = try runner.run(arguments: ["status"])
        #expect(ids.count == 2)
        #expect(ids[0] != ids[1])
    }
}
