import SwiftUI

struct NewTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DownloadCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    @Environment(\.responsiveLayout) private var parentLayout
    @State private var sourceText = ""
    @State private var saveDirectory = AppDefaults.downloadDirectory
    @State private var suggestedFilename: String?
    let draft: DownloadDraft?

    init(draft: DownloadDraft? = nil) {
        self.draft = draft
        _sourceText = State(initialValue: draft?.source ?? "")
        _suggestedFilename = State(initialValue: draft?.suggestedFilename)
    }

    var body: some View {
        let layout = ResponsiveLayout(scale: min(max(parentLayout.scale, 0.92), 1.08))

        ZStack {
            MonochromeWindowBackground()

            ScrollView(.vertical) {
                GlassSurface(level: .floating, cornerRadius: 18) {
                    content(layout: layout)
                        .padding(layout.value(22))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(1)
            }
            .scrollIndicators(.visible)
        }
        .environment(\.responsiveLayout, layout)
        .onAppear {
            saveDirectory = settings.defaultDownloadDirectory
        }
        .onChange(of: draft) { _, newDraft in
            apply(newDraft)
        }
        .frame(
            minWidth: 520,
            idealWidth: 560,
            maxWidth: 720,
            minHeight: 520,
            idealHeight: 540,
            maxHeight: 640
        )
    }

    @ViewBuilder
    private func content(layout: ResponsiveLayout) -> some View {
        VStack(alignment: .leading, spacing: layout.value(16)) {
            HStack(spacing: layout.value(12)) {
                ZStack {
                    RoundedRectangle(cornerRadius: layout.value(10), style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                        .frame(width: layout.value(42), height: layout.value(42))
                    Image(systemName: "doc.badge.plus")
                        .font(layout.font(18, weight: .semibold))
                        .foregroundStyle(Color.primary)
                }

                VStack(alignment: .leading, spacing: layout.value(3)) {
                    Text("新建下载任务")
                        .font(layout.font(16, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    Text(subtitle)
                        .font(layout.font(11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let draft {
                BrowserTakeoverBanner(draft: draft)
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
                    .foregroundStyle(Color.primary)
                    .padding(layout.value(8))
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: layout.value(8), style: .continuous))

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
                    coordinator.add(source: sourceText, saveDirectory: saveDirectory, suggestedFilename: suggestedFilename)
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
    }

    private var subtitle: String {
        if let draft, draft.isBrowserTakeover {
            return "浏览器下载已被接管，确认保存目录后即可添加任务。"
        }
        return "支持一次粘贴多个直链、磁力链接或种子文件地址。"
    }

    private func apply(_ draft: DownloadDraft?) {
        sourceText = draft?.source ?? ""
        suggestedFilename = draft?.suggestedFilename
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

private struct BrowserTakeoverBanner: View {
    @Environment(\.responsiveLayout) private var layout
    let draft: DownloadDraft

    var body: some View {
        HStack(alignment: .top, spacing: layout.value(10)) {
            Image(systemName: "safari")
                .font(layout.font(16, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: layout.value(24), height: layout.value(24))

            VStack(alignment: .leading, spacing: layout.value(3)) {
                Text("\(draft.browser ?? "浏览器") 接管下载")
                    .font(layout.font(12, weight: .semibold))
                Text(detailText)
                    .font(layout.font(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(layout.value(11))
        .background {
            ContentSurfaceBackground(cornerRadius: 8)
        }
    }

    private var detailText: String {
        if let suggestedFilename = draft.suggestedFilename, !suggestedFilename.isEmpty {
            return "已预填 \(suggestedFilename)，可在添加前调整链接或保存目录。"
        }
        return "已预填下载链接，可在添加前调整链接或保存目录。"
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
                    .foregroundStyle(sources.isEmpty ? .secondary : Color.primary)
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
