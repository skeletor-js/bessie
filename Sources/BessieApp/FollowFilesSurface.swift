import BessieCore
import SwiftUI

struct FollowFilesSurface: View {
    @ObservedObject var model: FollowFilesViewModel

    var body: some View {
        Group {
            switch model.availability {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .remoteUnsupported:
                message(
                    symbol: "externaldrive.badge.xmark",
                    title: "Remote files need an active SSH tunnel",
                    detail: "Reconnect this SSH Herdr session, then open Follow files again."
                )
            case .unavailable(let detail):
                message(symbol: "folder.badge.questionmark", title: "Files unavailable", detail: detail)
            case .local:
                localSurface
            }
        }
        .background(BessieDesign.panel)
    }

    private var localSurface: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(followStatus)
                    .font(.system(size: 10.5))
                    .foregroundStyle(BessieDesign.subtle)
                Spacer()
                Menu {
                    Button(model.touchState.followEnabled ? "Pause following" : "Follow latest") {
                        model.setFollowEnabled(!model.touchState.followEnabled)
                    }
                    Button(model.touchState.pinnedPath == nil ? "Pin selected" : "Unpin") {
                        model.togglePin()
                    }
                    .disabled(model.touchState.pinnedPath == nil && model.touchState.selectedPath == nil)
                } label: {
                    Label(followControlLabel, systemImage: model.touchState.pinnedPath == nil ? "arrow.down.to.line" : "pin.fill")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .overlay(alignment: .bottom) { Rectangle().fill(BessieDesign.border).frame(height: 1) }

            HSplitView {
                touchedList.frame(minWidth: 140, idealWidth: 200, maxWidth: 360)
                preview.frame(minWidth: 220, maxWidth: .infinity, maxHeight: .infinity)
            }

            Text("Workspace changes observed while watching. Changes are not attributed to an agent.")
                .font(.system(size: 9.5))
                .foregroundStyle(BessieDesign.faint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .overlay(alignment: .top) { Rectangle().fill(BessieDesign.border).frame(height: 1) }
        }
    }

    private var followStatus: String {
        if model.touchState.pinnedPath != nil { return "Keeping pinned file" }
        return model.touchState.followEnabled ? "Following workspace changes" : "Following paused"
    }

    private var followControlLabel: String {
        if model.touchState.pinnedPath != nil { return "Pinned" }
        return model.touchState.followEnabled ? "Following" : "Paused"
    }

    private var touchedList: some View {
        Group {
            if model.touchState.touchedPaths.isEmpty {
                message(
                    symbol: "waveform.path.ecg",
                    title: "Watching for changes",
                    detail: "Touched files will appear here."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.touchState.touchedPaths) { path in
                            Button {
                                model.select(path.relativePath)
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: symbol(for: path.changeKind))
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(BessieDesign.subtle)
                                    Text(path.relativePath)
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .lineLimit(2)
                                        .foregroundStyle(BessieDesign.strong)
                                    Spacer(minLength: 2)
                                    if model.touchState.pinnedPath == path.relativePath {
                                        Image(systemName: "pin.fill").font(.system(size: 8))
                                    }
                                }
                                .padding(.horizontal, 10)
                                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                                .background(
                                    model.touchState.selectedPath == path.relativePath
                                        ? BessieDesign.selected
                                        : BessieSemanticColor.clear
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var preview: some View {
        if model.previewLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let preview = model.preview {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(preview.relativePath)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                    Spacer()
                    if let banner = preview.banner {
                        Text(banner.uppercased())
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(BessieDesign.subtle)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 31)
                .background(BessieDesign.panel)
                .overlay(alignment: .bottom) { Rectangle().fill(BessieDesign.border).frame(height: 1) }

                if preview.kind == .text, let text = preview.text {
                    ScrollView([.horizontal, .vertical]) {
                        if text.isEmpty {
                            Text("No changes from the locked baseline.")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(BessieDesign.codeSubtle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        } else {
                            DiffTextView(text: text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                    }
                    .background(BessieDesign.code)
                } else {
                    message(
                        symbol: preview.kind == .binary ? "doc.zipper" : "exclamationmark.triangle",
                        title: preview.kind == .binary ? "Binary file" : "Preview unavailable",
                        detail: preview.banner ?? "This file cannot be previewed."
                    )
                }
            }
        } else {
            message(symbol: "doc.text.magnifyingglass", title: "No file selected", detail: "Touch a file to preview its changes.")
        }
    }

    private func message(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(BessieDesign.subtle)
            Text(title).font(.system(size: 11.5, weight: .semibold))
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(BessieDesign.subtle)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func symbol(for kind: FileChangeKind) -> String {
        switch kind {
        case .added: "plus"
        case .modified: "pencil"
        case .deleted: "minus"
        case .unknown: "questionmark"
        }
    }
}

/// Unified-diff renderer with addition/removal/hunk coloring.
struct DiffTextView: View {
    let text: String

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                Text(String(line.isEmpty ? " " : line))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(color(for: String(line)))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(background(for: String(line)))
                    .textSelection(.enabled)
            }
        }
    }

    private func color(for line: String) -> BessieSemanticColor {
        if line.hasPrefix("+++") || line.hasPrefix("---") { return BessieDesign.codeSubtle }
        if line.hasPrefix("@@") { return BessieDesign.diffHunk }
        if line.hasPrefix("+") { return BessieDesign.diffAdded }
        if line.hasPrefix("-") { return BessieDesign.diffRemoved }
        return BessieDesign.codeText
    }

    private func background(for line: String) -> BessieSemanticColor {
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            return BessieDesign.diffAddedPlate
        }
        if line.hasPrefix("-") && !line.hasPrefix("---") {
            return BessieDesign.diffRemovedPlate
        }
        if line.hasPrefix("@@") {
            return BessieDesign.diffHunkPlate
        }
        return BessieSemanticColor.clear
    }
}
