import SwiftUI

struct InspectorView: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    @Environment(\.responsiveLayout) private var layout
    @State private var selectedTab: InspectorTab = .overview

    var body: some View {
        GlassSurface(level: .panel, cornerRadius: 18) {
            VStack(spacing: 0) {
                if let task = coordinator.selectedTask {
                    header(for: task)
                    
                    Picker(L10n.string("inspector_details_picker"), selection: $selectedTab) {
                        ForEach(InspectorTab.tabs(for: task.kind)) { tab in
                            Label(tab.title, systemImage: tab.symbolName)
                                .tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, layout.value(14))
                    .padding(.bottom, layout.value(12))

                    Divider()
                        .opacity(0.24)

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: layout.value(14)) {
                            switch selectedTab {
                            case .overview:
                                OverviewPanel(task: task)
                            case .files:
                                FilesPanel(task: task)
                            case .connections:
                                ConnectionsPanel(task: task)
                            case .segments:
                                HTTPSegmentsPanel(task: task)
                            case .logs:
                                LogsPanel(task: task)
                            }
                        }
                        .padding(layout.value(14))
                    }
                    .transition(.opacity)
                } else {
                    VStack(spacing: layout.value(16)) {
                        Image(systemName: "sidebar.right")
                            .font(layout.font(26, weight: .light))
                            .foregroundStyle(.secondary)
                            .frame(width: layout.value(64), height: layout.value(64))
                            .background(ContentSurfaceBackground(cornerRadius: 32))

                        Text(L10n.string("inspector_select_task"))
                            .font(layout.font(14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func header(for task: DownloadTask) -> some View {
        VStack(alignment: .leading, spacing: layout.value(12)) {
            HStack(alignment: .top, spacing: layout.value(10)) {
                Image(systemName: task.status.symbolName)
                    .font(layout.font(16, weight: .semibold))
                    .foregroundStyle(statusColor(for: task.status))
                    .padding(.top, layout.value(2))
                
                VStack(alignment: .leading, spacing: layout.value(4)) {
                    Text(task.name)
                        .font(layout.font(14, weight: .semibold))
                        .lineLimit(2)
                        .foregroundStyle(Color.primary)
                    
                    Text(L10n.string("download_kind_badge", task.kind.title))
                        .font(layout.font(10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, layout.value(6))
                        .padding(.vertical, layout.value(2))
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }

            LiquidProgressBar(progress: task.progress, tint: statusColor(for: task.status))
            
            HStack {
                Text(task.progress.formatted(.percent.precision(.fractionLength(1))))
                    .font(layout.font(12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(statusColor(for: task.status))
                
                Spacer()
                
                Text(task.status.title)
                    .font(layout.font(11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(layout.value(14))
        .background {
            ContentSurfaceBackground(tint: statusColor(for: task.status), cornerRadius: 10)
        }
        .padding(layout.value(14))
        .padding(.bottom, layout.value(2))
    }

    private func statusColor(for status: DownloadStatus) -> Color {
        switch status {
        case .queued: .secondary
        case .running: .blue
        case .fetchingMetadata: .purple
        case .fetchingPeers: .cyan
        case .connectingPeers: .blue
        case .seeding: .mint
        case .paused: .orange
        case .verifying: .indigo
        case .completed: .green
        case .failed: .red
        case .cancelled: .gray
        }
    }
}

private enum InspectorTab: String, CaseIterable, Identifiable {
    case overview
    case files
    case connections
    case segments
    case logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: L10n.string("inspector_tab_overview")
        case .files: L10n.string("inspector_tab_files")
        case .connections: L10n.string("inspector_tab_connections")
        case .segments: L10n.string("inspector_tab_segments")
        case .logs: L10n.string("inspector_tab_logs")
        }
    }

    var symbolName: String {
        switch self {
        case .overview: "info.circle"
        case .files: "folder"
        case .connections: "point.3.connected.trianglepath.dotted"
        case .segments: "square.split.2x2"
        case .logs: "list.bullet.rectangle"
        }
    }

    static func tabs(for kind: DownloadKind) -> [InspectorTab] {
        switch kind {
        case .http:
            [.overview, .segments, .logs]
        case .torrentMagnet, .torrentFile:
            [.overview, .files, .connections, .logs]
        }
    }
}

private struct OverviewPanel: View {
    @Environment(\.responsiveLayout) private var layout
    let task: DownloadTask

    var body: some View {
        let columns = [
            GridItem(.flexible(), spacing: layout.value(10)),
            GridItem(.flexible(), spacing: layout.value(10))
        ]

        VStack(spacing: layout.value(12)) {
            LazyVGrid(columns: columns, spacing: layout.value(10)) {
                MetricCard(
                    title: L10n.string("metric_task_status"),
                    value: task.status.title,
                    symbol: task.status.symbolName,
                    color: statusColor
                )

                MetricCard(
                    title: L10n.string("metric_download_speed"),
                    value: task.status.usesActiveClock
                        ? ByteCountFormatter.downloadFormatter.string(fromByteCount: task.speedBytesPerSecond) + "/s"
                        : "--",
                    symbol: "arrow.down.circle",
                    color: task.status.usesActiveClock ? .green : .secondary
                )

                MetricCard(
                    title: L10n.string("metric_eta"),
                    value: task.status.usesActiveClock
                        ? (task.etaSeconds.map(TimeFormatter.eta) ?? L10n.string("unknown"))
                        : "--",
                    symbol: "clock",
                    color: .secondary
                )

                MetricCard(
                    title: L10n.string("metric_downloaded"),
                    value: ByteCountFormatter.downloadFormatter.string(fromByteCount: task.downloadedBytes),
                    symbol: "chart.bar.fill",
                    color: .blue
                )

                MetricCard(
                    title: L10n.string("metric_average_speed"),
                    value: speed(task.averageSpeedBytesPerSecond),
                    symbol: "speedometer",
                    color: .secondary
                )

                MetricCard(
                    title: L10n.string("metric_peak_speed"),
                    value: speed(task.peakSpeedBytesPerSecond),
                    symbol: "gauge.high",
                    color: .secondary
                )
            }

            VStack(spacing: layout.value(8)) {
                DetailRow(title: L10n.string("detail_total_size"), value: ByteCountFormatter.downloadFormatter.string(fromByteCount: task.totalBytes))
                DetailRow(
                    title: task.isTorrent ? L10n.string("torrent_content_path") : L10n.string("detail_save_path"),
                    value: task.displaySavePath
                )
                if task.isTorrent {
                    DetailRow(title: L10n.string("torrent_save_directory"), value: task.effectiveTorrentSaveDirectoryPath)
                    DetailRow(title: L10n.string("torrent_output_name"), value: task.effectiveTorrentOutputName)
                }
                DetailRow(title: L10n.string("detail_source"), value: task.displaySource)
                DetailRow(title: L10n.string("detail_resume"), value: task.supportsResume ? L10n.string("supported") : L10n.string("not_supported_or_unknown"))
                if let connectionSummary = task.connectionSummary {
                    DetailRow(title: L10n.string("detail_connection"), value: connectionSummary)
                }
                if task.kind == .http, let metadata = task.httpResponseMetadata {
                    DetailRow(title: L10n.string("detail_checksum"), value: metadata.checksumStatus.title)
                    if let checksumActualDigest = metadata.checksumActualDigest {
                        DetailRow(title: L10n.string("detail_checksum_actual"), value: checksumActualDigest.uppercased())
                    }
                }
                if let startedAt = task.startedAt {
                    DetailRow(title: L10n.string("detail_started_at"), value: Self.dateString(startedAt))
                }
                if let finishedAt = task.effectiveFinishedAt {
                    DetailRow(title: L10n.string("detail_finished_at"), value: Self.dateString(finishedAt))
                }
                DetailRow(title: L10n.string("detail_duration"), value: durationText)
                if let errorMessage = task.errorMessage {
                    ErrorActionCard(task: task, errorMessage: errorMessage)
                }
            }
        }
    }

    private var durationText: String {
        task.activeDurationSeconds > 0
            ? TimeFormatter.eta(task.activeDurationSeconds)
            : "--"
    }

    private func speed(_ bytesPerSecond: Int64) -> String {
        guard bytesPerSecond > 0 else { return "--" }
        return ByteCountFormatter.downloadFormatter.string(fromByteCount: bytesPerSecond) + "/s"
    }

    private static func dateString(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .medium)
    }

    private var statusColor: Color {
        switch task.status {
        case .queued: .secondary
        case .running: .blue
        case .fetchingMetadata: .purple
        case .fetchingPeers: .cyan
        case .connectingPeers: .blue
        case .seeding: .mint
        case .paused: .orange
        case .verifying: .indigo
        case .completed: .green
        case .failed: .red
        case .cancelled: .gray
        }
    }
}

private struct MetricCard: View {
    @Environment(\.responsiveLayout) private var layout
    let title: String
    let value: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: layout.value(8)) {
            HStack {
                Text(title)
                    .font(layout.font(10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: symbol)
                    .font(layout.font(11, weight: .semibold))
                    .foregroundStyle(color)
            }

            Text(value)
                .font(layout.font(13, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .foregroundStyle(Color.primary)
        }
        .padding(layout.value(12))
        .background {
            ContentSurfaceBackground(cornerRadius: 8)
        }
    }
}

private struct ErrorActionCard: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    @Environment(\.responsiveLayout) private var layout
    let task: DownloadTask
    let errorMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: layout.value(10)) {
            Label(L10n.string("detail_error"), systemImage: "exclamationmark.triangle.fill")
                .font(layout.font(10, weight: .semibold))
                .foregroundStyle(Color.red)

            Text(errorMessage)
                .font(layout.font(12, design: .monospaced))
                .foregroundStyle(Color.red)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: layout.value(8)) {
                Button {
                    coordinator.copyErrorMessage(task)
                } label: {
                    Label(L10n.string("action_copy_error"), systemImage: "doc.on.doc")
                }

                if task.status == .failed || task.status == .cancelled || task.status == .paused {
                    Button {
                        coordinator.retry(task)
                    } label: {
                        Label(L10n.string("action_retry_task"), systemImage: "arrow.clockwise")
                    }
                }

                if task.kind == .http {
                    Button {
                        coordinator.reprobeHTTPMetadata(task)
                    } label: {
                        Label(L10n.string("action_reprobe_metadata"), systemImage: "doc.text.magnifyingglass")
                    }
                }
            }
            .font(layout.font(11, weight: .semibold))
            .buttonStyle(.bordered)
        }
        .padding(layout.value(12))
        .background(ContentSurfaceBackground(tint: .red, cornerRadius: 8))
    }
}

private struct HTTPSegmentsPanel: View {
    @Environment(\.responsiveLayout) private var layout
    let task: DownloadTask

    var body: some View {
        VStack(alignment: .leading, spacing: layout.value(10)) {
            if task.httpSegments.isEmpty {
                Text(L10n.string("http_segments_empty"))
                    .font(layout.font(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(layout.value(20))
            } else {
                ForEach(task.httpSegments) { segment in
                    VStack(alignment: .leading, spacing: layout.value(8)) {
                        HStack {
                            Label(
                                L10n.string("http_segment_title", segment.index + 1),
                                systemImage: "square.split.2x2"
                            )
                            .font(layout.font(11, weight: .semibold))

                            Spacer()

                            Text(segment.progress.formatted(.percent.precision(.fractionLength(0))))
                                .font(layout.font(11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        LiquidProgressBar(progress: segment.progress, tint: .blue)

                        HStack(spacing: layout.value(12)) {
                            segmentValue(
                                title: L10n.string("http_segment_range"),
                                value: "\(segment.startByte)-\(segment.endByte)"
                            )
                            segmentValue(
                                title: L10n.string("http_segment_size"),
                                value: ByteCountFormatter.downloadFormatter.string(fromByteCount: segment.length)
                            )
                            segmentValue(
                                title: L10n.string("http_segment_speed"),
                                value: speed(segment.speedBytesPerSecond)
                            )
                            segmentValue(
                                title: L10n.string("http_segment_retries"),
                                value: "\(segment.retryCount)"
                            )
                        }
                    }
                    .padding(layout.value(10))
                    .background(ContentSurfaceBackground(cornerRadius: 8))
                }
            }
        }
    }

    private func segmentValue(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: layout.value(2)) {
            Text(title)
                .font(layout.font(9.5, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(layout.font(10.5, design: .monospaced))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func speed(_ bytesPerSecond: Int64) -> String {
        guard bytesPerSecond > 0 else { return "--" }
        return ByteCountFormatter.downloadFormatter.string(fromByteCount: bytesPerSecond) + "/s"
    }
}

private struct FilesPanel: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    @Environment(\.responsiveLayout) private var layout
    @State private var extensionFilter = ""
    @State private var extensionPriority: TorrentFilePriority = .normal
    @State private var relocatePath = ""
    let task: DownloadTask

    var body: some View {
        VStack(alignment: .leading, spacing: layout.value(12)) {
            if task.torrentFiles.isEmpty {
                Text(L10n.string("files_empty_metadata"))
                    .font(layout.font(12))
                    .foregroundStyle(.secondary)
                    .padding(layout.value(12))
            } else {
                HStack(spacing: layout.value(8)) {
                    Button(L10n.string("action_select_all")) {
                        coordinator.setTorrentFileSelection(
                            task,
                            selectedFileIndexes: task.torrentFiles.map(\.index)
                        )
                    }
                    .font(layout.font(11, weight: .semibold))
                    .buttonStyle(.bordered)
                    
                    Button(L10n.string("action_clear")) {
                        coordinator.setTorrentFileSelection(task, selectedFileIndexes: [])
                    }
                    .font(layout.font(11, weight: .semibold))
                    .buttonStyle(.bordered)

                    Toggle(
                        L10n.string("torrent_sequential_download"),
                        isOn: Binding(
                            get: { task.torrentRuntimeOptions?.isSequentialDownloadEnabled ?? false },
                            set: { coordinator.setTorrentSequentialDownload(task, enabled: $0) }
                        )
                    )
                    .font(layout.font(11, weight: .semibold))
                    .toggleStyle(.checkbox)
                    
                    Spacer()
                    
                    Text(L10n.string("files_selected_count", task.selectedFileIndexes.count, task.torrentFiles.count))
                        .font(layout.font(11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                batchControls
                folderControls

                ForEach(task.torrentFiles) { file in
                    HStack(spacing: layout.value(12)) {
                        Button {
                            toggle(file)
                        } label: {
                            Image(systemName: task.selectedFileIndexes.contains(file.index) ? "checkmark.circle.fill" : "circle")
                                .font(layout.font(14, weight: .semibold))
                                .foregroundStyle(task.selectedFileIndexes.contains(file.index) ? .green : .secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            task.selectedFileIndexes.contains(file.index)
                                ? L10n.string("action_clear_selection")
                                : L10n.string("action_select_task")
                        )
                        .help(
                            task.selectedFileIndexes.contains(file.index)
                                ? L10n.string("action_clear_selection")
                                : L10n.string("action_select_task")
                        )

                        VStack(alignment: .leading, spacing: layout.value(4)) {
                            Text(file.path)
                                .font(layout.font(12, weight: .medium))
                                .lineLimit(1)
                                .foregroundStyle(Color.primary)

                            LiquidProgressBar(progress: file.progress, tint: .blue)
                        }

                        Spacer()

                        Picker("", selection: Binding(
                            get: { file.priorityLevel },
                            set: { coordinator.setTorrentFilePriority(task, fileIndex: file.index, priority: $0) }
                        )) {
                            ForEach(TorrentFilePriority.allCases) { priority in
                                Text(priority.title).tag(priority)
                            }
                        }
                        .labelsHidden()
                        .frame(width: layout.value(112))

                        Text(ByteCountFormatter.downloadFormatter.string(fromByteCount: file.size))
                            .font(layout.font(11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: layout.value(74), alignment: .trailing)
                    }
                    .padding(layout.value(10))
                    .background {
                        ContentSurfaceBackground(cornerRadius: 8)
                    }
                }
            }
        }
    }

    private var batchControls: some View {
        VStack(alignment: .leading, spacing: layout.value(8)) {
            HStack(spacing: layout.value(8)) {
                TextField(L10n.string("torrent_extension_filter"), text: $extensionFilter)
                    .textFieldStyle(.roundedBorder)
                    .font(layout.font(11))

                Picker("", selection: $extensionPriority) {
                    ForEach(TorrentFilePriority.allCases) { priority in
                        Text(priority.title).tag(priority)
                    }
                }
                .labelsHidden()
                .frame(width: layout.value(108))

                Button {
                    coordinator.setTorrentExtensionPriority(
                        task,
                        extensionFilter: extensionFilter,
                        priority: extensionPriority
                    )
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .disabled(extensionFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(L10n.string("torrent_apply_extension_filter"))
                .help(L10n.string("torrent_apply_extension_filter"))
            }

            HStack(spacing: layout.value(8)) {
                TextField(L10n.string("torrent_relocate_path"), text: $relocatePath)
                    .textFieldStyle(.roundedBorder)
                    .font(layout.font(11))
                Button {
                    coordinator.relocateTorrent(task, toSaveDirectoryPath: relocatePath)
                    relocatePath = ""
                } label: {
                    Image(systemName: "folder.badge.gearshape")
                }
                .disabled(relocatePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(L10n.string("torrent_relocate_download"))
                .help(L10n.string("torrent_relocate_download"))
            }
        }
        .padding(layout.value(10))
        .background(ContentSurfaceBackground(cornerRadius: 8))
    }

    private var folderControls: some View {
        let folders = torrentFolders
        return Group {
            if !folders.isEmpty {
                VStack(alignment: .leading, spacing: layout.value(6)) {
                    Text(L10n.string("torrent_folders"))
                        .font(layout.font(10, weight: .semibold))
                        .foregroundStyle(.secondary)

                    ForEach(folders.prefix(6), id: \.self) { folder in
                        HStack(spacing: layout.value(8)) {
                            Image(systemName: "folder")
                                .font(layout.font(11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(folder)
                                .font(layout.font(11, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                            Menu {
                                ForEach(TorrentFilePriority.allCases) { priority in
                                    Button(priority.title) {
                                        coordinator.setTorrentFolderPriority(
                                            task,
                                            folderPath: folder,
                                            priority: priority
                                        )
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
                .padding(layout.value(10))
                .background(ContentSurfaceBackground(cornerRadius: 8))
            }
        }
    }

    private var torrentFolders: [String] {
        let folders = task.torrentFiles.flatMap { file -> [String] in
            let components = file.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard components.count > 1 else { return [] }
            return (1..<components.count).map { components.prefix($0).joined(separator: "/") }
        }
        return Array(Set(folders)).sorted()
    }

    private func toggle(_ file: TorrentFile) {
        var selected = Set(task.selectedFileIndexes)
        if selected.contains(file.index) {
            selected.remove(file.index)
        } else {
            selected.insert(file.index)
        }
        coordinator.setTorrentFileSelection(task, selectedFileIndexes: Array(selected))
    }
}

private struct ConnectionsPanel: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    @Environment(\.responsiveLayout) private var layout
    @State private var trackerURL = ""
    @State private var trackerBatchText = ""
    let task: DownloadTask

    var body: some View {
        VStack(spacing: layout.value(10)) {
            if let connection = task.torrentConnection {
                DetailRow(title: L10n.string("torrent_engine"), value: connection.engine.title)
                DetailRow(title: L10n.string("torrent_engine_status"), value: connection.engineStatus.title)
                DetailRow(title: L10n.string("torrent_metadata_status"), value: connection.metadataStatus.title)
                DetailRow(
                    title: L10n.string("connection_dht_status"),
                    value: connection.engineStatus.supportsRuntimeControls
                        ? enabledLabel(connection.isDHTEnabled)
                        : connection.engineStatus.title
                )
                DetailRow(
                    title: L10n.string("connection_pex"),
                    value: connection.engineStatus.supportsRuntimeControls
                        ? enabledLabel(connection.isPEXEnabled)
                        : connection.engineStatus.title
                )
                DetailRow(
                    title: L10n.string("connection_lsd"),
                    value: connection.engineStatus.supportsRuntimeControls
                        ? enabledLabel(connection.isLSDEnabled)
                        : connection.engineStatus.title
                )
                DetailRow(title: L10n.string("connection_local_port"), value: connection.localPortDescription.isEmpty ? L10n.string("unknown") : connection.localPortDescription)
                DetailRow(title: L10n.string("torrent_peer_count"), value: "\(connection.peerCount)")
                DetailRow(title: L10n.string("torrent_upload_speed"), value: ByteCountFormatter.downloadFormatter.string(fromByteCount: connection.uploadRate) + "/s")
                DetailRow(title: L10n.string("torrent_share_ratio"), value: String(format: "%.2f", connection.shareRatio))
                DetailRow(title: L10n.string("torrent_seeding_time"), value: TimeFormatter.eta(connection.seedingDurationSeconds))
                DetailRow(title: L10n.string("detail_connection"), value: connection.summary)
            } else {
                DetailRow(title: L10n.string("torrent_metadata_status"), value: task.torrentMetadataStatus.title)
                DetailRow(title: L10n.string("connection_dht_status"), value: task.kind == .http ? "--" : L10n.string("connection_waiting_peers"))
                DetailRow(title: L10n.string("connection_pex"), value: task.kind == .http ? "--" : L10n.string("connection_waiting_peers"))
                DetailRow(title: L10n.string("connection_lsd"), value: task.kind == .http ? "--" : L10n.string("connection_waiting_peers"))
                DetailRow(title: L10n.string("connection_local_port"), value: L10n.string("unknown"))
                DetailRow(title: L10n.string("detail_connection"), value: task.connectionSummary ?? L10n.string("connection_waiting_peers"))
            }
            seedingPolicyPanel
            if let health = task.torrentHealth {
                healthPanel(health)
            }
            trackerPanel
            peerPanel
        }
    }

    private func healthPanel(_ health: TorrentHealthInfo) -> some View {
        VStack(alignment: .leading, spacing: layout.value(8)) {
            Text(L10n.string("torrent_health"))
                .font(layout.font(10, weight: .semibold))
                .foregroundStyle(.secondary)
            DetailRow(title: L10n.string("torrent_engine"), value: health.engine.title)
            DetailRow(title: L10n.string("torrent_engine_status"), value: health.engineStatus.title)
            DetailRow(title: L10n.string("torrent_connections"), value: "\(health.connectionCount)")
            DetailRow(title: L10n.string("torrent_upload_slots"), value: "\(health.uploadSlotCount)")
            DetailRow(title: L10n.string("torrent_dht_nodes"), value: "\(health.dhtNodeCount)")
            DetailRow(title: L10n.string("torrent_peer_sources"), value: peerSourceSummary(health))
            DetailRow(title: L10n.string("torrent_distributed_copies"), value: String(format: "%.2f", health.distributedCopies))
            DetailRow(title: L10n.string("torrent_seeding_time"), value: TimeFormatter.eta(health.seedingDurationSeconds))
            DetailRow(title: L10n.string("torrent_resume_data"), value: health.needsResumeDataSave ? L10n.string("torrent_resume_data_dirty") : L10n.string("torrent_resume_data_clean"))
            if let lastError = health.lastError {
                DetailRow(title: L10n.string("detail_error"), value: lastError, color: .red)
            }
        }
    }

    private var seedingPolicyPanel: some View {
        VStack(alignment: .leading, spacing: layout.value(8)) {
            Text(L10n.string("connection_seed_limit"))
                .font(layout.font(10, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker(L10n.string("torrent_seeding_mode"), selection: seedingModeBinding) {
                ForEach(TorrentSeedingLimitMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()

            let options = task.torrentRuntimeOptions ?? TorrentRuntimeOptions()
            if options.seedingLimitMode == .stopAtRatio {
                Slider(value: seedingRatioBinding, in: 0...5, step: 0.1) {
                    Text(L10n.string("share_ratio_limit"))
                }
                Text(L10n.string("stop_seeding_ratio_message", options.stopSeedingAtRatio))
                    .font(layout.font(10.5))
                    .foregroundStyle(.secondary)
            } else if options.seedingLimitMode == .stopAfterTime {
                Stepper(
                    L10n.string("stop_seeding_time_limit", TimeFormatter.eta(options.stopSeedingAfterSeconds)),
                    value: seedingTimeBinding,
                    in: 60...604_800,
                    step: 60
                )
                Text(L10n.string("stop_seeding_time_message", TimeFormatter.eta(options.stopSeedingAfterSeconds)))
                    .font(layout.font(10.5))
                    .foregroundStyle(.secondary)
            } else {
                Text(options.seedingPolicyDescription)
                    .font(layout.font(10.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(layout.value(10))
        .background(ContentSurfaceBackground(cornerRadius: 8))
    }

    private var seedingModeBinding: Binding<TorrentSeedingLimitMode> {
        Binding(
            get: { task.torrentRuntimeOptions?.seedingLimitMode ?? .stopAtRatio },
            set: { coordinator.setTorrentSeedingLimitMode(task, mode: $0) }
        )
    }

    private var seedingRatioBinding: Binding<Double> {
        Binding(
            get: { task.torrentRuntimeOptions?.stopSeedingAtRatio ?? 1.0 },
            set: { coordinator.setTorrentStopSeedingAtRatio(task, ratio: $0) }
        )
    }

    private var seedingTimeBinding: Binding<TimeInterval> {
        Binding(
            get: { task.torrentRuntimeOptions?.stopSeedingAfterSeconds ?? 3600 },
            set: { coordinator.setTorrentStopSeedingAfterSeconds(task, seconds: $0) }
        )
    }

    private var trackerPanel: some View {
        VStack(alignment: .leading, spacing: layout.value(8)) {
            HStack {
                Text(L10n.string("torrent_trackers"))
                    .font(layout.font(10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    coordinator.forceTorrentReannounce(task)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L10n.string("torrent_force_reannounce"))
                .help(L10n.string("torrent_force_reannounce"))
            }

            HStack(spacing: layout.value(6)) {
                TextField(L10n.string("torrent_tracker_url"), text: $trackerURL)
                    .textFieldStyle(.roundedBorder)
                    .font(layout.font(11))
                Button {
                    coordinator.addTorrentTracker(task, url: trackerURL)
                    trackerURL = ""
                } label: {
                    Image(systemName: "plus.circle")
                }
                .disabled(trackerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(L10n.string("torrent_add_trackers"))
                .help(L10n.string("torrent_add_trackers"))
            }

            VStack(alignment: .leading, spacing: layout.value(6)) {
                TextEditor(text: $trackerBatchText)
                    .font(layout.font(11, design: .monospaced))
                    .frame(minHeight: layout.value(54), maxHeight: layout.value(76))
                    .scrollContentBackground(.hidden)
                    .padding(layout.value(6))
                    .background(ContentSurfaceBackground(cornerRadius: 6))
                    .overlay(alignment: .topLeading) {
                        if trackerBatchText.isEmpty {
                            Text(L10n.string("torrent_tracker_batch_placeholder"))
                                .font(layout.font(11, design: .monospaced))
                                .foregroundStyle(.secondary.opacity(0.75))
                                .padding(.horizontal, layout.value(10))
                                .padding(.vertical, layout.value(12))
                                .allowsHitTesting(false)
                        }
                    }

                HStack(spacing: layout.value(8)) {
                    Button {
                        coordinator.addTorrentTrackers(task, urlsText: trackerBatchText)
                        trackerBatchText = ""
                    } label: {
                        Label(L10n.string("torrent_add_trackers"), systemImage: "plus.rectangle.on.rectangle")
                    }
                    .disabled(trackerBatchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        coordinator.removeTorrentTrackers(task, urls: trackerBatchURLs)
                        trackerBatchText = ""
                    } label: {
                        Label(L10n.string("torrent_remove_listed_trackers"), systemImage: "minus.rectangle")
                    }
                    .disabled(trackerBatchURLs.isEmpty)

                    Spacer()

                    Button(role: .destructive) {
                        coordinator.removeTorrentTrackers(task, urls: task.torrentTrackers.map(\.url))
                    } label: {
                        Label(L10n.string("torrent_remove_all_trackers"), systemImage: "trash")
                    }
                    .disabled(task.torrentTrackers.isEmpty)
                }
                .font(layout.font(11, weight: .semibold))
            }

            if task.torrentTrackers.isEmpty {
                Text(L10n.string("torrent_trackers_empty"))
                    .font(layout.font(11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(task.torrentTrackers.prefix(20)) { tracker in
                    HStack(alignment: .top, spacing: layout.value(8)) {
                        VStack(alignment: .leading, spacing: layout.value(3)) {
                            Text(tracker.url)
                                .font(layout.font(11, weight: .medium, design: .monospaced))
                                .lineLimit(1)
                            Text(trackerSubtitle(tracker))
                                .font(layout.font(10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button {
                            coordinator.removeTorrentTracker(task, url: tracker.url)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(L10n.string("torrent_remove_tracker"))
                        .help(L10n.string("torrent_remove_tracker"))
                    }
                    .padding(layout.value(10))
                    .background(ContentSurfaceBackground(cornerRadius: 8))
                }
            }
        }
    }

    private var trackerBatchURLs: [String] {
        trackerBatchText
            .components(separatedBy: CharacterSet(charactersIn: ", \n\t"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var peerPanel: some View {
        VStack(alignment: .leading, spacing: layout.value(8)) {
            Text(L10n.string("torrent_peers"))
                .font(layout.font(10, weight: .semibold))
                .foregroundStyle(.secondary)

            if task.torrentPeers.isEmpty {
                Text(L10n.string("torrent_peers_empty"))
                    .font(layout.font(11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(task.torrentPeers.prefix(100)) { peer in
                    HStack(spacing: layout.value(8)) {
                        VStack(alignment: .leading, spacing: layout.value(3)) {
                            Text(peer.address)
                                .font(layout.font(11, weight: .medium, design: .monospaced))
                                .lineLimit(1)
                            Text(peerSubtitle(peer))
                                .font(layout.font(10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: layout.value(2)) {
                            Text(peer.progress.formatted(.percent.precision(.fractionLength(0))))
                            Text(L10n.string(
                                "torrent_peer_speed_pair",
                                speed(peer.downloadRate),
                                speed(peer.uploadRate)
                            ))
                        }
                        .font(layout.font(10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    }
                    .padding(layout.value(10))
                    .background(ContentSurfaceBackground(cornerRadius: 8))
                }
            }
        }
    }

    private func trackerSubtitle(_ tracker: TorrentTrackerInfo) -> String {
        let seeds = tracker.seedCount >= 0 ? "\(tracker.seedCount)" : "--"
        let peers = tracker.leecherCount >= 0 ? "\(tracker.leecherCount)" : "--"
        let base = L10n.string(
            "torrent_tracker_subtitle",
            tracker.status,
            tracker.tier,
            seeds,
            peers
        )
        guard let error = tracker.errorMessage else { return base }
        return L10n.string("torrent_detail_join", base, error)
    }

    private func peerSubtitle(_ peer: TorrentPeerInfo) -> String {
        let sourceLabel = peerSourceLabel(peer.source)
        let details = peer.client.isEmpty
            ? peer.flags
            : L10n.string("torrent_detail_join", peer.client, peer.flags)
        return L10n.string("torrent_detail_join", sourceLabel, details)
    }

    private func speed(_ bytesPerSecond: Int64) -> String {
        ByteCountFormatter.downloadFormatter.string(fromByteCount: bytesPerSecond) + "/s"
    }

    private func enabledLabel(_ enabled: Bool) -> String {
        enabled ? L10n.string("connection_enabled") : L10n.string("connection_disabled")
    }

    private func peerSourceSummary(_ health: TorrentHealthInfo) -> String {
        [
            L10n.string("torrent_peer_source_count", peerSourceLabel("tracker"), health.trackerPeerCount),
            L10n.string("torrent_peer_source_count", peerSourceLabel("dht"), health.dhtPeerCount),
            L10n.string("torrent_peer_source_count", peerSourceLabel("pex"), health.pexPeerCount),
            L10n.string("torrent_peer_source_count", peerSourceLabel("lsd"), health.lsdPeerCount)
        ].joined(separator: L10n.string("torrent_detail_separator"))
    }

    private func peerSourceLabel(_ source: String?) -> String {
        switch source?.lowercased() {
        case "dht":
            L10n.string("torrent_peer_source_dht")
        case "pex":
            L10n.string("torrent_peer_source_pex")
        case "lsd":
            L10n.string("torrent_peer_source_lsd")
        default:
            L10n.string("torrent_peer_source_tracker")
        }
    }
}

private struct LogsPanel: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    @Environment(\.responsiveLayout) private var layout
    let task: DownloadTask

    var body: some View {
        VStack(alignment: .leading, spacing: layout.value(8)) {
            HStack(spacing: layout.value(8)) {
                Text(L10n.string("inspector_tab_logs"))
                    .font(layout.font(10, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    coordinator.copyLogs(task)
                } label: {
                    Label(L10n.string("logs_copy_all"), systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .disabled(task.logEntries.isEmpty)
                .accessibilityLabel(L10n.string("logs_copy_all"))
                .help(L10n.string("logs_copy_all"))

                Button {
                    _ = coordinator.exportLogs(task)
                } label: {
                    Label(L10n.string("logs_export"), systemImage: "square.and.arrow.up")
                        .labelStyle(.iconOnly)
                }
                .disabled(task.logEntries.isEmpty)
                .accessibilityLabel(L10n.string("logs_export"))
                .help(L10n.string("logs_export"))

                Button(role: .destructive) {
                    coordinator.clearLogs(task)
                } label: {
                    Label(L10n.string("logs_clear"), systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .disabled(task.logEntries.isEmpty)
                .accessibilityLabel(L10n.string("logs_clear"))
                .help(L10n.string("logs_clear"))
            }

            if task.logEntries.isEmpty {
                Text(L10n.string("logs_empty"))
                    .font(layout.font(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(layout.value(20))
            } else {
                ForEach(task.logEntries, id: \.self) { entry in
                    HStack(alignment: .top, spacing: layout.value(8)) {
                        Text("•")
                            .font(layout.font(12, weight: .semibold))
                            .foregroundStyle(Color.blue)
                        
                        Text(entry)
                            .font(layout.font(11, design: .monospaced))
                            .textSelection(.enabled)
                            .lineSpacing(layout.value(2))
                            .foregroundStyle(Color.primary)
                    }
                    .padding(layout.value(8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        ContentSurfaceBackground(cornerRadius: 8)
                    }
                }
            }
        }
    }
}

private struct DetailRow: View {
    @Environment(\.responsiveLayout) private var layout
    let title: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: layout.value(4)) {
            Text(title)
                .font(layout.font(10, weight: .semibold))
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(layout.font(12, design: .monospaced))
                .foregroundStyle(color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(layout.value(12))
        .background {
            ContentSurfaceBackground(cornerRadius: 8)
        }
    }
}
