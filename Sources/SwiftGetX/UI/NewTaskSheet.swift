import AppKit
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
    @State private var filenameOverride = ""
    @State private var httpSegmentCount = 8
    @State private var httpRetryLimit = 3
    @State private var httpDownloadLimitBytes: Int64 = 0
    @State private var httpChecksumAlgorithm: HTTPChecksumAlgorithm = .sha256
    @State private var httpChecksumDigest = ""
    @State private var httpHeaderText = ""
    @State private var previews = [TorrentMetadataPreview]()
    @State private var previewSources = [String]()
    @State private var selectedFileIndexesBySource = [String: Set<Int>]()
    @State private var filePrioritiesBySource = [String: [Int: TorrentFilePriority]]()
    @State private var isLoadingPreviews = false
    @State private var previewRefreshNonce = 0
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
            httpSegmentCount = settings.httpMultithreadingEnabled ? settings.httpSegmentCount : 1
            httpRetryLimit = settings.retryLimit
            httpDownloadLimitBytes = 0
        }
        .onChange(of: draft) { _, newDraft in
            apply(newDraft)
        }
        .onDisappear {
            rejectNativeHandoffIfNeeded(reason: "userCancelled")
        }
        .task(id: previewRefreshKey) {
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

            if let draft, draft.isTrustedNativeHandoff, draft.isBrowserTakeover {
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

            if hasHTTPSources {
                HTTPDownloadOptionsEditor(
                    showsFilenameOverride: hasSingleHTTPSource,
                    filenameOverride: $filenameOverride,
                    segmentCount: $httpSegmentCount,
                    retryLimit: $httpRetryLimit,
                    speedLimitBytes: $httpDownloadLimitBytes,
                    checksumAlgorithm: $httpChecksumAlgorithm,
                    checksumDigest: $httpChecksumDigest,
                    headerText: $httpHeaderText
                )
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
                    Text(L10n.string("source_preview_loading"))
                        .font(layout.font(11))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            SourcePreviewView(
                sourceText: sourceText,
                saveDirectory: saveDirectory,
                previews: previews,
                selectedFileIndexesBySource: $selectedFileIndexesBySource,
                filePrioritiesBySource: $filePrioritiesBySource,
                onRetryPreview: { source in
                    retryPreview(for: source)
                },
                onAddAnyway: {
                    addTasksAndDismiss()
                },
                onCopySource: { source in
                    copyToPasteboard(source)
                },
                onCancelSource: { source in
                    removeSource(source)
                }
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
                    addTasksAndDismiss()
                } label: {
                    Label(L10n.string("add_task"), systemImage: "plus.circle.fill")
                        .font(layout.font(12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canAddTask)
            }
        }
    }

    private var subtitle: String {
        if let draft, draft.isTrustedNativeHandoff, draft.isBrowserTakeover {
            return L10n.string("new_task_browser_takeover_subtitle")
        }
        return L10n.string("new_task_subtitle")
    }

    private var previewRefreshKey: String {
        [
            sourceText,
            saveDirectory.path,
            suggestedFilename ?? "",
            filenameOverride,
            "\(httpSegmentCount)",
            "\(httpRetryLimit)",
            "\(httpDownloadLimitBytes)",
            httpChecksumAlgorithm.rawValue,
            httpChecksumDigest,
            httpHeaderText,
            "\(previewRefreshNonce)",
            draft?.browserContext?.finalURL ?? "",
            draft?.browserContext?.originalURL ?? ""
        ].joined(separator: "\u{1F}")
    }

    private func apply(_ draft: DownloadDraft?) {
        sourceText = draft?.source ?? ""
        suggestedFilename = draft?.suggestedFilename
        filenameOverride = ""
        httpChecksumAlgorithm = .sha256
        httpChecksumDigest = ""
        didResolveNativeHandoff = false
    }

    private var currentSources: [String] {
        SourceParser.extractSources(from: sourceText)
    }

    private var canAddTask: Bool {
        let sources = currentSources
        guard !sources.isEmpty, !isLoadingPreviews else { return false }
        guard hasCompletePreviews(for: sources) else { return true }

        return previews.allSatisfy { preview in
            guard preview.kind == .torrentMagnet || preview.kind == .torrentFile,
                  preview.metadataStatus == .available,
                  !preview.files.isEmpty
            else {
                return true
            }
            let selected = selectedFileIndexesBySource[preview.source] ?? Set(preview.selectedFileIndexes)
            return !selected.isEmpty
        }
    }

    private var hasHTTPSources: Bool {
        currentSources.contains { SourceParser.kind(for: $0) == .http }
    }

    private var hasSingleHTTPSource: Bool {
        currentSources.count == 1
            && currentSources.first.map { SourceParser.kind(for: $0) == .http } == true
    }

    private var effectiveFilenameOverride: String? {
        HTTPResponseMetadata(suggestedFilename: filenameOverride).suggestedFilename
    }

    private var effectiveSuggestedFilename: String? {
        effectiveFilenameOverride ?? suggestedFilename
    }

    private var httpDownloadOptions: HTTPDownloadOptions? {
        guard hasHTTPSources else { return nil }
        return HTTPDownloadOptions(
            segmentCountOverride: httpSegmentCount,
            retryLimitOverride: httpRetryLimit,
            perTaskDownloadLimitBytes: httpDownloadLimitBytes,
            filenameOverride: hasSingleHTTPSource ? effectiveFilenameOverride : nil,
            checksum: httpChecksum,
            additionalHeaders: HTTPDownloadOptions.headers(from: httpHeaderText)
        )
    }

    private var httpChecksum: HTTPChecksum? {
        HTTPChecksum(algorithm: httpChecksumAlgorithm, expectedHexDigest: httpChecksumDigest)
            ?? HTTPChecksum(input: httpChecksumDigest, preferredFilename: effectiveFilenameOverride ?? suggestedFilename)
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

    private func retryPreview(for source: String) {
        guard currentSources.contains(source) else { return }
        previews.removeAll { $0.source == source }
        previewRefreshNonce += 1
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func removeSource(_ source: String) {
        sourceText = currentSources
            .filter { $0 != source }
            .joined(separator: "\n")
    }

    private func addTasksAndDismiss() {
        guard !rejectExpiredNativeHandoffIfNeeded() else {
            dismiss()
            return
        }

        let sources = SourceParser.extractSources(from: sourceText)
        let tasks: [DownloadTask]
        if hasCompletePreviews(for: sources) {
            tasks = coordinator.add(
                previews: previews,
                saveDirectory: saveDirectory,
                selectedFileIndexes: selectedFileIndexesForCoordinator,
                filePriorities: filePrioritiesForCoordinator,
                httpOptions: httpDownloadOptions
            )
        } else {
            tasks = coordinator.add(
                source: sourceText,
                saveDirectory: saveDirectory,
                suggestedFilename: effectiveSuggestedFilename,
                browserContext: draft?.browserContext,
                httpOptions: httpDownloadOptions
            )
        }
        acknowledgeNativeHandoffIfNeeded(
            decision: NativeHandoffDecisionFactory.decision(
                queuedTaskCount: tasks.count,
                requiresUserConfirmation: draft?.requiresUserConfirmation == true
                    || draft?.isBrowserTakeover == true
            )
        )
        dismiss()
    }

    private var selectedFileIndexesForCoordinator: [String: [Int]] {
        Dictionary(uniqueKeysWithValues: previews.map { preview in
            let selected = selectedFileIndexesBySource[preview.source] ?? Set(preview.selectedFileIndexes)
            return (preview.source, selected.sorted())
        })
    }

    private func refreshPreviews() async {
        let sources = SourceParser.extractSources(from: sourceText)
        let httpOptions = httpDownloadOptions
        let filenameOverride = sources.count == 1 ? effectiveFilenameOverride : nil
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
        let httpPreviewService = HTTPMetadataPreviewService()
        let nextPreviews = await withTaskGroup(
            of: (Int, TorrentMetadataPreview)?.self,
            returning: [TorrentMetadataPreview].self
        ) { group in
            for (index, source) in sources.enumerated() {
                let suggested = sources.count == 1 ? suggestedFilename : nil
                group.addTask {
                    guard !Task.isCancelled else { return nil }
                    let preview: TorrentMetadataPreview
                    if SourceParser.kind(for: source) == .http {
                        preview = await httpPreviewService.preview(
                            source: source,
                            suggestedFilename: suggested,
                            filenameOverride: filenameOverride,
                            saveDirectory: saveDirectory,
                            browserContext: sources.count == 1 ? draft?.browserContext : nil,
                            httpOptions: httpOptions
                        )
                    } else {
                        preview = await previewService.preview(source: source, suggestedFilename: suggested)
                    }
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

    private func hasCompletePreviews(for sources: [String]) -> Bool {
        guard !sources.isEmpty, previews.count == sources.count else { return false }
        return zip(sources, previews).allSatisfy { source, preview in
            source == preview.source
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
                requiresUserConfirmation: draft?.requiresUserConfirmation == true
                    || draft?.isBrowserTakeover == true,
                message: "SwiftGetX download confirmation was cancelled"
            )
        )
    }

    private func acknowledgeNativeHandoffIfNeeded(decision: NativeHandoffAckDecision) {
        guard !didResolveNativeHandoff,
              draft?.canAcknowledgeNativeHandoff == true,
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

private struct HTTPDownloadOptionsEditor: View {
    @Environment(\.responsiveLayout) private var layout
    let showsFilenameOverride: Bool
    @Binding var filenameOverride: String
    @Binding var segmentCount: Int
    @Binding var retryLimit: Int
    @Binding var speedLimitBytes: Int64
    @Binding var checksumAlgorithm: HTTPChecksumAlgorithm
    @Binding var checksumDigest: String
    @Binding var headerText: String

    var body: some View {
        VStack(alignment: .leading, spacing: layout.value(10)) {
            HStack {
                Label(L10n.string("http_options_title"), systemImage: "slider.horizontal.3")
                    .font(layout.font(10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(speedLabel(for: speedLimitBytes))
                    .font(layout.font(10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if showsFilenameOverride {
                VStack(alignment: .leading, spacing: layout.value(4)) {
                    Text(L10n.string("http_options_filename"))
                        .font(layout.font(10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField(L10n.string("http_options_filename_placeholder"), text: $filenameOverride)
                        .textFieldStyle(.roundedBorder)
                        .font(layout.font(11.5))
                }
            }

            HStack(spacing: layout.value(12)) {
                Stepper(
                    L10n.string("http_options_segments", segmentCount),
                    value: $segmentCount,
                    in: 1...HTTPDownloadOptions.maximumSegmentCount
                )
                Stepper(
                    L10n.string("http_options_retries", retryLimit),
                    value: $retryLimit,
                    in: 0...HTTPDownloadOptions.maximumRetryLimit
                )
            }
            .font(layout.font(11.2))

            HStack(spacing: layout.value(10)) {
                Text(L10n.string("http_options_speed_limit"))
                    .font(layout.font(11.2))
                Picker("", selection: $speedLimitBytes) {
                    ForEach(speedLimitChoices, id: \.self) { value in
                        Text(speedLabel(for: value)).tag(value)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: layout.value(180))
            }

            VStack(alignment: .leading, spacing: layout.value(6)) {
                Text(L10n.string("http_options_checksum"))
                    .font(layout.font(10.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: layout.value(8)) {
                    Picker("", selection: $checksumAlgorithm) {
                        ForEach(HTTPChecksumAlgorithm.allCases, id: \.rawValue) { algorithm in
                            Text(algorithm.title).tag(algorithm)
                        }
                    }
                    .labelsHidden()
                    .frame(width: layout.value(104))

                    TextField(L10n.string("http_options_checksum_placeholder"), text: $checksumDigest)
                        .textFieldStyle(.roundedBorder)
                        .font(layout.font(11.5, design: .monospaced))
                }

                Text(checksumHelpText)
                    .font(layout.font(10.2))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            TextEditor(text: $headerText)
                .font(layout.font(11, design: .monospaced))
                .frame(minHeight: layout.value(54), maxHeight: layout.value(76))
                .scrollContentBackground(.hidden)
                .padding(layout.value(6))
                .background(ContentSurfaceBackground(cornerRadius: 6))
                .overlay(alignment: .topLeading) {
                    if headerText.isEmpty {
                        Text(L10n.string("http_options_headers_placeholder"))
                            .font(layout.font(11, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.75))
                            .padding(.horizontal, layout.value(10))
                            .padding(.vertical, layout.value(12))
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding(layout.value(12))
        .background {
            ContentSurfaceBackground(cornerRadius: 8)
        }
    }

    private var speedLimitChoices: [Int64] {
        [0, 500_000, 1_000_000, 5_000_000, 10_000_000, 20_000_000]
    }

    private func speedLabel(for value: Int64) -> String {
        guard value > 0 else { return L10n.string("speed_unlimited") }
        return ByteCountFormatter.downloadFormatter.string(fromByteCount: value) + "/s"
    }

    private var checksumHelpText: String {
        if checksumDigest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.string("http_options_checksum_help")
        }
        if HTTPChecksum(algorithm: checksumAlgorithm, expectedHexDigest: checksumDigest) != nil
            || HTTPChecksum(input: checksumDigest) != nil
        {
            return L10n.string("http_options_checksum_valid")
        }
        return L10n.string("http_options_checksum_invalid", checksumAlgorithm.title, checksumAlgorithm.hexDigitCount)
    }
}

// MARK: - Identified Source Preview Component
private struct SourcePreviewView: View {
    @Environment(\.responsiveLayout) private var layout
    let sourceText: String
    let saveDirectory: URL
    let previews: [TorrentMetadataPreview]
    @Binding var selectedFileIndexesBySource: [String: Set<Int>]
    @Binding var filePrioritiesBySource: [String: [Int: TorrentFilePriority]]
    let onRetryPreview: (String) -> Void
    let onAddAnyway: () -> Void
    let onCopySource: (String) -> Void
    let onCancelSource: (String) -> Void

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
                        ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                            if index < previews.count, previews[index].source == source {
                                let preview = previews[index]
                                TorrentPreviewRow(
                                    preview: preview.plannedForSaveDirectory(saveDirectory),
                                    selectedFileIndexes: selectionBinding(for: preview),
                                    filePriorities: priorityBinding(for: preview),
                                    onRetryPreview: { onRetryPreview(preview.source) },
                                    onAddAnyway: onAddAnyway,
                                    onCopySource: { onCopySource(preview.source) },
                                    onCancelSource: { onCancelSource(preview.source) }
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
                    }
                }
                .frame(maxHeight: layout.value(300))
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
    let onRetryPreview: () -> Void
    let onAddAnyway: () -> Void
    let onCopySource: () -> Void
    let onCancelSource: () -> Void
    @State private var fileSearchText = ""
    @State private var extensionFilter = ""
    @State private var bulkPriority: TorrentFilePriority = .normal

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

            if showsMagnetTimeoutActions {
                MagnetMetadataTimeoutActions(
                    preview: preview,
                    onRetryPreview: onRetryPreview,
                    onAddAnyway: onAddAnyway,
                    onCopySource: onCopySource,
                    onCancelSource: onCancelSource
                )
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

                torrentSelectionTools

                folderTree

                VStack(alignment: .leading, spacing: layout.value(4)) {
                    ForEach(filteredFiles) { file in
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
                                .help(file.path)

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
                                .frame(width: layout.value(78), alignment: .trailing)
                        }
                    }
                }

                if filteredFiles.isEmpty {
                    Text(L10n.string("torrent_file_filter_empty"))
                        .font(layout.font(10.5))
                        .foregroundStyle(.secondary)
                }
            }

            if !preview.trackers.isEmpty {
                VStack(alignment: .leading, spacing: layout.value(3)) {
                    Text(L10n.string("torrent_trackers"))
                        .font(layout.font(10, weight: .semibold))
                        .foregroundStyle(.secondary)

                    ForEach(Array(preview.trackers.prefix(3).enumerated()), id: \.offset) { _, tracker in
                        Text(tracker)
                            .font(layout.font(10.5))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if preview.trackers.count > 3 {
                        Text(L10n.string("torrent_preview_more_trackers", preview.trackers.count - 3))
                            .font(layout.font(10.5))
                            .foregroundStyle(.secondary)
                    }
                }
            } else if preview.kind == .http {
                HTTPPreviewDetails(preview: preview)
            }

            if preview.kind != .http {
                VStack(alignment: .leading, spacing: layout.value(3)) {
                    if let saveDirectoryPath = preview.torrentSaveDirectoryPath {
                        detailRow(title: L10n.string("torrent_save_directory"), value: saveDirectoryPath)
                    }
                    if let outputName = preview.torrentOutputName {
                        detailRow(title: L10n.string("torrent_output_name"), value: outputName)
                    }
                    if let displayPath = preview.torrentDisplayPath {
                        detailRow(title: L10n.string("torrent_content_path"), value: displayPath)
                    }
                }
            }

            if preview.kind != .http, let errorMessage = preview.errorMessage {
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

    private var showsMagnetTimeoutActions: Bool {
        preview.kind == .torrentMagnet
            && preview.metadataStatus == .fetching
            && preview.files.isEmpty
    }

    private var filteredFiles: [TorrentFile] {
        TorrentFileUX.filteredFiles(preview.files, searchText: fileSearchText)
    }

    private var folderGroups: [TorrentFileFolderGroup] {
        TorrentFileUX.folderGroups(in: preview.files)
    }

    private var extensionMatchedIndexes: [Int] {
        TorrentFileUX.fileIndexes(in: preview.files, matchingExtensions: extensionFilter)
    }

    private var torrentSelectionTools: some View {
        VStack(alignment: .leading, spacing: layout.value(8)) {
            TextField(L10n.string("torrent_file_search"), text: $fileSearchText)
                .textFieldStyle(.roundedBorder)
                .font(layout.font(10.8))

            HStack(spacing: layout.value(8)) {
                TextField(L10n.string("torrent_extension_filter"), text: $extensionFilter)
                    .textFieldStyle(.roundedBorder)
                    .font(layout.font(10.8))

                Picker("", selection: $bulkPriority) {
                    ForEach(TorrentFilePriority.allCases) { priority in
                        Text(priority.title).tag(priority)
                    }
                }
                .labelsHidden()
                .frame(width: layout.value(100))

                Button {
                    apply(priority: bulkPriority, to: extensionMatchedIndexes)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .disabled(extensionMatchedIndexes.isEmpty)
                .accessibilityLabel(L10n.string("torrent_apply_extension_filter"))
                .help(L10n.string("torrent_apply_extension_filter"))
            }
        }
    }

    @ViewBuilder
    private var folderTree: some View {
        if !folderGroups.isEmpty {
            VStack(alignment: .leading, spacing: layout.value(5)) {
                Text(L10n.string("torrent_folders"))
                    .font(layout.font(10, weight: .semibold))
                    .foregroundStyle(.secondary)

                ForEach(folderGroups.prefix(8)) { folder in
                    HStack(spacing: layout.value(7)) {
                        Image(systemName: "folder")
                            .font(layout.font(10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, CGFloat(folder.depth) * layout.value(10))

                        VStack(alignment: .leading, spacing: layout.value(1)) {
                            Text(folder.displayName)
                                .font(layout.font(10.8, weight: .medium))
                                .lineLimit(1)
                            Text(L10n.string(
                                "torrent_folder_file_count",
                                folder.fileIndexes.count,
                                ByteCountFormatter.downloadFormatter.string(fromByteCount: folder.totalBytes)
                            ))
                            .font(layout.font(9.8))
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Menu {
                            ForEach(TorrentFilePriority.allCases) { priority in
                                Button(priority.title) {
                                    apply(priority: priority, to: folder.fileIndexes)
                                }
                            }
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .menuStyle(.borderlessButton)
                        .accessibilityLabel(L10n.string("torrent_folder_priority"))
                        .help(L10n.string("torrent_folder_priority"))
                    }
                }
            }
            .padding(layout.value(8))
            .background(ContentSurfaceBackground(cornerRadius: 6))
        }
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

    private func apply(priority: TorrentFilePriority, to indexes: [Int]) {
        let plan = TorrentFileUX.apply(
            priority: priority,
            to: indexes,
            files: preview.files,
            selectedFileIndexes: selectedFileIndexes,
            priorities: filePriorities
        )
        selectedFileIndexes = plan.selectedFileIndexes
        filePriorities = plan.priorities
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

    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: layout.value(6)) {
            Text(title)
                .font(layout.font(10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: layout.value(112), alignment: .leading)
            Text(value)
                .font(layout.font(10.5))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct MagnetMetadataTimeoutActions: View {
    @Environment(\.responsiveLayout) private var layout
    let preview: TorrentMetadataPreview
    let onRetryPreview: () -> Void
    let onAddAnyway: () -> Void
    let onCopySource: () -> Void
    let onCancelSource: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: layout.value(7)) {
            HStack(alignment: .top, spacing: layout.value(8)) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(layout.font(12, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: layout.value(18))

                VStack(alignment: .leading, spacing: layout.value(3)) {
                    Text(L10n.string("torrent_magnet_timeout_title"))
                        .font(layout.font(10.8, weight: .semibold))
                    Text(timeoutDetail)
                        .font(layout.font(10.3))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            HStack(spacing: layout.value(6)) {
                Button(L10n.string("torrent_continue_waiting")) {
                    onRetryPreview()
                }
                Button(L10n.string("torrent_add_anyway")) {
                    onAddAnyway()
                }
                Button(L10n.string("torrent_copy_magnet")) {
                    onCopySource()
                }
                Button(L10n.string("action_cancel")) {
                    onCancelSource()
                }
            }
            .font(layout.font(10.3, weight: .semibold))
        }
        .padding(layout.value(8))
        .background(ContentSurfaceBackground(cornerRadius: 6))
    }

    private var timeoutDetail: String {
        let trackerCount = preview.trackers.count
        if trackerCount > 0 {
            return L10n.string("torrent_magnet_timeout_detail", trackerCount)
        }
        return preview.errorMessage ?? L10n.string("torrent_metadata_timeout")
    }
}

private struct HTTPPreviewDetails: View {
    @Environment(\.responsiveLayout) private var layout
    let preview: TorrentMetadataPreview

    var body: some View {
        VStack(alignment: .leading, spacing: layout.value(4)) {
            detailRow(
                title: L10n.string("http_preview_resume"),
                value: preview.supportsResume
                    ? L10n.string("http_connection_resumable")
                    : L10n.string("http_connection_not_resumable")
            )

            if let mimeType = preview.httpResponseMetadata?.mimeType {
                detailRow(title: L10n.string("http_preview_type"), value: mimeType)
            }

            if let finalURL = preview.httpResponseMetadata?.finalURL {
                detailRow(title: L10n.string("http_preview_final_url"), value: finalURL)
            }

            detailRow(title: L10n.string("http_preview_duplicate_strategy"), value: duplicateStrategyText)

            if let savePath = preview.savePath {
                detailRow(title: L10n.string("detail_save_path"), value: savePath)
            }

            if let errorMessage = preview.errorMessage {
                Text(L10n.string("http_preview_metadata_limited", errorMessage))
                    .font(layout.font(10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var duplicateStrategyText: String {
        switch preview.duplicateStrategy {
        case .none:
            L10n.string("http_preview_duplicate_available")
        case .autoRename(_, let resolvedFilename):
            L10n.string("http_preview_duplicate_renamed", resolvedFilename)
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: layout.value(6)) {
            Text(title)
                .font(layout.font(10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: layout.value(92), alignment: .leading)
            Text(value)
                .font(layout.font(10.5))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
