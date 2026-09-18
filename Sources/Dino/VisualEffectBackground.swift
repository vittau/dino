import AppKit
import SwiftUI

/// The frosted-glass layer behind the widget.
///
/// SwiftUI's `Material` can go flat inside a borderless transparent panel, so
/// this wraps NSVisualEffectView directly with `behindWindow` blending, which
/// is what actually samples and blurs the desktop showing through.
///
/// With `behindWindow` blending the blur belongs to the window server: there is
/// no backdrop layer we can tune (the in-process `CABackdropLayer` is only a
/// mirror, and `alphaValue` below 1 cancels the blur). The frost character
/// therefore comes from `material` alone; tune how much of it shows with the
/// tint drawn over the card.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    /// The dark variant of the material, independent of the app's light pin.
    var dark: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = ClickThroughEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = blending
        view.state = .active
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }

    /// The glass spans the whole card, so by default it becomes the hit target
    /// for every click and stops the window from being dragged by its
    /// background. It is decoration, so it should never take the mouse.
    private final class ClickThroughEffectView: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
