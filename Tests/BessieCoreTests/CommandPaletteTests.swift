import XCTest
@testable import BessieCore

final class CommandPaletteTests: XCTestCase {
    func testOneCharacterQueryFiltersImmediatelyAndIgnoresCase() {
        let alpha = entity(kind: .command, components: ["alpha"], title: "Alpha", detail: "First command")
        let zulu = entity(kind: .command, components: ["zulu"], title: "Zulu", detail: "Last command")

        XCTAssertEqual(
            CommandPaletteSearch().results(query: "P", entities: [alpha, zulu]).map(\.id),
            [alpha.id]
        )
    }

    func testCommandPrefixFindsCommandCenterProject() {
        let commandCenter = entity(
            kind: .project,
            components: ["command-center"],
            title: "Command Center",
            detail: "Project"
        )
        let unrelated = entity(
            kind: .project,
            components: ["bessie"],
            title: "Bessie",
            detail: "Project"
        )
        let search = CommandPaletteSearch()

        XCTAssertEqual(search.results(query: "com", entities: [unrelated, commandCenter]).map(\.id), [commandCenter.id])
        XCTAssertEqual(search.results(query: "command", entities: [unrelated, commandCenter]).map(\.id), [commandCenter.id])
    }

    func testFuzzySubsequenceMatchesInOrderAndRejectsOutOfOrderCharacters() {
        let schema = entity(kind: .project, components: ["schema"], title: "Schema migration", detail: "Project")

        XCTAssertEqual(CommandPaletteSearch().results(query: "shm", entities: [schema]).map(\.id), [schema.id])
        XCTAssertTrue(CommandPaletteSearch().results(query: "smh", entities: [schema]).isEmpty)
    }

    func testExactPrefixWordBoundaryAndContiguousMatchesRankAboveLooseSubsequence() {
        let exact = entity(kind: .command, components: ["exact"], title: "sch", detail: "Command")
        let prefix = entity(kind: .command, components: ["prefix"], title: "schema", detail: "Command")
        let wordBoundary = entity(kind: .command, components: ["word"], title: "open schema", detail: "Command")
        let contiguous = entity(kind: .command, components: ["contiguous"], title: "xxschema", detail: "Command")
        let loose = entity(kind: .command, components: ["loose"], title: "search", detail: "Command")

        XCTAssertEqual(
            CommandPaletteSearch().results(
                query: "sch",
                entities: [loose, contiguous, wordBoundary, prefix, exact]
            ).map(\.id),
            [exact.id, prefix.id, wordBoundary.id, contiguous.id, loose.id]
        )
    }

    func testRankingTiersStayDisjointForLongAndLateMatches() {
        let longPrefix = entity(
            kind: .command,
            components: ["long-prefix"],
            title: "sch" + String(repeating: "x", count: 2_000),
            detail: "Command"
        )
        let lateWordBoundary = entity(
            kind: .command,
            components: ["late-word"],
            title: String(repeating: "x", count: 2_000) + " schema",
            detail: "Command"
        )
        let lateContiguous = entity(
            kind: .command,
            components: ["late-contiguous"],
            title: String(repeating: "x", count: 2_000) + "schema",
            detail: "Command"
        )
        let loose = entity(kind: .command, components: ["loose"], title: "search", detail: "Command")

        XCTAssertEqual(
            CommandPaletteSearch().results(
                query: "sch",
                entities: [loose, lateContiguous, lateWordBoundary, longPrefix]
            ).map(\.id),
            [longPrefix.id, lateWordBoundary.id, lateContiguous.id, loose.id]
        )
    }

    func testLaterWordBoundaryOutranksEarlierEmbeddedOccurrence() {
        let boundary = entity(
            kind: .command,
            components: ["boundary"],
            title: "xcommand command center",
            detail: "Action"
        )
        let contiguous = entity(
            kind: .command,
            components: ["contiguous"],
            title: "xcommand center",
            detail: "Action"
        )

        XCTAssertEqual(
            CommandPaletteSearch().results(query: "command", entities: [contiguous, boundary]).map(\.id),
            [boundary.id, contiguous.id]
        )
    }

