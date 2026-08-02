import BessieCore
import Foundation
import XCTest
@testable import BessieApp

@MainActor
final class WorkspaceFilesViewModelTests: XCTestCase {
    func testModelLoadsBrowserAndKeepsPlainTextReadOnlySelection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("bessie-files-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("plain text".utf8).write(to: directory.appendingPathComponent("notes.txt"))
        let root = WorkspaceFileRoot(connectionID: "local", workspaceID: "workspace", rootURL: directory, gitTopLevel: nil, resolution: .herdrCwd)
        let model = WorkspaceFilesViewModel(root: root)

        model.load()
        await eventually { model.items.count == 1 }
        model.open(try XCTUnwrap(model.items.first))
        await eventually {
            if case .text(_, markdown: false) = model.selection { return true }
            return false
        }
    }

    func testFilesIsAnExplicitProductDestination() {
        XCTAssertTrue(ProductDestination.allCases.contains(.files))
        XCTAssertEqual(ProductDestination.files.symbol, "folder")
    }

    private func eventually(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition did not become true")
    }
}
