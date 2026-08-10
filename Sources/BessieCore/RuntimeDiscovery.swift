import Foundation
#if os(macOS)
import Darwin
#endif

public struct HerdrRuntime: Equatable, Sendable {
    public enum Source: String, Equatable, Sendable { case explicitOverride, bundled, system, custom, path, repositoryLocal }
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

    public func resolve(explicitPath: String?, selection: HerdrRuntimeSelection, bundledURL: URL?, path: String?, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> HerdrRuntime {
        if let explicitPath, !explicitPath.isEmpty {
            let url = URL(fileURLWithPath: explicitPath)
            guard isExecutable(url) else { throw RuntimeResolutionFailure.customNotExecutable(url.path) }
            return HerdrRuntime(url: url, source: .explicitOverride)
        }
        switch selection {
        case .bundled:
            guard let bundledURL, FileManager.default.fileExists(atPath: bundledURL.path) else { throw RuntimeResolutionFailure.bundledMissing }
            guard isExecutable(bundledURL) else { throw RuntimeResolutionFailure.bundledNotExecutable }
            return HerdrRuntime(url: bundledURL, source: .bundled)
        case .custom(let url):
            guard FileManager.default.fileExists(atPath: url.path) else { throw RuntimeResolutionFailure.customMissing(url.path) }
            guard isExecutable(url) else { throw RuntimeResolutionFailure.customNotExecutable(url.path) }
            return HerdrRuntime(url: url, source: .custom)
        case .system:
            for directory in (path ?? "").split(separator: ":") where !directory.isEmpty {
                let url = URL(fileURLWithPath: String(directory)).appendingPathComponent("herdr")
                if isExecutable(url) { return HerdrRuntime(url: url, source: .system) }
            }
            let url = homeDirectory.appendingPathComponent(".local/bin/herdr")
            if isExecutable(url) { return HerdrRuntime(url: url, source: .system) }
            throw RuntimeResolutionFailure.systemMissing
        }
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
    public typealias StatusProvider = @Sendable (HerdrRuntime, [String: String]) throws -> HerdrServerStatus

    private let statusProvider: StatusProvider?

    public init(statusProvider: StatusProvider? = nil) {
        self.statusProvider = statusProvider
    }

    public func status(runtime: HerdrRuntime, environment: [String: String]) throws -> HerdrServerStatus {
        if let statusProvider { return try statusProvider(runtime, environment) }
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

public struct HerdrServerLauncher: Sendable {
    public typealias StartOperation = @Sendable (HerdrRuntime, [String: String]) throws -> Void

    private let startOperation: StartOperation?

    public init(startOperation: StartOperation? = nil) {
        self.startOperation = startOperation
    }

    public func start(
        runtime: HerdrRuntime,
        environment: [String: String],
        startupDirectory: URL
    ) throws {
        var launchEnvironment = environment
        launchEnvironment["HERDR_STARTUP_CWD"] = startupDirectory.path
        if let startOperation {
            try startOperation(runtime, launchEnvironment)
            return
        }
        try Self.spawnDetached(runtime: runtime, environment: launchEnvironment)
    }

    private static func spawnDetached(runtime: HerdrRuntime, environment: [String: String]) throws {
        #if os(macOS)
        var actions: posix_spawn_file_actions_t?
        var status = posix_spawn_file_actions_init(&actions)
        guard status == 0 else { throw spawnError(runtime: runtime, operation: "prepare server launch", status: status) }
        defer { posix_spawn_file_actions_destroy(&actions) }

        for (descriptor, flags) in [
            (STDIN_FILENO, O_RDONLY),
            (STDOUT_FILENO, O_WRONLY),
            (STDERR_FILENO, O_WRONLY),
        ] {
            status = posix_spawn_file_actions_addopen(&actions, descriptor, "/dev/null", flags, 0)
            guard status == 0 else { throw spawnError(runtime: runtime, operation: "redirect server output", status: status) }
        }

        var attributes: posix_spawnattr_t?
        status = posix_spawnattr_init(&attributes)
        guard status == 0 else { throw spawnError(runtime: runtime, operation: "prepare detached server", status: status) }
        defer { posix_spawnattr_destroy(&attributes) }

        let flags = Int16(POSIX_SPAWN_SETSID)
        status = posix_spawnattr_setflags(&attributes, flags)
        guard status == 0 else { throw spawnError(runtime: runtime, operation: "detach server", status: status) }

        let argumentStrings: [String] = [runtime.url.path, "server"]
        let argumentStorage: [UnsafeMutablePointer<CChar>?] = argumentStrings.map { value in
            value.withCString { strdup($0) }
        }
        let environmentStorage: [UnsafeMutablePointer<CChar>?] = environment.keys.sorted().map { key in
            "\(key)=\(environment[key]!)".withCString { strdup($0) }
        }
        defer {
            argumentStorage.forEach { free($0) }
            environmentStorage.forEach { free($0) }
        }
        guard argumentStorage.allSatisfy({ $0 != nil }), environmentStorage.allSatisfy({ $0 != nil }) else {
            throw HerdrClientError.process(path: runtime.url.path, message: "couldn't allocate the Herdr server launch environment")
        }

        var arguments = argumentStorage + [nil]
        var environmentPointers = environmentStorage + [nil]
        var processID: pid_t = 0
        status = posix_spawn(
            &processID,
            runtime.url.path,
            &actions,
            &attributes,
            &arguments,
            &environmentPointers
        )
        guard status == 0 else { throw spawnError(runtime: runtime, operation: "start server", status: status) }

        let launchedProcessID = processID
        DispatchQueue.global(qos: .utility).async {
            var childStatus: Int32 = 0
            while waitpid(launchedProcessID, &childStatus, 0) == -1, errno == EINTR {}
        }
        #else
        let process = Process()
        process.executableURL = runtime.url
        process.arguments = ["server"]
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() }
        catch { throw HerdrClientError.process(path: runtime.url.path, message: error.localizedDescription) }
        #endif
    }

    #if os(macOS)
    private static func spawnError(runtime: HerdrRuntime, operation: String, status: Int32) -> HerdrClientError {
        HerdrClientError.process(
            path: runtime.url.path,
            message: "couldn't \(operation): \(String(cString: strerror(status)))"
        )
    }
    #endif
}

public enum HerdrCompatibility {
    public static func incompatibility(for identity: HerdrServerIdentity) -> String? {
        guard identity.protocolVersion == BessieCompatibility.protocolVersion else {
            return "Herdr uses protocol \(identity.protocolVersion). Bessie requires protocol \(BessieCompatibility.protocolVersion)."
        }
        guard identity.version == BessieCompatibility.herdrVersion else {
            return "This Herdr runtime isn't supported."
        }
        return nil
    }
}
