import Foundation

enum BessieDiagnosticLog {
    nonisolated static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["BESSIE_STATE_LOG_PATH"] != nil
    }

    nonisolated static func append(_ line: String) {
        guard let path = ProcessInfo.processInfo.environment["BESSIE_STATE_LOG_PATH"] else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        let data = Data(String(format: "t=%.3f %@\n", uptime, line).utf8)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: data)
            return
        }
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch { return }
    }
}
