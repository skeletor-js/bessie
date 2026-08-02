import BessieCore
import SwiftUI

struct MarkdownFileEditor: View {
    let document: WorkspaceTextDocument
    let save: (String, WorkspaceFileRevision, Bool) async throws -> WorkspaceFileRevision
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
        reload: @escaping () -> Void
    ) {
        self.document = document
        self.save = save
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
                    Text((try? AttributedString(markdown: text)) ?? AttributedString(text))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
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
        saving = true
        Task {
            do {
                revision = try await save(text, revision, overwrite)
                savedText = text
            }
            catch WorkspaceFileOperationError.staleRevision { conflict = true }
            catch { self.error = error.localizedDescription }
            saving = false
        }
    }
}
