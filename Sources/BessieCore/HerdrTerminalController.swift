import Foundation

public struct HerdrTerminalEndpoint: Equatable, Sendable {
    public let executablePath: String
    public let socketPath: String

    public init(executablePath: String, socketPath: String) {
        self.executablePath = executablePath
        self.socketPath = socketPath
    }
}

public enum TerminalControllerStatus: Equatable, Sendable {
    case starting
    case waitingForFull
    case ready(grid: TerminalGrid, sequence: UInt64, full: Bool)
    case reconnecting(reason: String)
    case ownershipConflict(String)
    case stopped
    case failed(String)
}

public enum TerminalControllerFailure: Equatable, Sendable {
    case ownershipConflict(String)
    case processExit(String)

    public static func classify(stderr: String, status: Int32) -> TerminalControllerFailure {
        let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.localizedCaseInsensitiveContains("already has an attached client")
            || message.localizedCaseInsensitiveContains("retry with --takeover")
        {
            return .ownershipConflict(message)
        }
        return .processExit(message.isEmpty ? "terminal controller exited \(status)" : message)
    }
}

public enum TerminalReconnectPolicy {
    public static let delays: [TimeInterval] = [0.25, 0.5, 1, 2, 4]
}

public final class HerdrTerminalController: TerminalInputTransport, @unchecked Sendable {
    public typealias FrameHandler = @Sendable (Data) -> Void
    public typealias StateHandler = @Sendable (TerminalControllerStatus) -> Void

    private let executablePath: String
    private let paneID: String
    private let socketPath: String
    private let environment: [String: String]
    private let onFrame: FrameHandler
    private let onState: StateHandler
    private let queue = DispatchQueue(label: "bessie.terminal.controller.\(UUID().uuidString)")
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputFramer = NDJSONFramer()
    private var stderr = ""
    private var sequencer: TerminalFrameSequencer
    private var grid: TerminalGrid
    private var cellWidthPixels = 0
    private var cellHeightPixels = 0
    private var pendingResize: DispatchWorkItem?
    private var active = false
    private var restartWhenProcessExits = false
    private var restartAttempt = 0
    private var mode: TerminalSessionMode = .control
    private let restartDelays = TerminalReconnectPolicy.delays
    private let stderrLimit = 16_384

    public init(
        executablePath: String,
        paneID: String,
        socketPath: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        initialGrid: TerminalGrid = TerminalGrid(columns: 80, rows: 24),
        onFrame: @escaping FrameHandler,
        onState: @escaping StateHandler
    ) {
        self.executablePath = executablePath
        self.paneID = paneID
        self.socketPath = socketPath
        self.environment = environment
        self.grid = initialGrid
        sequencer = TerminalFrameSequencer(grid: initialGrid)
        self.onFrame = onFrame
        self.onState = onState
    }

    public func start() {
        start(mode: .control)
    }

    public func observe() {
        start(mode: .observe)
    }

