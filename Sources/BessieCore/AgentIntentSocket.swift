#if os(macOS)
import Darwin
import Foundation

public enum BessieIntentSocketPath {
    public static func resolved(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let override = environment["BESSIE_INTENT_SOCKET_PATH"], !override.isEmpty { return override }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Bessie/intent.sock").path
    }
}

public struct BessieIntentClient: Sendable {
    public let path: String

    public init(path: String = BessieIntentSocketPath.resolved()) { self.path = path }

    public func call(_ request: BessieIntentRequest) -> BessieIntentResult {
        do {
            let connection = try UnixSocketNDJSONConnection(path: path)
            defer { connection.close() }
            try connection.sendLine(JSONEncoder().encode(request))
            let result = try JSONDecoder().decode(BessieIntentResult.self, from: connection.readLine())
            guard result.id == request.id else {
                return .failure(id: request.id, code: .invalidParams, message: "Intent response correlation ID did not match the request.")
            }
            return result
        } catch {
            return .failure(id: request.id, code: .bessieNotRunning, message: "Bessie is not running or its local intent socket is unavailable.")
        }
    }
}

public enum BessieIntentSocketError: Error, Equatable {
    case alreadyRunning(String)
    case socket(String)
}

public final class BessieIntentSocketServer: @unchecked Sendable {
    public typealias Handler = @Sendable (BessieIntentRequest) -> BessieIntentResult

    private let path: String
    private let handler: Handler
    private let lock = NSLock()
    private let queue = DispatchQueue(
        label: "work.bessie.intent-socket",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private var descriptor: Int32 = -1
    private var lockDescriptor: Int32 = -1
    private var endpointIdentity: (device: dev_t, inode: ino_t)?

    public init(path: String = BessieIntentSocketPath.resolved(), handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    deinit { stop() }

    public func start() throws {
        try lock.withLock {
            guard descriptor < 0 else { return }
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: path).deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let ownerLock = Darwin.open(path + ".lock", O_CREAT | O_RDWR, 0o600)
            guard ownerLock >= 0 else { throw socketError() }
            guard flock(ownerLock, LOCK_EX | LOCK_NB) == 0 else {
                Darwin.close(ownerLock)
                throw BessieIntentSocketError.alreadyRunning(path)
            }
            lockDescriptor = ownerLock
            do {
                try startLocked()
            } catch {
                flock(ownerLock, LOCK_UN)
                Darwin.close(ownerLock)
                lockDescriptor = -1
                throw error
            }
            queue.async { [weak self] in self?.acceptLoop() }
        }
    }

    private func startLocked() throws {
            try removeStaleEndpointIfNeeded()

            let socketDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard socketDescriptor >= 0 else { throw socketError() }
            var didBind = false
            do {
                var address = try socketAddress(path: path)
                let length = socklen_t(MemoryLayout<sa_family_t>.size + path.utf8CString.count)
                let bindResult = withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(socketDescriptor, $0, length) }
                }
                guard bindResult == 0 else { throw socketError() }
                didBind = true
                guard chmod(path, 0o600) == 0 else { throw socketError() }
                guard Darwin.listen(socketDescriptor, 16) == 0 else { throw socketError() }
                descriptor = socketDescriptor
                endpointIdentity = identity(at: path)
            } catch {
                Darwin.close(socketDescriptor)
                if didBind { _ = unlink(path) }
                throw error
            }
    }

    public func stop() {
        let ownedIdentity = lock.withLock { () -> (dev_t, ino_t)? in
            guard descriptor >= 0 else { return nil }
            let current = descriptor
            descriptor = -1
            Darwin.shutdown(current, SHUT_RDWR)
            Darwin.close(current)
            if lockDescriptor >= 0 {
                flock(lockDescriptor, LOCK_UN)
                Darwin.close(lockDescriptor)
                lockDescriptor = -1
            }
            defer { endpointIdentity = nil }
            return endpointIdentity
        }
        if let ownedIdentity, let current = identity(at: path), current == ownedIdentity { _ = unlink(path) }
    }

    private func acceptLoop() {
        while true {
            let listening = lock.withLock { descriptor }
            guard listening >= 0 else { return }
            let client = Darwin.accept(listening, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            queue.async { [weak self] in self?.serve(client) }
        }
    }

    private func serve(_ client: Int32) {
        defer { Darwin.close(client) }
        do {
            let line = try readLine(from: client)
            let result: BessieIntentResult
            do {
                result = handler(try JSONDecoder().decode(BessieIntentRequest.self, from: line))
            } catch {
                result = .failure(
                    id: recoverID(from: line),
                    code: .invalidParams,
                    message: "Malformed intent request: \(error.localizedDescription)"
                )
            }
            var encoded = try JSONEncoder().encode(result)
            encoded.append(0x0A)
            try writeAll(encoded, to: client)
        } catch {
            // A client that disconnects before sending a line has no request to answer.
        }
    }

    private func removeStaleEndpointIfNeeded() throws {
        guard FileManager.default.fileExists(atPath: path) else { return }
        do {
            let connection = try UnixSocketNDJSONConnection(path: path)
            connection.close()
            throw BessieIntentSocketError.alreadyRunning(path)
        } catch let error as BessieIntentSocketError {
            throw error
        } catch {
            var facts = stat()
            guard lstat(path, &facts) == 0, facts.st_mode & S_IFMT == S_IFSOCK else {
                throw BessieIntentSocketError.socket("Refusing to replace a non-socket path at \(path).")
            }
            guard unlink(path) == 0 else { throw socketError() }
        }
    }
}

private func socketAddress(path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = path.utf8CString
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
        throw BessieIntentSocketError.socket("Intent socket path is too long.")
    }
    path.withCString { source in
        withUnsafeMutablePointer(to: &address.sun_path.0) { destination in
            _ = Darwin.strncpy(destination, source, bytes.count)
        }
    }
    return address
}

private func readLine(from descriptor: Int32) throws -> Data {
    var data = Data()
    var byte: UInt8 = 0
    while data.count < 1_048_576 {
        let count = Darwin.read(descriptor, &byte, 1)
        guard count > 0 else { throw BessieIntentSocketError.socket("Connection closed before a request line was received.") }
        if byte == 0x0A { return data }
        data.append(byte)
    }
    throw BessieIntentSocketError.socket("Intent request line exceeds 1 MiB.")
}

private func writeAll(_ data: Data, to descriptor: Int32) throws {
    try data.withUnsafeBytes { bytes in
        guard var pointer = bytes.baseAddress else { return }
        var remaining = bytes.count
        while remaining > 0 {
            let count = Darwin.write(descriptor, pointer, remaining)
            guard count > 0 else { throw BessieIntentSocketError.socket(String(cString: strerror(errno))) }
            pointer = pointer.advanced(by: count)
            remaining -= count
        }
    }
}

private func recoverID(from data: Data) -> String {
    (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["id"] as? String ?? ""
}

private func identity(at path: String) -> (dev_t, ino_t)? {
    var facts = stat()
    guard lstat(path, &facts) == 0 else { return nil }
    return (facts.st_dev, facts.st_ino)
}

private func socketError() -> BessieIntentSocketError {
    .socket(String(cString: strerror(errno)))
}
#endif
