#if os(macOS)
import Darwin
import Foundation

public protocol HerdrLineConnection: AnyObject, Sendable {
    func sendLine(_ data: Data) throws
    func readLine() throws -> Data
    func close()
}

public struct HerdrLineSendFailure: Error, @unchecked Sendable {
    public let disposition: HerdrMutationDisposition
    public let underlying: any Error

    public init(disposition: HerdrMutationDisposition, underlying: any Error) {
        self.disposition = disposition
        self.underlying = underlying
    }
}

public struct HerdrRequestDeadlines: Equatable, Sendable {
    public let send: TimeInterval
    public let read: TimeInterval

    public init(send: TimeInterval, read: TimeInterval) {
        precondition(send > 0 && read > 0)
        self.send = send
        self.read = read
    }

    public static let prefixDispatch = HerdrRequestDeadlines(send: 5, read: 5)
}

public final class UnixSocketNDJSONConnection: HerdrLineConnection, @unchecked Sendable {
    private let path: String
    private let descriptor: Int32
    private let closeLock = NSLock()
    private var isClosed = false
    private var framer = NDJSONFramer()
    private var readyLines: [String] = []
    private let deadlines: HerdrRequestDeadlines?

    public init(path: String, deadlines: HerdrRequestDeadlines? = nil) throws {
        self.path = path
        self.deadlines = deadlines
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw HerdrClientError.socket(path: path, message: String(cString: strerror(errno))) }
        self.descriptor = descriptor

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            Darwin.close(descriptor)
            throw HerdrClientError.socket(path: path, message: "path is too long")
        }
        path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path.0) { destination in
                _ = Darwin.strncpy(destination, source, bytes.count)
            }
        }
        let length = socklen_t(MemoryLayout<sa_family_t>.size + bytes.count)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, length) }
        }
        guard result == 0 else {
            let message = String(cString: strerror(errno))
            Darwin.close(descriptor)
            throw HerdrClientError.socket(path: path, message: message)
        }
        if deadlines != nil {
            let flags = Darwin.fcntl(descriptor, F_GETFL, 0)
            guard flags >= 0, Darwin.fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
                let message = String(cString: strerror(errno))
                Darwin.close(descriptor)
                throw HerdrClientError.socket(path: path, message: message)
            }
        }
    }

    init(
        connectedDescriptor: Int32,
        path: String,
        deadlines: HerdrRequestDeadlines? = nil
    ) throws {
        self.path = path
        descriptor = connectedDescriptor
        self.deadlines = deadlines
        guard connectedDescriptor >= 0 else {
            throw HerdrClientError.socket(path: path, message: "invalid connected descriptor")
        }
        if deadlines != nil {
            let flags = Darwin.fcntl(connectedDescriptor, F_GETFL, 0)
            guard flags >= 0,
                  Darwin.fcntl(connectedDescriptor, F_SETFL, flags | O_NONBLOCK) == 0
            else {
                let message = String(cString: strerror(errno))
                Darwin.close(connectedDescriptor)
                throw HerdrClientError.socket(path: path, message: message)
            }
        }
    }

    deinit { close() }

    public func sendLine(_ data: Data) throws {
        var payload = data
        payload.append(0x0A)
        let deadline = deadlines.map { ProcessInfo.processInfo.systemUptime + $0.send }
        var transmitted = false
        do {
            try payload.withUnsafeBytes { rawBuffer in
                guard var pointer = rawBuffer.baseAddress else { return }
                var remaining = rawBuffer.count
                while remaining > 0 {
                    try waitUntilReady(Int16(POLLOUT), deadline: deadline)
                    let written = Darwin.write(descriptor, pointer, remaining)
                    if written < 0, errno == EINTR || errno == EAGAIN { continue }
                    guard written > 0 else {
                        throw HerdrClientError.socket(path: path, message: String(cString: strerror(errno)))
                    }
                    transmitted = true
                    remaining -= written
                    pointer = pointer.advanced(by: written)
                }
            }
        } catch {
            throw HerdrLineSendFailure(
                disposition: transmitted ? .mutationOutcomeUnknown : .definitelyUnsent,
                underlying: error
            )
        }
    }

    public func readLine() throws -> Data {
        let deadline = deadlines.map { ProcessInfo.processInfo.systemUptime + $0.read }
        while true {
            if !readyLines.isEmpty { return Data(readyLines.removeFirst().utf8) }
            try waitUntilReady(Int16(POLLIN), deadline: deadline)
            var buffer = [UInt8](repeating: 0, count: 16_384)
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count == 0 { throw HerdrClientError.connectionClosed }
            if count < 0, errno == EINTR || errno == EAGAIN { continue }
            guard count > 0 else { throw HerdrClientError.socket(path: path, message: String(cString: strerror(errno))) }
            readyLines.append(contentsOf: try framer.append(Data(buffer[..<count])))
        }
    }

    private func waitUntilReady(_ events: Int16, deadline: TimeInterval?) throws {
        guard let deadline else { return }
        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else {
                throw HerdrClientError.socket(path: path, message: "request timed out")
            }
            var item = pollfd(fd: descriptor, events: events, revents: 0)
            let milliseconds = Int32(min(Double(Int32.max), ceil(remaining * 1_000)))
            let result = Darwin.poll(&item, 1, milliseconds)
            if result < 0, errno == EINTR { continue }
            guard result >= 0 else {
                throw HerdrClientError.socket(path: path, message: String(cString: strerror(errno)))
            }
            guard result > 0 else {
                throw HerdrClientError.socket(path: path, message: "request timed out")
            }
            if item.revents & events != 0 { return }
            if item.revents & Int16(POLLERR | POLLHUP | POLLNVAL) != 0 {
                throw HerdrClientError.connectionClosed
            }
        }
    }

    public func close() {
        closeLock.lock()
        defer { closeLock.unlock() }
        guard !isClosed else { return }
        isClosed = true
        Darwin.shutdown(descriptor, SHUT_RDWR)
        Darwin.close(descriptor)
    }
}
#endif
