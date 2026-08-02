import BessieCore
import Foundation

struct BessieMCPRunner {
    private let call: (BessieIntentRequest) -> BessieIntentResult
    private let requestID: () -> String

    init(
        call: @escaping (BessieIntentRequest) -> BessieIntentResult,
        requestID: @escaping () -> String = { UUID().uuidString }
    ) {
        self.call = call
        self.requestID = requestID
    }

    func handle(line: String) throws -> Data? {
        let request: [String: Any]
        do {
            guard let data = line.data(using: .utf8),
                  let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return try error(id: NSNull(), code: -32600, message: "Invalid Request") }
            request = decoded
        } catch {
            return try self.error(id: NSNull(), code: -32700, message: "Parse error")
        }

        let hasID = request.keys.contains("id")
        guard request["jsonrpc"] as? String == "2.0", let method = request["method"] as? String else {
            return hasID ? try error(id: request["id"] ?? NSNull(), code: -32600, message: "Invalid Request") : nil
        }
        guard hasID else { return nil }
        let id = request["id"] ?? NSNull()

        switch method {
        case "initialize":
            let requested = (request["params"] as? [String: Any])?["protocolVersion"] as? String
            return try response(id: id, result: [
                "protocolVersion": requested ?? "2024-11-05",
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "bessie-mcp", "version": "1.0.0"],
            ])
        case "tools/list":
            let tools = effectiveCatalog().intents.map { intent in
                [
                    "name": intent.id.rawValue,
                    "description": intent.description,
                    "inputSchema": jsonObject(toolSchema(for: intent)),
                ] as [String: Any]
            }
            return try response(id: id, result: ["tools": tools])
        case "tools/call":
            guard let params = request["params"] as? [String: Any],
                  let name = params["name"] as? String
            else { return try error(id: id, code: -32602, message: "Invalid tools/call params") }
            let rawArguments: [String: Any]
            if let supplied = params["arguments"] {
                guard let supplied = supplied as? [String: Any] else {
                    return try error(id: id, code: -32602, message: "Tool arguments must be a JSON object")
                }
                rawArguments = supplied
            } else {
                rawArguments = [:]
            }
            var arguments = rawArguments
            let confirmToken = arguments.removeValue(forKey: "confirm_token") as? String
            guard let values = try? decodeValues(arguments) else {
                return try error(id: id, code: -32602, message: "Tool arguments must be valid JSON values")
            }
            let result = call(BessieIntentRequest(
                id: requestID(), intent: name, params: values, confirmToken: confirmToken
            ))
            let encoded = try JSONEncoder().encode(result)
            let text = String(decoding: encoded, as: UTF8.self)
            return try response(id: id, result: [
                "content": [["type": "text", "text": text]],
                "isError": !result.ok,
            ])
        default:
            return try error(id: id, code: -32601, message: "Method not found")
        }
    }

    private func effectiveCatalog() -> BessieIntentCatalog {
        let id = requestID()
        let result = call(BessieIntentRequest(id: id, intent: "intents.list", params: [:]))
        guard result.ok, let value = result.value,
              let data = try? JSONEncoder().encode(value),
              let catalog = try? JSONDecoder().decode(BessieIntentCatalog.self, from: data)
        else { return BessieIntentRegistry.catalog }
        return catalog
    }

    private func decodeValues(_ object: [String: Any]) throws -> [String: JSONValue] {
        try JSONDecoder().decode([String: JSONValue].self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func toolSchema(for intent: BessieIntentDefinition) -> BessieJSONSchema {
        guard intent.risk == .destructive else { return intent.paramsSchema }
        var properties = intent.paramsSchema.properties ?? [:]
        properties["confirm_token"] = .string("One-shot confirmation token returned by needs_confirmation.")
        return BessieJSONSchema(
            type: .object,
            properties: properties,
            required: intent.paramsSchema.required,
            additionalProperties: false
        )
    }

    private func jsonObject<T: Encodable>(_ value: T) -> Any {
        let data = try! JSONEncoder().encode(value)
        return try! JSONSerialization.jsonObject(with: data)
    }

    private func response(id: Any, result: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func error(id: Any, code: Int, message: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message],
        ])
    }
}

@main
enum BessieMCP {
    static func main() {
        let runner = BessieMCPRunner(call: BessieIntentClient().call)
        while let line = readLine() {
            do {
                if var output = try runner.handle(line: line) {
                    output.append(0x0A)
                    FileHandle.standardOutput.write(output)
                }
            } catch {
                FileHandle.standardError.write(Data("bessie-mcp: \(error.localizedDescription)\n".utf8))
            }
        }
    }
}
