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

            VStack(spacing: 14) {
                ToolbarView(
                    showingNewTask: $showingNewTask
                )

                HStack(spacing: 14) {
                    SidebarView(tasks: allTasks)
                        .frame(width: 210)

                    TaskListView(tasks: visibleTasks)
                        .frame(minWidth: 520)

                    InspectorView()
                        .frame(width: 340)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 18)

            VStack {
                ClipboardSuggestionBar()
                    .padding(.top, 64)
                Spacer()
            }
            .padding(.horizontal, 22)
            .allowsHitTesting(clipboardMonitor.suggestedSource != nil)
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
            .frame(maxWidth: 760)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

private struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(nsColor: colorScheme == .dark ? .windowBackgroundColor : .underPageBackgroundColor)

            LinearGradient(
                colors: [
                    Color.accentColor.opacity(colorScheme == .dark ? 0.16 : 0.12),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .center
            )
            .blendMode(colorScheme == .dark ? .screen : .normal)

            LinearGradient(
                colors: [
                    Color(nsColor: .systemTeal).opacity(colorScheme == .dark ? 0.08 : 0.07),
                    Color.clear,
                    Color(nsColor: .systemOrange).opacity(colorScheme == .dark ? 0.05 : 0.04)
                ],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
            .blendMode(colorScheme == .dark ? .screen : .normal)
        }
        .ignoresSafeArea()
    }
}
