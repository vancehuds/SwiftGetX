import SwiftUI

struct SidebarView: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    let tasks: [DownloadTask]

    var body: some View {
        @Bindable var coordinator = coordinator

        GlassSurface(level: .panel, cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("SwiftGetX")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("下载管理器")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 16)

                Divider()
                    .opacity(0.35)
                    .padding(.horizontal, 10)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
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
                    .padding(.horizontal, 8)
                }

                Spacer()

                GlassSurface(level: .floating, cornerRadius: 12) {
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

                        Text("Safari + Chrome 扩展已就绪。系统会自动捕获并把下载发送到 SwiftGetX。")
                            .font(.system(size: 10.5))
                            .lineSpacing(2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                }
                .padding(10)
            }
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
            HStack(spacing: 12) {
                Circle()
                    .fill(filter.statusColor)
                    .frame(width: 6, height: 6)

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
                        .background(
                            Color.primary.opacity(isSelected ? 0.08 : 0.05),
                            in: Capsule()
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    GlassCellBackground(isSelected: true, tint: filter.statusColor, cornerRadius: 12)
                } else if isHovered {
                    GlassCellBackground(isSelected: false, tint: filter.statusColor.opacity(0.2), cornerRadius: 12)
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
