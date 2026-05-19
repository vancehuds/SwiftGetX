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
            LiquidBackground()

            VStack(spacing: 12) {
                ClipboardSuggestionBar()

                ToolbarView(
                    showingNewTask: $showingNewTask
                )

                HStack(spacing: 12) {
                    SidebarView(tasks: allTasks)
                        .frame(width: 196)

                    TaskListView(tasks: visibleTasks)
                        .frame(minWidth: 520)

                    InspectorView()
                        .frame(width: 320)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(16)
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

private struct LiquidBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            if !reduceTransparency {
                baseGradient

                LiquidFlowBand(
                    colors: colorScheme == .dark
                        ? [
                            Color(red: 0.10, green: 0.35, blue: 0.34).opacity(0.24),
                            Color(red: 0.35, green: 0.18, blue: 0.40).opacity(0.18),
                            Color.clear
                        ]
                        : [
                            Color(red: 0.55, green: 0.88, blue: 0.86).opacity(0.44),
                            Color(red: 0.90, green: 0.62, blue: 0.76).opacity(0.28),
                            Color.clear
                        ],
                    angle: -15,
                    verticalScale: 1.45
                )

                LiquidFlowBand(
                    colors: colorScheme == .dark
                        ? [
                            Color.clear,
                            Color(red: 0.32, green: 0.30, blue: 0.12).opacity(0.15),
                            Color(red: 0.12, green: 0.20, blue: 0.38).opacity(0.18)
                        ]
                        : [
                            Color.clear,
                            Color(red: 0.99, green: 0.83, blue: 0.48).opacity(0.26),
                            Color(red: 0.56, green: 0.70, blue: 0.96).opacity(0.28)
                        ],
                    angle: 19,
                    verticalScale: 1.30
                )

                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.08 : 0.34),
                        Color.clear,
                        Color.black.opacity(colorScheme == .dark ? 0.26 : 0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }

    private var baseGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.045, green: 0.052, blue: 0.058),
                    Color(red: 0.075, green: 0.085, blue: 0.090),
                    Color(red: 0.040, green: 0.052, blue: 0.050)
                ]
                : [
                    Color(red: 0.93, green: 0.97, blue: 0.98),
                    Color(red: 0.985, green: 0.98, blue: 0.94),
                    Color(red: 0.94, green: 0.95, blue: 0.99)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct LiquidFlowBand: View {
    let colors: [Color]
    let angle: Double
    let verticalScale: CGFloat

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .scaleEffect(x: 1.30, y: verticalScale)
            .rotationEffect(.degrees(angle))
            .blur(radius: 54)
            .opacity(0.92)
            .blendMode(.plusLighter)
    }
}
