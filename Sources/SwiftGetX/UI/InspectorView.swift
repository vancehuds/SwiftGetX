import SwiftUI

struct InspectorView: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    @State private var selectedTab: InspectorTab = .overview

    var body: some View {
        GlassSurface(level: .panel, cornerRadius: 22) {
            VStack(spacing: 0) {
                if let task = coordinator.selectedTask {
                    // Header Status Info
                    header(for: task)
                    
                    // Segmented Tabs picker
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
                        .opacity(0.18)

                    // Tab View Panels Scroll
                    ScrollView(.vertical, showsIndicators: false) {
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
                    .transition(.opacity)
                } else {
                    // Empty State Selected View
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.primary.opacity(0.04))
                                .frame(width: 64, height: 64)
                            Image(systemName: "sidebar.right")
                                .font(.system(size: 26, weight: .light))
                                .foregroundStyle(.secondary)
                        }

                        Text("选择任务查看详情")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func header(for task: DownloadTask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: task.status.symbolName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(statusColor(for: task.status))
                    .padding(.top, 2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.name)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(2)
                        .foregroundStyle(Color.primary)
                    
                    Text(task.kind.title + " 下载")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }

            LiquidProgressBar(progress: task.progress, tint: statusColor(for: task.status))
            
            HStack {
                Text(task.progress.formatted(.percent.precision(.fractionLength(1))))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(statusColor(for: task.status))
                
                Spacer()
                
                Text(task.status.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.02))
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

// MARK: - Premium 2x2 Grid Overview Panel
private struct OverviewPanel: View {
    let task: DownloadTask
    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(spacing: 12) {
            // MARK: - 2x2 Performance Grid
            LazyVGrid(columns: columns, spacing: 10) {
                // Status Card
                MetricCard(
                    title: "任务状态",
                    value: task.status.title,
                    symbol: task.status.symbolName,
                    color: statusColor
                )

                // Speed Card
                MetricCard(
                    title: "下载速度",
                    value: task.status == .running
                        ? ByteCountFormatter.downloadFormatter.string(fromByteCount: task.speedBytesPerSecond) + "/s"
                        : "--",
                    symbol: "arrow.down.circle",
                    color: task.status == .running ? .green : .secondary
                )

                // ETA Card
                MetricCard(
                    title: "剩余时间",
                    value: task.status == .running
                        ? (task.etaSeconds.map(TimeFormatter.eta) ?? "未知")
                        : "--",
                    symbol: "clock",
                    color: .secondary
                )

                // Progress Size Card
                MetricCard(
                    title: "已下载比例",
                    value: ByteCountFormatter.downloadFormatter.string(fromByteCount: task.downloadedBytes),
                    symbol: "chart.bar.fill",
                    color: .blue
                )
            }

            // MARK: - Secondary Parameters
            VStack(spacing: 8) {
                DetailRow(title: "文件总大小", value: ByteCountFormatter.downloadFormatter.string(fromByteCount: task.totalBytes))
                DetailRow(title: "保存路径", value: task.savePath)
                DetailRow(title: "下载链接/种子源", value: task.source)
                DetailRow(title: "断点续传", value: task.supportsResume ? "支持" : "不支持/未知")
                if let connectionSummary = task.connectionSummary {
                    DetailRow(title: "连接详情", value: connectionSummary)
                }
                if let errorMessage = task.errorMessage {
                    DetailRow(title: "错误消息", value: errorMessage, color: .red)
                }
            }
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .queued: .secondary
        case .running: .blue
        case .paused: .orange
        case .verifying: .purple
        case .completed: .green
        case .failed: .red
        }
    }
}

// MARK: - Metric Card Widget
private struct MetricCard: View {
    let title: String
    let value: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
            }

            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .foregroundStyle(Color.primary)
        }
        .padding(12)
        .background {
            GlassCellBackground(cornerRadius: 14)
        }
    }
}

// MARK: - Files List Panel
private struct FilesPanel: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    let task: DownloadTask

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if task.torrentFiles.isEmpty {
                Text("BT 文件列表会在 metadata 获取后展示。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                HStack {
                    Button("全选") {
                        coordinator.setTorrentFileSelection(
                            task,
                            selectedFileIndexes: task.torrentFiles.map(\.index)
                        )
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.bordered)
                    
                    Button("清空") {
                        coordinator.setTorrentFileSelection(task, selectedFileIndexes: [])
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Text("\(task.selectedFileIndexes.count) / \(task.torrentFiles.count) 个文件")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                ForEach(task.torrentFiles) { file in
                    Button {
                        toggle(file)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: task.selectedFileIndexes.contains(file.index) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(task.selectedFileIndexes.contains(file.index) ? .green : .secondary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(file.path)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                    .foregroundStyle(Color.primary)
                                
                                LiquidProgressBar(progress: file.progress, tint: .blue)
                            }
                            
                            Spacer()
                            
                            Text(ByteCountFormatter.downloadFormatter.string(fromByteCount: file.size))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background {
                            GlassCellBackground(cornerRadius: 12)
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

// MARK: - Connections Panel
private struct ConnectionsPanel: View {
    let task: DownloadTask

    var body: some View {
        VStack(spacing: 8) {
            DetailRow(title: "DHT 状态", value: "已启动 (接收正常)")
            DetailRow(title: "PEX 交换", value: "已启用")
            DetailRow(title: "本地监听端口", value: "端口分配就绪")
            DetailRow(title: "连接详情", value: task.connectionSummary ?? "等待 BT 引擎上报连接 Peer 节点数")
            DetailRow(title: "做种分享限制", value: "达到 1.0 倍率后自动停止")
        }
    }
}

// MARK: - Logs Panel
private struct LogsPanel: View {
    let task: DownloadTask

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if task.logEntries.isEmpty {
                Text("暂无日志记录")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(20)
            } else {
                ForEach(task.logEntries, id: \.self) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.blue)
                        
                        Text(entry)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .lineSpacing(2)
                            .foregroundStyle(Color.primary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        GlassCellBackground(cornerRadius: 10)
                    }
                }
            }
        }
    }
}

// MARK: - Key-Value Row Widget
private struct DetailRow: View {
    let title: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background {
            GlassCellBackground(cornerRadius: 14)
        }
    }
}
