import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    @Environment(BrowserBridge.self) private var browserBridge
    @Environment(ClipboardMonitor.self) private var clipboardMonitor
    @Environment(\.openSettings) private var openSettings
    @Query(sort: \DownloadTask.createdAt, order: .reverse) private var allTasks: [DownloadTask]
    @State private var showingNewTask = false
    @State private var newTaskDraft: DownloadDraft?

    var body: some View {
        GeometryReader { proxy in
            let layout = ResponsiveLayout(windowSize: proxy.size)
            let columnSpacing = layout.value(14)
            let horizontalPadding = layout.value(22)
            let availablePanelWidth = max(proxy.size.width - horizontalPadding * 2 - columnSpacing * 2, 1)
            let requestedPanelWidth = layout.value(210 + 520 + 340)
            let panelFitScale = min(1, availablePanelWidth / max(requestedPanelWidth, 1))
            let visibleTasks = filteredTasks()

            ZStack {
                MonochromeWindowBackground()

                VStack(spacing: columnSpacing) {
                    ToolbarView(
                        showingNewTask: $showingNewTask
                    )

                    HStack(spacing: columnSpacing) {
                        SidebarView(tasks: allTasks)
                            .frame(width: layout.value(210) * panelFitScale)

                        TaskListView(tasks: visibleTasks)
                            .frame(minWidth: layout.value(520) * panelFitScale)

                        InspectorView()
                            .frame(width: layout.value(340) * panelFitScale)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, layout.value(14))
                .padding(.bottom, layout.value(18))

                VStack {
                    ClipboardSuggestionBar()
                        .padding(.top, layout.value(64))
                    Spacer()
                }
                .padding(.horizontal, horizontalPadding)
                .allowsHitTesting(clipboardMonitor.suggestedSource != nil)
            }
            .environment(\.responsiveLayout, layout)
            .sheet(isPresented: $showingNewTask) {
                NewTaskSheet(draft: newTaskDraft)
            }
        }
        .frame(minWidth: 720, minHeight: 450)
        .onReceive(NotificationCenter.default.publisher(for: .showNewTaskSheet)) { notification in
            newTaskDraft = notification.object as? DownloadDraft
            showingNewTask = true
        }
        .onChange(of: showingNewTask) { _, isShowing in
            if !isShowing {
                newTaskDraft = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pauseAllDownloads)) { _ in
            coordinator.pauseAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .resumeAllDownloads)) { _ in
            coordinator.resumeAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSwiftGetXSettings)) { _ in
            openSettings()
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
    @Environment(\.responsiveLayout) private var layout

    var body: some View {
        if let source = clipboardMonitor.suggestedSource {
            GlassSurface(level: .floating, cornerRadius: 16) {
                HStack(spacing: layout.value(10)) {
                    Label("检测到下载链接", systemImage: "doc.on.clipboard")
                        .font(layout.font(13, weight: .semibold))
                    Text(source)
                        .font(layout.font(12))
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
                .padding(.horizontal, layout.value(14))
                .padding(.vertical, layout.value(10))
            }
            .frame(maxWidth: layout.value(760))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
