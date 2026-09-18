import AppKit
import SwiftUI

/// The settings window, built directly in AppKit instead of as a SwiftUI
/// `Settings` scene.
///
/// The scene version brought three problems: macOS opened it by itself at
/// launch (so it had to be ordered out again), it could only be summoned
/// through the private `showSettingsWindow:` selector, and being a normal
/// window it sat *behind* the floating pet panel.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        // The pet is a floating panel, so it would otherwise cover this window.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.title = "Preferências do Dino"
        window.contentViewController = NSHostingController(rootView: SettingsView())
        // Kept alive across closes so reopening is instant and keeps state.
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
