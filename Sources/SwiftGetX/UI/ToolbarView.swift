import SwiftUI

struct ToolbarView: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var colorScheme
    @Binding var showingNewTask: Bool

    var body: some View {
        @Bindable var coordinator = coordinator

        GlassSurface(level: .floating, cornerRadius: 20) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Button {
                        showingNewTask = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(IconButtonStyle())
                    .help("新建下载任务")

                    Button {
                        guard let task = coordinator.selectedTask else { return }
                        switch task.status {
                        case .running, .queued, .verifying:
                            coordinator.pause(task)
                        default:
                            coordinator.resume(task)
                        }
                    } label: {
                        Image(systemName: coordinator.selectedTask?.status == .running ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(IconButtonStyle())
                    .disabled(coordinator.selectedTask == nil)
                    .help("开始或暂停选中任务")

                    Button {
                        NotificationCenter.default.post(name: .confirmSelectedTaskRemoval, object: nil)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(IconButtonStyle())
                    .disabled(coordinator.selectedTask == nil)
                    .help("删除任务")
                }

                Divider()
                    .frame(height: 24)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索任务、链接或文件名", text: $coordinator.searchText)
                        .textFieldStyle(.plain)
                        .frame(maxWidth: 320)
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background {
                    Capsule()
                        .fill(.thinMaterial)
                        .overlay {
                            Capsule()
                                .fill(Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.035))
                        }
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.15 : 0.45), lineWidth: 0.8)
                        }
                }

                Spacer()

                SpeedLimitMenu()

                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(IconButtonStyle())
                .help("设置")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
}

private struct SpeedLimitMenu: View {
    @Environment(DownloadCoordinator.self) private var coordinator

    var body: some View {
        Menu {
            Button("不限速") {
                coordinator.setSpeedLimit(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0)
            }
            Button("1 MB/s") {
                coordinator.setSpeedLimit(downloadBytesPerSecond: 1_000_000, uploadBytesPerSecond: 256_000)
            }
            Button("5 MB/s") {
                coordinator.setSpeedLimit(downloadBytesPerSecond: 5_000_000, uploadBytesPerSecond: 512_000)
            }
            Button("10 MB/s") {
                coordinator.setSpeedLimit(downloadBytesPerSecond: 10_000_000, uploadBytesPerSecond: 1_000_000)
            }
        } label: {
            Label("限速", systemImage: "speedometer")
                .labelStyle(.iconOnly)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(
                    GlassIconButtonBackground(isPressed: false)
                )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .help("全局限速")
    }
}
