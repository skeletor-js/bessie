import Foundation

enum BessieDiagnosticLog {
    nonisolated static func append(_ line: String) {
        guard let path = ProcessInfo.processInfo.environment["BESSIE_STATE_LOG_PATH"] else { return }
        let data = Data("\(line)\n".utf8)
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
