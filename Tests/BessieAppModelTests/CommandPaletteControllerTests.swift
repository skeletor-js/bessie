import XCTest
@testable import BessieApp
@testable import BessieCore

@MainActor
final class CommandPaletteControllerTests: XCTestCase {
    func testFirstTypedCharacterUpdatesVisibleRowsWithoutWaitingForAnotherCharacter() {
        let alpha = entity("alpha", title: "Alpha")
        let zulu = entity("zulu", title: "Zulu")
        let controller = BessieCommandPaletteKeyRouting()

        controller.update(query: "", entities: [alpha, zulu])
        XCTAssertEqual(controller.results.map(\.id), [alpha.id, zulu.id])

        controller.update(query: "p", entities: [alpha, zulu])
        XCTAssertEqual(controller.results.map(\.id), [alpha.id])
    }

    func testSelectionStaysValidWhileTypingDeletingAndChangingResultSets() {
        let alpha = entity("alpha", title: "Alpha")
        let alpine = entity("alpine", title: "Alpine")
        let zulu = entity("zulu", title: "Zulu")
        let controller = BessieCommandPaletteKeyRouting()

        controller.update(query: "", entities: [zulu, alpine, alpha])
        controller.selection = 2
        controller.update(query: "al", entities: [zulu, alpine, alpha])
        XCTAssertEqual(controller.selection, 0)
        XCTAssertEqual(controller.results[controller.selection].id, alpha.id)

        controller.update(query: "z", entities: [zulu, alpine, alpha])
        XCTAssertEqual(controller.selection, 0)
        XCTAssertEqual(controller.results[controller.selection].id, zulu.id)

        controller.update(query: "missing", entities: [zulu, alpine, alpha])
        XCTAssertTrue(controller.results.isEmpty)
        XCTAssertEqual(controller.selection, 0)

        controller.update(query: "", entities: [zulu, alpine, alpha])
        XCTAssertEqual(controller.selection, 0)
        XCTAssertEqual(controller.results[controller.selection].id, zulu.id)
    }

    func testKeyboardExecutionUsesSelectedFilteredResultNotStaleUnfilteredRow() {
        let alpha = entity("alpha", title: "Alpha")
        let zulu = entity("zulu", title: "Zulu")
        let controller = BessieCommandPaletteKeyRouting()
        var performed: [CommandPaletteRouteIntent] = []
        controller.onActivate = { performed.append($0) }

        controller.update(query: "", entities: [alpha, zulu])
        controller.selection = 1
        controller.update(query: "p", entities: [alpha, zulu])
        controller.activate(alternate: false)
        controller.activate(alternate: false)

        XCTAssertEqual(performed, [alpha.route])
    }

    func testImmediateArrowThenReturnExecutesNewSelection() {
        let alpha = entity("alpha", title: "Alpha")
        let zulu = entity("zulu", title: "Zulu")
        let controller = BessieCommandPaletteKeyRouting()
        var performed: [CommandPaletteRouteIntent] = []
        controller.onActivate = { performed.append($0) }

        controller.update(query: "", entities: [alpha, zulu])
        controller.moveSelection(by: 1)
        controller.activate(alternate: false)

        XCTAssertEqual(performed, [zulu.route])
    }

    func testProjectPrefixSearchExecutesCommandCenterLaunchRoute() {
        let projectID = UUID()
        let commandCenter = CommandPaletteEntity(
            id: .init(kind: .project, components: [projectID.uuidString]),
            kind: .project,
            title: "Command Center",
            detail: "Project",
            route: .project(projectID)
        )
        let unrelated = entity("settings", title: "Settings")
        let controller = BessieCommandPaletteKeyRouting()
        var performed: [CommandPaletteRouteIntent] = []
        controller.onActivate = { performed.append($0) }

        controller.update(query: "com", entities: [unrelated, commandCenter])
        XCTAssertEqual(controller.results.first?.id, commandCenter.id)
        controller.activate(alternate: false)

        XCTAssertEqual(performed, [.project(projectID)])
    }

    func testPaletteCatalogIncludesNewAndManageProjectCommands() {
        let newProject = BessieKeyboardShortcutRouter.commands.first { $0.command == .newProject }
        let manageProjects = BessieKeyboardShortcutRouter.commands.first { $0.command == .projectsPicker }

        XCTAssertEqual(newProject?.title, "New project")
        XCTAssertEqual(manageProjects?.title, "Manage projects")
    }

    private func entity(_ id: String, title: String) -> CommandPaletteEntity {
        CommandPaletteEntity(
            id: .init(kind: .command, components: [id]),
            kind: .command,
            title: title,
            detail: "Command",
            route: .command(id == "alpha" ? .showSettings : .showHerd)
        )
    }
}
