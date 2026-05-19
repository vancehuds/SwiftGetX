import AppKit

enum WindowConfigurator {
    @MainActor
    static func configureDefaultAppearance() {
        DispatchQueue.main.async {
            for window in NSApplication.shared.windows {
                configure(window)
            }
        }
    }

    @MainActor
    static func configure(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.hasShadow = true
    }
}
