import AppKit

/// Actions that need AppKit-level access from SwiftUI.
enum AppCommands {
    @MainActor
    static func openSettings() {
        SettingsWindowController.shared.show()
    }
}
