import BessieCore
import Foundation

enum BessieCLIParseError: Error, Equatable, LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case let .invalid(message): message
        }
    }
}

enum BessieCLICommand: Equatable {
    case intents
    case call(intent: String, params: [String: JSONValue], confirmToken: String?)

    static func parse(_ arguments: [String]) throws -> BessieCLICommand {
        guard let verb = arguments.first else { throw invalid("Missing command.") }
        switch verb {
        case "intents":
            guard arguments.count == 1 else { throw invalid("'intents' does not accept arguments.") }
            return .intents
        case "status":
            guard arguments.count == 1 else { throw invalid("'status' does not accept arguments.") }
            return .call(intent: "app.status", params: [:], confirmToken: nil)
        case "call":
            guard arguments.count >= 2, !arguments[1].isEmpty else { throw invalid("Missing intent ID after 'call'.") }
            var params: [String: JSONValue] = [:]
            var confirmToken: String?
            var sawJSON = false
            var index = 2
            while index < arguments.count {
                let option = arguments[index]
                guard index + 1 < arguments.count else { throw invalid("Missing value for '\(option)'.") }
                switch option {
                case "--json":
                    guard !sawJSON else { throw invalid("'--json' may be provided only once.") }
                    params = try decodeObject(arguments[index + 1])
                    sawJSON = true
                case "--confirm":
                    guard confirmToken == nil else { throw invalid("'--confirm' may be provided only once.") }
                    confirmToken = arguments[index + 1]
                default:
                    throw invalid("Unknown option '\(option)'.")
                }
                index += 2
            }
            return .call(intent: arguments[1], params: params, confirmToken: confirmToken)
        default:
            throw invalid("Unknown command '\(verb)'.")
        }
    }

    private static func decodeObject(_ source: String) throws -> [String: JSONValue] {
        guard let data = source.data(using: .utf8) else { throw invalid("JSON must be valid UTF-8.") }
        do {
            let value = try JSONDecoder().decode(JSONValue.self, from: data)
            guard case let .object(object) = value else { throw invalid("'--json' must contain a JSON object.") }
            return object
        } catch let error as BessieCLIParseError {
            throw error
        } catch {
            throw invalid("Invalid JSON for '--json': \(error.localizedDescription)")
        }
    }

    private static func invalid(_ message: String) -> BessieCLIParseError { .invalid(message) }
}

struct BessieCLIOutcome {
    let result: BessieIntentResult
    let exitCode: Int32
}

struct BessieCLIRunner {
    private let call: (BessieIntentRequest) -> BessieIntentResult
    private let requestID: () -> String

    init(
        call: @escaping (BessieIntentRequest) -> BessieIntentResult,
        requestID: @escaping () -> String = { UUID().uuidString }
    ) {
        self.call = call
        self.requestID = requestID
    }

    func run(arguments: [String]) throws -> BessieCLIOutcome {
        let command = try BessieCLICommand.parse(arguments)
        let result: BessieIntentResult
        switch command {
        case .intents:
            let id = requestID()
            let liveResult = call(BessieIntentRequest(id: id, intent: "intents.list", params: [:]))
            if liveResult.error?.code == .bessieNotRunning {
                result = .success(id: id, value: try encodeValue(BessieIntentRegistry.catalog))
            } else {
                result = liveResult
            }
        case let .call(intent, params, confirmToken):
            result = call(BessieIntentRequest(
                id: requestID(), intent: intent, params: params, confirmToken: confirmToken
            ))
        }
        return BessieCLIOutcome(result: result, exitCode: result.ok ? 0 : 1)
    }

    private func encodeValue<T: Encodable>(_ value: T) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }
}

@main
enum BessieCLI {
    static func main() {
        let runner = BessieCLIRunner(call: BessieIntentClient().call)
        do {
            let outcome = try runner.run(arguments: Array(CommandLine.arguments.dropFirst()))
            write(outcome.result)
            exit(outcome.exitCode)
        } catch {
            let result = BessieIntentResult.failure(
                id: UUID().uuidString,
                code: .invalidParams,
                message: error.localizedDescription
            )
            FileHandle.standardError.write(Data("Usage: bessie intents | bessie status | bessie call <intent-id> [--json '<object>'] [--confirm <token>]\n".utf8))
            write(result)
            exit(2)
        }
    }

    private static func write(_ result: BessieIntentResult) {
        do {
            var data = try JSONEncoder().encode(result)
            data.append(0x0A)
            FileHandle.standardOutput.write(data)
        } catch {
            FileHandle.standardError.write(Data("Failed to encode CLI result: \(error.localizedDescription)\n".utf8))
            exit(3)
        }
    }
}
