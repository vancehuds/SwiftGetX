import SwiftUI

struct NewTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DownloadCoordinator.self) private var coordinator
    @State private var sourceText = ""
    @State private var saveDirectory = AppDefaults.downloadDirectory

    var body: some View {
        GlassSurface(level: .floating, cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(0.10))
                            .frame(width: 42, height: 42)
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("新建下载任务")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.primary)
                        Text("支持一次粘贴多个直链、磁力链接或种子文件地址。")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                ZStack(alignment: .topLeading) {
                    if sourceText.isEmpty {
                        Text("在此粘贴一个或多个下载链接（支持多行直链、磁力链接、或种子 URL）")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary.opacity(0.8))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $sourceText)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 140)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                }
                .background {
                    GlassCellBackground(cornerRadius: 12)
                }

                HStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.orange)
                        .padding(8)
                        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("保存目录")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(saveDirectory.path)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(Color.primary)
                    }

                    Spacer()

                    Button("选择目录") {
                        chooseDirectory()
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .buttonStyle(.bordered)
                }
                .padding(10)
                .background {
                    GlassCellBackground(cornerRadius: 12)
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
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(SourceParser.extractSources(from: sourceText).isEmpty)
                }
            }
            .padding(22)
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
    let sourceText: String

    var body: some View {
        let sources = SourceParser.extractSources(from: sourceText)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("识别预览")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("已识别 \(sources.count) 个任务")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(sources.isEmpty ? .secondary : Color.green)
            }

            if sources.isEmpty {
                Text("粘贴合法链接后会在此处实时显示识别到的类型与资源名预览。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(sources.prefix(4), id: \.self) { source in
                            let kind = SourceParser.kind(for: source)
                            
                            HStack(spacing: 8) {
                                Image(systemName: kind.symbolName)
                                    .font(.system(size: 11))
                                    .foregroundStyle(previewColor(for: kind))
                                
                                Text(SourceParser.displayName(for: source, kind: kind))
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                                    .foregroundStyle(Color.primary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        
                        if sources.count > 4 {
                            Text("... 以及其它 \(sources.count - 4) 个任务")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 8)
                        }
                    }
                }
                .frame(maxHeight: 100)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GlassCellBackground(cornerRadius: 12)
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
