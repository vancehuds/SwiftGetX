import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    @Environment(BrowserBridge.self) private var browserBridge
    @Environment(ClipboardMonitor.self) private var clipboardMonitor
    @Query(sort: \DownloadTask.createdAt, order: .reverse) private var allTasks: [DownloadTask]
    @State private var showingNewTask = false

    var body: some View {
        @Bindable var coordinator = coordinator
        let visibleTasks = filteredTasks()

        ZStack {
            AppBackground()

            VStack(spacing: 10) {
                ClipboardSuggestionBar()

                ToolbarView(
                    showingNewTask: $showingNewTask
                )

                HStack(spacing: 10) {
                    SidebarView(tasks: allTasks)
                        .frame(width: 196)

                    TaskListView(tasks: visibleTasks)
                        .frame(minWidth: 520)

                    InspectorView()
                        .frame(width: 320)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(12)
        }
        .frame(minWidth: 1080, minHeight: 680)
        .sheet(isPresented: $showingNewTask) {
            NewTaskSheet()
                .frame(width: 560)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showNewTaskSheet)) { _ in
            showingNewTask = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .pauseAllDownloads)) { _ in
            coordinator.pauseAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .resumeAllDownloads)) { _ in
            coordinator.resumeAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusTaskFromNotification)) { notification in
            if let idString = notification.object as? String, let id = UUID(uuidString: idString) {
                coordinator.selectedTaskID = id
            }
        }
    }

    private func filteredTasks() -> [DownloadTask] {
        allTasks.filter { task in
            let matchesFilter = coordinator.activeFilter.matches(task)
            let matchesSearch = coordinator.searchText.isEmpty
                || task.name.localizedCaseInsensitiveContains(coordinator.searchText)
                || task.source.localizedCaseInsensitiveContains(coordinator.searchText)
            return matchesFilter && matchesSearch
        }
    }
}

private struct ClipboardSuggestionBar: View {
    @Environment(ClipboardMonitor.self) private var clipboardMonitor

    var body: some View {
        if let source = clipboardMonitor.suggestedSource {
            GlassSurface(level: .floating, cornerRadius: 16) {
                HStack(spacing: 10) {
                    Label("检测到下载链接", systemImage: "doc.on.clipboard")
                        .font(.callout.weight(.semibold))
                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("忽略") {
                        clipboardMonitor.dismissSuggestion()
                    }
                    Button {
                        clipboardMonitor.acceptSuggestion()
                    } label: {
                        Label("添加", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }
}

private struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color(nsColor: colorScheme == .dark ? .windowBackgroundColor : .underPageBackgroundColor)
        .ignoresSafeArea()
    }
}
