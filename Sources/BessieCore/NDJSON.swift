import Foundation

public struct NDJSONFramer: Sendable {
    public private(set) var remainder = Data()

    public init() {}

    public mutating func append(_ data: Data) throws -> [String] {
        remainder.append(data)
        var lines: [String] = []
        while let newline = remainder.firstIndex(of: 0x0A) {
            let lineData = remainder[..<newline]
            remainder.removeSubrange(...newline)
            guard let line = String(data: lineData, encoding: .utf8) else {
                throw HerdrClientError.invalidNDJSON("record is not UTF-8")
            }
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }
}

public struct HerdrResponse: Sendable {
    public let id: String
    public let result: JSONValue

    public func snapshot() throws -> HerdrSnapshot {
        guard case .object(let resultObject) = result,
              resultObject["type"] == .string("session_snapshot"),
              let snapshotValue = resultObject["snapshot"] else {
            throw HerdrClientError.unexpectedResponse("expected session_snapshot")
        }
        return try JSONDecoder().decode(HerdrSnapshot.self, from: JSONEncoder().encode(snapshotValue))
    }

    public func identity() throws -> HerdrServerIdentity {
        guard case .object(let object) = result,
              object["type"] == .string("pong"),
              case .string(let version)? = object["version"],
              case .number(let protocolValue)? = object["protocol"] else {
            throw HerdrClientError.unexpectedResponse("expected pong")
        }
        return HerdrServerIdentity(version: version, protocolVersion: Int(protocolValue))
    }
}

public enum HerdrResponseDecoder {
    private struct Envelope: Decodable {
        struct ErrorBody: Decodable { let code: String; let message: String }
        let id: String
        let result: JSONValue?
        let error: ErrorBody?
    }

    public static func decode(_ data: Data, expectedID: String) throws -> HerdrResponse {
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
        catch { throw HerdrClientError.invalidNDJSON(error.localizedDescription) }
        if let error = envelope.error, envelope.id.isEmpty {
            throw HerdrClientError.server(code: error.code, message: error.message)
        }
        guard envelope.id == expectedID else {
            throw HerdrClientError.mismatchedResponseID(expected: expectedID, actual: envelope.id)
        }
        if let error = envelope.error { throw HerdrClientError.server(code: error.code, message: error.message) }
        guard let result = envelope.result else { throw HerdrClientError.unexpectedResponse("missing result") }
        return HerdrResponse(id: envelope.id, result: result)
    }
}
