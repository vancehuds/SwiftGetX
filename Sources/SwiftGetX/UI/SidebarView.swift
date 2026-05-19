import SwiftUI

struct SidebarView: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    @Environment(\.colorScheme) private var colorScheme
    let tasks: [DownloadTask]

    var body: some View {
        @Bindable var coordinator = coordinator

        GlassSurface(level: .panel, cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                // MARK: - Premium Branding Header
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.35), Color.purple.opacity(0.25)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 38, height: 38)
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.58), lineWidth: 0.8)
                            }
                            .shadow(color: Color.blue.opacity(0.28), radius: 5, y: 2)

                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.cyan, Color.blue, Color.purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("SwiftGetX")
                            .font(.system(size: 18, weight: .black))
                            .tracking(0.5)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: colorScheme == .dark
                                        ? [Color.white, Color.white.opacity(0.85), Color.cyan.opacity(0.9)]
                                        : [Color.blue, Color.indigo, Color.purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        Text("液态玻璃下载器")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .opacity(0.85)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)

                Divider()
                    .opacity(0.18)
                    .padding(.horizontal, 10)

                // MARK: - Navigation Filters
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(DownloadFilter.allCases) { filter in
                            SidebarRow(
                                filter: filter,
                                count: tasks.filter { filter.matches($0) }.count,
                                isSelected: coordinator.activeFilter == filter
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    coordinator.activeFilter = filter
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }

                Spacer()

                // MARK: - Premium Browser Takeover Widget
                GlassSurface(level: .floating, cornerRadius: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("浏览器接管", systemImage: "safari.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.cyan)
                            
                            Spacer()
                            
                            // Active status pulse dot
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                                .shadow(color: Color.green.opacity(0.8), radius: 3)
                                .overlay {
                                    Circle()
                                        .stroke(Color.green.opacity(0.4), lineWidth: 1.5)
                                        .scaleEffect(1.8)
                                }
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
                // Colored Status Indicator Dot
                Circle()
                    .fill(filter.statusColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: filter.statusColor.opacity(0.6), radius: 2)

                Image(systemName: filter.symbolName)
                    .font(.system(size: 13, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? filter.statusColor : .secondary)
                    .frame(width: 18)

                Text(filter.title)
                    .font(.system(size: 13.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : .secondary)

                Spacer()

                if count > 0 {
                    Text(count.formatted())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.white : filter.statusColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            isSelected
                                ? filter.statusColor
                                : filter.statusColor.opacity(0.12),
                            in: Capsule()
                        )
                        .overlay {
                            if !isSelected {
                                Capsule()
                                    .strokeBorder(filter.statusColor.opacity(0.24), lineWidth: 0.8)
                            }
                        }
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
            .indigo
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
            .purple
        case .torrent:
            .teal
        }
    }
}
