import SwiftUI

struct NewTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DownloadCoordinator.self) private var coordinator
    @State private var sourceText = ""
    @State private var saveDirectory = AppDefaults.downloadDirectory

    var body: some View {
        GlassSurface(level: .floating, cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("新建下载任务")
                            .font(.title2.weight(.semibold))
                        Text("支持一次粘贴多个 HTTP/HTTPS 链接、磁力链接或种子文件地址。")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                TextEditor(text: $sourceText)
                    .font(.body.monospaced())
                    .frame(minHeight: 160)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("保存到")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(saveDirectory.path)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button("选择目录") {
                        chooseDirectory()
                    }
                }
                .padding(12)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))

                SourcePreviewView(sourceText: sourceText)

                HStack {
                    Button("取消") {
                        dismiss()
                    }
                    Spacer()
                    Button {
                        coordinator.add(source: sourceText, saveDirectory: saveDirectory)
                        dismiss()
                    } label: {
                        Label("添加任务", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
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

private struct SourcePreviewView: View {
    let sourceText: String

    var body: some View {
        let sources = SourceParser.extractSources(from: sourceText)

        VStack(alignment: .leading, spacing: 8) {
            Text("识别到 \(sources.count) 个任务")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if sources.isEmpty {
                Text("粘贴链接后会在这里显示类型预览。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sources.prefix(5), id: \.self) { source in
                    let kind = SourceParser.kind(for: source)
                    Label(SourceParser.displayName(for: source, kind: kind), systemImage: kind.symbolName)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }
}
