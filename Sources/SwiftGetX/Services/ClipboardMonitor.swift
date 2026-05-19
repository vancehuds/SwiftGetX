import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ClipboardMonitor {
    private weak var coordinator: DownloadCoordinator?
    private weak var settings: AppSettings?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var lastSuggestedSource: String?
    private var timer: Timer?

    var suggestedSource: String?

    func attach(coordinator: DownloadCoordinator, settings: AppSettings) {
        self.coordinator = coordinator
        self.settings = settings
        start()
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func acceptSuggestion() {
        guard let suggestedSource else { return }
        coordinator?.add(source: suggestedSource)
        lastSuggestedSource = suggestedSource
        self.suggestedSource = nil
    }

    func dismissSuggestion() {
        lastSuggestedSource = suggestedSource
        suggestedSource = nil
    }

    private func poll() {
        guard settings?.clipboardDetectionEnabled ?? false else {
            suggestedSource = nil
            return
        }

        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard let text = pasteboard.string(forType: .string),
              let firstSource = SourceParser.extractSources(from: text).first,
              firstSource != lastSuggestedSource
        else {
            return
        }

        suggestedSource = firstSource
    }
}
