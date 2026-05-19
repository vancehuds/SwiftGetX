import SwiftUI

struct InspectorView: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    @State private var selectedTab: InspectorTab = .overview

    var body: some View {
        GlassSurface(level: .panel, cornerRadius: 22) {
            VStack(spacing: 0) {
                if let task = coordinator.selectedTask {
                    header(for: task)
                    Picker("详情", selection: $selectedTab) {
                        ForEach(InspectorTab.tabs(for: task.kind)) { tab in
                            Label(tab.title, systemImage: tab.symbolName)
                                .tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)

                    Divider()
                        .opacity(0.28)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            switch selectedTab {
                            case .overview:
                                OverviewPanel(task: task)
                            case .files:
                                FilesPanel(task: task)
                            case .connections:
                                ConnectionsPanel(task: task)
                            case .logs:
                                LogsPanel(task: task)
                            }
                        }
                        .padding(14)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "sidebar.right")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("选择任务查看详情")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func header(for task: DownloadTask) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: task.status.symbolName)
                    .foregroundStyle(statusColor(for: task.status))
                Text(task.name)
                    .font(.headline)
                    .lineLimit(2)
            }

            LiquidProgressBar(progress: task.progress, tint: statusColor(for: task.status))
            Text(task.progress.formatted(.percent.precision(.fractionLength(1))))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(14)
    }

    private func statusColor(for status: DownloadStatus) -> Color {
        switch status {
        case .queued: .secondary
        case .running: .blue
        case .paused: .orange
        case .verifying: .purple
        case .completed: .green
        case .failed: .red
        }
    }
}

private enum InspectorTab: String, CaseIterable, Identifiable {
    case overview
    case files
    case connections
    case logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "概览"
        case .files: "文件"
        case .connections: "连接"
        case .logs: "日志"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: "info.circle"
        case .files: "folder"
        case .connections: "point.3.connected.trianglepath.dotted"
        case .logs: "list.bullet.rectangle"
        }
    }

    static func tabs(for kind: DownloadKind) -> [InspectorTab] {
        switch kind {
        case .http:
            [.overview, .logs]
        case .torrentMagnet, .torrentFile:
            [.overview, .files, .connections, .logs]
        }
    }
}

private struct OverviewPanel: View {
    let task: DownloadTask

    var body: some View {
        VStack(spacing: 10) {
            DetailRow(title: "状态", value: task.status.title)
            DetailRow(title: "类型", value: task.kind.title)
            DetailRow(title: "保存路径", value: task.savePath)
            DetailRow(title: "已下载", value: ByteCountFormatter.downloadFormatter.string(fromByteCount: task.downloadedBytes))
            DetailRow(title: "总大小", value: ByteCountFormatter.downloadFormatter.string(fromByteCount: task.totalBytes))
            DetailRow(title: "速度", value: ByteCountFormatter.downloadFormatter.string(fromByteCount: task.speedBytesPerSecond) + "/s")
            DetailRow(title: "剩余时间", value: task.etaSeconds.map(TimeFormatter.eta) ?? "--")
            DetailRow(title: "断点续传", value: task.supportsResume ? "支持" : "未知/不支持")
            if let connectionSummary = task.connectionSummary {
                DetailRow(title: "连接", value: connectionSummary)
            }
            if let errorMessage = task.errorMessage {
                DetailRow(title: "错误", value: errorMessage)
            }
        }
    }
}

private struct FilesPanel: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    let task: DownloadTask

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if task.torrentFiles.isEmpty {
                Text("BT 文件列表会在 metadata 获取后展示。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Button("全选") {
                        coordinator.setTorrentFileSelection(
                            task,
                            selectedFileIndexes: task.torrentFiles.map(\.index)
                        )
                    }
                    Button("全不选") {
                        coordinator.setTorrentFileSelection(task, selectedFileIndexes: [])
                    }
                    Spacer()
                    Text("\(task.selectedFileIndexes.count) / \(task.torrentFiles.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ForEach(task.torrentFiles) { file in
                    Button {
                        toggle(file)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: task.selectedFileIndexes.contains(file.index) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(task.selectedFileIndexes.contains(file.index) ? .green : .secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(file.path)
                                    .lineLimit(1)
                                LiquidProgressBar(progress: file.progress, tint: .blue)
                            }
                            Text(ByteCountFormatter.downloadFormatter.string(fromByteCount: file.size))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background {
                            GlassCellBackground(cornerRadius: 10)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
    let task: DownloadTask

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DetailRow(title: "DHT", value: "默认开启")
            DetailRow(title: "PEX", value: "默认开启")
            DetailRow(title: "连接", value: task.connectionSummary ?? "等待 BT 引擎上报")
            DetailRow(title: "分享率限制", value: "1.0")
        }
    }
}

private struct LogsPanel: View {
    let task: DownloadTask

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if task.logEntries.isEmpty {
                Text("暂无日志")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(task.logEntries, id: \.self) { entry in
                    Text(entry)
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background {
                            GlassCellBackground(cornerRadius: 8)
                        }
                }
            }
        }
    }
}

private struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background {
            GlassCellBackground(cornerRadius: 12)
        }
    }
}
