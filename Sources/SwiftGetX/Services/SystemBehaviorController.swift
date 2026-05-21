import AppKit
import Foundation
import IOKit.pwr_mgt
import ServiceManagement

@MainActor
final class SystemBehaviorController {
    static let shared = SystemBehaviorController()

    private var sleepAssertionID = IOPMAssertionID(0)
    private var hasSleepAssertion = false

    private init() {}

    func applyLaunchAtLogin(enabled: Bool) {
        guard !Self.isRunningTests, Self.canManageLoginItem else { return }
        do {
            if enabled, SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            } else if !enabled, SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            assertionFailure("Unable to update login item: \(error)")
        }
    }

    static var canManageLoginItem: Bool {
        canManageLoginItem(bundleURL: Bundle.main.bundleURL)
    }

    static func canManageLoginItem(bundleURL: URL) -> Bool {
        bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }

    func updateSleepPrevention(isEnabled: Bool, hasActiveDownloads: Bool) {
        guard !Self.isRunningTests else { return }
        let shouldPreventSleep = isEnabled && hasActiveDownloads
        if shouldPreventSleep == hasSleepAssertion {
            return
        }

        if shouldPreventSleep {
            let reason = "SwiftGetX active downloads" as CFString
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypeNoIdleSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &sleepAssertionID
            )
            hasSleepAssertion = result == kIOReturnSuccess
        } else {
            if hasSleepAssertion {
                IOPMAssertionRelease(sleepAssertionID)
            }
            sleepAssertionID = 0
            hasSleepAssertion = false
        }
    }

    func performCompletionActions(for task: DownloadTask, settings: AppSettings) {
        if settings.completionSoundEnabled {
            NSSound(named: NSSound.Name("Glass"))?.play()
        }

        if settings.completionRevealInFinderEnabled {
            NSWorkspace.shared.activateFileViewerSelecting([task.revealURL])
        }

        if settings.completionOpenFileEnabled {
            NSWorkspace.shared.open(task.revealURL)
        }

        let scriptPath = settings.completionScriptPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scriptPath.isEmpty else { return }
        runCompletionScript(at: scriptPath, task: task)
    }

    private func runCompletionScript(at path: String, task: DownloadTask) {
        let expandedPath = (path as NSString).expandingTildeInPath
        guard FileManager.default.isExecutableFile(atPath: expandedPath) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: expandedPath)
        process.arguments = [
            task.id.uuidString,
            task.name,
            task.source,
            task.displaySavePath
        ]
        do {
            try process.run()
        } catch {
            assertionFailure("Unable to run completion script: \(error)")
        }
    }

    private static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
