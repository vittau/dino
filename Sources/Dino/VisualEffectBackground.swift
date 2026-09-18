import AppKit
import SwiftUI

/// The frosted-glass layer behind the widget.
///
/// SwiftUI's `Material` can go flat inside a borderless transparent panel, so
/// this wraps NSVisualEffectView directly with `behindWindow` blending, which
/// is what actually samples and blurs the desktop showing through.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = ClickThroughEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
        nsView.state = .active
    }

    /// The glass spans the whole card, so by default it becomes the hit target
    /// for every click and stops the window from being dragged by its
    /// background. It is decoration, so it should never take the mouse.
    private final class ClickThroughEffectView: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
