import SwiftData
import SwiftUI

struct SettingsView: View {
    @State private var diagnostics = NativeHostDiagnostics()

    var body: some View {
        SettingsHost(diagnostics: diagnostics)
    }
}

private struct SettingsHost: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Environment(DownloadCoordinator.self) private var coordinator
    @Environment(\.responsiveLayout) private var parentLayout
    let diagnostics: NativeHostDiagnostics

    var body: some View {
        content.modifier(lifecycleModifier)
    }

    private var content: SettingsContent {
        SettingsContent(
            settings: settings,
            diagnostics: diagnostics,
            parentLayout: parentLayout,
            chooseDirectory: chooseDirectory
        )
    }

    private var lifecycleModifier: SettingsLifecycleModifier {
        SettingsLifecycleModifier(
            snapshot: SettingsSnapshot(settings),
            diagnostics: diagnostics,
            persistSettings: persistSettings
        )
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.defaultDownloadDirectory
        if panel.runModal() == .OK, let url = panel.url {
            settings.defaultDownloadDirectory = url
        }
    }

    private func persistSettings() {
        let descriptor = FetchDescriptor<AppSettingsRecord>(
            predicate: #Predicate { $0.id == "default" }
        )

        do {
            if let record = try modelContext.fetch(descriptor).first {
                settings.update(record)
            } else {
                modelContext.insert(settings.makeRecord())
            }
            try modelContext.save()
            coordinator.reloadSettings(settings)
        } catch {
            assertionFailure("Failed to persist settings: \(error)")
        }
    }

}

private struct SettingsSnapshot: Equatable {
    let defaultDownloadDirectory: URL
    let concurrentTaskLimit: Int
    let httpMultithreadingEnabled: Bool
    let httpSegmentCount: Int
    let hideHTTPTemporaryFiles: Bool
    let retryLimit: Int
    let globalDownloadLimitBytes: Int64
    let globalUploadLimitBytes: Int64
    let completionNotificationsEnabled: Bool
    let clipboardDetectionEnabled: Bool
    let confirmBrowserTakeoverDownloads: Bool
    let stopSeedingAtRatio: Double

    @MainActor
    init(_ settings: AppSettings) {
        defaultDownloadDirectory = settings.defaultDownloadDirectory
        concurrentTaskLimit = settings.concurrentTaskLimit
        httpMultithreadingEnabled = settings.httpMultithreadingEnabled
        httpSegmentCount = settings.httpSegmentCount
        hideHTTPTemporaryFiles = settings.hideHTTPTemporaryFiles
        retryLimit = settings.retryLimit
        globalDownloadLimitBytes = settings.globalDownloadLimitBytes
        globalUploadLimitBytes = settings.globalUploadLimitBytes
        completionNotificationsEnabled = settings.completionNotificationsEnabled
        clipboardDetectionEnabled = settings.clipboardDetectionEnabled
        confirmBrowserTakeoverDownloads = settings.confirmBrowserTakeoverDownloads
        stopSeedingAtRatio = settings.stopSeedingAtRatio
    }
}

private struct SettingsLifecycleModifier: ViewModifier {
    let snapshot: SettingsSnapshot
    let diagnostics: NativeHostDiagnostics
    let persistSettings: () -> Void

    func body(content: Content) -> some View {
        content
            .padding(1)
            .onChange(of: snapshot) { _, _ in
                persistSettings()
            }
            .onAppear(perform: checkDiagnostics)
    }

    private func checkDiagnostics() {
        if diagnostics.status == .unchecked {
            diagnostics.repair()
        }
    }
}

private struct SettingsContent: View {
    let settings: AppSettings
    let diagnostics: NativeHostDiagnostics
    let parentLayout: ResponsiveLayout
    let chooseDirectory: () -> Void

    var body: some View {
        GeometryReader(content: panelFrame)
    }

    private func panelFrame(for proxy: GeometryProxy) -> SettingsPanelFrame {
        SettingsPanelFrame(
            settings: settings,
            diagnostics: diagnostics,
            parentLayout: parentLayout,
            size: proxy.size,
            chooseDirectory: chooseDirectory
        )
    }
}

private struct SettingsPanelFrame: View {
    let settings: AppSettings
    let diagnostics: NativeHostDiagnostics
    let parentLayout: ResponsiveLayout
    let size: CGSize
    let chooseDirectory: () -> Void

    var body: some View {
        SettingsPanel(
            settings: settings,
            diagnostics: diagnostics,
            layout: layout,
            chooseDirectory: chooseDirectory
        )
        .environment(\.responsiveLayout, layout)
    }

    private var layout: ResponsiveLayout {
        let widthScale = max(size.width, 1) / 520
        let heightScale = max(size.height, 1) / 480
        let settingsScale = min(widthScale, heightScale)
        return ResponsiveLayout(scale: max(parentLayout.scale, settingsScale))
    }
}

private struct SettingsPanel: View {
    let settings: AppSettings
    let diagnostics: NativeHostDiagnostics
    let layout: ResponsiveLayout
    let chooseDirectory: () -> Void

    var body: some View {
        ZStack {
            MonochromeWindowBackground()

            GlassSurface(level: .panel, cornerRadius: 18) {
                SettingsForm(
                    settings: settings,
                    diagnostics: diagnostics,
                    layout: layout,
                    chooseDirectory: chooseDirectory
                )
            }
            .padding(layout.value(10))
        }
    }
}

