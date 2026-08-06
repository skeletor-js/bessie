import AppKit
import BessieCore
import Foundation
import SwiftUI

struct NativeMarkdownDocument {
    static let maximumPreviewCharacters = 250_000

    enum BlockKind: Equatable {
        case paragraph
        case heading(level: Int)
        case unorderedListItem
        case orderedListItem(ordinal: Int)
        case code(language: String?)
        case blockQuote
        case thematicBreak
    }

    enum Segment {
        case text(AttributedString)
        case image(reference: URL, altText: String)
    }

    struct Block {
        let kind: BlockKind
        var content: AttributedString
        var imageReferences: [URL]
        var segments: [Segment]
    }

    let blocks: [Block]

    init(markdown: String) throws {
        guard markdown.count <= Self.maximumPreviewCharacters else {
            throw WorkspacePathError.tooLarge
        }
        let attributed = try AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        )
        var blocks: [Block] = []
        var currentIdentity: Int?

        for run in attributed.runs {
            let descriptor = Self.blockDescriptor(for: run.presentationIntent)
            if currentIdentity != descriptor.identity {
                blocks.append(Block(
                    kind: descriptor.kind,
                    content: AttributedString(),
                    imageReferences: [],
                    segments: []
                ))
                currentIdentity = descriptor.identity
            }
            guard !blocks.isEmpty else { continue }
            let runContent = AttributedString(attributed[run.range])
            if let reference = run.imageURL {
                blocks[blocks.count - 1].imageReferences.append(reference)
                blocks[blocks.count - 1].segments.append(.image(
                    reference: reference,
                    altText: String(runContent.characters)
                ))
            } else {
                blocks[blocks.count - 1].content.append(runContent)
                if case .text(let existing)? = blocks[blocks.count - 1].segments.last {
                    var combined = existing
                    combined.append(runContent)
                    blocks[blocks.count - 1].segments[blocks[blocks.count - 1].segments.count - 1] = .text(combined)
                } else {
                    blocks[blocks.count - 1].segments.append(.text(runContent))
                }
            }
        }
        self.blocks = blocks
    }

    private static func blockDescriptor(
        for intent: PresentationIntent?
    ) -> (identity: Int, kind: BlockKind) {
        guard let components = intent?.components else { return (0, .paragraph) }
        for component in components.reversed() {
            switch component.kind {
            case .header(let level): return (component.identity, .heading(level: level))
            case .codeBlock(let language): return (component.identity, .code(language: language))
            case .listItem(let ordinal):
                let ordered = components.contains { if case .orderedList = $0.kind { true } else { false } }
                return (component.identity, ordered ? .orderedListItem(ordinal: ordinal) : .unorderedListItem)
            case .blockQuote: return (component.identity, .blockQuote)
            case .thematicBreak: return (component.identity, .thematicBreak)
            default: continue
            }
        }
        if let paragraph = components.last(where: { if case .paragraph = $0.kind { true } else { false } }) {
            return (paragraph.identity, .paragraph)
        }
        return (components.last?.identity ?? 0, .paragraph)
    }
}

struct MarkdownFileEditor: View {
    let save: (String, WorkspaceFileRevision, Bool) async throws -> WorkspaceFileRevision
    let loadImage: (URL) async throws -> WorkspaceDecodedImage
    let reload: () -> Void
    @State private var text: String
    @State private var revision: WorkspaceFileRevision
    @State private var savedText: String
    @State private var editing = false
    @State private var saving = false
    @State private var conflict = false
    @State private var error: String?

