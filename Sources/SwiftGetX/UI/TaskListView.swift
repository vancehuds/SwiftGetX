import AppKit
import SwiftUI

struct TaskListView: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    @Environment(\.responsiveLayout) private var layout
    let tasks: [DownloadTask]
    @State private var tasksToDelete: [DownloadTask] = []

    var body: some View {
        @Bindable var coordinator = coordinator

        GlassSurface(level: .panel, cornerRadius: 18) {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: layout.value(2)) {
                        Text(coordinator.activeListTitle)
                            .font(layout.font(16, weight: .semibold))
                            .foregroundStyle(Color.primary)
                        Text(summary(for: tasks))
                            .font(layout.font(11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !tasks.isEmpty {
                        Button {
                            coordinator.selectAllVisible(tasks)
                        } label: {
                            Label(L10n.string("action_select_all"), systemImage: "checklist")
                                .labelStyle(.iconOnly)
                                .font(layout.font(12, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .help(L10n.string("action_select_all"))

                        Menu {
                            Button(L10n.string("batch_cleanup_completed_failed")) {
                                coordinator.cleanupCompletedAndFailed(deletingFiles: false)
                            }
                            Button(L10n.string("batch_cleanup_completed_failed_files"), role: .destructive) {
                                coordinator.cleanupCompletedAndFailed(deletingFiles: true)
                            }
                            Divider()
                            Button(L10n.string("batch_archive_completed")) {
                                coordinator.archiveCompletedTasks()
                            }
                            Button(L10n.string("batch_archive_failed")) {
                                coordinator.archiveFailedTasks()
                            }
                            if coordinator.activeFilter == .archived {
                                Divider()
                                Button(L10n.string("batch_remove_archived_records"), role: .destructive) {
                                    coordinator.removeArchivedTaskRecords()
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(layout.font(13, weight: .semibold))
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .help(L10n.string("task_list_actions"))
                    }
                }
                .padding(.horizontal, layout.value(18))
                .padding(.vertical, layout.value(14))

                Divider()
                    .opacity(0.24)

                if coordinator.selectedTaskCount > 1 {
                    BatchTaskActionBar(
                        selectedCount: coordinator.selectedTaskCount,
                        deleteAction: {
                            tasksToDelete = coordinator.selectedTasks
                        }
                    )
                    Divider()
                        .opacity(0.24)
                }

                if tasks.isEmpty {
                    EmptyTaskView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: layout.value(7)) {
                            ForEach(tasks) { task in
                                TaskRowView(
                                    task: task,
                                    isSelected: coordinator.effectiveSelectedTaskIDs.contains(task.id)
                                )
                                .onTapGesture {
                                    withAnimation(.easeOut(duration: 0.12)) {
                                        if NSEvent.modifierFlags.contains(.command) {
                                            coordinator.toggleSelection(task)
                                        } else {
                                            coordinator.selectOnly(task)
                                        }
                                    }
                                }
                                .contextMenu {
                                    let isPausable = task.status == .running || task.status == .fetchingMetadata || task.status == .fetchingPeers || task.status == .connectingPeers || task.status == .seeding || task.status == .verifying
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
                                    Menu(L10n.string("task_category")) {
                                        ForEach(DownloadTaskCategory.allCases) { category in
                                            Button {
                                                coordinator.selectOnly(task)
                                                coordinator.setSelectedCategory(category)
                                            } label: {
                                                Label(category.title, systemImage: category.symbolName)
                                            }
                                        }
                                    }
                                    Menu(L10n.string("task_tags")) {
                                        ForEach(["Important", "Later", "Review"], id: \.self) { tag in
                                            Button(tag) {
                                                coordinator.selectOnly(task)
                                                coordinator.setSelectedTags([tag])
                                            }
                                        }
                                        if !task.normalizedTags.isEmpty {
                                            Button(L10n.string("task_tags_clear")) {
                                                coordinator.selectOnly(task)
                                                coordinator.setSelectedTags([])
                                            }
                                        }
                                    }
                                    if task.isArchived {
                                        Button(L10n.string("action_unarchive")) {
                                            coordinator.selectOnly(task)
                                            coordinator.unarchiveSelected()
                                        }
                                    } else {
                                        Button(L10n.string("action_archive")) {
                                            coordinator.selectOnly(task)
                                            coordinator.archiveSelected()
                                        }
                                    }
                                    Divider()
                                    Button(L10n.string("action_reveal_in_finder")) {
                                        NSWorkspace.shared.activateFileViewerSelecting([task.revealURL])
                                    }
                                    Divider()
                                    Button(L10n.string("action_delete_task"), role: .destructive) {
                                        tasksToDelete = [task]
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
            deleteDialogTitle,
            isPresented: Binding(
                get: { !tasksToDelete.isEmpty },
                set: { if !$0 { tasksToDelete = [] } }
            )
        ) {
            if !tasksToDelete.isEmpty {
                if tasksToDelete.allSatisfy(\.hasFinishedDownloading) {
                    Button(L10n.string("delete_task_only"), role: .destructive) {
                        removePendingTasks(deletingFiles: false)
                    }
                    Button(L10n.string("delete_task_and_local_file"), role: .destructive) {
                        removePendingTasks(deletingFiles: true)
                    }
                } else {
                    Button(L10n.string("delete_task_and_partial_file"), role: .destructive) {
                        removePendingTasks(deletingFiles: true)
                    }
                }
            }
            Button(L10n.string("action_cancel"), role: .cancel) {
                tasksToDelete = []
            }
        } message: {
            if !tasksToDelete.isEmpty {
                if tasksToDelete.count == 1, let task = tasksToDelete.first {
                    if task.hasFinishedDownloading {
                        Text(L10n.string("delete_task_completed_message", task.localContentDeletionPathSummary))
                    } else {
                        Text(L10n.string("delete_task_unfinished_message", task.localContentDeletionPathSummary))
                    }
                } else {
                    Text(batchDeleteMessage)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .confirmSelectedTaskRemoval)) { _ in
            tasksToDelete = coordinator.selectedTasks
        }
    }

    private var deleteDialogTitle: String {
        if tasksToDelete.count > 1 {
            return L10n.string("delete_tasks_dialog_title", tasksToDelete.count)
        }
        return L10n.string("delete_task_dialog_title")
    }

    private var batchDeleteMessage: String {
        let paths = tasksToDelete
            .flatMap(\.localContentDeletionURLs)
            .map(\.path)
            .joined(separator: "\n")
        let summary = paths.isEmpty ? L10n.string("delete_task_no_known_local_content") : paths
        if tasksToDelete.allSatisfy(\.hasFinishedDownloading) {
            return L10n.string("delete_tasks_completed_message", tasksToDelete.count, summary)
        }
        return L10n.string("delete_tasks_unfinished_message", tasksToDelete.count, summary)
    }

    private func removePendingTasks(deletingFiles: Bool) {
        let pending = tasksToDelete
        tasksToDelete = []
        if Set(pending.map(\.id)) == coordinator.effectiveSelectedTaskIDs {
            coordinator.removeSelected(deletingFiles: deletingFiles)
        } else {
            for task in pending {
                coordinator.remove(task, deletingFiles: deletingFiles)
            }
        }
    }

    private func summary(for tasks: [DownloadTask]) -> String {
        let running = tasks.filter(\.usesActiveDownloadSlot).count
        let completed = tasks.filter(\.hasFinishedDownloading).count
        return L10n.string("task_list_summary", tasks.count, running, completed)
    }
}

private struct BatchTaskActionBar: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    @Environment(\.responsiveLayout) private var layout
    let selectedCount: Int
    let deleteAction: () -> Void

    var body: some View {
        HStack(spacing: layout.value(8)) {
            Text(L10n.string("tasks_selected_count", selectedCount))
                .font(layout.font(12, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                coordinator.resumeSelected()
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.plain)
            .help(L10n.string("action_start"))

            Button {
                coordinator.pauseSelected()
            } label: {
                Image(systemName: "pause.fill")
            }
            .buttonStyle(.plain)
            .help(L10n.string("action_pause"))

            Button {
                coordinator.recheckSelected()
            } label: {
                Image(systemName: "checkmark.seal")
            }
            .buttonStyle(.plain)
            .help(L10n.string("action_recheck"))

            Menu {
                Button(L10n.string("batch_move_default_folder")) {
                    coordinator.moveSelectedToDefaultDirectory()
                }
                Divider()
                Button(L10n.string("queue_move_top")) {
                    coordinator.moveSelectedToTop()
                }
                Button(L10n.string("queue_move_up")) {
                    coordinator.moveSelectedUp()
                }
                Button(L10n.string("queue_move_down")) {
                    coordinator.moveSelectedDown()
                }
                Divider()
                ForEach(DownloadQueuePriority.allCases) { priority in
                    Button {
                        coordinator.setSelectedQueuePriority(priority)
                    } label: {
                        Label(priority.title, systemImage: priority.symbolName)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .help(L10n.string("queue_priority"))

            Menu {
                ForEach(DownloadTaskCategory.allCases) { category in
                    Button {
                        coordinator.setSelectedCategory(category)
                    } label: {
                        Label(category.title, systemImage: category.symbolName)
                    }
                }
            } label: {
                Image(systemName: "folder.badge.gearshape")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .help(L10n.string("task_category"))

            Menu {
                ForEach(["Important", "Later", "Review"], id: \.self) { tag in
                    Button(tag) {
                        coordinator.setSelectedTags([tag])
                    }
                }
                Button(L10n.string("task_tags_clear")) {
                    coordinator.setSelectedTags([])
                }
            } label: {
                Image(systemName: "tag")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .help(L10n.string("task_tags"))

            Menu {
                Button(L10n.string("speed_unlimited")) {
                    coordinator.setSelectedDownloadLimit(0)
                }
                Button("1 MB/s") {
                    coordinator.setSelectedDownloadLimit(1_000_000)
                }
                Button("5 MB/s") {
                    coordinator.setSelectedDownloadLimit(5_000_000)
                }
                Button("10 MB/s") {
                    coordinator.setSelectedDownloadLimit(10_000_000)
                }
            } label: {
                Image(systemName: "speedometer")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .help(L10n.string("speed_limit"))

            Button {
                coordinator.archiveSelected()
            } label: {
                Image(systemName: "archivebox")
            }
            .buttonStyle(.plain)
            .help(L10n.string("action_archive"))

            Button {
                coordinator.unarchiveSelected()
            } label: {
                Image(systemName: "archivebox.fill")
            }
            .buttonStyle(.plain)
            .help(L10n.string("action_unarchive"))

            Button(role: .destructive, action: deleteAction) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .help(L10n.string("action_delete_task"))

            Button {
                coordinator.clearSelection()
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.plain)
            .help(L10n.string("action_clear_selection"))
        }
        .font(layout.font(12, weight: .semibold))
        .padding(.horizontal, layout.value(18))
        .padding(.vertical, layout.value(9))
    }
}

extension Notification.Name {
    static let confirmSelectedTaskRemoval = Notification.Name("SwiftGetX.confirmSelectedTaskRemoval")
}

private struct TaskRowView: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.responsiveLayout) private var layout
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let task: DownloadTask
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: layout.value(12)) {
            Button {
                coordinator.toggleSelection(task)
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(layout.font(15, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: layout.value(22), height: layout.value(34))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? L10n.string("action_clear_selection") : L10n.string("action_select_task"))
            .help(isSelected ? L10n.string("action_clear_selection") : L10n.string("action_select_task"))

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
                    } else if task.status == .seeding {
                        HStack(spacing: layout.value(3)) {
                            Image(systemName: "arrow.up")
                                .font(layout.font(9, weight: .bold))
                            Text(ByteCountFormatter.downloadFormatter.string(fromByteCount: task.torrentConnection?.uploadRate ?? 0) + "/s")
                        }
                        .font(layout.font(11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.mint)

                        HStack(spacing: layout.value(3)) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(layout.font(9))
                            Text(String(format: "%.2f", task.torrentConnection?.shareRatio ?? 0))
                        }
                        .font(layout.font(11, design: .monospaced))
                        .foregroundStyle(.secondary)

                        HStack(spacing: layout.value(3)) {
                            Image(systemName: "clock")
                                .font(layout.font(9))
                            Text(TimeFormatter.eta(task.torrentConnection?.seedingDurationSeconds ?? task.torrentHealth?.seedingDurationSeconds ?? 0))
                        }
                        .font(layout.font(11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    } else if task.status == .fetchingMetadata || task.status == .fetchingPeers || task.status == .connectingPeers {
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
                    let isPausable = task.status == .running || task.status == .fetchingMetadata || task.status == .fetchingPeers || task.status == .connectingPeers || task.status == .seeding || task.status == .verifying
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
                    .accessibilityLabel(isPausable ? L10n.string("action_pause") : L10n.string("action_start"))
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
                    .accessibilityLabel(L10n.string("action_reveal_in_finder"))
                    .help(L10n.string("action_reveal_in_finder"))

                    Button {
                        coordinator.selectOnly(task)
                        NotificationCenter.default.post(name: .confirmSelectedTaskRemoval, object: nil)
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(layout.font(10, weight: .bold))
                            .foregroundStyle(.red)
                            .frame(width: layout.value(26), height: layout.value(26))
                            .background(Color.red.opacity(colorScheme == .dark ? 0.20 : 0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.string("action_delete_task"))
                    .help(L10n.string("action_delete_task"))
                }
                .padding(layout.value(4))
                .background {
                    if reduceTransparency {
                        Capsule()
                            .fill(Color(nsColor: .controlBackgroundColor))
                    } else {
                        Capsule()
                            .fill(.regularMaterial)
                    }
                }
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
        case .fetchingMetadata:
            .purple
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
