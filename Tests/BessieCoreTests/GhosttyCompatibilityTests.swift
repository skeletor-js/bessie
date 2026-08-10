import Foundation
import XCTest
@testable import BessieCore

final class GhosttyCompatibilityTests: XCTestCase {
    func testParserUsesGhosttyImportOrderAndRetainsBoundedProvenanceAndClassifications() throws {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let selected = root.appendingPathComponent("config")
        let first = nested.appendingPathComponent("first.conf")
        let second = root.appendingPathComponent("second.conf")
        try """
        font-thicken = true
        config-file = "nested/first.conf"
        cursor-style = bar
        font-thicken = false
        """.write(to: selected, atomically: true, encoding: .utf8)
        try """
          # Indented full-line comments are ignored.
        font-family = "JetBrains Mono "
        config-file = ../second.conf
        cursor-style = underline
        """.write(to: first, atomically: true, encoding: .utf8)
        try """
        font-family =
        font-family = Symbols Nerd Font
        font-thicken-strength = 128
        cursor-style-blink = false
        command = /bin/echo secret-token
        foreground = #123456
        """.write(to: second, atomically: true, encoding: .utf8)

        let profile = try GhosttyCompatibilityParser().parse(selected)

        XCTAssertEqual(profile.resolvedFiles, [selected, first, second].map { $0.resolvingSymlinksInPath() })
        XCTAssertEqual(profile.effective.fontFamilies, ["Symbols Nerd Font"])
        XCTAssertTrue(profile.effective.fontFamilyWasReset)
        XCTAssertEqual(profile.effective.fontThicken, false)
        XCTAssertEqual(profile.effective.fontThickenStrength, 128)
        XCTAssertEqual(profile.effective.cursorStyle, .underline)
        XCTAssertEqual(profile.effective.cursorStyleBlink, false)
        XCTAssertTrue(profile.isValid)
        XCTAssertEqual(profile.assignments.map(\.classification), [
            .overridden, .ignored, .overridden, .applied,
            .overridden, .ignored, .applied,
            .applied, .applied, .applied, .applied, .ignored, .unsupported,
        ])
        XCTAssertEqual(profile.assignments[4].value, "JetBrains Mono ")
        XCTAssertEqual(profile.assignments[11].value, "<redacted>")
        XCTAssertEqual(profile.assignments[4].sourceURL, first.resolvingSymlinksInPath())
        XCTAssertEqual(profile.assignments[4].line, 2)
    }

    func testParserPreservesRepeatableFamiliesAndEmptyResetSemantics() throws {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let selected = root.appendingPathComponent("config")
        try """
        font-family = Primary
        font-family = Fallback
        font-family =
        font-family = "Replacement "
        font-family = Symbols # this is literal, not an inline comment
        """.write(to: selected, atomically: true, encoding: .utf8)

        let profile = try GhosttyCompatibilityParser().parse(selected)

        XCTAssertEqual(profile.effective.fontFamilies, ["Replacement ", "Symbols # this is literal, not an inline comment"])
        XCTAssertTrue(profile.effective.fontFamilyWasReset)
        XCTAssertEqual(profile.assignments.map(\.classification), [
            .overridden, .overridden, .applied, .applied, .applied,
        ])
    }

    func testImportResetInsideReplayDropsPendingImportsButStillLoadsLaterImports() throws {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let selected = root.appendingPathComponent("config")
        try "config-file = first\nconfig-file = skipped".write(to: selected, atomically: true, encoding: .utf8)
        try "config-file =\nconfig-file = replacement".write(
            to: root.appendingPathComponent("first"), atomically: true, encoding: .utf8
        )
        try "font-thicken = false".write(
            to: root.appendingPathComponent("skipped"), atomically: true, encoding: .utf8
        )
        try "font-thicken = true".write(
            to: root.appendingPathComponent("replacement"), atomically: true, encoding: .utf8
        )

        let profile = try GhosttyCompatibilityParser().parse(selected)

        XCTAssertEqual(profile.resolvedFiles.map(\.lastPathComponent), ["config", "first", "replacement"])
        XCTAssertEqual(profile.effective.fontThicken, true)
    }

    func testParserMarksCyclesDuplicatesRequiredMissingImportsAndInvalidValuesInvalid() throws {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let selected = root.appendingPathComponent("config")
        let imported = root.appendingPathComponent("imported")
        try """
        config-file = imported
        config-file = imported
        config-file = ?optional-missing
        config-file = required-missing
        cursor-style = beam
        cursor-style-blink = maybe
        font-thicken = yes
        font-thicken-strength = 256
        unknown-setting = value
        """.write(to: selected, atomically: true, encoding: .utf8)
        try "config-file = config".write(to: imported, atomically: true, encoding: .utf8)

        let profile = try GhosttyCompatibilityParser().parse(selected)

        XCTAssertEqual(profile.resolvedFiles, [selected, imported].map { $0.resolvingSymlinksInPath() })
        XCTAssertEqual(profile.assignments.map(\.classification), [
            .ignored, .invalid, .ignored, .invalid, .invalid, .invalid, .applied, .invalid, .invalid,
            .invalid,
        ])
        XCTAssertFalse(profile.isValid)
    }

