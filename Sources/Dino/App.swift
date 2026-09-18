import AppKit

/// Plain AppKit entry point.
///
/// There is deliberately no SwiftUI `App`/`Scene` here: the app is an AppKit
/// application that happens to draw its content with SwiftUI. Earlier it used a
/// `Settings` scene just to satisfy the protocol, and that scene insisted on
/// opening itself at launch and could not be focused properly.
@main
enum Main {
    /// Retained explicitly: `NSApplication.delegate` is weak.
    @MainActor private static let delegate = AppDelegate()

    @MainActor
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--selftest") {
            SelfTest.runAndExit()
        }
        if args.contains("--prompt") {
            // Prints exactly what is sent as the system prompt, so a long
            // prompt can be checked without reading Swift source.
            print(Personality.default)
            exit(0)
        }
        if let index = args.firstIndex(of: "--render"), index + 1 < args.count {
            RenderHarness.runAndExit(into: args[index + 1])
        }

        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pet: PetWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        pet = PetWindowController()
        pet?.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Reopening from the Dock brings the panel back rather than opening a
    /// window (there is no document window to open).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        pet?.show()
        return true
    }

    // MARK: - menu

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let app = NSMenu(title: "Dino")
        app.addItem(withTitle: "Sobre o Dino",
                    action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                    keyEquivalent: "")
        app.addItem(.separator())
        let prefs = NSMenuItem(title: "Preferências…", action: #selector(openSettings),
                               keyEquivalent: ",")
        prefs.target = self
        app.addItem(prefs)
        app.addItem(.separator())
        let newChat = NSMenuItem(title: "Nova conversa", action: #selector(newChat),
                                 keyEquivalent: "n")
        newChat.target = self
        app.addItem(newChat)
        app.addItem(.separator())
        app.addItem(withTitle: "Ocultar Dino", action: #selector(NSApplication.hide(_:)),
                    keyEquivalent: "h")
        app.addItem(withTitle: "Sair do Dino", action: #selector(NSApplication.terminate(_:)),
                    keyEquivalent: "q")
        appItem.submenu = app

        // Cmd+X/C/V/A only work when the app declares an Edit menu.
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Editar")
        edit.addItem(withTitle: "Desfazer", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Refazer", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Colar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Selecionar tudo",
                     action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let window = NSMenu(title: "Janela")
        let center = NSMenuItem(title: "Centralizar o Dino", action: #selector(centerDino),
                                keyEquivalent: "")
        center.target = self
        window.addItem(center)
        window.addItem(withTitle: "Minimizar", action: #selector(NSWindow.performMiniaturize(_:)),
                       keyEquivalent: "m")
        windowItem.submenu = window

        NSApp.mainMenu = main
    }

    @objc private func openSettings() {
        AppCommands.openSettings()
    }

    @objc private func newChat() {
        ChatStore.shared.newChat()
        pet?.show()
    }

    @objc private func centerDino() {
        pet?.centerOnScreen()
    }
}
