import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Environment(DownloadCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var settings = settings

        GlassSurface(level: .floating, cornerRadius: 24) {
            Form {
                Section("下载") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("默认下载目录")
                            Text(settings.defaultDownloadDirectory.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("选择") {
                            chooseDirectory()
                        }
                    }
                    Stepper("同时下载任务：\(settings.concurrentTaskLimit)", value: $settings.concurrentTaskLimit, in: 1...12)
                    Toggle("启用 HTTP 多线程下载", isOn: $settings.httpMultithreadingEnabled)
                    Stepper("HTTP 线程数：\(settings.httpSegmentCount)", value: $settings.httpSegmentCount, in: 1...32)
                        .disabled(!settings.httpMultithreadingEnabled)
                    Toggle("隐藏 HTTP 分块临时文件", isOn: $settings.hideHTTPTemporaryFiles)
                    Stepper("失败重试次数：\(settings.retryLimit)", value: $settings.retryLimit, in: 0...10)
                    SpeedLimitSettingsRow(
                        title: "下载限速",
                        value: $settings.globalDownloadLimitBytes,
                        values: [0, 1_000_000, 5_000_000, 10_000_000, 20_000_000]
                    )
                }

                Section("BT") {
                    SpeedLimitSettingsRow(
                        title: "上传限速",
                        value: $settings.globalUploadLimitBytes,
                        values: [0, 256_000, 512_000, 1_000_000, 5_000_000]
                    )
                    Slider(value: $settings.stopSeedingAtRatio, in: 0...5, step: 0.1) {
                        Text("分享率限制")
                    }
                    Text("分享率达到 \(settings.stopSeedingAtRatio, specifier: "%.1f") 后停止做种")
                        .foregroundStyle(.secondary)
                }

                Section("系统") {
                    Toggle("完成后通知", isOn: $settings.completionNotificationsEnabled)
                    Toggle("剪贴板链接检测", isOn: $settings.clipboardDetectionEnabled)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .padding(10)
        }
        .padding(1)
        .onChange(of: settings.defaultDownloadDirectory) { _, _ in persistSettings() }
        .onChange(of: settings.concurrentTaskLimit) { _, _ in persistSettings() }
        .onChange(of: settings.httpMultithreadingEnabled) { _, _ in persistSettings() }
        .onChange(of: settings.httpSegmentCount) { _, _ in persistSettings() }
        .onChange(of: settings.hideHTTPTemporaryFiles) { _, _ in persistSettings() }
        .onChange(of: settings.retryLimit) { _, _ in persistSettings() }
        .onChange(of: settings.globalDownloadLimitBytes) { _, _ in persistSettings() }
        .onChange(of: settings.globalUploadLimitBytes) { _, _ in persistSettings() }
        .onChange(of: settings.completionNotificationsEnabled) { _, _ in persistSettings() }
        .onChange(of: settings.clipboardDetectionEnabled) { _, _ in persistSettings() }
        .onChange(of: settings.stopSeedingAtRatio) { _, _ in persistSettings() }
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
        guard value > 0 else { return "不限速" }
        return ByteCountFormatter.downloadFormatter.string(fromByteCount: value) + "/s"
    }
}
