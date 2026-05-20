import SwiftUI

struct NewTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DownloadCoordinator.self) private var coordinator
    @Environment(\.responsiveLayout) private var parentLayout
    @State private var sourceText = ""
    @State private var saveDirectory = AppDefaults.downloadDirectory

    var body: some View {
        GeometryReader { proxy in
            let sheetScale = min(max(proxy.size.width, 1) / 560, max(proxy.size.height, 1) / 520)
            let layout = ResponsiveLayout(scale: max(parentLayout.scale, sheetScale))

            GlassSurface(level: .floating, cornerRadius: 18) {
                VStack(alignment: .leading, spacing: layout.value(16)) {
                    HStack(spacing: layout.value(12)) {
                        ZStack {
                            RoundedRectangle(cornerRadius: layout.value(10), style: .continuous)
                                .fill(Color.accentColor.opacity(0.10))
                                .frame(width: layout.value(42), height: layout.value(42))
                            Image(systemName: "doc.badge.plus")
                                .font(layout.font(18, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }

                        VStack(alignment: .leading, spacing: layout.value(3)) {
                            Text("新建下载任务")
                                .font(layout.font(16, weight: .semibold))
                                .foregroundStyle(Color.primary)
                            Text("支持一次粘贴多个直链、磁力链接或种子文件地址。")
                                .font(layout.font(11.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    ZStack(alignment: .topLeading) {
                        if sourceText.isEmpty {
                            Text("在此粘贴一个或多个下载链接（支持多行直链、磁力链接、或种子 URL）")
                                .font(layout.font(12))
                                .foregroundStyle(.secondary.opacity(0.8))
                                .padding(.horizontal, layout.value(14))
                                .padding(.vertical, layout.value(14))
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $sourceText)
                            .font(layout.font(12, design: .monospaced))
                            .frame(minHeight: layout.value(140))
                            .scrollContentBackground(.hidden)
                            .padding(layout.value(8))
                    }
                    .background {
                        ContentSurfaceBackground(cornerRadius: 8)
                    }

                    HStack(spacing: layout.value(12)) {
                        Image(systemName: "folder.fill")
                            .font(layout.font(16))
                            .foregroundStyle(Color.orange)
                            .padding(layout.value(8))
                            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: layout.value(8), style: .continuous))

                        VStack(alignment: .leading, spacing: layout.value(3)) {
                            Text("保存目录")
                                .font(layout.font(10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(saveDirectory.path)
                                .font(layout.font(12, weight: .medium))
                                .lineLimit(1)
                                .foregroundStyle(Color.primary)
                        }

                        Spacer()

                        Button("选择目录") {
                            chooseDirectory()
                        }
                        .font(layout.font(11.5, weight: .semibold))
                        .buttonStyle(.bordered)
                    }
                    .padding(layout.value(10))
                    .background {
                        ContentSurfaceBackground(cornerRadius: 8)
                    }

                    SourcePreviewView(sourceText: sourceText)

                    HStack {
                        Button("取消") {
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        
                        Spacer()
                        
                        Button {
                            coordinator.add(source: sourceText, saveDirectory: saveDirectory)
                            dismiss()
                        } label: {
                            Label("添加任务", systemImage: "plus.circle.fill")
                                .font(layout.font(12, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(SourceParser.extractSources(from: sourceText).isEmpty)
                    }
                }
                .padding(layout.value(22))
            }
            .environment(\.responsiveLayout, layout)
        }
        .padding(1)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = saveDirectory
        if panel.runModal() == .OK, let url = panel.url {
            saveDirectory = url
        }
    }
}

// MARK: - Identified Source Preview Component
private struct SourcePreviewView: View {
    @Environment(\.responsiveLayout) private var layout
    let sourceText: String

    var body: some View {
        let sources = SourceParser.extractSources(from: sourceText)

        VStack(alignment: .leading, spacing: layout.value(10)) {
            HStack {
                Text("识别预览")
                    .font(layout.font(10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("已识别 \(sources.count) 个任务")
                    .font(layout.font(10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(sources.isEmpty ? .secondary : Color.green)
            }

            if sources.isEmpty {
                Text("粘贴合法链接后会在此处实时显示识别到的类型与资源名预览。")
                    .font(layout.font(11))
                    .foregroundStyle(.secondary.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: layout.value(6)) {
                        ForEach(sources.prefix(4), id: \.self) { source in
                            let kind = SourceParser.kind(for: source)
                            
                            HStack(spacing: layout.value(8)) {
                                Image(systemName: kind.symbolName)
                                    .font(layout.font(11))
                                    .foregroundStyle(previewColor(for: kind))
                                
                                Text(SourceParser.displayName(for: source, kind: kind))
                                    .font(layout.font(11, design: .monospaced))
                                    .lineLimit(1)
                                    .foregroundStyle(Color.primary)
                            }
                            .padding(.horizontal, layout.value(8))
                            .padding(.vertical, layout.value(4))
                            .background(ContentSurfaceBackground(cornerRadius: 6))
                        }
                        
                        if sources.count > 4 {
                            Text("... 以及其它 \(sources.count - 4) 个任务")
                                .font(layout.font(10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.leading, layout.value(8))
                        }
                    }
                }
                .frame(maxHeight: layout.value(100))
            }
        }
        .padding(layout.value(12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ContentSurfaceBackground(cornerRadius: 8)
        }
    }

    private func previewColor(for kind: DownloadKind) -> Color {
        switch kind {
        case .http:
            .indigo
        case .torrentMagnet:
            .teal
        case .torrentFile:
            .blue
        }
    }
}
