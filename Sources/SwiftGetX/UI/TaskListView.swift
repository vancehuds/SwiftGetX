import AppKit
import SwiftUI

struct TaskListView: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    @Environment(\.responsiveLayout) private var layout
    let tasks: [DownloadTask]
    @State private var taskToDelete: DownloadTask?

    var body: some View {
        @Bindable var coordinator = coordinator

        GlassSurface(level: .panel, cornerRadius: 18) {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: layout.value(2)) {
                        Text(coordinator.activeFilter.title)
                            .font(layout.font(16, weight: .semibold))
                            .foregroundStyle(Color.primary)
                        Text(summary(for: tasks))
                            .font(layout.font(11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, layout.value(18))
                .padding(.vertical, layout.value(14))

                Divider()
                    .opacity(0.24)

                if tasks.isEmpty {
                    EmptyTaskView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: layout.value(7)) {
                            ForEach(tasks) { task in
                                TaskRowView(
                                    task: task,
                                    isSelected: coordinator.selectedTaskID == task.id
                                )
                                .onTapGesture {
                                    withAnimation(.easeOut(duration: 0.12)) {
                                        coordinator.selectedTaskID = task.id
                                    }
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
                                    Button("在访达中显示") {
                                        let url = URL(fileURLWithPath: task.savePath)
                                        NSWorkspace.shared.activateFileViewerSelecting([url])
                                    }
                                    Divider()
                                    Button("删除任务", role: .destructive) {
                                        taskToDelete = task
                                    }
                                }
                            }
                        }
                        .padding(layout.value(12))
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
                if taskToDelete.status == .completed {
                    Button("仅删除任务", role: .destructive) {
                        coordinator.remove(taskToDelete, deletingFiles: false)
                        self.taskToDelete = nil
                    }
                    Button("删除任务和本地文件", role: .destructive) {
                        coordinator.remove(taskToDelete, deletingFiles: true)
                        self.taskToDelete = nil
                    }
                } else {
                    Button("删除任务和已下载部分", role: .destructive) {
                        coordinator.remove(taskToDelete, deletingFiles: true)
                        self.taskToDelete = nil
                    }
                }
            }
            Button("取消", role: .cancel) {
                taskToDelete = nil
            }
        } message: {
            if let taskToDelete {
                if taskToDelete.status == .completed {
                    Text("可以只删除任务记录，也可以同时删除本地文件。")
                } else {
                    Text("未完成的下载会自动删除已下载部分和临时分块，避免残留。")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .confirmSelectedTaskRemoval)) { _ in
            taskToDelete = coordinator.selectedTask
        }
    }

    private func summary(for tasks: [DownloadTask]) -> String {
        let running = tasks.filter { $0.status == .running }.count
        let completed = tasks.filter { $0.status == .completed }.count
        return "\(tasks.count) 个任务 · \(running) 下载中 · \(completed) 已完成"
    }
}

extension Notification.Name {
    static let confirmSelectedTaskRemoval = Notification.Name("SwiftGetX.confirmSelectedTaskRemoval")
}

