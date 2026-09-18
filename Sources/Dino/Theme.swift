import SwiftUI

/// Offscreen rendering cannot snapshot an NSViewRepresentable, so the glass
/// layer is swapped for a flat tint while the render harness is drawing.
enum RenderMode {
    static var offscreen = false
}

/// Palette pulled from the sprite art so the widget and the dino agree.
enum Palette {
    static let skin = Color(red: 122 / 255, green: 210 / 255, blue: 144 / 255)
    static let skinDeep = Color(red: 74 / 255, green: 168 / 255, blue: 116 / 255)
    static let cream = Color(red: 253 / 255, green: 237 / 255, blue: 201 / 255)
    static let ink = Color(red: 51 / 255, green: 23 / 255, blue: 25 / 255)
    static let blush = Color(red: 247 / 255, green: 159 / 255, blue: 176 / 255)
    static let spike = Color(red: 247 / 255, green: 176 / 255, blue: 61 / 255)
    static let sky = Color(red: 0.85, green: 0.95, blue: 0.98)

    // Text and controls sitting directly on the smoked glass.
    static let onGlass = Color.white.opacity(0.94)
    static let onGlassDim = Color.white.opacity(0.58)
    static let onGlassFaint = Color.white.opacity(0.42)
}

enum Metrics {
    /// Default card size. The card itself flexes; this is only the starting
    /// shape and what the render harness draws.
    static let content = CGSize(width: 380, height: 560)
    /// Extra room around the content so the drop shadow is not clipped.
    static let shadowPadding: CGFloat = 26
    static let minContent = CGSize(width: 300, height: 380)
    static let maxPanelSize = CGSize(width: 900, height: 1400)
    static let corner: CGFloat = 26
    static let cardPadding: CGFloat = 14
    static let headerHeight: CGFloat = 28
    /// Buttons the header drag strip has to stay clear of
    /// (new chat + pin + settings).
    static let headerButtonsWidth: CGFloat = 92
    /// Generous grab area for the corner grip; only its corner is drawn.
    static let resizeGripSide: CGFloat = 32
    /// Keeps the input row clear of that grab area.
    static var resizeGripClearance: CGFloat { resizeGripSide + 6 }
    /// Below this the placeholder starts breaking mid-word, so the input row
    /// stacks instead of squeezing.
    static let minInputWidth: CGFloat = 170

    static var panelSize: CGSize {
        CGSize(width: content.width + shadowPadding * 2,
               height: content.height + shadowPadding * 2)
    }
    static var minPanelSize: CGSize {
        CGSize(width: minContent.width + shadowPadding * 2,
               height: minContent.height + shadowPadding * 2)
    }

    /// Where the invisible drag strip sits, in the content view's coordinates
    /// (bottom-left origin).
    static func dragHandleRect(in size: CGSize) -> CGRect {
        let leading = shadowPadding + cardPadding
        let trailing = shadowPadding + cardPadding + headerButtonsWidth
        let top = size.height - shadowPadding - cardPadding
        return CGRect(x: leading,
                      y: top - headerHeight,
                      width: max(40, size.width - leading - trailing),
                      height: headerHeight)
    }

    static func resizeGripRect(in size: CGSize) -> CGRect {
        // Bottom-right of the grab area lands just inside the card's rounded
        // corner, so the drawn strokes stay on the glass.
        let inset = shadowPadding + 8
        return CGRect(x: size.width - inset - resizeGripSide,
                      y: inset,
                      width: resizeGripSide,
                      height: resizeGripSide)
    }
}

extension View {
    /// Smoked-glass card: real behind-window blur, lightly darkened so it reads
    /// as glass rather than a white panel.
    func widgetCard() -> some View {
        self
            .background {
                ZStack {
                    if RenderMode.offscreen {
                        Color.black.opacity(0.45)
                    } else {
                        VisualEffectBackground(material: .hudWindow)
                    }
                    LinearGradient(
                        colors: [Color.black.opacity(0.06),
                                 Palette.ink.opacity(0.20)],
                        startPoint: .top, endPoint: .bottom)
                }
                .clipShape(RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
                .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 22, y: 10)
    }
}