    func testTieOrderingIsDeterministicByExistingIdentity() {
        let alpha = entity(kind: .command, components: ["alpha"], title: "map", detail: "Command")
        let zulu = entity(kind: .command, components: ["zulu"], title: "map", detail: "Command")
        let search = CommandPaletteSearch()

        XCTAssertEqual(search.results(query: "m", entities: [zulu, alpha]).map(\.id), [alpha.id, zulu.id])
        XCTAssertEqual(search.results(query: "m", entities: [alpha, zulu]).map(\.id), [alpha.id, zulu.id])
    }

    func testEmptyAndWhitespaceOnlyQueriesRetainUnfilteredCandidateOrder() {
        let zulu = entity(kind: .command, components: ["zulu"], title: "Zulu", detail: "Command")
        let alpha = entity(kind: .pane, components: ["alpha"], title: "Alpha", detail: "Pane")
        let search = CommandPaletteSearch()

        XCTAssertEqual(search.results(query: "", entities: [zulu, alpha]).map(\.id), [zulu.id, alpha.id])
        XCTAssertEqual(search.results(query: "  \t", entities: [zulu, alpha]).map(\.id), [zulu.id, alpha.id])
    }

    func testNoResultsAndMultipleWhitespaceSeparatedTerms() {
        let schema = entity(kind: .project, components: ["schema"], title: "Schema migration", detail: "Local Project")
        let search = CommandPaletteSearch()

        XCTAssertEqual(search.results(query: "  SCH   proj  ", entities: [schema]).map(\.id), [schema.id])
        XCTAssertTrue(search.results(query: "missing", entities: [schema]).isEmpty)
    }

    func testDuplicateLabelsAcrossHerdsKeepCompositeIdentityAndLocation() {
        let local = pane(connection: "local", title: "scratch", location: "Local / bessie / dev")
        let remote = pane(connection: "ci", title: "scratch", location: "CI / bessie / dev")

        let results = CommandPaletteSearch().results(query: "scratch", entities: [remote, local])

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(Set(results.map(\.id.description)), ["pane::local::w::t::p", "pane::ci::w::t::p"])
        XCTAssertEqual(Set(results.compactMap(\.location)), ["Local / bessie / dev", "CI / bessie / dev"])
    }