    init(
        document: WorkspaceTextDocument,
        save: @escaping (String, WorkspaceFileRevision, Bool) async throws -> WorkspaceFileRevision,
        loadImage: @escaping (URL) async throws -> WorkspaceDecodedImage,
        reload: @escaping () -> Void
    ) {
        self.save = save
        self.loadImage = loadImage
        self.reload = reload
        _text = State(initialValue: document.text)
        _revision = State(initialValue: document.revision)
        _savedText = State(initialValue: document.text)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Markdown mode", selection: $editing) {
                    Text("Preview").tag(false)
                    Text("Edit").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                Spacer()
                if text != savedText { Text("Unsaved").foregroundStyle(BessieDesign.accent) }
                Button("Save") { performSave(overwrite: false) }
                    .disabled(!editing || text == savedText || saving)
            }
            .padding(10)
            Divider()
            if editing {
                TextEditor(text: $text)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(8)
            } else {
                ScrollView {
                    NativeMarkdownPreview(markdown: text, loadImage: loadImage)
                        .padding(20)
                }
            }
        }
        .alert("File changed on disk", isPresented: $conflict) {
            Button("Reload", role: .destructive) { reload() }
            Button("Overwrite") { performSave(overwrite: true) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Reload the newer version or explicitly overwrite it with your draft.") }
        .alert("Couldn’t save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "Unknown error") }
    }

    private func performSave(overwrite: Bool) {
        let draft = text
        let expectedRevision = revision
        saving = true
        Task {
            do {
                revision = try await save(draft, expectedRevision, overwrite)
                savedText = draft
            }
            catch WorkspaceFileOperationError.staleRevision { conflict = true }
            catch { self.error = error.localizedDescription }
            saving = false
        }
    }
}

private struct NativeMarkdownPreview: View {
    let document: Result<NativeMarkdownDocument, Error>
    let loadImage: (URL) async throws -> WorkspaceDecodedImage

    init(markdown: String, loadImage: @escaping (URL) async throws -> WorkspaceDecodedImage) {
        self.document = Result { try NativeMarkdownDocument(markdown: markdown) }
        self.loadImage = loadImage
    }

    var body: some View {
        switch document {
        case .success(let document):
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                guard ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") else {
                    return .discarded
                }
                NSWorkspace.shared.open(url)
                return .handled
            })
        case .failure(let error):
            ContentUnavailableView(
                "Markdown preview unavailable",
                systemImage: "doc.text.magnifyingglass",
                description: Text(error.localizedDescription + " You can still use Edit mode.")
            )
        }
    }

    @ViewBuilder
    private func blockView(_ block: NativeMarkdownDocument.Block) -> some View {
        switch block.kind {
        case .heading(let level):
            blockContent(block, font: headingFont(level))
                .fontWeight(level <= 2 ? .bold : .semibold)
        case .unorderedListItem:
            listRow(marker: "•", block: block)
        case .orderedListItem(let ordinal):
            listRow(marker: "\(ordinal).", block: block)
        case .code:
            ScrollView(.horizontal) {
                Text(block.content)
                    .font(.system(size: 12, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BessieDesign.inset, in: RoundedRectangle(cornerRadius: 6))
        case .blockQuote:
            HStack(alignment: .top, spacing: 10) {
                Rectangle().fill(BessieDesign.accent).frame(width: 3)
                paragraph(block)
            }
        case .thematicBreak:
            Divider()
        case .paragraph:
            blockContent(block, font: .system(size: 14))
        }
    }

    private func paragraph(_ block: NativeMarkdownDocument.Block) -> some View {
        blockContent(block, font: .system(size: 14))
    }

    private func blockContent(_ block: NativeMarkdownDocument.Block, font: Font) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(block.segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text):
                    Text(text).font(font).lineSpacing(3)
                case .image(let reference, let altText):
                    MarkdownImagePreview(
                        reference: reference,
                        altText: altText,
                        load: loadImage
                    )
                }
            }
        }
    }

    private func listRow(marker: String, block: NativeMarkdownDocument.Block) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(marker).font(.system(size: 14, weight: .semibold)).frame(minWidth: 18, alignment: .trailing)
            paragraph(block)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .system(size: 28)
        case 2: .system(size: 23)
        case 3: .system(size: 19)
        default: .system(size: 16)
        }
    }
}

private struct MarkdownImagePreview: View {
    let reference: URL
    let altText: String
    let load: (URL) async throws -> WorkspaceDecodedImage
    @State private var image: WorkspaceDecodedImage?
    @State private var error: String?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image.cgImage, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 520)
                    .accessibilityLabel(altText.isEmpty ? reference.lastPathComponent : altText)
            } else if let error {
                Label(
                    (altText.isEmpty ? reference.lastPathComponent : altText) + ": " + error,
                    systemImage: "photo.badge.exclamationmark"
                )
                    .font(.caption)
                    .foregroundStyle(BessieDesign.subtle)
            } else {
                ProgressView("Loading \(reference.lastPathComponent)…")
                    .controlSize(.small)
            }
        }
        .task(id: reference) {
            do {
                image = try await load(reference)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
