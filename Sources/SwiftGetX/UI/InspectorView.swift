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
                    
                    Picker("详情", selection: $selectedTab) {
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

                        Text("选择任务查看详情")
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
                    
                    Text(task.kind.title + " 下载")
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
        case .paused: .orange
        case .verifying: .indigo
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
                    title: "任务状态",
                    value: task.status.title,
                    symbol: task.status.symbolName,
                    color: statusColor
                )

                MetricCard(
                    title: "下载速度",
                    value: task.status == .running
                        ? ByteCountFormatter.downloadFormatter.string(fromByteCount: task.speedBytesPerSecond) + "/s"
                        : "--",
                    symbol: "arrow.down.circle",
                    color: task.status == .running ? .green : .secondary
                )

                MetricCard(
                    title: "剩余时间",
                    value: task.status == .running
                        ? (task.etaSeconds.map(TimeFormatter.eta) ?? "未知")
                        : "--",
                    symbol: "clock",
                    color: .secondary
                )

                MetricCard(
                    title: "已下载比例",
                    value: ByteCountFormatter.downloadFormatter.string(fromByteCount: task.downloadedBytes),
                    symbol: "chart.bar.fill",
                    color: .blue
                )
            }

            VStack(spacing: layout.value(8)) {
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
        case .verifying: .indigo
        case .completed: .green
        case .failed: .red
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

private struct FilesPanel: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    @Environment(\.responsiveLayout) private var layout
    let task: DownloadTask

    var body: some View {
        VStack(alignment: .leading, spacing: layout.value(12)) {
            if task.torrentFiles.isEmpty {
                Text("BT 文件列表会在 metadata 获取后展示。")
                    .font(layout.font(12))
                    .foregroundStyle(.secondary)
                    .padding(layout.value(12))
            } else {
                HStack {
                    Button("全选") {
                        coordinator.setTorrentFileSelection(
                            task,
                            selectedFileIndexes: task.torrentFiles.map(\.index)
                        )
                    }
                    .font(layout.font(11, weight: .semibold))
                    .buttonStyle(.bordered)
                    
                    Button("清空") {
                        coordinator.setTorrentFileSelection(task, selectedFileIndexes: [])
                    }
                    .font(layout.font(11, weight: .semibold))
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Text("\(task.selectedFileIndexes.count) / \(task.torrentFiles.count) 个文件")
                        .font(layout.font(11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                ForEach(task.torrentFiles) { file in
                    Button {
                        toggle(file)
                    } label: {
                        HStack(spacing: layout.value(12)) {
                            Image(systemName: task.selectedFileIndexes.contains(file.index) ? "checkmark.circle.fill" : "circle")
                                .font(layout.font(14, weight: .semibold))
                                .foregroundStyle(task.selectedFileIndexes.contains(file.index) ? .green : .secondary)
                            
                            VStack(alignment: .leading, spacing: layout.value(4)) {
                                Text(file.path)
                                    .font(layout.font(12, weight: .medium))
                                    .lineLimit(1)
                                    .foregroundStyle(Color.primary)
                                
                                LiquidProgressBar(progress: file.progress, tint: .blue)
                            }
                            
                            Spacer()
                            
                            Text(ByteCountFormatter.downloadFormatter.string(fromByteCount: file.size))
                                .font(layout.font(11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(layout.value(10))
                        .background {
                            ContentSurfaceBackground(cornerRadius: 8)
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
    @Environment(\.responsiveLayout) private var layout
    let task: DownloadTask

    var body: some View {
        VStack(spacing: layout.value(8)) {
            DetailRow(title: "DHT 状态", value: "已启动 (接收正常)")
            DetailRow(title: "PEX 交换", value: "已启用")
            DetailRow(title: "本地监听端口", value: "端口分配就绪")
            DetailRow(title: "连接详情", value: task.connectionSummary ?? "等待 BT 引擎上报连接 Peer 节点数")
            DetailRow(title: "做种分享限制", value: "达到 1.0 倍率后自动停止")
        }
    }
}

private struct LogsPanel: View {
    @Environment(\.responsiveLayout) private var layout
    let task: DownloadTask

    var body: some View {
        VStack(alignment: .leading, spacing: layout.value(6)) {
            if task.logEntries.isEmpty {
                Text("暂无日志记录")
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
