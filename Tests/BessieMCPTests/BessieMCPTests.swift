import BessieCore
import Foundation
import Testing
@testable import BessieMCP

@Suite("Bessie MCP stdio adapter")
struct BessieMCPTests {
    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func output(_ runner: BessieMCPRunner, _ line: String) throws -> Data {
        let value = try runner.handle(line: line)
        return try #require(value)
    }

    @Test func initializePreservesNumericIDAndAdvertisesTools() throws {
        let output = try output(runner(), #"{"jsonrpc":"2.0","id":7,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}"#)
        let response = try object(output)
        #expect(response["id"] as? Int == 7)
        let result = try #require(response["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2024-11-05")
        #expect((result["capabilities"] as? [String: Any])?["tools"] != nil)
        #expect((result["serverInfo"] as? [String: Any])?["name"] as? String == "bessie-mcp")
    }

    @Test func toolsListUsesExactEffectiveRegistryCatalog() throws {
        let output = try output(runner(), #"{"jsonrpc":"2.0","id":"list","method":"tools/list"}"#)
        let tools = try #require((try object(output)["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(tools.compactMap { $0["name"] as? String } == BessieIntentRegistry.catalog.intents.map(\.id.rawValue))
        for (tool, intent) in zip(tools, BessieIntentRegistry.catalog.intents) {
            #expect(tool["description"] as? String == intent.description)
            let schema = try JSONDecoder().decode(BessieJSONSchema.self, from: JSONSerialization.data(withJSONObject: tool["inputSchema"] as Any))
            #expect(schema.properties?.keys.contains("confirm_token") == (intent.risk == .destructive))
            #expect(schema.required == intent.paramsSchema.required)
        }
    }

    @Test func toolsListNamesEqualCustomEffectiveCatalog() throws {
        let effective = BessieIntentCatalog(version: 9, intents: [
            BessieIntentRegistry.catalog.intents[2],
            BessieIntentRegistry.catalog.intents[6],
        ])
        let adapter = runner { request in
            let value = try! JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(effective))
            return .success(id: request.id, value: value)
        }
        let data = try output(adapter, #"{"jsonrpc":"2.0","id":"effective","method":"tools/list"}"#)
        let tools = try #require((try object(data)["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(tools.compactMap { $0["name"] as? String } == effective.intents.map(\.id.rawValue))
        let destructive = try #require(tools.first { ($0["name"] as? String) == "workspace.close" })
        let schema = try #require(destructive["inputSchema"] as? [String: Any])
        let properties = try #require(schema["properties"] as? [String: Any])
        #expect(properties["confirm_token"] != nil)
    }

    @Test func toolsCallTranslatesArgumentsAndConfirmationToken() throws {
        var received: BessieIntentRequest?
        let adapter = runner { request in
            received = request
            return .success(id: request.id, value: .string("done"))
        }
        let output = try output(adapter, #"{"jsonrpc":"2.0","id":"call-1","method":"tools/call","params":{"name":"workspace.close","arguments":{"connection_id":"c1","workspace_id":"w1","confirm_token":"token"}}}"#)
        #expect(received?.intent.rawValue == "workspace.close")
        #expect(received?.params == ["connection_id": .string("c1"), "workspace_id": .string("w1")])
        #expect(received?.confirmToken == "token")
        let result = try #require((try object(output)["result"] as? [String: Any]))
        #expect(result["isError"] as? Bool == false)
        let text = try #require((result["content"] as? [[String: Any]])?.first?["text"] as? String)
        #expect(try JSONDecoder().decode(BessieIntentResult.self, from: Data(text.utf8)).ok)
    }

    @Test func offlineCallReturnsToolErrorContent() throws {
        let output = try output(runner { request in
            .failure(id: request.id, code: .bessieNotRunning, message: "Bessie is not running.")
        }, #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"app.status"}}"#)
        let result = try #require((try object(output)["result"] as? [String: Any]))
        #expect(result["isError"] as? Bool == true)
        let text = try #require((result["content"] as? [[String: Any]])?.first?["text"] as? String)
        #expect(try JSONDecoder().decode(BessieIntentResult.self, from: Data(text.utf8)).error?.code == .bessieNotRunning)
    }

    @Test func notificationsProduceNoOutput() throws {
        let initialized = try runner().handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        let unknown = try runner().handle(line: #"{"jsonrpc":"2.0","method":"unknown/notification"}"#)
        #expect(initialized == nil)
        #expect(unknown == nil)
    }

    @Test func malformedAndUnknownRequestsAreProtocolErrors() throws {
        let malformed = try output(runner(), "{")
        #expect(((try object(malformed)["error"] as? [String: Any])?["code"] as? Int) == -32700)
        let unknown = try output(runner(), #"{"jsonrpc":"2.0","id":"x","method":"missing"}"#)
        let response = try object(unknown)
        #expect(response["id"] as? String == "x")
        #expect((response["error"] as? [String: Any])?["code"] as? Int == -32601)
    }

    @Test func encodedResponsesAreSingleProtocolLines() throws {
        let output = try output(runner(), #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
        #expect(!output.contains(0x0A))
        #expect(try JSONSerialization.jsonObject(with: output) is [String: Any])
    }

    private func runner(
        call: @escaping (BessieIntentRequest) -> BessieIntentResult = { request in
            if request.intent.rawValue == "intents.list" {
                let value = try! JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(BessieIntentRegistry.catalog))
                return .success(id: request.id, value: value)
            }
            return .success(id: request.id, value: .null)
        }
    ) -> BessieMCPRunner { BessieMCPRunner(call: call, requestID: { "intent-request" }) }
}
