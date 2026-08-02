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
                    title: "Follow files is local-only",
                    detail: "This agent is on a remote connection. Bessie does not pretend remote files are local."
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
                Toggle(
                    "Follow latest",
                    isOn: Binding(
                        get: { model.touchState.followEnabled },
                        set: { model.setFollowEnabled($0) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                Spacer()
                Button(model.touchState.pinnedPath == nil ? "Pin" : "Unpin") {
                    model.togglePin()
                }
                .buttonStyle(BessieSecondaryButtonStyle())
                .disabled(model.touchState.selectedPath == nil)
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .overlay(alignment: .bottom) { Rectangle().fill(BessieDesign.border).frame(height: 1) }

            HSplitView {
                touchedList.frame(minWidth: 150, idealWidth: 175, maxWidth: 210)
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
                                        : Color.clear
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
                        Text(text.isEmpty ? "No changes from the locked baseline." : text)
                            .font(.system(size: 10.5, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
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
