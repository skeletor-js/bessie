import Foundation

public enum GhosttyCompatibilityClassification: String, Equatable, Sendable {
    case applied
    case overridden
    case ignored
    case unsupported
    case invalid
}

public enum GhosttyCompatibilityCursorStyle: String, Equatable, Sendable {
    case block
    case bar
    case underline
}

public struct GhosttyCompatibilityAssignment: Equatable, Sendable {
    public let key: String
    public let value: String
    public let sourceURL: URL
    public let line: Int
    public var classification: GhosttyCompatibilityClassification

    public init(
        key: String,
        value: String,
        sourceURL: URL,
        line: Int,
        classification: GhosttyCompatibilityClassification
    ) {
        self.key = key
        self.value = value
        self.sourceURL = sourceURL
        self.line = line
        self.classification = classification
    }
}

public struct GhosttyCompatibilityValues: Equatable, Sendable {
    public var fontFamilies: [String]
    public var fontFamilyWasReset: Bool
    public var fontThicken: Bool?
    public var fontThickenStrength: Int?
    public var cursorStyle: GhosttyCompatibilityCursorStyle?
    public var cursorStyleBlink: Bool?

    public init(
        fontFamilies: [String] = [],
        fontFamilyWasReset: Bool = false,
        fontThicken: Bool? = nil,
        fontThickenStrength: Int? = nil,
        cursorStyle: GhosttyCompatibilityCursorStyle? = nil,
        cursorStyleBlink: Bool? = nil
    ) {
        self.fontFamilies = fontFamilies
        self.fontFamilyWasReset = fontFamilyWasReset
        self.fontThicken = fontThicken
        self.fontThickenStrength = fontThickenStrength
        self.cursorStyle = cursorStyle
        self.cursorStyleBlink = cursorStyleBlink
    }
}

public struct GhosttyCompatibilityProfile: Equatable, Sendable {
    public let rootURL: URL
    public let resolvedFiles: [URL]
    public let assignments: [GhosttyCompatibilityAssignment]
    public let effective: GhosttyCompatibilityValues

    public init(
        rootURL: URL,
        resolvedFiles: [URL],
        assignments: [GhosttyCompatibilityAssignment],
        effective: GhosttyCompatibilityValues
    ) {
        self.rootURL = rootURL
        self.resolvedFiles = resolvedFiles
        self.assignments = assignments
        self.effective = effective
    }

    public var isValid: Bool {
        !assignments.contains { $0.classification == .invalid }
    }
}

public struct GhosttyCompatibilityLimits: Equatable, Sendable {
    public var maximumImportDepth: Int
    public var maximumFiles: Int
    public var maximumBytes: Int

    public init(maximumImportDepth: Int = 8, maximumFiles: Int = 32, maximumBytes: Int = 1_048_576) {
        self.maximumImportDepth = maximumImportDepth
        self.maximumFiles = maximumFiles
        self.maximumBytes = maximumBytes
    }
}

public enum GhosttyCompatibilityError: Error, Equatable, Sendable {
    case unreadableFile(URL)
    case invalidUTF8
    case importDepthExceeded
    case fileCountExceeded
    case byteCountExceeded
}

public struct GhosttyCompatibilityParser {
    public typealias FileLoader = (URL) throws -> Data

    private let limits: GhosttyCompatibilityLimits
    private let fileLoader: FileLoader

    public init(
        limits: GhosttyCompatibilityLimits = .init(),
        fileLoader: FileLoader? = nil
    ) {
        self.limits = limits
        self.fileLoader = fileLoader ?? Self.boundedRegularFileLoader(maximumBytes: limits.maximumBytes)
    }

    public func parse(_ selectedURL: URL) throws -> GhosttyCompatibilityProfile {
        let root = canonical(selectedURL)
        var state = ParseState()
        do {
            try loadFile(root, depth: 0, state: &state)
        } catch let error as GhosttyCompatibilityError {
            throw error
        } catch {
            throw GhosttyCompatibilityError.unreadableFile(root)
        }

        while !state.pendingImports.isEmpty {
            let pending = state.pendingImports.removeFirst()
            if state.visited.contains(pending.url) {
                state.assignments[pending.assignmentIndex].classification = .invalid
                continue
            }
            do {
                try loadFile(pending.url, depth: pending.depth, state: &state)
            } catch let failure as FileLoadFailure {
                if !pending.optional || !failure.isMissing {
                    state.assignments[pending.assignmentIndex].classification = .invalid
                }
            }
        }

        return GhosttyCompatibilityProfile(
            rootURL: root,
            resolvedFiles: state.resolvedFiles,
            assignments: state.assignments,
            effective: state.effective
        )
    }

