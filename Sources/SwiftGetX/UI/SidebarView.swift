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
                                filter: filter,
                                count: tasks.filter { filter.matches($0) }.count,
                                isSelected: coordinator.activeFilter == filter
                            ) {
                                withAnimation(.easeOut(duration: 0.12)) {
                                    coordinator.activeFilter = filter
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
    let filter: DownloadFilter
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.responsiveLayout) private var layout
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: layout.value(10)) {
                Image(systemName: filter.symbolName)
                    .font(layout.font(13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? filter.statusColor : .secondary)
                    .frame(width: layout.value(18))

                Text(filter.title)
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
                        tint: filter.statusColor,
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
        case .http:
            .indigo
        case .torrent:
            .teal
        }
    }
}
