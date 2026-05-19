import AppKit
import SwiftUI

struct TaskListView: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    let tasks: [DownloadTask]
    @State private var taskToDelete: DownloadTask?

    var body: some View {
        @Bindable var coordinator = coordinator

        GlassSurface(level: .panel, cornerRadius: 22) {
            VStack(spacing: 0) {
                // MARK: - Header Area
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(coordinator.activeFilter.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.primary)
                        Text(summary(for: tasks))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)

                Divider()
                    .opacity(0.18)

                // MARK: - Task Items Scroll
                if tasks.isEmpty {
                    EmptyTaskView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(tasks) { task in
                                TaskRowView(
                                    task: task,
                                    isSelected: coordinator.selectedTaskID == task.id
                                )
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
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
                        .padding(14)
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

// MARK: - Premium Task Row View
private struct TaskRowView: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    @Environment(\.colorScheme) private var colorScheme
    let task: DownloadTask
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Icon Category Indicator
            ZStack {
                Circle()
                    .fill(statusColor.opacity(colorScheme == .dark ? 0.16 : 0.10))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Circle()
                            .strokeBorder(statusColor.opacity(0.24), lineWidth: 0.8)
                    }

                Image(systemName: task.kind.symbolName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                // Title and Status Label
                HStack(spacing: 8) {
                    Text(task.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(Color.primary)

                    Label(task.status.title, systemImage: task.status.symbolName)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.08), in: Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(statusColor.opacity(0.18), lineWidth: 0.7)
                        }

                    Spacer()

                    // File Total Size
                    Text(ByteCountFormatter.downloadFormatter.string(fromByteCount: task.totalBytes))
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                // Progress Bar
                LiquidProgressBar(progress: task.progress, tint: statusColor)

                // Sub-Metrics
                HStack(spacing: 14) {
                    // Task source domain/IP
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.system(size: 10))
                        Text(task.source)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 180, alignment: .leading)

                    Spacer()

                    if task.status == .running {
                        // Current Speed
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 9, weight: .bold))
                            Text(ByteCountFormatter.downloadFormatter.string(fromByteCount: task.speedBytesPerSecond) + "/s")
                        }
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.green)

                        // ETA
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                            Text(task.etaSeconds.map(TimeFormatter.eta) ?? "--")
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    } else if task.status == .completed {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.shield")
                                .font(.system(size: 9))
                            Text("已安全就绪")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.green)
                    } else if task.status == .paused {
                        Text("已暂停")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                    } else if task.status == .failed {
                        Text("失败：\(task.errorMessage ?? "未知错误")")
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(.red)
                    } else {
                        Text(task.status.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background {
            GlassCellBackground(isSelected: isSelected, tint: statusColor, cornerRadius: 16)
        }
        // Elegant Selected Neon Breathing Glow
        .breathingGlow(color: statusColor, isAnimating: isSelected, cornerRadius: 16)
        // Inline Floating Action Overlay on Hover
        .overlay(alignment: .topTrailing) {
            if isHovered {
                HStack(spacing: 6) {
                    // Play/Pause Action
                    Button {
                        if task.status == .running {
                            coordinator.pause(task)
                        } else {
                            coordinator.resume(task)
                        }
                    } label: {
                        Image(systemName: task.status == .running ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.primary)
                            .frame(width: 26, height: 26)
                            .background(Color.primary.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(task.status == .running ? "暂停" : "开始")

                    // Open Finder Action
                    Button {
                        let url = URL(fileURLWithPath: task.savePath)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.primary)
                            .frame(width: 26, height: 26)
                            .background(Color.primary.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("在访达中显示")

                    // Delete Action
                    Button {
                        coordinator.selectedTaskID = task.id
                        NotificationCenter.default.post(name: .confirmSelectedTaskRemoval, object: nil)
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.red)
                            .frame(width: 26, height: 26)
                            .background(Color.red.opacity(colorScheme == .dark ? 0.20 : 0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("删除任务")
                }
                .padding(4)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8)
                }
                .shadow(color: Color.black.opacity(0.18), radius: 6, y: 3)
                .padding(.top, 10)
                .padding(.trailing, 10)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.72), value: isHovered)
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
            .purple
        case .completed:
            .green
        case .failed:
            .red
        }
    }
}

// MARK: - Premium Empty State View
private struct EmptyTaskView: View {
    @State private var animateDrop = false

    var body: some View {
        VStack(spacing: 20) {
            // Immersive Liquid Glass Drop Art
            ZStack {
                // Outer blurring glow
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.cyan.opacity(0.24), Color.blue.opacity(0.16)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 90, height: 90)
                    .blur(radius: 12)
                    .scaleEffect(animateDrop ? 1.15 : 0.95)

                // Glass body
                Circle()
                    .fill(.thinMaterial)
                    .frame(width: 80, height: 80)
                    .overlay {
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.68), Color.white.opacity(0.18)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.2
                            )
                    }
                    .shadow(color: Color.black.opacity(0.08), radius: 8, y: 4)

                // Shimmer core
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.cyan, Color.blue, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .offset(y: animateDrop ? 3 : -3)
            }
            .onAppear {
                withAnimation(
                    Animation
                        .easeInOut(duration: 2.2)
                        .repeatForever(autoreverses: true)
                ) {
                    animateDrop = true
                }
            }

            VStack(spacing: 6) {
                Text("还没有下载任务")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.primary)
                Text("点击左上角加号，粘贴直链、磁力链接或种子文件地址。")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
        }
        .padding(40)
    }
}
