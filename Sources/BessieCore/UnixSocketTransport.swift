#if os(macOS)
import Darwin
import Foundation

public protocol HerdrLineConnection: AnyObject, Sendable {
    func sendLine(_ data: Data) throws
    func readLine() throws -> Data
    func close()
}

public final class UnixSocketNDJSONConnection: HerdrLineConnection, @unchecked Sendable {
    private let path: String
    private let descriptor: Int32
    private let closeLock = NSLock()
    private var isClosed = false
    private var framer = NDJSONFramer()
    private var readyLines: [String] = []

    public init(path: String) throws {
        self.path = path
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
    }

    deinit { close() }

    public func sendLine(_ data: Data) throws {
        var payload = data
        payload.append(0x0A)
        try payload.withUnsafeBytes { rawBuffer in
            guard var pointer = rawBuffer.baseAddress else { return }
            var remaining = rawBuffer.count
            while remaining > 0 {
                let written = Darwin.write(descriptor, pointer, remaining)
                guard written > 0 else { throw HerdrClientError.socket(path: path, message: String(cString: strerror(errno))) }
                remaining -= written
                pointer = pointer.advanced(by: written)
            }
        }
    }

    public func readLine() throws -> Data {
        while true {
            if !readyLines.isEmpty { return Data(readyLines.removeFirst().utf8) }
            var buffer = [UInt8](repeating: 0, count: 16_384)
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count == 0 { throw HerdrClientError.connectionClosed }
            guard count > 0 else { throw HerdrClientError.socket(path: path, message: String(cString: strerror(errno))) }
            readyLines.append(contentsOf: try framer.append(Data(buffer[..<count])))
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