    func testFuzzyRankingAndDedupAreDeterministicAndDoNotNeedTerminalOutput() {
        let exact = pane(connection: "local", title: "schema", location: "Local / docs / main")
        let fuzzy = entity(kind: .project, components: ["project"], title: "docs schema migration", detail: "Project")
        let duplicate = CommandPaletteEntity(
            id: exact.id, kind: exact.kind, title: exact.title, detail: exact.detail,
            location: nil, route: exact.route
        )

        let first = CommandPaletteSearch().results(query: "sch", entities: [fuzzy, duplicate, exact])
        let second = CommandPaletteSearch().results(query: "sch", entities: [exact, fuzzy, duplicate])

        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first.first?.id, exact.id)
        XCTAssertEqual(first.filter { $0.id == exact.id }.count, 1)
        XCTAssertEqual(first.first?.location, exact.location)
    }

    func testReturnDispatchesOnceAndAlternateRequiresExplicitCommandCapability() {
        let ordinary = pane(connection: "local", title: "shell", location: "Local / main / dev")
        let alternate = CommandPaletteEntity(
            id: .init(kind: .command, components: ["settings"]), kind: .command,
            title: "Settings", detail: "Open settings", route: .command(.showSettings),
            alternateRoute: .command(.showCommandPalette)
        )
        var gate = CommandPaletteDispatchGate()
        XCTAssertNil(gate.take(ordinary, alternate: true))
        XCTAssertEqual(gate.take(alternate, alternate: true), .command(.showCommandPalette))
        XCTAssertNil(gate.take(alternate, alternate: false))

        var returnGate = CommandPaletteDispatchGate()
        XCTAssertEqual(returnGate.take(ordinary, alternate: false), ordinary.route)
        XCTAssertNil(returnGate.take(ordinary, alternate: false))
    }

    func testStaleLiveTargetRequiresAuthoritativeRefreshInsteadOfDispatch() {
        let stale = pane(connection: "removed", title: "shell", location: "Old / main / dev")
        XCTAssertEqual(CommandPaletteTargetResolver.resolve(stale, currentEntityIDs: []), .refreshRequired)
        XCTAssertEqual(
            CommandPaletteTargetResolver.resolve(stale, currentEntityIDs: [stale.id]),
            .dispatch(stale.route)
        )
    }

    func testPaletteKeyboardArrowsReturnAndEscapeWhileSearchFocused() {
        XCTAssertEqual(
            CommandPaletteKeyboard.action(keyCode: CommandPaletteKeyboard.downArrow, command: false, option: false, control: false, shift: false),
            .moveSelection(delta: 1)
        )
        XCTAssertEqual(
            CommandPaletteKeyboard.action(keyCode: CommandPaletteKeyboard.upArrow, command: false, option: false, control: false, shift: false),
            .moveSelection(delta: -1)
        )
        XCTAssertEqual(
            CommandPaletteKeyboard.action(keyCode: CommandPaletteKeyboard.returnKey, command: false, option: false, control: false, shift: false),
            .activate(alternate: false)
        )
        XCTAssertEqual(
            CommandPaletteKeyboard.action(keyCode: CommandPaletteKeyboard.returnKey, command: true, option: false, control: false, shift: false),
            .activate(alternate: true)
        )
        XCTAssertEqual(
            CommandPaletteKeyboard.action(keyCode: CommandPaletteKeyboard.escape, command: false, option: false, control: false, shift: false),
            .dismiss
        )
        // Typing and modified arrows stay with the search field / system.
        XCTAssertEqual(
            CommandPaletteKeyboard.action(keyCode: 5 /* g */, command: false, option: false, control: false, shift: false),
            .ignore
        )
        XCTAssertEqual(
            CommandPaletteKeyboard.action(keyCode: CommandPaletteKeyboard.downArrow, command: true, option: false, control: false, shift: false),
            .ignore
        )
        XCTAssertEqual(CommandPaletteKeyboard.movedSelection(current: 0, delta: 1, count: 3), 1)
        XCTAssertEqual(CommandPaletteKeyboard.movedSelection(current: 2, delta: 1, count: 3), 2)
        XCTAssertEqual(CommandPaletteKeyboard.movedSelection(current: 0, delta: -1, count: 3), 0)
        XCTAssertEqual(CommandPaletteKeyboard.movedSelection(current: 5, delta: 0, count: 2), 1)
        XCTAssertEqual(CommandPaletteKeyboard.movedSelection(current: 0, delta: 1, count: 0), 0)
    }

    private func pane(connection: String, title: String, location: String) -> CommandPaletteEntity {
        CommandPaletteEntity(
            id: .init(kind: .pane, components: [connection, "w", "t", "p"]), kind: .pane,
            title: title, detail: "Agent pane", state: "Working", location: location,
            keywords: ["codex"], route: .pane(connectionID: connection, workspaceID: "w", tabID: "t", paneID: "p")
        )
    }

    private func entity(
        kind: CommandPaletteEntity.Kind,
        components: [String],
        title: String,
        detail: String
    ) -> CommandPaletteEntity {
        CommandPaletteEntity(
            id: .init(kind: kind, components: components), kind: kind, title: title, detail: detail,
            route: .project(UUID())
        )
    }
}
