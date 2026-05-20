import SwiftUI
import SwiftGetXCore
import UniformTypeIdentifiers

struct NewTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DownloadCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    @Environment(\.responsiveLayout) private var parentLayout
    @State private var sourceText = ""
    @State private var saveDirectory = AppDefaults.downloadDirectory
    @State private var suggestedFilename: String?
    @State private var previews = [TorrentMetadataPreview]()
    @State private var previewSources = [String]()
    @State private var selectedFileIndexesBySource = [String: Set<Int>]()
    @State private var filePrioritiesBySource = [String: [Int: TorrentFilePriority]]()
    @State private var isLoadingPreviews = false
    @State private var didResolveNativeHandoff = false
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
        .onDisappear {
            rejectNativeHandoffIfNeeded(reason: "userCancelled")
        }
        .task(id: sourceText) {
            await refreshPreviews()
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
                    Text(L10n.string("new_task_title"))
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
                    Text(L10n.string("new_task_source_placeholder"))
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
                    Text(L10n.string("save_directory"))
                        .font(layout.font(10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(saveDirectory.path)
                        .font(layout.font(12, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(Color.primary)
                }

                Spacer()

                Button(L10n.string("choose_directory")) {
                    chooseDirectory()
                }
                .font(layout.font(11.5, weight: .semibold))
                .buttonStyle(.bordered)
            }
            .padding(layout.value(10))
            .background {
                ContentSurfaceBackground(cornerRadius: 8)
            }

            HStack(spacing: layout.value(10)) {
                Button {
                    chooseTorrentFile()
                } label: {
                    Label(L10n.string("action_choose_torrent_file"), systemImage: "doc.badge.plus")
                }
                .font(layout.font(11.5, weight: .semibold))
                .buttonStyle(.bordered)

                if isLoadingPreviews {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.string("torrent_preview_loading"))
                        .font(layout.font(11))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            SourcePreviewView(
                sourceText: sourceText,
                previews: previews,
                selectedFileIndexesBySource: $selectedFileIndexesBySource,
                filePrioritiesBySource: $filePrioritiesBySource
            )

            HStack {
                Button(L10n.string("action_cancel")) {
                    rejectNativeHandoffIfNeeded(reason: "userCancelled")
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Spacer()

                Button {
                    guard !rejectExpiredNativeHandoffIfNeeded() else {
                        dismiss()
                        return
                    }

                    let tasks: [DownloadTask]
                    if previews.contains(where: { $0.kind == .torrentMagnet || $0.kind == .torrentFile }) {
                        tasks = coordinator.add(
                            previews: previews,
                            saveDirectory: saveDirectory,
                            selectedFileIndexes: selectedFileIndexesForCoordinator,
                            filePriorities: filePrioritiesForCoordinator
                        )
                    } else {
                        tasks = coordinator.add(
                            source: sourceText,
                            saveDirectory: saveDirectory,
                            suggestedFilename: suggestedFilename,
                            browserContext: draft?.browserContext
                        )
                    }
                    acknowledgeNativeHandoffIfNeeded(
                        decision: NativeHandoffDecisionFactory.decision(
                            queuedTaskCount: tasks.count,
                            requiresUserConfirmation: draft?.isBrowserTakeover == true
                        )
                    )
                    dismiss()
                } label: {
                    Label(L10n.string("add_task"), systemImage: "plus.circle.fill")
                        .font(layout.font(12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(SourceParser.extractSources(from: sourceText).isEmpty || isLoadingPreviews)
            }
        }
    }

    private var subtitle: String {
        if let draft, draft.isBrowserTakeover {
            return L10n.string("new_task_browser_takeover_subtitle")
        }
        return L10n.string("new_task_subtitle")
    }

    private func apply(_ draft: DownloadDraft?) {
        sourceText = draft?.source ?? ""
        suggestedFilename = draft?.suggestedFilename
        didResolveNativeHandoff = false
    }

    private func rejectExpiredNativeHandoffIfNeeded() -> Bool {
        guard let resolution = PendingNativeHandoffPolicy.expirationResolution(draft: draft) else {
            return false
        }

        didResolveNativeHandoff = true
        PendingNativeHandoffPolicy.acknowledge(resolution)
        return true
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

    private func chooseTorrentFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType(filenameExtension: "torrent") ?? .data]
        if panel.runModal() == .OK {
            let paths = panel.urls.map(\.path)
            guard !paths.isEmpty else { return }
            let separator = sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n"
            sourceText += separator + paths.joined(separator: "\n")
        }
    }

    private var selectedFileIndexesForCoordinator: [String: [Int]] {
        Dictionary(uniqueKeysWithValues: previews.map { preview in
            let selected = selectedFileIndexesBySource[preview.source] ?? Set(preview.selectedFileIndexes)
            return (preview.source, selected.sorted())
        })
    }

    private func refreshPreviews() async {
        let sources = SourceParser.extractSources(from: sourceText)
        await MainActor.run {
            previewSources = sources
            isLoadingPreviews = !sources.isEmpty
        }

        guard !sources.isEmpty else {
            await MainActor.run {
                previews = []
                selectedFileIndexesBySource = [:]
                filePrioritiesBySource = [:]
                isLoadingPreviews = false
            }
            return
        }

        let previewService = TorrentMetadataService(
            magnetTimeout: .seconds(settings.torrentMagnetMetadataTimeoutSeconds)
        )
        let nextPreviews = await withTaskGroup(
            of: (Int, TorrentMetadataPreview)?.self,
            returning: [TorrentMetadataPreview].self
        ) { group in
            for (index, source) in sources.enumerated() {
                let suggested = sources.count == 1 ? suggestedFilename : nil
                group.addTask {
                    guard !Task.isCancelled else { return nil }
                    let preview = await previewService.preview(source: source, suggestedFilename: suggested)
                    return (index, preview)
                }
            }

            var orderedPreviews = Array<TorrentMetadataPreview?>(repeating: nil, count: sources.count)
            for await result in group {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return []
                }
                if let result {
                    orderedPreviews[result.0] = result.1
                }
            }
            return orderedPreviews.compactMap(\.self)
        }
        if Task.isCancelled { return }

        await MainActor.run {
            guard previewSources == sources else { return }
            previews = nextPreviews
            for preview in nextPreviews where selectedFileIndexesBySource[preview.source] == nil {
                selectedFileIndexesBySource[preview.source] = Set(preview.selectedFileIndexes)
            }
            let validSources = Set(nextPreviews.map(\.source))
            selectedFileIndexesBySource = selectedFileIndexesBySource.filter { validSources.contains($0.key) }
            filePrioritiesBySource = filePrioritiesBySource.filter { validSources.contains($0.key) }
            isLoadingPreviews = false
        }
    }

    private var filePrioritiesForCoordinator: [String: [Int: Int]] {
        Dictionary(uniqueKeysWithValues: previews.map { preview -> (String, [Int: Int]) in
            let selected = selectedFileIndexesBySource[preview.source] ?? Set(preview.selectedFileIndexes)
            let priorities = filePrioritiesBySource[preview.source] ?? defaultPriorities(for: preview, selected: selected)
            var rawPriorities = [Int: Int]()
            for (fileIndex, priority) in priorities {
                rawPriorities[fileIndex] = priority.rawValue
            }
            return (preview.source, rawPriorities)
        })
    }

    private func defaultPriorities(for preview: TorrentMetadataPreview, selected: Set<Int>) -> [Int: TorrentFilePriority] {
        Dictionary(uniqueKeysWithValues: preview.files.map { file in
            (file.index, selected.contains(file.index) ? file.priorityLevel : .skip)
        })
    }

    private func rejectNativeHandoffIfNeeded(reason: String) {
        acknowledgeNativeHandoffIfNeeded(
            decision: .rejected(
                reason: reason,
                requiresUserConfirmation: draft?.isBrowserTakeover == true,
                message: "SwiftGetX download confirmation was cancelled"
            )
        )
    }

    private func acknowledgeNativeHandoffIfNeeded(decision: NativeHandoffAckDecision) {
        guard !didResolveNativeHandoff,
              let handoffAck = draft?.handoffAck
        else {
            return
        }

        didResolveNativeHandoff = true
        Task.detached {
            try? await NativeHandoffAckClient.acknowledge(decision, handoff: handoffAck)
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
                Text(L10n.string("browser_takeover_download_title", draft.browser ?? L10n.string("browser_generic")))
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
            return L10n.string("browser_takeover_prefilled_filename", suggestedFilename)
        }
        return L10n.string("browser_takeover_prefilled_link")
    }
}

// MARK: - Identified Source Preview Component
private struct SourcePreviewView: View {
    @Environment(\.responsiveLayout) private var layout
    let sourceText: String
    let previews: [TorrentMetadataPreview]
    @Binding var selectedFileIndexesBySource: [String: Set<Int>]
    @Binding var filePrioritiesBySource: [String: [Int: TorrentFilePriority]]

    var body: some View {
        let sources = SourceParser.extractSources(from: sourceText)

        VStack(alignment: .leading, spacing: layout.value(10)) {
            HStack {
                Text(L10n.string("source_preview_title"))
                    .font(layout.font(10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(L10n.string("source_preview_count", sources.count))
                    .font(layout.font(10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(sources.isEmpty ? .secondary : Color.primary)
            }

            if sources.isEmpty {
                Text(L10n.string("source_preview_empty"))
                    .font(layout.font(11))
                    .foregroundStyle(.secondary.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: layout.value(6)) {
                        ForEach(sources.prefix(4), id: \.self) { source in
                            if let preview = previews.first(where: { $0.source == source }) {
                                TorrentPreviewRow(
                                    preview: preview,
                                    selectedFileIndexes: selectionBinding(for: preview),
                                    filePriorities: priorityBinding(for: preview)
                                )
                            } else {
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
                        }
                        
                        if sources.count > 4 {
                            Text(L10n.string("source_preview_more_tasks", sources.count - 4))
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

    private func selectionBinding(for preview: TorrentMetadataPreview) -> Binding<Set<Int>> {
        Binding(
            get: { selectedFileIndexesBySource[preview.source] ?? Set(preview.selectedFileIndexes) },
            set: { selection in
                selectedFileIndexesBySource[preview.source] = selection
                var priorities = filePrioritiesBySource[preview.source] ?? [:]
                for file in preview.files {
                    priorities[file.index] = selection.contains(file.index) ? .normal : .skip
                }
                filePrioritiesBySource[preview.source] = priorities
            }
        )
    }

    private func priorityBinding(for preview: TorrentMetadataPreview) -> Binding<[Int: TorrentFilePriority]> {
        Binding(
            get: { filePrioritiesBySource[preview.source] ?? defaultPriorities(for: preview) },
            set: { priorities in
                filePrioritiesBySource[preview.source] = priorities
                selectedFileIndexesBySource[preview.source] = Set(priorities.compactMap { fileIndex, priority in
                    priority == .skip ? nil : fileIndex
                })
            }
        )
    }

    private func defaultPriorities(for preview: TorrentMetadataPreview) -> [Int: TorrentFilePriority] {
        Dictionary(uniqueKeysWithValues: preview.files.map { file in
            let selected = selectedFileIndexesBySource[preview.source] ?? Set(preview.selectedFileIndexes)
            return (file.index, selected.contains(file.index) ? file.priorityLevel : .skip)
        })
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

private struct TorrentPreviewRow: View {
    @Environment(\.responsiveLayout) private var layout
    let preview: TorrentMetadataPreview
    @Binding var selectedFileIndexes: Set<Int>
    @Binding var filePriorities: [Int: TorrentFilePriority]

    var body: some View {
        VStack(alignment: .leading, spacing: layout.value(8)) {
            HStack(spacing: layout.value(8)) {
                Image(systemName: preview.kind.symbolName)
                    .font(layout.font(11))
                    .foregroundStyle(previewColor)

                VStack(alignment: .leading, spacing: layout.value(2)) {
                    Text(preview.displayName)
                        .font(layout.font(11.5, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(layout.font(10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }

            if !preview.files.isEmpty {
                HStack {
                    Button(L10n.string("action_select_all")) {
                        selectedFileIndexes = Set(preview.files.map(\.index))
                        filePriorities = Dictionary(uniqueKeysWithValues: preview.files.map { ($0.index, .normal) })
                    }
                    .font(layout.font(10.5, weight: .semibold))

                    Button(L10n.string("action_clear")) {
                        selectedFileIndexes = []
                        filePriorities = Dictionary(uniqueKeysWithValues: preview.files.map { ($0.index, .skip) })
                    }
                    .font(layout.font(10.5, weight: .semibold))

                    Spacer()

                    Text(L10n.string("files_selected_count", selectedFileIndexes.count, preview.files.count))
                        .font(layout.font(10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                ForEach(preview.files.prefix(8)) { file in
                    HStack(spacing: layout.value(8)) {
                        Button {
                            toggle(file)
                        } label: {
                            Image(systemName: selectedFileIndexes.contains(file.index) ? "checkmark.circle.fill" : "circle")
                                .font(layout.font(12, weight: .semibold))
                                .foregroundStyle(selectedFileIndexes.contains(file.index) ? .green : .secondary)
                        }
                        .buttonStyle(.plain)

                        Text(file.path)
                            .font(layout.font(10.8))
                            .lineLimit(1)
                            .foregroundStyle(Color.primary)

                        Spacer()

                        Picker("", selection: priorityBinding(for: file)) {
                            ForEach(TorrentFilePriority.allCases) { priority in
                                Text(priority.title).tag(priority)
                            }
                        }
                        .labelsHidden()
                        .frame(width: layout.value(100))

                        Text(ByteCountFormatter.downloadFormatter.string(fromByteCount: file.size))
                            .font(layout.font(10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                if preview.files.count > 8 {
                    Text(L10n.string("torrent_preview_more_files", preview.files.count - 8))
                        .font(layout.font(10.5))
                        .foregroundStyle(.secondary)
                }
            } else if let errorMessage = preview.errorMessage {
                Text(errorMessage)
                    .font(layout.font(10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, layout.value(8))
        .padding(.vertical, layout.value(8))
        .background(ContentSurfaceBackground(cornerRadius: 6))
    }

    private var subtitle: String {
        if preview.totalBytes > 0 {
            return "\(preview.metadataStatus.title) · \(ByteCountFormatter.downloadFormatter.string(fromByteCount: preview.totalBytes))"
        }
        return preview.metadataStatus.title
    }

    private var previewColor: Color {
        switch preview.kind {
        case .http:
            .indigo
        case .torrentMagnet:
            .teal
        case .torrentFile:
            .blue
        }
    }

    private func toggle(_ file: TorrentFile) {
        if selectedFileIndexes.contains(file.index) {
            selectedFileIndexes.remove(file.index)
            filePriorities[file.index] = .skip
        } else {
            selectedFileIndexes.insert(file.index)
            filePriorities[file.index] = .normal
        }
    }

    private func priorityBinding(for file: TorrentFile) -> Binding<TorrentFilePriority> {
        Binding(
            get: { filePriorities[file.index] ?? (selectedFileIndexes.contains(file.index) ? file.priorityLevel : .skip) },
            set: { priority in
                filePriorities[file.index] = priority
                if priority == .skip {
                    selectedFileIndexes.remove(file.index)
                } else {
                    selectedFileIndexes.insert(file.index)
                }
            }
        )
    }
}
