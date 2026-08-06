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
            if case .text(path: "notes.txt", document: _) = model.selection { return true }
            return false
        }
    }

    func testModelOpensSupportedImageAndReportsInvalidImage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("bessie-image-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let validURL = directory.appendingPathComponent("valid.png")
        let invalidURL = directory.appendingPathComponent("invalid.png")
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: validURL)
        try Data("not an image".utf8).write(to: invalidURL)
        let root = WorkspaceFileRoot(connectionID: "local", workspaceID: "workspace", rootURL: directory, gitTopLevel: nil, resolution: .herdrCwd)
        let model = WorkspaceFilesViewModel(root: root)

        model.load()
        await eventually { model.items.count == 2 }
        model.open(try XCTUnwrap(model.items.first { $0.name == "valid.png" }))
        await eventually {
            if case .image(let image) = model.selection { return image.size == CGSize(width: 2, height: 2) }
            return false
        }

        model.open(try XCTUnwrap(model.items.first { $0.name == "invalid.png" }))
        await eventually { model.errorMessage == WorkspacePathError.invalidImage.localizedDescription }
    }

    func testNativeMarkdownDocumentPreservesBlockAndInlineSemantics() throws {
        let markdown = """
        # Heading

        - first
        - **second** with [link](https://example.com)

        ```swift
        let value = 1
        ```

        ![diagram](images/diagram.png)
        """

        let document = try NativeMarkdownDocument(markdown: markdown)

        XCTAssertEqual(document.blocks.map(\.kind), [
            .heading(level: 1),
            .unorderedListItem,
            .unorderedListItem,
            .code(language: "swift"),
            .paragraph,
        ])
        XCTAssertEqual(document.blocks.map { String($0.content.characters) }, [
            "Heading", "first", "second with link", "let value = 1\n", "",
        ])
        XCTAssertTrue(document.blocks[2].content.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        XCTAssertEqual(document.blocks[2].content.runs.compactMap(\.link), [URL(string: "https://example.com")!])
        XCTAssertEqual(document.blocks[4].imageReferences, [URL(string: "images/diagram.png")!])
        guard case .image(let reference, let altText) = document.blocks[4].segments.first else {
            return XCTFail("Expected a semantic Markdown image segment")
        }
        XCTAssertEqual(reference, URL(string: "images/diagram.png")!)
        XCTAssertEqual(altText, "diagram")
    }

    func testNativeMarkdownPreviewHasAnExplicitCharacterBound() {
        XCTAssertThrowsError(try NativeMarkdownDocument(
            markdown: String(repeating: "a", count: NativeMarkdownDocument.maximumPreviewCharacters + 1)
        )) {
            XCTAssertEqual($0 as? WorkspacePathError, .tooLarge)
        }
    }

    func testMarkdownImagesRejectNetworkAndWorkspaceEscapeReferences() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bessie-markdown-images-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("docs", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = WorkspaceFilesViewModel(root: WorkspaceFileRoot(
            connectionID: "local",
            workspaceID: "workspace",
            rootURL: directory,
            gitTopLevel: nil,
            resolution: .herdrCwd
        ))

        do {
            _ = try await model.loadMarkdownImage(
                markdownPath: "docs/readme.md",
                reference: try XCTUnwrap(URL(string: "https://example.com/tracker.png"))
            )
            XCTFail("Network Markdown images must not load")
        } catch {
            XCTAssertEqual(error as? WorkspacePathError, .unsupportedType)
        }
        do {
            _ = try await model.loadMarkdownImage(
                markdownPath: "docs/readme.md",
                reference: try XCTUnwrap(URL(string: "../../outside.png"))
            )
            XCTFail("Markdown images must stay inside the workspace root")
        } catch {
            XCTAssertEqual(error as? WorkspacePathError, .pathEscape)
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
