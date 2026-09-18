import AppKit
import SwiftUI

/// Borderless panel that can take keyboard focus without pulling the whole app
/// forward, so typing in the balloon does not yank you out of whatever you were
/// doing.
final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PetWindowController {
    static private(set) var shared: PetWindowController?

    private let panel: PetPanel
    private let defaults = UserDefaults.standard
    private static let originKey = "panelOrigin"
    private var dragHandle: WindowDragHandle?
    private var resizeGrip: WindowResizeGrip?
    private var chromeLayer: WindowChromeLayer?

    /// The floating widget, so the settings window can be lifted above it and
    /// the menu commands have something to talk to.
    var window: PetPanel { panel }

    /// Positions the drag strip and resize grip for the current size.
    private func layoutChrome() {
        guard let size = chromeLayer?.bounds.size else { return }
        dragHandle?.frame = Metrics.dragHandleRect(in: size)
        resizeGrip?.frame = Metrics.resizeGripRect(in: size)
    }

    /// `DINO_DEBUG=1` sanity check: confirms the chrome actually wins hit
    /// testing at its own centre - which is what makes the drag and the resize
    /// grip reachable - and, just as important, that it does *not* cover the
    /// header buttons, which live in the SwiftUI layer underneath.
    private func verifyChrome() {
        guard Debug.enabled, let chrome = chromeLayer else { return }
        let size = chrome.bounds.size
        Debug.log("content \(size), chrome \(chrome.frame), subviews \(chrome.subviews.count)")

        // Centre of the right-most header button (the gear).
        let gear = CGPoint(x: size.width - 56, y: size.height - 54)
        for (name, point) in [("drag", centre(of: Metrics.dragHandleRect(in: size))),
                              ("grip", centre(of: Metrics.resizeGripRect(in: size))),
                              ("gear button", gear)] {
            let hit = chrome.hitTest(point)
            Debug.log("hitTest \(name) at \(Int(point.x)),\(Int(point.y)) -> "
                      + (hit.map { "\(type(of: $0))" } ?? "nil (falls through to SwiftUI)"))
        }
    }

    private func centre(of rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.midY)
    }

    init() {
        panel = PetPanel(
            contentRect: NSRect(origin: .zero, size: Metrics.panelSize),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false)

        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false           // the card draws its own, unclipped
        // The widget is a fixed pastel design, so pin it to the light
        // appearance: in dark mode the material went grey and the field text
        // turned white on cream.
        panel.appearance = NSAppearance(named: .aqua)
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = Metrics.minPanelSize
        panel.maxSize = Metrics.maxPanelSize

        // A plain container holds the SwiftUI host and the window chrome side
        // by side. The chrome must not be a subview of NSHostingView: SwiftUI's
        // host does its own hit testing for its content and would never hand a
        // click to a plain AppKit sibling nested inside it.
        let container = NSView(frame: NSRect(origin: .zero, size: panel.contentLayoutRect.size))
        container.autoresizingMask = [.width, .height]

        let host = MovableHostingView(rootView: PetRootView())
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)

        let chrome = WindowChromeLayer()
        chrome.frame = container.bounds
        chrome.autoresizingMask = [.width, .height]
        container.addSubview(chrome)
        chromeLayer = chrome

        panel.contentView = container

        // Drag and resize are real views layered above the SwiftUI host rather
        // than relying on background dragging, which a borderless panel with
        // SwiftUI content does not honour.
        // Positions come from layoutChrome() on every resize, so no
        // autoresizing masks: two sources of truth would fight each other.
        let drag = WindowDragHandle()
        drag.frame = Metrics.dragHandleRect(in: chrome.bounds.size)
        chrome.addSubview(drag)
        dragHandle = drag

        let grip = WindowResizeGrip()
        grip.frame = Metrics.resizeGripRect(in: chrome.bounds.size)
        chrome.addSubview(grip)
        resizeGrip = grip

        applyLevel()
        restoreFrame()
        layoutChrome()
        observeAlwaysOnTop()
        DispatchQueue.main.async { [weak self] in
            self?.layoutChrome()
            self?.verifyChrome()
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(persistFrame),
            name: NSWindow.didMoveNotification, object: panel)
        NotificationCenter.default.addObserver(
            self, selector: #selector(persistFrame),
            name: NSWindow.didEndLiveResizeNotification, object: panel)
        // The grip resizes via setFrame, which is not a live resize, so the
        // chrome is repositioned from the resize notification instead.
        NotificationCenter.default.addObserver(
            self, selector: #selector(panelDidResize),
            name: NSWindow.didResizeNotification, object: panel)
        PetWindowController.shared = self
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func centerOnScreen() {
        panel.center()
        saveFrame()
    }

    private func applyLevel() {
        panel.level = AppSettings.shared.alwaysOnTop ? .floating : .normal
    }

    /// AppSettings is a plain observable, so re-arm after every change.
    private func observeAlwaysOnTop() {
        withObservationTracking {
            _ = AppSettings.shared.alwaysOnTop
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyLevel()
                self?.observeAlwaysOnTop()
            }
        }
    }

    // MARK: - frame

    /// Saves both origin and size, so a resized dino comes back the same shape.
    @objc func saveFrame() {
        defaults.set(["x": Double(panel.frame.origin.x),
                      "y": Double(panel.frame.origin.y),
                      "w": Double(panel.frame.width),
                      "h": Double(panel.frame.height)],
                     forKey: Self.originKey)
    }

    @objc private func persistFrame() {
        saveFrame()
    }

    @objc private func panelDidResize() {
        layoutChrome()
    }

    private func restoreFrame() {
        let saved = defaults.dictionary(forKey: Self.originKey)
        guard let saved,
              let x = number(saved["x"]), let y = number(saved["y"])
        else {
            if let visible = NSScreen.main?.visibleFrame {
                panel.setFrameOrigin(NSPoint(
                    x: visible.maxX - Metrics.panelSize.width - 28,
                    y: visible.minY + 28))
            } else {
                panel.center()
            }
            return
        }
        var size = Metrics.panelSize
        if let w = number(saved["w"]), let h = number(saved["h"]) {
            size = NSSize(width: max(w, Metrics.minPanelSize.width),
                          height: max(h, Metrics.minPanelSize.height))
        }
        panel.setFrame(NSRect(origin: clamped(NSPoint(x: x, y: y)), size: size),
                       display: true)
    }

    /// UserDefaults is loose about what comes back: NSNumber does not bridge to
    /// Double when the value was written as an integer, and a hand-edited
    /// default (or `defaults write` with an old-style plist) lands as a string.
    private func number(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }

    /// Keeps at least a corner on screen, so a changed display setup cannot
    /// strand the dino somewhere unreachable.
    private func clamped(_ origin: NSPoint) -> NSPoint {
        guard let visible = NSScreen.main?.visibleFrame else { return origin }
        let reachable: CGFloat = 90
        return NSPoint(
            x: min(max(origin.x, visible.minX - Metrics.panelSize.width + reachable),
                   visible.maxX - reachable),
            y: min(max(origin.y, visible.minY - Metrics.panelSize.height + reachable),
                   visible.maxY - reachable))
    }
}
