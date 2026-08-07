import Darwin
import Foundation

enum BessieDiagnosticLog {
    nonisolated static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["BESSIE_STATE_LOG_PATH"] != nil
    }

    nonisolated static func append(_ line: String) {
        guard let path = ProcessInfo.processInfo.environment["BESSIE_STATE_LOG_PATH"] else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        let data = Data(String(format: "t=%.3f %@\n", uptime, line).utf8)
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
        let descriptor = open(path, O_CREAT | O_WRONLY | O_APPEND | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        var details = stat()
        guard fstat(descriptor, &details) == 0,
              (details.st_mode & S_IFMT) == S_IFREG,
              details.st_nlink == 1 else { return }
        _ = fchmod(descriptor, S_IRUSR | S_IWUSR)
        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            _ = Darwin.write(descriptor, baseAddress, bytes.count)
        }
    }
}