    private func loadFile(_ url: URL, depth: Int, state: inout ParseState) throws {
        guard depth <= limits.maximumImportDepth else {
            throw GhosttyCompatibilityError.importDepthExceeded
        }
        guard state.resolvedFiles.count < limits.maximumFiles else {
            throw GhosttyCompatibilityError.fileCountExceeded
        }
        guard limits.maximumBytes >= 0, state.byteCount <= limits.maximumBytes else {
            throw GhosttyCompatibilityError.byteCountExceeded
        }

        let fileURL = canonical(url)
        let data: Data
        do {
            data = try fileLoader(fileURL)
        } catch {
            throw FileLoadFailure(url: fileURL, isMissing: Self.isMissingFileError(error))
        }
        guard data.count <= limits.maximumBytes - state.byteCount else {
            throw GhosttyCompatibilityError.byteCountExceeded
        }
        guard let contents = String(data: data, encoding: .utf8) else {
            throw GhosttyCompatibilityError.invalidUTF8
        }

        state.visited.insert(fileURL)
        state.resolvedFiles.append(fileURL)
        state.byteCount += data.count
        parseContents(contents, sourceURL: fileURL, depth: depth, state: &state)
    }

    private func parseContents(
        _ contents: String,
        sourceURL: URL,
        depth: Int,
        state: inout ParseState
    ) {
        for (offset, rawLine) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = offset + 1
            let line = rawLine.trimmingCharacters(in: Self.lineWhitespace)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let equals = line.firstIndex(of: "=") else {
                state.appendAssignment(
                    key: "",
                    value: "<redacted>",
                    sourceURL: sourceURL,
                    line: lineNumber,
                    classification: .invalid
                )
                continue
            }

            let key = line[..<equals].trimmingCharacters(in: Self.horizontalWhitespace).lowercased()
            let rawValue = String(line[line.index(after: equals)...].trimmingCharacters(in: Self.horizontalWhitespace))
            let parsedValue = Self.parseGenericValue(rawValue)
            guard !key.isEmpty else {
                state.appendAssignment(
                    key: key,
                    value: "<redacted>",
                    sourceURL: sourceURL,
                    line: lineNumber,
                    classification: .invalid
                )
                continue
            }

            if key == "config-file" {
                parseImport(
                    rawValue: rawValue,
                    parsedValue: parsedValue,
                    sourceURL: sourceURL,
                    line: lineNumber,
                    depth: depth,
                    state: &state
                )
            } else {
                parseAssignment(
                    key: key,
                    value: parsedValue.text,
                    sourceURL: sourceURL,
                    line: lineNumber,
                    state: &state
                )
            }
        }
    }

    private func parseImport(
        rawValue: String,
        parsedValue: ParsedValue,
        sourceURL: URL,
        line: Int,
        depth: Int,
        state: inout ParseState
    ) {
        let assignmentIndex = state.appendAssignment(
            key: "config-file",
            value: parsedValue.text.isEmpty ? "" : "<redacted>",
            sourceURL: sourceURL,
            line: line,
            classification: .ignored
        )

        // Ghostty's RepeatablePath uses an unquoted empty assignment to clear all
        // imports accumulated so far. A quoted empty string is only a no-op.
        if rawValue.isEmpty {
            state.pendingImports.removeAll()
            return
        }
        guard !parsedValue.text.isEmpty else { return }

        var path = parsedValue.text
        var optional = false
        if !parsedValue.wasQuoted, path.hasPrefix("?") {
            optional = true
            path.removeFirst()
            path = Self.parseGenericValue(path).text
        }
        guard !path.isEmpty, Self.isBoundedSafeString(path) else {
            state.assignments[assignmentIndex].classification = .invalid
            return
        }

        let expanded = (path as NSString).expandingTildeInPath
        let importURL: URL
        if expanded.hasPrefix("/") {
            importURL = URL(fileURLWithPath: expanded)
        } else {
            importURL = URL(fileURLWithPath: expanded, relativeTo: sourceURL.deletingLastPathComponent())
        }
        state.pendingImports.append(.init(
            url: canonical(importURL),
            depth: depth + 1,
            optional: optional,
            assignmentIndex: assignmentIndex
        ))
    }

    private func parseAssignment(
        key: String,
        value: String,
        sourceURL: URL,
        line: Int,
        state: inout ParseState
    ) {
        if Self.ignoredKeys.contains(key) || Self.ignoredPrefixes.contains(where: { key.hasPrefix($0) }) {
            state.appendAssignment(
                key: key,
                value: "<redacted>",
                sourceURL: sourceURL,
                line: line,
                classification: .ignored
            )
            return
        }
        if Self.knownUnsupportedKeys.contains(key) {
            state.appendAssignment(
                key: key,
                value: "<redacted>",
                sourceURL: sourceURL,
                line: line,
                classification: .unsupported
            )
            return
        }

        let assignmentIndex = state.appendAssignment(
            key: key,
            value: Self.allowlistedKeys.contains(key) ? Self.boundedDiagnosticValue(value) : "<redacted>",
            sourceURL: sourceURL,
            line: line,
            classification: .invalid
        )
        switch key {
        case "font-family":
            guard value.isEmpty || Self.isBoundedSafeString(value) else { return }
            state.applyFontFamily(value, assignmentIndex: assignmentIndex)
        case "font-style", "font-style-bold", "font-style-italic", "font-style-bold-italic":
            guard value.isEmpty || Self.isBoundedSafeString(value) else { return }
            // Pinned libghostty-spm 1.3.2 has no typed builder commands for
            // font-style keys. Keep them inside the strict recognized allowlist,
            // but report them honestly instead of using the untyped escape hatch.
            state.applyUnsupportedScalar(slot: key, assignmentIndex: assignmentIndex)
        case "font-thicken":
            if value.isEmpty {
                state.applyScalar(slot: key, assignmentIndex: assignmentIndex)
                state.effective.fontThicken = nil
            } else if let parsed = Self.parseBoolean(value) {
                state.applyScalar(slot: key, assignmentIndex: assignmentIndex)
                state.effective.fontThicken = parsed
            }
        case "font-thicken-strength":
            if value.isEmpty {
                state.applyScalar(slot: key, assignmentIndex: assignmentIndex)
                state.effective.fontThickenStrength = nil
            } else if let parsed = Int(value), (0...255).contains(parsed) {
                state.applyScalar(slot: key, assignmentIndex: assignmentIndex)
                state.effective.fontThickenStrength = parsed
            }
        case "cursor-style":
            if value.isEmpty {
                state.applyScalar(slot: key, assignmentIndex: assignmentIndex)
                state.effective.cursorStyle = nil
            } else if value == "block_hollow" {
                state.applyUnsupportedScalar(slot: key, assignmentIndex: assignmentIndex)
                state.effective.cursorStyle = nil
            } else if let style = GhosttyCompatibilityCursorStyle(rawValue: value) {
                state.applyScalar(slot: key, assignmentIndex: assignmentIndex)
                state.effective.cursorStyle = style
            }
        case "cursor-style-blink":
            if value.isEmpty {
                state.applyScalar(slot: key, assignmentIndex: assignmentIndex)
                state.effective.cursorStyleBlink = nil
            } else if let parsed = Self.parseBoolean(value) {
                state.applyScalar(slot: key, assignmentIndex: assignmentIndex)
                state.effective.cursorStyleBlink = parsed
            }
        default:
            break
        }
    }

    private func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func parseGenericValue(_ value: String) -> ParsedValue {
        guard value.count >= 2, value.first == "\"", value.last == "\"" else {
            return ParsedValue(text: value, wasQuoted: false)
        }
        return ParsedValue(text: String(value.dropFirst().dropLast()), wasQuoted: true)
    }

    private static func parseBoolean(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "true", "t", "yes", "y", "on", "1": true
        case "false", "f", "no", "n", "off", "0": false
        default: nil
        }
    }

    private static func isMissingFileError(_ error: Error) -> Bool {
        let cocoa = error as NSError
        guard cocoa.domain == NSCocoaErrorDomain else { return false }
        return cocoa.code == CocoaError.Code.fileNoSuchFile.rawValue
            || cocoa.code == CocoaError.Code.fileReadNoSuchFile.rawValue
    }

    private static func isBoundedSafeString(_ value: String) -> Bool {
        value.utf8.count <= maximumDiagnosticValueBytes
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    private static func boundedDiagnosticValue(_ value: String) -> String {
        guard value.utf8.count > maximumDiagnosticValueBytes else { return value }
        var result = ""
        for character in value {
            guard result.utf8.count + String(character).utf8.count <= maximumDiagnosticValueBytes else { break }
            result.append(character)
        }
        return result + "…"
    }

    private static func boundedRegularFileLoader(maximumBytes: Int) -> FileLoader {
        let byteLimit = max(0, maximumBytes)
        return { url in
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { throw CocoaError(.fileReadUnsupportedScheme) }
            if let fileSize = values.fileSize, fileSize > byteLimit {
                return Data(repeating: 0, count: byteLimit == Int.max ? byteLimit : byteLimit + 1)
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            return try handle.read(upToCount: byteLimit == Int.max ? byteLimit : byteLimit + 1) ?? Data()
        }
    }

    private static let maximumDiagnosticValueBytes = 256
    private static let horizontalWhitespace = CharacterSet(charactersIn: " \t")
    private static let lineWhitespace = CharacterSet(charactersIn: " \t\r")
    private static let allowlistedKeys: Set<String> = [
        "font-family", "font-style", "font-style-bold", "font-style-italic", "font-style-bold-italic",
        "font-thicken", "font-thicken-strength", "cursor-style", "cursor-style-blink",
    ]

    // These settings are owned by Herdr/Bessie and never forwarded. Their values
    // are redacted because diagnostics need the key and provenance, not commands,
    // paths, input policy, or other potentially sensitive content.
    private static let ignoredKeys: Set<String> = [
        "command", "initial-command", "working-directory", "keybind", "mouse-reporting",
        "mouse-hide-while-typing", "macos-option-as-alt", "auto-update", "auto-update-channel",
        "quit-after-last-window-closed", "confirm-close-surface", "shell-integration",
    ]
    private static let ignoredPrefixes = ["window-", "mouse-", "keybind", "macos-", "clipboard-", "osc-"]

    // Known Ghostty settings outside the nine-key compatibility allowlist.
    private static let knownUnsupportedKeys: Set<String> = [
        "font-family-bold", "font-family-italic", "font-family-bold-italic", "font-size", "font-feature",
        "font-variation", "font-variation-bold", "font-variation-italic", "font-variation-bold-italic",
        "foreground", "background", "palette", "selection-foreground", "selection-background",
        "cursor-color", "cursor-text", "cursor-opacity", "bold-color", "minimum-contrast", "theme",
        "background-opacity", "background-blur", "background-blur-radius", "unfocused-split-opacity",
    ]
}

private struct ParsedValue {
    let text: String
    let wasQuoted: Bool
}

private struct PendingImport {
    let url: URL
    let depth: Int
    let optional: Bool
    let assignmentIndex: Int
}

private struct FileLoadFailure: Error {
    let url: URL
    let isMissing: Bool
}

private struct ParseState {
    var visited: Set<URL> = []
    var resolvedFiles: [URL] = []
    var byteCount = 0
    var pendingImports: [PendingImport] = []
    var assignments: [GhosttyCompatibilityAssignment] = []
    var effective = GhosttyCompatibilityValues()
    var effectiveAssignmentBySlot: [String: Int] = [:]
    var effectiveFontFamilyAssignments: [Int] = []

    @discardableResult
    mutating func appendAssignment(
        key: String,
        value: String,
        sourceURL: URL,
        line: Int,
        classification: GhosttyCompatibilityClassification
    ) -> Int {
        assignments.append(.init(
            key: key,
            value: value,
            sourceURL: sourceURL,
            line: line,
            classification: classification
        ))
        return assignments.count - 1
    }

    mutating func applyScalar(slot: String, assignmentIndex: Int) {
        if let prior = effectiveAssignmentBySlot[slot], assignments[prior].classification == .applied {
            assignments[prior].classification = .overridden
        }
        assignments[assignmentIndex].classification = .applied
        effectiveAssignmentBySlot[slot] = assignmentIndex
    }

    mutating func applyUnsupportedScalar(slot: String, assignmentIndex: Int) {
        if let prior = effectiveAssignmentBySlot[slot], assignments[prior].classification == .applied {
            assignments[prior].classification = .overridden
        }
        assignments[assignmentIndex].classification = .unsupported
        effectiveAssignmentBySlot[slot] = assignmentIndex
    }

    mutating func applyFontFamily(_ value: String, assignmentIndex: Int) {
        if value.isEmpty {
            for prior in effectiveFontFamilyAssignments where assignments[prior].classification == .applied {
                assignments[prior].classification = .overridden
            }
            effectiveFontFamilyAssignments = [assignmentIndex]
            effective.fontFamilies.removeAll()
            effective.fontFamilyWasReset = true
        } else {
            effectiveFontFamilyAssignments.append(assignmentIndex)
            effective.fontFamilies.append(value)
        }
        assignments[assignmentIndex].classification = .applied
    }
}
