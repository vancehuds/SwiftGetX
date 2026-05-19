import SwiftUI

struct ToolbarView: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    @Environment(\.openSettings) private var openSettings
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
                .background(Color.primary.opacity(0.07), in: Capsule())

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
                .frame(width: 34, height: 34)
                .background(Color.primary.opacity(0.08), in: Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .help("全局限速")
    }
}
