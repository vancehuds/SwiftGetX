import AppKit
import SwiftUI

struct StartupRecoveryView: View {
    let issue: StartupRecoveryIssue
    let onRetry: () -> Void
    let onUseTemporaryStore: () -> Void
    let onBackupAndReset: () -> Void

    @State private var statusMessage: String?

    var body: some View {
        GeometryReader { proxy in
            let layout = ResponsiveLayout(windowSize: proxy.size)

            ZStack {
                MonochromeWindowBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: layout.value(18)) {
                        header(layout: layout)
                        details(layout: layout)
                        actions(layout: layout)
                    }
                    .frame(maxWidth: layout.value(760), alignment: .leading)
                    .padding(layout.value(28))
                }
            }
            .environment(\.responsiveLayout, layout)
        }
        .frame(minWidth: 620, minHeight: 440)
    }

    private func header(layout: ResponsiveLayout) -> some View {
        VStack(alignment: .leading, spacing: layout.value(8)) {
            Label {
                Text(L10n.string("startup_recovery_title"))
                    .font(layout.font(22, weight: .bold))
            } icon: {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(layout.font(24, weight: .semibold))
                    .foregroundStyle(.orange)
            }

            Text(L10n.string("startup_recovery_message"))
                .font(layout.font(13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func details(layout: ResponsiveLayout) -> some View {
        GlassSurface(level: .panel, cornerRadius: 10) {
            VStack(alignment: .leading, spacing: layout.value(10)) {
                startupDetailRow(
                    title: L10n.string("startup_recovery_store_path"),
                    value: issue.redactedStorePath,
                    layout: layout
                )
                startupDetailRow(
                    title: L10n.string("startup_recovery_schema_version"),
                    value: issue.schemaVersion,
                    layout: layout
                )
                startupDetailRow(
                    title: L10n.string("startup_recovery_error"),
                    value: issue.errorDescription,
                    layout: layout
                )

                if let statusMessage {
                    Divider()
                    Text(statusMessage)
                        .font(layout.font(12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(layout.value(14))
        }
    }

    private func startupDetailRow(title: String, value: String, layout: ResponsiveLayout) -> some View {
        VStack(alignment: .leading, spacing: layout.value(3)) {
            Text(title)
                .font(layout.font(11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? L10n.string("startup_recovery_empty_value") : value)
                .font(layout.font(12, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func actions(layout: ResponsiveLayout) -> some View {
        VStack(alignment: .leading, spacing: layout.value(12)) {
            HStack(spacing: layout.value(10)) {
                Button {
                    onRetry()
                } label: {
                    Label(L10n.string("startup_recovery_retry"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    copyDiagnostics()
                } label: {
                    Label(L10n.string("startup_recovery_copy_diagnostics"), systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Button {
                    revealStoreFolder()
                } label: {
                    Label(L10n.string("startup_recovery_reveal_store"), systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: layout.value(8)) {
                Button {
                    onUseTemporaryStore()
                } label: {
                    Label(L10n.string("startup_recovery_use_temporary"), systemImage: "memories")
                }
                .buttonStyle(.bordered)

                Text(L10n.string("startup_recovery_use_temporary_help"))
                    .font(layout.font(11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: layout.value(8)) {
                Button(role: .destructive) {
                    onBackupAndReset()
                } label: {
                    Label(L10n.string("startup_recovery_backup_reset"), systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .disabled(!issue.canRebuildPersistentStore)

                Text(L10n.string("startup_recovery_backup_reset_help"))
                    .font(layout.font(11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            StartupRecoveryService.diagnosticsText(for: issue),
            forType: .string
        )
        statusMessage = L10n.string("startup_recovery_diagnostics_copied")
    }

    private func revealStoreFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([
            issue.storeURL.deletingLastPathComponent()
        ])
        statusMessage = L10n.string("startup_recovery_store_revealed")
    }
}
