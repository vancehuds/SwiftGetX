import SwiftUI

struct SidebarView: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    let tasks: [DownloadTask]

    var body: some View {
        @Bindable var coordinator = coordinator

        GlassSurface(level: .panel, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SwiftGetX")
                        .font(.system(size: 24, weight: .bold))
                    Text("液态玻璃下载器")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.top, 16)

                VStack(spacing: 4) {
                    ForEach(DownloadFilter.allCases) { filter in
                        SidebarRow(
                            filter: filter,
                            count: tasks.filter { filter.matches($0) }.count,
                            isSelected: coordinator.activeFilter == filter
                        ) {
                            coordinator.activeFilter = filter
                        }
                    }
                }
                .padding(.horizontal, 8)

                Spacer()

                GlassSurface(level: .floating, cornerRadius: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("浏览器接管", systemImage: "safari")
                            .font(.subheadline.weight(.semibold))
                        Text("Safari + Chrome 扩展通过显式操作把下载发送到 SwiftGetX。")
                            .font(.caption)
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: filter.symbolName)
                    .frame(width: 18)
                Text(filter.title)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                Spacer()
                Text(count.formatted())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    GlassCellBackground(isSelected: true, cornerRadius: 12)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
