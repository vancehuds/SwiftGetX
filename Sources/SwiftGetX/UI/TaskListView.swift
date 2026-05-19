import SwiftUI

struct TaskListView: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    let tasks: [DownloadTask]
    @State private var taskToDelete: DownloadTask?

    var body: some View {
        @Bindable var coordinator = coordinator

        GlassSurface(level: .panel, cornerRadius: 22) {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(coordinator.activeFilter.title)
                            .font(.title3.weight(.semibold))
                        Text(summary(for: tasks))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(16)

                Divider()
                    .opacity(0.28)

                if tasks.isEmpty {
                    EmptyTaskView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(tasks) { task in
                                TaskRowView(
                                    task: task,
                                    isSelected: coordinator.selectedTaskID == task.id
                                )
                                .onTapGesture {
                                    coordinator.selectedTaskID = task.id
                                }
                                .contextMenu {
                                    Button(task.status == .running ? "暂停" : "开始") {
                                        if task.status == .running {
                                            coordinator.pause(task)
                                        } else {
                                            coordinator.resume(task)
                                        }
                                    }
                                    Button("校验") {
                                        coordinator.recheck(task)
                                    }
                                    Divider()
                                    Button("删除任务", role: .destructive) {
                                        taskToDelete = task
                                    }
                                }
                            }
                        }
                        .padding(12)
                    }
                }
            }
        }
        .confirmationDialog(
            "删除下载任务？",
            isPresented: Binding(
                get: { taskToDelete != nil },
                set: { if !$0 { taskToDelete = nil } }
            )
        ) {
            if let taskToDelete {
                Button("仅删除任务", role: .destructive) {
                    coordinator.remove(taskToDelete, deletingFiles: false)
                    self.taskToDelete = nil
                }
                Button("删除任务和本地文件", role: .destructive) {
                    coordinator.remove(taskToDelete, deletingFiles: true)
                    self.taskToDelete = nil
                }
            }
            Button("取消", role: .cancel) {
                taskToDelete = nil
            }
        }
    }

    private func summary(for tasks: [DownloadTask]) -> String {
        let running = tasks.filter { $0.status == .running }.count
        let completed = tasks.filter { $0.status == .completed }.count
        return "\(tasks.count) 个任务 · \(running) 下载中 · \(completed) 已完成"
    }
}

private struct TaskRowView: View {
    let task: DownloadTask
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.16))
                Image(systemName: task.kind.symbolName)
                    .foregroundStyle(statusColor)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(task.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)

                    Label(task.status.title, systemImage: task.status.symbolName)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)

                    Spacer()

                    Text(ByteCountFormatter.downloadFormatter.string(fromByteCount: task.totalBytes))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                LiquidProgressBar(progress: task.progress, tint: statusColor)

                HStack(spacing: 10) {
                    Text(task.source)
                        .lineLimit(1)
                    Spacer()
                    Text(ByteCountFormatter.downloadFormatter.string(fromByteCount: task.speedBytesPerSecond) + "/s")
                    Text(task.etaSeconds.map(TimeFormatter.eta) ?? "--")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background {
            GlassCellBackground(isSelected: isSelected, tint: statusColor, cornerRadius: 16)
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .queued:
            .secondary
        case .running:
            .blue
        case .paused:
            .orange
        case .verifying:
            .purple
        case .completed:
            .green
        case .failed:
            .red
        }
    }
}

private struct EmptyTaskView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.secondary)
            Text("还没有下载任务")
                .font(.headline)
            Text("点击左上角加号，粘贴直链、磁力链接或种子文件地址。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }
}
