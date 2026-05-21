import SwiftData
import SwiftUI

struct ToolbarView: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.responsiveLayout) private var layout
    @Binding var showingNewTask: Bool

    @Query private var allTasks: [DownloadTask]
    @FocusState private var isSearchFocused: Bool

    private var totalDownloadSpeed: Int64 {
        allTasks
            .filter { $0.status == .running || $0.status == .fetchingMetadata || $0.status == .fetchingPeers || $0.status == .connectingPeers }
            .reduce(0) { $0 + $1.speedBytesPerSecond }
    }

    private var selectedTaskIsPausable: Bool {
        guard let status = coordinator.selectedTask?.status else { return false }
        return status == .running || status == .fetchingMetadata || status == .fetchingPeers || status == .connectingPeers || status == .seeding || status == .verifying
    }

    var body: some View {
        @Bindable var coordinator = coordinator

        GlassSurface(level: .floating, cornerRadius: 16) {
            HStack(spacing: layout.value(12)) {
                HStack(spacing: layout.value(9)) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(layout.font(21, weight: .semibold))
                        .foregroundStyle(Color.primary)

                    Text("SwiftGetX")
                        .font(layout.font(14.5, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .padding(.trailing, layout.value(2))

                Divider()
                    .frame(height: layout.value(22))
                    .opacity(0.28)

                HStack(spacing: layout.value(8)) {
                    Button {
                        showingNewTask = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(IconButtonStyle())
                    .help(L10n.string("command_new_download"))

                    Button {
                        guard let task = coordinator.selectedTask else { return }
                        switch task.status {
                        case .running, .fetchingMetadata, .fetchingPeers, .connectingPeers, .seeding, .verifying:
                            coordinator.pause(task)
                        default:
                            coordinator.resume(task)
                        }
                    } label: {
                        Image(systemName: selectedTaskIsPausable ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(IconButtonStyle())
                    .disabled(coordinator.selectedTask == nil)
                    .help(L10n.string("help_toggle_selected_task"))

                    Button {
                        NotificationCenter.default.post(name: .confirmSelectedTaskRemoval, object: nil)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(IconButtonStyle())
                    .disabled(coordinator.selectedTask == nil)
                    .help(L10n.string("action_delete_task"))
                }

                Divider()
                    .frame(height: layout.value(20))
                    .opacity(0.35)

                HStack(spacing: layout.value(8)) {
                    Image(systemName: "magnifyingglass")
                        .font(layout.font(13, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField(L10n.string("search_placeholder"), text: $coordinator.searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .font(layout.font(13))
                }
                .padding(.horizontal, layout.value(12))
                .frame(height: layout.value(34))
                .frame(width: layout.value(280))
                .background {
                    RoundedRectangle(cornerRadius: layout.value(9), style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.075 : 0.035))
                        .overlay {
                            RoundedRectangle(cornerRadius: layout.value(9), style: .continuous)
                                .fill(Color.primary.opacity(isSearchFocused ? 0.025 : 0))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: layout.value(9), style: .continuous)
                                .strokeBorder(
                                    isSearchFocused
                                        ? Color.primary.opacity(colorScheme == .dark ? 0.36 : 0.24)
                                        : Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.08),
                                    lineWidth: 1
                                )
                        }
                }
                .animation(.easeOut(duration: 0.12), value: isSearchFocused)

                Spacer()

                HStack(spacing: layout.value(8)) {
                    Circle()
                        .fill(totalDownloadSpeed > 0 ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: layout.value(7), height: layout.value(7))

                    Image(systemName: "arrow.down")
                        .font(layout.font(10, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(totalDownloadSpeed > 0 ? ByteCountFormatter.downloadFormatter.string(fromByteCount: totalDownloadSpeed) + "/s" : "0 KB/s")
                        .font(layout.font(11.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, layout.value(12))
                .padding(.vertical, layout.value(6))
                .background(Color.primary.opacity(0.04), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(
                            Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.07),
                            lineWidth: 1
                        )
                }

                Divider()
                    .frame(height: layout.value(20))
                    .opacity(0.35)

                HStack(spacing: layout.value(8)) {
                    SpeedLimitMenu()
                    
                    Button {
                        openSettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(IconButtonStyle())
                    .help(L10n.string("menu_settings_plain"))
                }
            }
            .padding(.horizontal, layout.value(12))
            .padding(.vertical, layout.value(7))
        }
    }
}

private struct SpeedLimitMenu: View {
    @Environment(DownloadCoordinator.self) private var coordinator
    @Environment(\.responsiveLayout) private var layout

    var body: some View {
        Menu {
            Button(L10n.string("speed_unlimited")) {
                coordinator.setSpeedLimit(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0, persistsToSettings: true)
            }
            Button("1 MB/s") {
                coordinator.setSpeedLimit(
                    downloadBytesPerSecond: 1_000_000,
                    uploadBytesPerSecond: 256_000,
                    persistsToSettings: true
                )
            }
            Button("5 MB/s") {
                coordinator.setSpeedLimit(
                    downloadBytesPerSecond: 5_000_000,
                    uploadBytesPerSecond: 512_000,
                    persistsToSettings: true
                )
            }
            Button("10 MB/s") {
                coordinator.setSpeedLimit(
                    downloadBytesPerSecond: 10_000_000,
                    uploadBytesPerSecond: 1_000_000,
                    persistsToSettings: true
                )
            }
        } label: {
            Label(L10n.string("speed_limit"), systemImage: "speedometer")
                .labelStyle(.iconOnly)
                .font(layout.font(14, weight: .semibold))
                .frame(width: layout.value(34), height: layout.value(34))
                .background(
                    GlassIconButtonBackground(isPressed: false)
                )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .help(L10n.string("global_speed_limit"))
    }
}