    public func takeOver() {
        queue.async { [weak self] in
            guard let self else { return }
            if active || process != nil {
                guard mode == .observe else { return }
                restartWhenProcessExits = false
                pendingResize?.cancel()
                pendingResize = nil
                try? write(.release)
                try? inputHandle?.close()
                inputHandle = nil
                if let process {
                    (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
                    (process.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
                    process.terminationHandler = nil
                    if process.isRunning { process.terminate() }
                }
                process = nil
                active = false
            }
            mode = .takeover
            active = true
            restartAttempt = 0
            launch()
        }
    }

    public func retry() {
        queue.async { [weak self] in
            guard let self, !active, process == nil else { return }
            if mode == .takeover { mode = .control }
            active = true
            restartAttempt = 0
            launch()
        }
    }

    public func release() {
        queue.sync {
            guard active || process != nil else { return }
            active = false
            restartWhenProcessExits = false
            pendingResize?.cancel()
            pendingResize = nil
            try? write(.release)
            try? inputHandle?.close()
            inputHandle = nil
            if process?.isRunning == true { process?.terminate() }
            process = nil
            onState(.stopped)
        }
    }

    public func reconnect(reason: String) {
        queue.async { [weak self] in self?.beginReconnect(reason: reason) }
    }

    public func requestResize(
        grid: TerminalGrid,
        cellWidthPixels: Int,
        cellHeightPixels: Int,
        debounce: TimeInterval = 0.08
    ) {
        guard grid.columns > 0, grid.rows > 0 else { return }
        queue.async { [weak self] in
            guard let self, active, mode != .observe else { return }
            let nextCellWidth = max(0, cellWidthPixels)
            let nextCellHeight = max(0, cellHeightPixels)
            guard self.grid != grid
                    || self.cellWidthPixels != nextCellWidth
                    || self.cellHeightPixels != nextCellHeight
            else { return }
            self.grid = grid
            self.cellWidthPixels = nextCellWidth
            self.cellHeightPixels = nextCellHeight
            self.sequencer.requestGrid(grid)
            self.onState(.waitingForFull)
            self.pendingResize?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, active else { return }
                do {
                    try write(.resize(grid, cellWidthPixels: self.cellWidthPixels, cellHeightPixels: self.cellHeightPixels))
                } catch {
                    beginReconnect(reason: "terminal resize failed: \(error.localizedDescription)")
                }
            }
            pendingResize = work
            queue.asyncAfter(deadline: .now() + debounce, execute: work)
        }
    }

    public func sendRaw(_ data: Data) throws {
        try queue.sync {
            try requireReady()
            try write(.input(data))
        }
    }

    public func sendKeys(_ keys: [String]) throws {
        try queue.sync {
            try requireReady()
            _ = try HerdrSocketAPI(socketPath: socketPath).request(
                method: "pane.send_keys",
                params: ["pane_id": .string(paneID), "keys": .array(keys.map(JSONValue.string))]
            )
        }
    }

    public func sendPaste(_ text: String) throws {
        try queue.sync {
            try requireReady()
            _ = try HerdrSocketAPI(socketPath: socketPath).request(
                method: "pane.send_input",
                params: ["pane_id": .string(paneID), "text": .string(text), "keys": .array([])]
            )
        }
    }

    public func sendScroll(direction: TerminalScrollDirection, lines: Int, source: TerminalScrollSource, column: Int?, row: Int?, modifiers: Int) throws {
        try queue.sync {
            try requireReady()
            try write(.scroll(direction: direction, lines: max(1, lines), source: source, column: column, row: row, modifiers: modifiers))
        }
    }

    private func requireReady() throws {
        guard active, mode != .observe, sequencer.acceptsInput else {
            throw HerdrClientError.process(path: executablePath, message: "terminal is waiting for a writable Herdr frame")
        }
    }

    private func launch() {
        guard active, process == nil else { return }
        onState(.starting)
        sequencer.reset(grid: grid)
        outputFramer = NDJSONFramer()
        stderr = ""
        let launchMode = mode
        let invocation = HerdrTerminalProcessInvocation(
            executablePath: executablePath,
            paneID: paneID,
            grid: grid,
            mode: launchMode
        )
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: invocation.executablePath)
        process.arguments = invocation.arguments
        var processEnvironment = environment
        processEnvironment["HERDR_SOCKET_PATH"] = socketPath
        process.environment = processEnvironment
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.enqueueOutput(data)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.enqueueError(data)
        }
        process.terminationHandler = { [weak self] terminated in
            self?.enqueueExit(terminated)
        }
        do {
            try process.run()
            if launchMode == .takeover { mode = .control }
            self.process = process
            inputHandle = inputPipe.fileHandleForWriting
            onState(.waitingForFull)
        } catch {
            self.process = nil
            inputHandle = nil
            active = false
            onState(.failed("could not launch terminal controller: \(error.localizedDescription)"))
        }
    }

    private func enqueueOutput(_ data: Data) {
        queue.async { [weak self] in self?.consume(data) }
    }

    private func enqueueError(_ data: Data) {
        queue.async { [weak self] in
            guard let self else { return }
            stderr += String(decoding: data, as: UTF8.self)
            if stderr.utf8.count > stderrLimit { stderr = String(stderr.suffix(stderrLimit)) }
        }
    }

    private func enqueueExit(_ exitedProcess: Process) {
        queue.async { [weak self] in
            self?.processExited(exitedProcess, status: exitedProcess.terminationStatus)
        }
    }

    private func consume(_ data: Data) {
        do {
            for line in try outputFramer.append(data) {
                switch try HerdrTerminalEnvelope.decode(Data(line.utf8)) {
                case .frame(let frame):
                    switch sequencer.accept(frame) {
                    case .apply(let bytes):
                        if frame.full { restartAttempt = 0 }
                        onFrame(bytes)
                        onState(.ready(grid: frame.grid, sequence: frame.sequence, full: frame.full))
                    case .ignored: break
                    case .waitingForFull: onState(.waitingForFull)
                    case .reconnect(let reason): beginReconnect(reason: reason)
                    }
                case .closed(let reason):
                    beginReconnect(reason: reason)
                }
            }
        } catch {
            beginReconnect(reason: "invalid terminal stream: \(error.localizedDescription)")
        }
    }

    private func beginReconnect(reason: String) {
        guard active, !restartWhenProcessExits else { return }
        onState(.reconnecting(reason: reason))
        sequencer.reset(grid: grid)
        restartWhenProcessExits = true
        try? write(.release)
        try? inputHandle?.close()
        inputHandle = nil
        if process?.isRunning != true {
            let old = process
            process = nil
            processExited(old, status: old?.terminationStatus ?? 0)
        }
    }

    private func processExited(_ exitedProcess: Process?, status: Int32) {
        guard exitedProcess === process || process == nil else { return }
        process = nil
        inputHandle = nil
        if restartWhenProcessExits, active {
            restartWhenProcessExits = false
            scheduleRestart(reason: "terminal controller reconnect failed")
            return
        }
        guard active else { return }
        switch TerminalControllerFailure.classify(stderr: stderr, status: status) {
        case .ownershipConflict(let message):
            active = false
            onState(.ownershipConflict(message))
        case .processExit(let message):
            onState(.reconnecting(reason: message))
            scheduleRestart(reason: message)
        }
    }

    private func scheduleRestart(reason: String) {
        guard active else { return }
        guard restartDelays.indices.contains(restartAttempt) else {
            active = false
            onState(.failed("terminal controller retry budget exhausted: \(reason)"))
            return
        }
        let delay = restartDelays[restartAttempt]
        restartAttempt += 1
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, active, process == nil else { return }
            launch()
        }
    }

    private func start(mode: TerminalSessionMode) {
        queue.async { [weak self] in
            guard let self, !active, process == nil else { return }
            self.mode = mode
            active = true
            restartAttempt = 0
            launch()
        }
    }

    private func write(_ command: TerminalControlCommand) throws {
        guard let inputHandle else {
            throw HerdrClientError.process(path: executablePath, message: "terminal controller stdin is unavailable")
        }
        try inputHandle.write(contentsOf: command.lineData())
    }
}