private struct TaskRowView: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.responsiveLayout) private var layout
    let task: DownloadTask
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: layout.value(12)) {
            Image(systemName: task.kind.symbolName)
                .font(layout.font(16, weight: .medium))
                .foregroundStyle(statusColor)
                .frame(width: layout.value(34), height: layout.value(34))
                .background(statusColor.opacity(colorScheme == .dark ? 0.14 : 0.09), in: RoundedRectangle(cornerRadius: layout.value(7), style: .continuous))

            VStack(alignment: .leading, spacing: layout.value(6)) {
                HStack(spacing: layout.value(8)) {
                    Text(task.name)
                        .font(layout.font(13.5, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(Color.primary)

                    Label(task.status.title, systemImage: task.status.symbolName)
                        .font(layout.font(10, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, layout.value(6))
                        .padding(.vertical, layout.value(2))
                        .background(statusColor.opacity(colorScheme == .dark ? 0.16 : 0.09), in: Capsule())

                    Spacer()

                    Text(ByteCountFormatter.downloadFormatter.string(fromByteCount: task.totalBytes))
                        .font(layout.font(11.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                LiquidProgressBar(progress: task.progress, tint: statusColor)

                HStack(spacing: layout.value(14)) {
                    HStack(spacing: layout.value(4)) {
                        Image(systemName: "globe")
                            .font(layout.font(10))
                        Text(task.source)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: layout.value(180), alignment: .leading)

                    Spacer()

                    if task.status == .running {
                        HStack(spacing: layout.value(3)) {
                            Image(systemName: "arrow.down")
                                .font(layout.font(9, weight: .bold))
                            Text(ByteCountFormatter.downloadFormatter.string(fromByteCount: task.speedBytesPerSecond) + "/s")
                        }
                        .font(layout.font(11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.green)

                        HStack(spacing: layout.value(3)) {
                            Image(systemName: "clock")
                                .font(layout.font(9))
                            Text(task.etaSeconds.map(TimeFormatter.eta) ?? "--")
                        }
                        .font(layout.font(11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    } else if task.status == .completed {
                        HStack(spacing: layout.value(3)) {
                            Image(systemName: "checkmark.shield")
                                .font(layout.font(9))
                            Text("已安全就绪")
                        }
                        .font(layout.font(11, weight: .semibold))
                        .foregroundStyle(Color.green)
                    } else if task.status == .paused {
                        Text("已暂停")
                            .font(layout.font(11, weight: .medium))
                            .foregroundStyle(.orange)
                    } else if task.status == .failed {
                        Text("失败：\(task.errorMessage ?? "未知错误")")
                            .font(layout.font(11, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(.red)
                    } else {
                        Text(task.status.title)
                            .font(layout.font(11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(layout.font(11))
                .foregroundStyle(.secondary)
            }
        }
        .padding(layout.value(12))
        .background {
            GlassCellBackground(isSelected: isSelected, tint: statusColor, cornerRadius: 8)
        }
        .overlay(alignment: .topTrailing) {
            if isHovered {
                HStack(spacing: layout.value(6)) {
                    Button {
                        if task.status == .running {
                            coordinator.pause(task)
                        } else {
                            coordinator.resume(task)
                        }
                    } label: {
                        Image(systemName: task.status == .running ? "pause.fill" : "play.fill")
                            .font(layout.font(10, weight: .bold))
                            .foregroundStyle(Color.primary)
                            .frame(width: layout.value(26), height: layout.value(26))
                            .background(Color.primary.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(task.status == .running ? "暂停" : "开始")

                    Button {
                        let url = URL(fileURLWithPath: task.savePath)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Image(systemName: "folder.fill")
                            .font(layout.font(10))
                            .foregroundStyle(Color.primary)
                            .frame(width: layout.value(26), height: layout.value(26))
                            .background(Color.primary.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("在访达中显示")

                    Button {
                        coordinator.selectedTaskID = task.id
                        NotificationCenter.default.post(name: .confirmSelectedTaskRemoval, object: nil)
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(layout.font(10, weight: .bold))
                            .foregroundStyle(.red)
                            .frame(width: layout.value(26), height: layout.value(26))
                            .background(Color.red.opacity(colorScheme == .dark ? 0.20 : 0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("删除任务")
                }
                .padding(layout.value(4))
                .background(.regularMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 1)
                }
                .padding(.top, layout.value(10))
                .padding(.trailing, layout.value(10))
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
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
            .indigo
        case .completed:
            .green
        case .failed:
            .red
        }
    }
}

private struct EmptyTaskView: View {
    @Environment(\.responsiveLayout) private var layout

    var body: some View {
        VStack(spacing: layout.value(16)) {
            Image(systemName: "arrow.down.doc")
                .font(layout.font(34, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: layout.value(72), height: layout.value(72))
                .background(ContentSurfaceBackground(cornerRadius: 36))

            VStack(spacing: layout.value(6)) {
                Text("还没有下载任务")
                    .font(layout.font(16, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Text("点击左上角加号，粘贴直链、磁力链接或种子文件地址。")
                    .font(layout.font(12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, layout.value(30))
            }
        }
        .padding(layout.value(40))
    }
}
