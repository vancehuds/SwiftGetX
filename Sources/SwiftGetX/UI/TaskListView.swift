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
                                    let isPausable = task.status == .running || task.status == .fetchingPeers || task.status == .connectingPeers || task.status == .seeding || task.status == .verifying
                                    Button(isPausable ? L10n.string("action_pause") : L10n.string("action_start")) {
                                        if isPausable {
                                            coordinator.pause(task)
                                        } else {
                                            coordinator.resume(task)
                                        }
                                    }
                                    Button(L10n.string("action_recheck")) {
                                        coordinator.recheck(task)
                                    }
                                    if task.status == .failed || task.status == .cancelled {
                                        Button(L10n.string("action_retry_task")) {
                                            coordinator.retry(task)
                                        }
                                    }
                                    if let errorMessage = task.errorMessage,
                                       !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    {
                                        Button(L10n.string("action_copy_error")) {
                                            coordinator.copyErrorMessage(task)
                                        }
                                    }
                                    if task.kind == .http {
                                        Button(L10n.string("action_reprobe_metadata")) {
                                            coordinator.reprobeHTTPMetadata(task)
                                        }
                                        if task.status == .failed || task.status == .cancelled || task.status == .paused {
                                            Button(L10n.string("action_rename_and_continue")) {
                                                coordinator.renameAndContinue(task)
                                            }
                                        }
                                        if HTTPPartialDataStore(savePath: task.savePath).hasData {
                                            Button(L10n.string("action_retain_partial_data")) {
                                                coordinator.retainPartialData(task)
                                            }
                                            Button(L10n.string("action_open_partial_data")) {
                                                coordinator.openPartialData(task)
                                            }
                                            Button(L10n.string("action_reveal_partial_data")) {
                                                coordinator.revealPartialData(task)
                                            }
                                            Button(L10n.string("action_delete_partial_data"), role: .destructive) {
                                                coordinator.deletePartialData(task)
                                            }
                                        }
                                    }
                                    if task.isQueueManageable {
                                        Divider()
                                        Button(L10n.string("queue_move_top")) {
                                            coordinator.moveQueueItemToTop(task)
                                        }
                                        Button(L10n.string("queue_move_up")) {
                                            coordinator.moveQueueItemUp(task)
                                        }
                                        Button(L10n.string("queue_move_down")) {
                                            coordinator.moveQueueItemDown(task)
                                        }
                                        Menu(L10n.string("queue_priority")) {
                                            ForEach(DownloadQueuePriority.allCases) { priority in
                                                Button {
                                                    coordinator.setQueuePriority(task, priority: priority)
                                                } label: {
                                                    Label(priority.title, systemImage: priority.symbolName)
                                                }
                                            }
                                        }
                                    }
                                    Divider()
                                    Button(L10n.string("action_reveal_in_finder")) {
                                        NSWorkspace.shared.activateFileViewerSelecting([task.revealURL])
                                    }
                                    Divider()
                                    Button(L10n.string("action_delete_task"), role: .destructive) {
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
            L10n.string("delete_task_dialog_title"),
            isPresented: Binding(
                get: { taskToDelete != nil },
                set: { if !$0 { taskToDelete = nil } }
            )
        ) {
            if let taskToDelete {
                if taskToDelete.hasFinishedDownloading {
                    Button(L10n.string("delete_task_only"), role: .destructive) {
                        coordinator.remove(taskToDelete, deletingFiles: false)
                        self.taskToDelete = nil
                    }
                    Button(L10n.string("delete_task_and_local_file"), role: .destructive) {
                        coordinator.remove(taskToDelete, deletingFiles: true)
                        self.taskToDelete = nil
                    }
                } else {
                    Button(L10n.string("delete_task_and_partial_file"), role: .destructive) {
                        coordinator.remove(taskToDelete, deletingFiles: true)
                        self.taskToDelete = nil
                    }
                }
            }
            Button(L10n.string("action_cancel"), role: .cancel) {
                taskToDelete = nil
            }
        } message: {
            if let taskToDelete {
                if taskToDelete.hasFinishedDownloading {
                    Text(L10n.string("delete_task_completed_message", taskToDelete.localContentDeletionPathSummary))
                } else {
                    Text(L10n.string("delete_task_unfinished_message", taskToDelete.localContentDeletionPathSummary))
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .confirmSelectedTaskRemoval)) { _ in
            taskToDelete = coordinator.selectedTask
        }
    }

    private func summary(for tasks: [DownloadTask]) -> String {
        let running = tasks.filter(\.usesActiveDownloadSlot).count
        let completed = tasks.filter(\.hasFinishedDownloading).count
        return L10n.string("task_list_summary", tasks.count, running, completed)
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

                    if task.isQueueManageable {
                        Label(task.queuePriority.title, systemImage: task.queuePriority.symbolName)
                            .font(layout.font(10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, layout.value(6))
                            .padding(.vertical, layout.value(2))
                            .background(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06), in: Capsule())
                    }

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
                        Text(task.displaySource)
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
                    } else if task.status == .fetchingPeers || task.status == .connectingPeers {
                        Text(task.status.title)
                            .font(layout.font(11, weight: .medium))
                            .foregroundStyle(.blue)
                    } else if task.status == .completed {
                        HStack(spacing: layout.value(3)) {
                            Image(systemName: "checkmark.shield")
                                .font(layout.font(9))
                            Text(L10n.string("task_ready"))
                        }
                        .font(layout.font(11, weight: .semibold))
                        .foregroundStyle(Color.green)
                    } else if task.status == .paused {
                        Text(L10n.string("download_status_paused"))
                            .font(layout.font(11, weight: .medium))
                            .foregroundStyle(.orange)
                    } else if task.status == .failed || task.status == .cancelled {
                        Text(L10n.string("task_failed_message", task.errorMessage ?? L10n.string("error_unknown")))
                            .font(layout.font(11, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(task.status == .cancelled ? .gray : .red)
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
                    let isPausable = task.status == .running || task.status == .fetchingPeers || task.status == .connectingPeers || task.status == .seeding || task.status == .verifying
                    Button {
                        if isPausable {
                            coordinator.pause(task)
                        } else {
                            coordinator.resume(task)
                        }
                    } label: {
                        Image(systemName: isPausable ? "pause.fill" : "play.fill")
                            .font(layout.font(10, weight: .bold))
                            .foregroundStyle(Color.primary)
                            .frame(width: layout.value(26), height: layout.value(26))
                            .background(Color.primary.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(isPausable ? L10n.string("action_pause") : L10n.string("action_start"))

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([task.revealURL])
                    } label: {
                        Image(systemName: "folder.fill")
                            .font(layout.font(10))
                            .foregroundStyle(Color.primary)
                            .frame(width: layout.value(26), height: layout.value(26))
                            .background(Color.primary.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(L10n.string("action_reveal_in_finder"))

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
                    .help(L10n.string("action_delete_task"))
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
        case .fetchingPeers:
            .cyan
        case .connectingPeers:
            .blue
        case .seeding:
            .mint
        case .paused:
            .orange
        case .verifying:
            .indigo
        case .completed:
            .green
        case .failed:
            .red
        case .cancelled:
            .gray
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
                Text(L10n.string("empty_tasks_title"))
                    .font(layout.font(16, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Text(L10n.string("empty_tasks_message"))
                    .font(layout.font(12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, layout.value(30))
            }
        }
        .padding(layout.value(40))
    }
}
