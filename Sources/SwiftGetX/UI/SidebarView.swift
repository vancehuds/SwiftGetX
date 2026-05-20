import SwiftUI

struct SidebarView: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    let tasks: [DownloadTask]

    var body: some View {
        @Bindable var coordinator = coordinator

        GlassSurface(level: .panel, cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("任务")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                            .padding(.bottom, 2)

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
                    .padding(8)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("浏览器接管", systemImage: "safari")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)

                        Spacer()

                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                    }

                    Text("Safari + Chrome 扩展已就绪")
                        .font(.system(size: 10.5))
                        .lineSpacing(2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background {
                    ContentSurfaceBackground(cornerRadius: 10)
                }
                .padding(10)
            }
            .padding(.top, 8)
        }
    }
}

private struct SidebarRow: View {
    let filter: DownloadFilter
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: filter.symbolName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? filter.statusColor : .secondary)
                    .frame(width: 18)

                Text(filter.title)
                    .font(.system(size: 13.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : .secondary)

                Spacer()

                if count > 0 {
                    Text(count.formatted())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(isSelected ? 0.08 : 0.045), in: Capsule())
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
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
            .accentColor
        case .running:
            .blue
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
