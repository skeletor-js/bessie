import Foundation
#if os(macOS)
import Darwin
#else
import Glibc
#endif

struct FoundationProcessCommandResult: Equatable, Sendable {
    let exitCode: Int32
    let stdout: Data
    let stderr: Data
}

enum FoundationProcessCommandError: Error, Equatable {
    case timedOut
}

enum FoundationProcessCommandRunner {
    static func run(
        executableURL: URL,
        arguments: [String],
        standardInput: Data? = nil,
        timeout: TimeInterval
    ) throws -> FoundationProcessCommandResult {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        let input = standardInput.map { _ in Pipe() }
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = input ?? FileHandle.nullDevice
        try process.run()

        output.fileHandleForWriting.closeFile()
        errors.fileHandleForWriting.closeFile()

        let outputCapture = FoundationProcessDataCapture()
        let errorCapture = FoundationProcessDataCapture()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outputCapture.store(output.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errorCapture.store(errors.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }

        if let standardInput, let input {
            input.fileHandleForWriting.write(standardInput)
            input.fileHandleForWriting.closeFile()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        let timedOut = process.isRunning
        if timedOut {
            process.terminate()
            let terminationDeadline = Date().addingTimeInterval(1)
            while process.isRunning, Date() < terminationDeadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        process.waitUntilExit()
        readers.wait()
        if timedOut { throw FoundationProcessCommandError.timedOut }
        return FoundationProcessCommandResult(
            exitCode: process.terminationStatus,
            stdout: outputCapture.load(),
            stderr: errorCapture.load()
        )
    }
}

private final class FoundationProcessDataCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func store(_ value: Data) {
        lock.lock()
        data = value
        lock.unlock()
    }

    func load() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