    func testParserClassifiesAllowlistedValuesMissingTypedBuilderCoverageHonestly() throws {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let selected = root.appendingPathComponent("config")
        try """
        font-style = Book
        font-style-bold = false
        font-style-italic = default
        font-style-bold-italic = Bold Italic
        cursor-style = block_hollow
        """.write(to: selected, atomically: true, encoding: .utf8)

        let profile = try GhosttyCompatibilityParser().parse(selected)

        XCTAssertTrue(profile.isValid)
        XCTAssertEqual(profile.assignments.map(\.classification), Array(repeating: .unsupported, count: 5))
        XCTAssertNil(profile.effective.cursorStyle)
    }

    func testValidUnsupportedCursorStyleOverridesEarlierTypedValueWithoutResurrectingIt() throws {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let selected = root.appendingPathComponent("config")
        try """
        cursor-style = bar
        cursor-style = block_hollow
        """.write(to: selected, atomically: true, encoding: .utf8)

        let profile = try GhosttyCompatibilityParser().parse(selected)

        XCTAssertTrue(profile.isValid)
        XCTAssertEqual(profile.assignments.map(\.classification), [.overridden, .unsupported])
        XCTAssertNil(profile.effective.cursorStyle)
    }

    func testParserMatchesGhosttyBooleanAliasesAndCaseSensitiveCursorValues() throws {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let selected = root.appendingPathComponent("config")
        try """
        font-thicken = 1
        cursor-style-blink = F
        cursor-style = BAR
        """.write(to: selected, atomically: true, encoding: .utf8)

        let profile = try GhosttyCompatibilityParser().parse(selected)

        XCTAssertEqual(profile.effective.fontThicken, true)
        XCTAssertEqual(profile.effective.cursorStyleBlink, false)
        XCTAssertNil(profile.effective.cursorStyle)
        XCTAssertEqual(profile.assignments.map(\.classification), [.applied, .applied, .invalid])
        XCTAssertFalse(profile.isValid)
    }

    func testOptionalImportSuppressesOnlyMissingFiles() throws {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let selected = root.appendingPathComponent("config")
        try """
        config-file = ?missing
        config-file = ?denied
        """.write(to: selected, atomically: true, encoding: .utf8)
        let parser = GhosttyCompatibilityParser(fileLoader: { url in
            if url.lastPathComponent == "missing" { throw CocoaError(.fileNoSuchFile) }
            if url.lastPathComponent == "denied" { throw CocoaError(.fileReadNoPermission) }
            return try Data(contentsOf: url)
        })

        let profile = try parser.parse(selected)

        XCTAssertEqual(profile.assignments.map(\.classification), [.ignored, .invalid])
        XCTAssertFalse(profile.isValid)
    }

    func testParserEnforcesDepthFileAndAggregateByteBounds() throws {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first")
        let second = root.appendingPathComponent("second")
        let third = root.appendingPathComponent("third")
        try "config-file = second".write(to: first, atomically: true, encoding: .utf8)
        try "config-file = third".write(to: second, atomically: true, encoding: .utf8)
        try "font-thicken = true".write(to: third, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try GhosttyCompatibilityParser(
            limits: .init(maximumImportDepth: 1, maximumFiles: 8, maximumBytes: 1_024)
        ).parse(first)) { XCTAssertEqual($0 as? GhosttyCompatibilityError, .importDepthExceeded) }
        XCTAssertThrowsError(try GhosttyCompatibilityParser(
            limits: .init(maximumImportDepth: 8, maximumFiles: 2, maximumBytes: 1_024)
        ).parse(first)) { XCTAssertEqual($0 as? GhosttyCompatibilityError, .fileCountExceeded) }
        XCTAssertThrowsError(try GhosttyCompatibilityParser(
            limits: .init(maximumImportDepth: 8, maximumFiles: 8, maximumBytes: 20)
        ).parse(first)) { XCTAssertEqual($0 as? GhosttyCompatibilityError, .byteCountExceeded) }
    }

    func testParserRejectsUnreadableRootAndNonUTF8Content() throws {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let invalid = root.appendingPathComponent("invalid")
        try Data([0xff]).write(to: invalid)

        XCTAssertThrowsError(try GhosttyCompatibilityParser().parse(root.appendingPathComponent("missing"))) {
            guard case .unreadableFile = $0 as? GhosttyCompatibilityError else { return XCTFail("\($0)") }
        }
        XCTAssertThrowsError(try GhosttyCompatibilityParser().parse(invalid)) {
            XCTAssertEqual($0 as? GhosttyCompatibilityError, .invalidUTF8)
        }
    }

    func testPreferencesPersistOnlyCompatibilityEnablementAndSelectedPathWithLegacyDefaults() throws {
        let preferences = BessiePreferences(
            ghosttyCompatibilityEnabled: true,
            ghosttyCompatibilitySelectedPath: "/tmp/ghostty-config"
        )
        let data = try JSONEncoder().encode(preferences)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["ghosttyCompatibilityEnabled"] as? Bool, true)
        XCTAssertEqual(json["ghosttyCompatibilitySelectedPath"] as? String, "/tmp/ghostty-config")
        XCTAssertFalse(json.keys.contains { $0.localizedCaseInsensitiveContains("content") || $0.localizedCaseInsensitiveContains("profile") || $0.localizedCaseInsensitiveContains("watch") })
        XCTAssertEqual(try JSONDecoder().decode(BessiePreferences.self, from: data), preferences)

        let legacy = try JSONDecoder().decode(BessiePreferences.self, from: Data("{}".utf8))
        XCTAssertFalse(legacy.ghosttyCompatibilityEnabled)
        XCTAssertNil(legacy.ghosttyCompatibilitySelectedPath)
    }

    private func makeFixtureDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
