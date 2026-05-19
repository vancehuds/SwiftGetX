import SwiftData
import SwiftUI

struct ToolbarView: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var colorScheme
    @Binding var showingNewTask: Bool

    @Query private var allTasks: [DownloadTask]
    @FocusState private var isSearchFocused: Bool

    private var totalDownloadSpeed: Int64 {
        allTasks.filter { $0.status == .running }.reduce(0) { $0 + $1.speedBytesPerSecond }
    }

    var body: some View {
        @Bindable var coordinator = coordinator

        GlassSurface(level: .floating, cornerRadius: 20) {
            HStack(spacing: 12) {
                // MARK: - Action Group
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
                    .frame(height: 20)
                    .opacity(0.28)

                // MARK: - Animated Expanding Search Bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isSearchFocused ? Color.blue : Color.secondary)
                        .scaleEffect(isSearchFocused ? 1.1 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isSearchFocused)

                    TextField("搜索任务、链接或文件名...", text: $coordinator.searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .frame(width: isSearchFocused ? 280 : 200) // Smooth width expansion!
                .background {
                    Capsule()
                        .fill(isSearchFocused ? .regularMaterial : .thinMaterial)
                        .overlay {
                            Capsule()
                                .fill(Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.035))
                        }
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    isSearchFocused
                                        ? Color.blue.opacity(0.8)
                                        : Color.white.opacity(colorScheme == .dark ? 0.15 : 0.45),
                                    lineWidth: isSearchFocused ? 1.5 : 0.8
                                )
                                .shadow(color: isSearchFocused ? Color.blue.opacity(0.25) : Color.clear, radius: 4)
                        }
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.75), value: isSearchFocused)

                Spacer()

                // MARK: - Overall Speed Monitor Dashboard
                HStack(spacing: 8) {
                    Circle()
                        .fill(totalDownloadSpeed > 0 ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 7, height: 7)
                        .shadow(color: totalDownloadSpeed > 0 ? Color.green.opacity(0.8) : Color.clear, radius: 3)
                        .overlay {
                            if totalDownloadSpeed > 0 {
                                Circle()
                                    .stroke(Color.green.opacity(0.4), lineWidth: 1.5)
                                    .scaleEffect(1.8)
                            }
                        }

                    Text("⬇️ " + (totalDownloadSpeed > 0 ? ByteCountFormatter.downloadFormatter.string(fromByteCount: totalDownloadSpeed) + "/s" : "0 KB/s"))
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(totalDownloadSpeed > 0 ? Color.green : Color.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Color.primary.opacity(totalDownloadSpeed > 0 ? 0.06 : 0.03),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .strokeBorder(
                            totalDownloadSpeed > 0 ? Color.green.opacity(0.25) : Color.white.opacity(0.12),
                            lineWidth: 0.8
                        )
                }
                .animation(.spring, value: totalDownloadSpeed)

                Divider()
                    .frame(height: 20)
                    .opacity(0.28)

                // MARK: - Speed Limit Menu & Settings
                HStack(spacing: 8) {
                    SpeedLimitMenu()
                    
                    Button {
                        openSettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(IconButtonStyle())
                    .help("设置")
                }
            }
            .padding(.horizontal, 14)
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
