import Foundation

public struct HerdrRuntime: Equatable, Sendable {
    public enum Source: String, Equatable, Sendable { case explicitOverride, path, repositoryLocal }
    public let url: URL
    public let source: Source

    public init(url: URL, source: Source) {
        self.url = url
        self.source = source
    }
}

public struct HerdrRuntimeLocator: Sendable {
    private let isExecutable: @Sendable (URL) -> Bool

    public init(isExecutable: @escaping @Sendable (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) }) {
        self.isExecutable = isExecutable
    }

    public func locate(
        explicitPath: String?,
        path: String?,
        repositoryRoot: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> HerdrRuntime? {
        if let explicitPath, !explicitPath.isEmpty {
            let candidate = URL(fileURLWithPath: explicitPath)
            if isExecutable(candidate) { return HerdrRuntime(url: candidate, source: .explicitOverride) }
        }

        for directory in (path ?? "").split(separator: ":") where !directory.isEmpty {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("herdr")
            if isExecutable(candidate) { return HerdrRuntime(url: candidate, source: .path) }
        }

        let userLocal = homeDirectory.appendingPathComponent(".local/bin/herdr")
        if isExecutable(userLocal) { return HerdrRuntime(url: userLocal, source: .path) }

        for relativePath in [".local/herdr/herdr", ".local/bin/herdr"] {
            let candidate = repositoryRoot.appendingPathComponent(relativePath)
            if isExecutable(candidate) { return HerdrRuntime(url: candidate, source: .repositoryLocal) }
        }
        return nil
    }
}

public struct HerdrServerStatus: Codable, Equatable, Sendable {
    public let status: String
    public let running: Bool
    public let version: String?
    public let protocolVersion: Int?
    public let socketPath: String

    enum CodingKeys: String, CodingKey {
        case status, running, version
        case protocolVersion = "protocol"
        case socketPath = "socket"
    }
}

public struct HerdrRuntimeProbe: Sendable {
    public init() {}

    public func status(runtime: HerdrRuntime, environment: [String: String]) throws -> HerdrServerStatus {
        let data = try run(runtime: runtime, arguments: ["status", "server", "--json"], environment: environment)
        do { return try JSONDecoder().decode(HerdrServerStatus.self, from: data) }
        catch { throw HerdrClientError.process(path: runtime.url.path, message: "invalid status JSON: \(error)") }
    }

    private func run(runtime: HerdrRuntime, arguments: [String], environment: [String: String]) throws -> Data {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = runtime.url
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = output
        process.standardError = errors
        do { try process.run() }
        catch { throw HerdrClientError.process(path: runtime.url.path, message: error.localizedDescription) }
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw HerdrClientError.process(path: runtime.url.path, message: message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return data
    }
}

public enum HerdrCompatibility {
    public static func incompatibility(for identity: HerdrServerIdentity) -> String? {
        guard identity.protocolVersion == BessieCompatibility.protocolVersion else {
            return "Herdr uses protocol \(identity.protocolVersion). Bessie requires protocol \(BessieCompatibility.protocolVersion)."
        }
        guard identity.version == BessieCompatibility.herdrVersion else {
            return "Herdr \(identity.version) isn't supported. Bessie requires \(BessieCompatibility.herdrVersion)."
        }
        return nil
    }
}
