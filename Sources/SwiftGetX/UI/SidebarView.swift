import SwiftUI

struct SidebarView: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    @Environment(\.responsiveLayout) private var layout
    @State private var diagnostics = NativeHostDiagnostics()
    let tasks: [DownloadTask]

    var body: some View {
        @Bindable var coordinator = coordinator

        GlassSurface(level: .panel, cornerRadius: 18) {
            VStack(alignment: .leading, spacing: layout.value(10)) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: layout.value(5)) {
                        Text(L10n.string("sidebar_tasks"))
                            .font(layout.font(11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, layout.value(12))
                            .padding(.top, layout.value(4))
                            .padding(.bottom, layout.value(2))

                        ForEach(DownloadFilter.allCases) { filter in
                            SidebarRow(
                                title: filter.title,
                                symbolName: filter.symbolName,
                                statusColor: filter.statusColor,
                                count: tasks.filter { filter.matches($0) }.count,
                                isSelected: coordinator.activeFilter == filter
                                    && coordinator.activeCategory == nil
                                    && coordinator.activeTag == nil
                            ) {
                                withAnimation(.easeOut(duration: 0.12)) {
                                    coordinator.selectFilter(filter)
                                }
                            }
                        }

                        let categories = coordinator.categories(in: tasks)
                        if !categories.isEmpty {
                            Text(L10n.string("sidebar_categories"))
                                .font(layout.font(11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, layout.value(12))
                                .padding(.top, layout.value(12))
                                .padding(.bottom, layout.value(2))

                            ForEach(categories) { category in
                                SidebarRow(
                                    title: category.title,
                                    symbolName: category.symbolName,
                                    statusColor: .purple,
                                    count: tasks.filter { !$0.isArchived && $0.category == category }.count,
                                    isSelected: coordinator.activeCategory == category
                                ) {
                                    withAnimation(.easeOut(duration: 0.12)) {
                                        coordinator.selectCategory(category)
                                    }
                                }
                            }
                        }

                        let tags = coordinator.tags(in: tasks)
                        if !tags.isEmpty {
                            Text(L10n.string("sidebar_tags"))
                                .font(layout.font(11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, layout.value(12))
                                .padding(.top, layout.value(12))
                                .padding(.bottom, layout.value(2))

                            ForEach(tags, id: \.self) { tag in
                                SidebarRow(
                                    title: "#\(tag)",
                                    symbolName: "tag",
                                    statusColor: .pink,
                                    count: tasks.filter {
                                        !$0.isArchived
                                            && $0.normalizedTags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
                                    }.count,
                                    isSelected: coordinator.activeTag == tag
                                ) {
                                    withAnimation(.easeOut(duration: 0.12)) {
                                        coordinator.selectTag(tag)
                                    }
                                }
                            }
                        }
                    }
                    .padding(layout.value(8))
                }

                Spacer()

                BrowserStatusSidebarPanel(diagnostics: diagnostics)
                .padding(layout.value(12))
                .background {
                    ContentSurfaceBackground(cornerRadius: 10)
                }
                .padding(layout.value(10))
            }
            .padding(.top, layout.value(8))
        }
        .onAppear(perform: checkBrowserDiagnostics)
    }

    private func checkBrowserDiagnostics() {
        if diagnostics.status == .unchecked {
            diagnostics.check()
        }
    }
}

private struct BrowserStatusSidebarPanel: View {
    @Bindable var diagnostics: NativeHostDiagnostics
    @Environment(\.responsiveLayout) private var layout

    var body: some View {
        VStack(alignment: .leading, spacing: layout.value(8)) {
            HStack {
                Label(L10n.string("browser_takeover"), systemImage: "safari")
                    .font(layout.font(12, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Circle()
                    .fill(diagnostics.status.statusColor)
                    .frame(width: layout.value(6), height: layout.value(6))
                    .opacity(diagnostics.status == .checking ? 0.6 : 1)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                        value: diagnostics.status == .checking
                    )
            }

            Text(diagnostics.sidebarStatusMessage)
                .font(layout.font(10.5))
                .lineSpacing(layout.value(2))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if diagnostics.configuredBrowserCount > 0 || diagnostics.discoveredExtensionCount > 0 {
                Text(
                    L10n.string(
                        "browser_diagnostics_sidebar_counts",
                        diagnostics.configuredBrowserCount,
                        diagnostics.discoveredExtensionCount
                    )
                )
                .font(layout.font(10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
        }
    }
}

private struct SidebarRow: View {
    let title: String
    let symbolName: String
    let statusColor: Color
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.responsiveLayout) private var layout
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: layout.value(10)) {
                Image(systemName: symbolName)
                    .font(layout.font(13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? statusColor : .secondary)
                    .frame(width: layout.value(18))

                Text(title)
                    .font(layout.font(13.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : .secondary)

                Spacer()

                if count > 0 {
                    Text(count.formatted())
                        .font(layout.font(10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .padding(.horizontal, layout.value(7))
                        .padding(.vertical, layout.value(3))
                        .background(Color.primary.opacity(isSelected ? 0.08 : 0.045), in: Capsule())
                }
            }
            .padding(.horizontal, layout.value(11))
            .padding(.vertical, layout.value(8))
            .contentShape(Rectangle())
            .background {
                if isSelected || isHovered {
                    ContentSurfaceBackground(
                        isSelected: isSelected,
                        isHovered: isHovered,
                        tint: statusColor,
                        cornerRadius: 8
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private extension DownloadFilter {
    var statusColor: Color {
        switch self {
        case .all:
            .primary
        case .today:
            .blue
        case .recent:
            .cyan
        case .large:
            .indigo
        case .needsAttention:
            .red
        case .running:
            .blue
        case .seeding:
            .mint
        case .queued:
            .secondary
        case .paused:
            .orange
        case .completed:
            .green
        case .failed:
            .red
        case .cancelled:
            .gray
        case .http:
            .indigo
        case .torrent:
            .teal
        case .archived:
            .brown
        }
    }
}
