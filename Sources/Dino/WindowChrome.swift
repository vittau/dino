import AppKit
import SwiftUI

/// Hosting view that allows the window to be dragged from its background.
///
/// Belt and braces next to `WindowDragHandle`: a borderless panel with SwiftUI
/// content often will not background-drag, because NSHostingView reports
/// `mouseDownCanMoveWindow == false`.
final class MovableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
}

/// Pass-through container for the window chrome.
///
/// NSHostingView is flipped, which would mirror any bottom-left position math.
/// This view is deliberately not flipped so the chrome can use ordinary
/// bottom-left coordinates, and it forwards hit testing to its subviews only -
/// otherwise, being the size of the whole card, it would swallow every click
/// meant for the SwiftUI content beneath it.
final class WindowChromeLayer: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` arrives in the superview's coordinates, but a subview's
        // hitTest wants it in *its* superview's coordinates - which is ours.
        // Without this conversion the chrome is never hit at all.
        let local = superview.map { convert(point, from: $0) } ?? point
        for subview in subviews.reversed() {
            if let hit = subview.hitTest(local) {
                return hit
            }
        }
        return nil
    }
}

/// A real view that moves the window when dragged.
///
/// Background dragging turned out to be unreliable here: SwiftUI's host keeps
/// hit testing for its own content and the glass layer swallows clicks, so no
/// amount of `isMovableByWindowBackground` made the card move. Handling the
/// events directly, in a view that sits above the SwiftUI content, always works.
final class WindowDragHandle: NSView {
    private var startOrigin = NSPoint.zero
    private var startMouse = NSPoint.zero

    /// This view does its own dragging. Leaving the default `true` would let
    /// AppKit start a background drag as well, and the window would travel
    /// roughly twice as far as the pointer.
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        Debug.log("drag handle mouseDown")
        startOrigin = window?.frame.origin ?? .zero
        startMouse = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        Debug.log("drag handle mouseDragged")
        guard let window else { return }
        let now = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(x: startOrigin.x + now.x - startMouse.x,
                                     y: startOrigin.y + now.y - startMouse.y))
    }

    override func mouseUp(with event: NSEvent) {
        PetWindowController.shared?.saveFrame()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

/// Corner grip that resizes the window. A borderless window gives no edge to
/// grab, so this stands in for the missing chrome.
final class WindowResizeGrip: NSView {
    private var startFrame = NSRect.zero
    private var startMouse = NSPoint.zero

    override var mouseDownCanMoveWindow: Bool { false }

    /// Perpendicular distance between the grip strokes.
    private let step: CGFloat = 4.5

    override func mouseDown(with event: NSEvent) {
        Debug.log("resize grip mouseDown")
        startFrame = window?.frame ?? .zero
        startMouse = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        Debug.log("resize grip mouseDragged")
        guard let window else { return }
        let now = NSEvent.mouseLocation
        var width = startFrame.width + (now.x - startMouse.x)
        // Screen y grows upward, so subtracting the delta makes the bottom edge
        // follow the pointer: drag down and the window grows downward. Adding
        // it shrank the window upward, so the corner ran away from the mouse.
        var height = startFrame.height - (now.y - startMouse.y)
        width = min(max(width, window.minSize.width), window.maxSize.width)
        height = min(max(height, window.minSize.height), window.maxSize.height)
        // Top-left stays put; the bottom-right corner follows the pointer.
        window.setFrame(NSRect(x: startFrame.minX,
                               y: startFrame.maxY - height,
                               width: width,
                               height: height),
                        display: true)
    }

    override func mouseUp(with event: NSEvent) {
        PetWindowController.shared?.saveFrame()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .frameResize(position: .bottomRight, directions: .all))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.6).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.8
        path.lineCapStyle = .round
        for index in 0..<4 {
            let offset = CGFloat(index) * step
            path.move(to: NSPoint(x: bounds.maxX - offset, y: bounds.minY + 2))
            path.line(to: NSPoint(x: bounds.maxX - 2, y: bounds.minY + offset))
        }
        path.stroke()
    }
}
