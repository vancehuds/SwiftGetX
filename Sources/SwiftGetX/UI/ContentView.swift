import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    @Environment(BrowserBridge.self) private var browserBridge
    @Environment(ClipboardMonitor.self) private var clipboardMonitor
    @Environment(AppSettings.self) private var settings
    @Environment(\.openSettings) private var openSettings
    @Query(sort: \DownloadTask.createdAt, order: .reverse) private var allTasks: [DownloadTask]
    @State private var showingNewTask = false
    @State private var newTaskDraft: DownloadDraft?
    @State private var isDropTargeted = false

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

                if isDropTargeted {
                    DropTargetOverlay()
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .environment(\.responsiveLayout, layout)
            .sheet(isPresented: $showingNewTask) {
                NewTaskSheet(draft: newTaskDraft)
            }
            .onDrop(
                of: DownloadDropSourceLoader.supportedTypeIdentifiers,
                isTargeted: $isDropTargeted
            ) { providers in
                DownloadDropSourceLoader.loadDraft(from: providers) { draft in
                    guard let draft else { return }
                    presentDownloadDraft(draft)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 450)
        .id(settings.language)
        .onReceive(NotificationCenter.default.publisher(for: .showNewTaskSheet)) { notification in
            presentDownloadDraft(notification.object as? DownloadDraft)
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
                coordinator.selectedTaskIDs = [id]
            }
        }
    }

    private func filteredTasks() -> [DownloadTask] {
        coordinator.filteredTasks(from: allTasks)
    }

    private func presentDownloadDraft(_ draft: DownloadDraft?) {
        PendingNativeHandoffPolicy.rejectIfReplaced(
            current: newTaskDraft,
            incoming: draft
        )
        newTaskDraft = draft
        showingNewTask = true
    }
}

private struct DropTargetOverlay: View {
    @Environment(\.responsiveLayout) private var layout
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        RoundedRectangle(cornerRadius: layout.value(18), style: .continuous)
            .strokeBorder(
                Color.accentColor.opacity(0.72),
                style: StrokeStyle(lineWidth: layout.value(2), dash: [layout.value(8), layout.value(6)])
            )
            .background(Color.accentColor.opacity(0.06))
            .overlay {
                Image(systemName: "square.and.arrow.down")
                    .font(layout.font(30, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(layout.value(20))
                    .background {
                        if reduceTransparency {
                            Circle()
                                .fill(Color(nsColor: .controlBackgroundColor))
                        } else {
                            Circle()
                                .fill(.thinMaterial)
                        }
                    }
            }
            .padding(layout.value(12))
    }
}

private struct ClipboardSuggestionBar: View {
    @Environment(ClipboardMonitor.self) private var clipboardMonitor
    @Environment(\.responsiveLayout) private var layout

    var body: some View {
        if let source = clipboardMonitor.suggestedSource {
            GlassSurface(level: .floating, cornerRadius: 16) {
                HStack(spacing: layout.value(10)) {
                    Label(L10n.string("clipboard_detected_link"), systemImage: "doc.on.clipboard")
                        .font(layout.font(13, weight: .semibold))
                    Text(source)
                        .font(layout.font(12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button(L10n.string("action_ignore")) {
                        clipboardMonitor.dismissSuggestion()
                    }
                    Button {
                        clipboardMonitor.acceptSuggestion()
                    } label: {
                        Label(L10n.string("action_add"), systemImage: "plus.circle.fill")
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
