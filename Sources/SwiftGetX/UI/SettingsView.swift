import SwiftData
import SwiftUI

struct SettingsView: View {
    @ObservedObject var updater: SoftwareUpdater
    @State private var diagnostics = NativeHostDiagnostics()

    var body: some View {
        SettingsHost(
            updater: updater,
            diagnostics: diagnostics
        )
    }
}

private struct SettingsHost: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Environment(DownloadCoordinator.self) private var coordinator
    @Environment(\.responsiveLayout) private var parentLayout
    @ObservedObject var updater: SoftwareUpdater
    let diagnostics: NativeHostDiagnostics

    @State private var activeTab = 0

    var body: some View {
        TabView(selection: $activeTab) {
            DownloadSettingsTab(
                settings: settings,
                layout: parentLayout,
                chooseDirectory: chooseDirectory
            )
            .tabItem {
                Label(L10n.string("settings_download_section"), systemImage: "arrow.down.circle")
            }
            .tag(0)

            TorrentSettingsTab(
                settings: settings,
                layout: parentLayout
            )
            .tabItem {
                Label("BT", systemImage: "bolt.horizontal")
            }
            .tag(1)

            SystemSettingsTab(
                settings: settings,
                layout: parentLayout
            )
            .tabItem {
                Label(L10n.string("settings_system_section"), systemImage: "gearshape")
            }
            .tag(2)

            BrowserIntegrationTab(
                settings: settings,
                diagnostics: diagnostics,
                layout: parentLayout
            )
            .tabItem {
                Label(L10n.string("browser_integration_section"), systemImage: "safari")
            }
            .tag(3)

            UpdateSettingsTab(
                updater: updater,
                layout: parentLayout
            )
            .tabItem {
                Label(L10n.string("settings_updates_section"), systemImage: "arrow.triangle.2.circlepath")
            }
            .tag(4)
        }
        .frame(width: parentLayout.value(520), height: parentLayout.value(440))
        .modifier(lifecycleModifier)
        .id(settings.language)
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
    let downloadRestartPolicy: DownloadRestartPolicy
    let automaticallyRequeuesFailedTasks: Bool
    let queueFailureRetryLimit: Int
    let stopSeedingAtRatio: Double
    let stopSeedingAfterSeconds: TimeInterval
    let torrentDHTEnabled: Bool
    let torrentPEXEnabled: Bool
    let torrentLSDEnabled: Bool
    let torrentSequentialDownloadEnabled: Bool
    let torrentMagnetMetadataTimeoutSeconds: Int
    let torrentMaxConnections: Int
    let torrentMaxUploadSlots: Int
    let torrentSeedingLimitMode: TorrentSeedingLimitMode
    let torrentEngine: TorrentEngineKind
    let torrentDHTBootstrapNodes: [String]
    let language: AppLanguage

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
        downloadRestartPolicy = settings.downloadRestartPolicy
        automaticallyRequeuesFailedTasks = settings.automaticallyRequeuesFailedTasks
        queueFailureRetryLimit = settings.queueFailureRetryLimit
        stopSeedingAtRatio = settings.stopSeedingAtRatio
        stopSeedingAfterSeconds = settings.stopSeedingAfterSeconds
        torrentDHTEnabled = settings.torrentDHTEnabled
        torrentPEXEnabled = settings.torrentPEXEnabled
        torrentLSDEnabled = settings.torrentLSDEnabled
        torrentSequentialDownloadEnabled = settings.torrentSequentialDownloadEnabled
        torrentMagnetMetadataTimeoutSeconds = settings.torrentMagnetMetadataTimeoutSeconds
        torrentMaxConnections = settings.torrentMaxConnections
        torrentMaxUploadSlots = settings.torrentMaxUploadSlots
        torrentSeedingLimitMode = settings.torrentSeedingLimitMode
        torrentEngine = settings.torrentEngine
        torrentDHTBootstrapNodes = settings.torrentDHTBootstrapNodes
        language = settings.language
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

// MARK: - Download Tab
private struct DownloadSettingsTab: View {
    @Bindable var settings: AppSettings
    let layout: ResponsiveLayout
    let chooseDirectory: () -> Void

    var body: some View {
        Form {
            Section {
                downloadDirectoryRow
            }

            Section(L10n.string("settings_download_section")) {
                Stepper(
                    L10n.string("settings_concurrent_tasks", settings.concurrentTaskLimit),
                    value: $settings.concurrentTaskLimit,
                    in: 1...12
                )
                
                Picker(L10n.string("queue_restart_policy"), selection: $settings.downloadRestartPolicy) {
                    ForEach(DownloadRestartPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                
                Toggle(L10n.string("queue_auto_requeue_failed"), isOn: $settings.automaticallyRequeuesFailedTasks)
                
                Stepper(
                    L10n.string("queue_retry_limit", settings.queueFailureRetryLimit),
                    value: $settings.queueFailureRetryLimit,
                    in: 0...10
                )
                .disabled(!settings.automaticallyRequeuesFailedTasks)
                
                SpeedLimitSettingsRow(
                    title: L10n.string("download_speed_limit"),
                    value: $settings.globalDownloadLimitBytes,
                    values: [0, 1_000_000, 5_000_000, 10_000_000, 20_000_000]
                )
            }

            Section("HTTP 多线程") {
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
            }
        }
        .formStyle(.grouped)
    }

    private var downloadDirectoryRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: layout.value(4)) {
                Text(L10n.string("default_download_directory"))
                    .font(layout.font(13, weight: .semibold))
                Text(settings.defaultDownloadDirectory.path)
                    .font(layout.font(11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(L10n.string("action_choose")) {
                chooseDirectory()
            }
            .buttonStyle(.bordered)
        }
        .padding(layout.value(10))
        .background {
            ContentSurfaceBackground(cornerRadius: 10)
        }
    }
}

// MARK: - BT Tab
private struct TorrentSettingsTab: View {
    @Bindable var settings: AppSettings
    let layout: ResponsiveLayout

    var body: some View {
        Form {
            Section("BT 引擎") {
                Picker(L10n.string("torrent_engine"), selection: $settings.torrentEngine) {
                    ForEach(TorrentEngineKind.allCases) { engine in
                        Text(engine.title).tag(engine)
                    }
                }
                
                Text(settings.torrentEngine == .swift
                    ? L10n.string("torrent_engine_swift_status")
                    : L10n.string("torrent_engine_libtorrent_status"))
                    .font(layout.font(11))
                    .foregroundStyle(.secondary)
            }

            Section("网络与连接") {
                Toggle(L10n.string("torrent_enable_dht"), isOn: $settings.torrentDHTEnabled)
                
                if settings.torrentDHTEnabled {
                    VStack(alignment: .leading, spacing: layout.value(4)) {
                        Text(L10n.string("torrent_dht_bootstrap_nodes"))
                            .font(layout.font(11, weight: .semibold))
                        
                        TextEditor(text: Binding(
                            get: { settings.torrentDHTBootstrapNodes.joined(separator: "\n") },
                            set: { settings.torrentDHTBootstrapNodes = $0.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
                        ))
                        .frame(height: layout.value(64))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        .font(.system(.body, design: .monospaced))
                    }
                    .padding(.vertical, layout.value(4))
                }

                Toggle(L10n.string("torrent_enable_pex"), isOn: $settings.torrentPEXEnabled)
                Toggle(L10n.string("torrent_enable_lsd"), isOn: $settings.torrentLSDEnabled)
                Toggle(L10n.string("torrent_enable_sequential_default"), isOn: $settings.torrentSequentialDownloadEnabled)

                Stepper(
                    L10n.string("torrent_magnet_timeout_seconds", settings.torrentMagnetMetadataTimeoutSeconds),
                    value: $settings.torrentMagnetMetadataTimeoutSeconds,
                    in: 3...120
                )
                Stepper(
                    L10n.string("torrent_max_connections", settings.torrentMaxConnections),
                    value: $settings.torrentMaxConnections,
                    in: 2...1000
                )
                Stepper(
                    L10n.string("torrent_max_upload_slots", settings.torrentMaxUploadSlots),
                    value: $settings.torrentMaxUploadSlots,
                    in: -1...128
                )
            }

            Section("做种与限速") {
                SpeedLimitSettingsRow(
                    title: L10n.string("upload_speed_limit"),
                    value: $settings.globalUploadLimitBytes,
                    values: [0, 256_000, 512_000, 1_000_000, 5_000_000]
                )

                Picker(L10n.string("torrent_seeding_mode"), selection: $settings.torrentSeedingLimitMode) {
                    ForEach(TorrentSeedingLimitMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                if settings.torrentSeedingLimitMode == .stopAtRatio {
                    VStack(alignment: .leading, spacing: layout.value(4)) {
                        Slider(value: $settings.stopSeedingAtRatio, in: 0...5, step: 0.1) {
                            Text(L10n.string("share_ratio_limit"))
                        }
                        
                        Text(L10n.string("stop_seeding_ratio_message", settings.stopSeedingAtRatio))
                            .font(layout.font(11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, layout.value(4))
                }

                if settings.torrentSeedingLimitMode == .stopAfterTime {
                    VStack(alignment: .leading, spacing: layout.value(4)) {
                        Stepper(
                            L10n.string(
                                "stop_seeding_time_limit",
                                TimeFormatter.eta(settings.stopSeedingAfterSeconds)
                            ),
                            value: $settings.stopSeedingAfterSeconds,
                            in: 60...604_800,
                            step: 60
                        )

                        Text(L10n.string("stop_seeding_time_message", TimeFormatter.eta(settings.stopSeedingAfterSeconds)))
                            .font(layout.font(11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, layout.value(4))
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - System Tab
private struct SystemSettingsTab: View {
    @Bindable var settings: AppSettings
    let layout: ResponsiveLayout

    var body: some View {
        Form {
            Section(L10n.string("settings_system_section")) {
                Picker(L10n.string("settings_system_language"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                
                Toggle(L10n.string("completion_notifications"), isOn: $settings.completionNotificationsEnabled)
                Toggle(L10n.string("clipboard_link_detection"), isOn: $settings.clipboardDetectionEnabled)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Browser Tab
private struct BrowserIntegrationTab: View {
    @Bindable var settings: AppSettings
    let diagnostics: NativeHostDiagnostics
    let layout: ResponsiveLayout

    var body: some View {
        Form {
            Section("选项") {
                Toggle(L10n.string("confirm_browser_takeover_downloads"), isOn: $settings.confirmBrowserTakeoverDownloads)
            }

            Section(L10n.string("browser_integration_section")) {
                BrowserIntegrationRow(diagnostics: diagnostics, layout: layout)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Updates Tab
private struct UpdateSettingsTab: View {
    @ObservedObject var updater: SoftwareUpdater
    let layout: ResponsiveLayout

    var body: some View {
        Form {
            Section(L10n.string("settings_updates_section")) {
                VStack(alignment: .leading, spacing: layout.value(10)) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: layout.value(3)) {
                            Text(L10n.string("updates_current_version", updater.currentVersion))
                                .font(layout.font(13, weight: .semibold))
                            Text(lastCheckedText)
                                .font(layout.font(11.5))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(L10n.string("command_check_for_updates")) {
                            updater.checkForUpdates()
                        }
                        .disabled(!updater.canCheckForUpdates)
                    }

                    if let feedURL = updater.feedURL {
                        Text(L10n.string("updates_feed_url", feedURL.absoluteString))
                            .font(layout.font(10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, layout.value(4))
            }

            Section {
                Toggle(
                    L10n.string("updates_automatic_checks"),
                    isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.setAutomaticUpdateChecksEnabled($0) }
                    )
                )

                Toggle(
                    L10n.string("updates_automatic_downloads"),
                    isOn: Binding(
                        get: { updater.automaticallyDownloadsUpdates },
                        set: { updater.setAutomaticDownloadsEnabled($0) }
                    )
                )
                .disabled(!updater.allowsAutomaticUpdates)
            }
        }
        .formStyle(.grouped)
    }

    private var lastCheckedText: String {
        guard let date = updater.lastUpdateCheckDate else {
            return L10n.string("updates_last_checked_never")
        }

        return L10n.string(
            "updates_last_checked",
            DateFormatter.updateCheckFormatter.string(from: date)
        )
    }
}

// MARK: - Components
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
        VStack(alignment: .leading, spacing: layout.value(10)) {
            summaryRow

            if !diagnostics.detailMessage.isEmpty {
                Text(diagnostics.detailMessage)
                    .font(layout.font(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text(
                L10n.string(
                    "browser_diagnostics_supported_summary",
                    diagnostics.detectedBrowserCount,
                    diagnostics.supportedBrowserCount,
                    diagnostics.configuredBrowserCount
                )
            )
            .font(layout.font(11))
            .foregroundStyle(.secondary)

            if !diagnostics.browserDiagnostics.isEmpty {
                Divider()
                    .padding(.vertical, layout.value(2))

                ForEach(diagnostics.browserDiagnostics) { browserDiagnostic in
                    BrowserDiagnosticRow(diagnostic: browserDiagnostic, layout: layout)
                }
            }
        }
        .padding(layout.value(12))
        .background {
            ContentSurfaceBackground(cornerRadius: 12)
        }
    }

    private var summaryRow: some View {
        HStack(spacing: layout.value(8)) {
            statusDot
            VStack(alignment: .leading, spacing: layout.value(2)) {
                Text(L10n.string("browser_native_host"))
                    .font(layout.font(13, weight: .semibold))
                Text(diagnostics.statusMessage)
                    .font(layout.font(12))
                    .foregroundStyle(statusColor)
            }
            Spacer()
            actionButtons
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
        diagnostics.status.statusColor
    }
}

private struct BrowserDiagnosticRow: View {
    let diagnostic: ChromeNativeHostBrowserDiagnostic
    let layout: ResponsiveLayout

    var body: some View {
        VStack(alignment: .leading, spacing: layout.value(5)) {
            HStack(alignment: .firstTextBaseline, spacing: layout.value(7)) {
                Circle()
                    .fill(statusColor)
                    .frame(width: layout.value(6), height: layout.value(6))
                    .offset(y: layout.value(-1))

                VStack(alignment: .leading, spacing: layout.value(2)) {
                    Text(diagnostic.browserName)
                        .font(layout.font(12, weight: .semibold))
                    Text(diagnostic.statusMessage)
                        .font(layout.font(11))
                        .foregroundStyle(statusColor)
                }
                Spacer()
            }

            if !diagnostic.detailMessage.isEmpty {
                diagnosticText(diagnostic.detailMessage)
            }

            diagnosticText(
                L10n.string(
                    "browser_diagnostics_extension_ids",
                    extensionIDSummary(diagnostic.discoveredExtensionIDs)
                )
            )
            diagnosticText(L10n.string("browser_diagnostics_manifest_path", diagnostic.manifestURL.path))

            if let nativeHostPath = diagnostic.nativeHostPath {
                diagnosticText(L10n.string("browser_diagnostics_native_host_path", nativeHostPath))
            }

            if let allowedOriginCount = diagnostic.allowedOriginCount {
                diagnosticText(L10n.string("browser_diagnostics_allowed_origins", allowedOriginCount))
            }
        }
        .padding(.vertical, layout.value(3))
    }

    private func diagnosticText(_ value: String) -> some View {
        Text(value)
            .font(layout.font(10.5))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .truncationMode(.middle)
            .textSelection(.enabled)
    }

    private func extensionIDSummary(_ extensionIDs: [String]) -> String {
        extensionIDs.isEmpty
            ? L10n.string("browser_diagnostics_no_extension_ids")
            : extensionIDs.joined(separator: ", ")
    }

    private var statusColor: Color {
        switch diagnostic.status {
        case .ok:
            .green
        case .warning:
            diagnostic.isConfigured ? .orange : .secondary
        case .error:
            .red
        }
    }
}

extension NativeHostDiagnostics.DiagnosticStatus {
    var statusColor: Color {
        switch self {
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