private struct SettingsForm: View {
    let settings: AppSettings
    let diagnostics: NativeHostDiagnostics
    let layout: ResponsiveLayout
    let chooseDirectory: () -> Void

    var body: some View {
        Form {
            DownloadSettingsSection(
                settings: settings,
                layout: layout,
                chooseDirectory: chooseDirectory
            )
            TorrentSettingsSection(settings: settings)
            SystemSettingsSection(settings: settings)
            BrowserIntegrationSection(settings: settings, diagnostics: diagnostics, layout: layout)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

private struct DownloadSettingsSection: View {
    @Bindable var settings: AppSettings
    let layout: ResponsiveLayout
    let chooseDirectory: () -> Void

    var body: some View {
        Section(L10n.string("settings_download_section")) {
            downloadDirectoryRow
            Stepper(
                L10n.string("settings_concurrent_tasks", settings.concurrentTaskLimit),
                value: $settings.concurrentTaskLimit,
                in: 1...12
            )
            Toggle(L10n.string("settings_enable_http_multithreading"), isOn: $settings.httpMultithreadingEnabled)
            Stepper(
                L10n.string("settings_http_thread_count", settings.httpSegmentCount),
                value: $settings.httpSegmentCount,
                in: 1...32
            )
                .disabled(!settings.httpMultithreadingEnabled)
            Toggle(L10n.string("settings_hide_http_temp_files"), isOn: $settings.hideHTTPTemporaryFiles)
            Stepper(
                L10n.string("settings_retry_count", settings.retryLimit),
                value: $settings.retryLimit,
                in: 0...10
            )
            SpeedLimitSettingsRow(
                title: L10n.string("download_speed_limit"),
                value: $settings.globalDownloadLimitBytes,
                values: [0, 1_000_000, 5_000_000, 10_000_000, 20_000_000]
            )
        }
    }

    private var downloadDirectoryRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: layout.value(4)) {
                Text(L10n.string("default_download_directory"))
                Text(settings.defaultDownloadDirectory.path)
                    .font(layout.font(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(L10n.string("action_choose")) {
                chooseDirectory()
            }
        }
    }
}

private struct TorrentSettingsSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Section("BT") {
            SpeedLimitSettingsRow(
                title: L10n.string("upload_speed_limit"),
                value: $settings.globalUploadLimitBytes,
                values: [0, 256_000, 512_000, 1_000_000, 5_000_000]
            )
            Slider(value: $settings.stopSeedingAtRatio, in: 0...5, step: 0.1) {
                Text(L10n.string("share_ratio_limit"))
            }
            Text(L10n.string("stop_seeding_ratio_message", settings.stopSeedingAtRatio))
                .foregroundStyle(.secondary)
        }
    }
}

private struct SystemSettingsSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Section(L10n.string("settings_system_section")) {
            Toggle(L10n.string("completion_notifications"), isOn: $settings.completionNotificationsEnabled)
            Toggle(L10n.string("clipboard_link_detection"), isOn: $settings.clipboardDetectionEnabled)
        }
    }
}

private struct BrowserIntegrationSection: View {
    @Bindable var settings: AppSettings
    let diagnostics: NativeHostDiagnostics
    let layout: ResponsiveLayout

    var body: some View {
        Section(L10n.string("browser_integration_section")) {
            Toggle(L10n.string("confirm_browser_takeover_downloads"), isOn: $settings.confirmBrowserTakeoverDownloads)
            BrowserIntegrationRow(diagnostics: diagnostics, layout: layout)
        }
    }
}

private struct SpeedLimitSettingsRow: View {
    let title: String
    @Binding var value: Int64
    let values: [Int64]

    var body: some View {
        Picker(title, selection: $value) {
            ForEach(values, id: \.self) { value in
                Text(label(for: value)).tag(value)
            }
        }
    }

    private func label(for value: Int64) -> String {
        guard value > 0 else { return L10n.string("speed_unlimited") }
        return ByteCountFormatter.downloadFormatter.string(fromByteCount: value) + "/s"
    }
}

private struct BrowserIntegrationRow: View {
    @Bindable var diagnostics: NativeHostDiagnostics
    let layout: ResponsiveLayout

    var body: some View {
        VStack(alignment: .leading, spacing: layout.value(8)) {
            HStack(spacing: layout.value(8)) {
                statusDot
                VStack(alignment: .leading, spacing: layout.value(2)) {
                    Text("Chrome Native Host")
                    Text(diagnostics.statusMessage)
                        .font(layout.font(12))
                        .foregroundStyle(statusColor)
                }
                Spacer()
                actionButtons
            }

            if !diagnostics.detailMessage.isEmpty {
                Text(diagnostics.detailMessage)
                    .font(layout.font(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: layout.value(8), height: layout.value(8))
            .opacity(diagnostics.status == .checking ? 0.6 : 1)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                        value: diagnostics.status == .checking)
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: layout.value(6)) {
            if diagnostics.isRepairable {
                Button(L10n.string("action_try_repair")) {
                    diagnostics.repair()
                }
                .disabled(diagnostics.isChecking)
            }

            Button(L10n.string("action_check")) {
                diagnostics.check()
            }
            .disabled(diagnostics.isChecking)

            Button {
                diagnostics.revealManifest()
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help(L10n.string("help_reveal_manifest"))
        }
    }

    private var statusColor: Color {
        switch diagnostics.status {
        case .unchecked, .checking:
            .secondary
        case .ok:
            .green
        case .warning:
            .orange
        case .error:
            .red
        }
    }
}
