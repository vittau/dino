import AppKit
import SwiftUI

/// Rounded speech balloon with a soft tail. Same fill as the balloon, so
/// there is no seam where they meet.
///
/// The tail is carved out of the shape's rect rather than drawn outside it,
/// which means callers must reserve `tailHeight` of padding at the bottom or
/// the content will run into the tail.
struct BalloonShape: Shape {
    enum Tail { case leading, trailing }

    static let tailHeight: CGFloat = 11
    static let tailWidth: CGFloat = 20
    static let cornerRadius: CGFloat = 18

    /// Narrowest balloon that still leaves a flat stretch of bottom edge for
    /// the tail. Below this the tail would sit on a rounded corner.
    static var minWidth: CGFloat { cornerRadius * 2 + tailWidth + 16 }

    var tail: Tail?
    var corner: CGFloat = BalloonShape.cornerRadius
    var tailWidth: CGFloat = BalloonShape.tailWidth

    func path(in rect: CGRect) -> Path {
        var body = rect
        if tail != nil {
            body.size.height -= Self.tailHeight
        }
        var path = Path(roundedRect: body, cornerRadius: corner, style: .continuous)
        guard let tail else { return path }

        let half = tailWidth / 2
        // Keep the tail on the straight part of the bottom edge. On a narrow
        // balloon a tail overlapping the corner pokes outside the body and
        // reads as a chopped-off nub.
        let wanted = tail == .trailing
            ? body.maxX - (corner + 12)
            : body.minX + (corner + 12)
        let lowest = body.minX + corner + half
        let highest = body.maxX - corner - half
        let apex = highest < lowest
            ? body.midX
            : min(max(wanted, lowest), highest)
        let edge = body.maxY - 1
        // Traversed right-to-left either way: the rounded rect winds clockwise,
        // and an opposite winding would cancel the overlap into a hole.
        let lean = tail == .trailing ? half * 0.7 : -half * 0.7

        var tip = Path()
        tip.move(to: CGPoint(x: apex + half, y: edge))
        tip.addQuadCurve(
            to: CGPoint(x: apex - half, y: edge),
            control: CGPoint(x: apex + lean, y: edge + Self.tailHeight * 2))
        tip.closeSubpath()
        path.addPath(tip)
        return path
    }
}

struct TypingDots: View {
    @State private var lit = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Palette.skinDeep.opacity(lit == index ? 0.95 : 0.35))
                    .frame(width: 7, height: 7)
                    .offset(y: lit == index ? -3 : 0)
            }
        }
        .frame(height: 16)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 260_000_000)
                withAnimation(.easeInOut(duration: 0.18)) { lit = (lit + 1) % 3 }
            }
        }
    }
}

struct BalloonRow: View {
    let message: ChatStore.Message

    private var isUser: Bool { message.author == .user }

    private static let linkDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Detect links without parsing Markdown, preserving the message's line
    /// breaks and literal text even while a reply is streaming.
    private var linkedText: AttributedString {
        var attributed = AttributedString(message.text)
        let matches = Self.linkDetector?.matches(
            in: message.text, range: NSRange(message.text.startIndex..., in: message.text)) ?? []
        for match in matches {
            guard let range = Range(match.range, in: message.text), let url = match.url else { continue }
            let lower = attributed.characters.index(attributed.startIndex,
                offsetBy: message.text.distance(from: message.text.startIndex, to: range.lowerBound))
            let upper = attributed.characters.index(attributed.startIndex,
                offsetBy: message.text.distance(from: message.text.startIndex, to: range.upperBound))
            attributed[lower..<upper].link = url
        }
        return attributed
    }

    var body: some View {
        HStack(spacing: 0) {
            if isUser { Spacer(minLength: 34) }
            balloon
            if !isUser { Spacer(minLength: 34) }
        }
        .transition(.asymmetric(
            insertion: .scale(scale: 0.92, anchor: isUser ? .bottomTrailing : .bottomLeading)
                .combined(with: .opacity),
            removal: .opacity))
    }

    private var balloon: some View {
        Group {
            if message.isStreaming && message.text.isEmpty {
                TypingDots()
            } else if !RenderMode.offscreen && linkedText.runs.contains(where: { $0.link != nil }) {
                LinkedBalloonText(text: linkedText, color: isUser ? .white : NSColor(Palette.ink))
            } else {
                Text(linkedText)
                    .textSelection(.enabled)
                    .font(.system(size: 13.5, weight: .regular, design: .rounded))
                    .foregroundStyle(isUser ? .white : Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minWidth: BalloonShape.minWidth, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.top, 9)
        // The shape spends the bottom of its rect on the tail, so the text has
        // to leave room for it.
        .padding(.bottom, 9 + BalloonShape.tailHeight)
        // Tail sits under the balloon on the sender's side, so the dino's
        // balloons point left towards the dino and yours point right.
        .background {
            BalloonShape(tail: isUser ? .trailing : .leading)
                .fill(isUser ? AnyShapeStyle(Palette.userBubble) : AnyShapeStyle(Palette.amber))
        }
        .overlay {
            if message.isError {
                BalloonShape(tail: isUser ? .trailing : .leading)
                    .stroke(Palette.blush.opacity(0.85), lineWidth: 1.5)
            }
        }
    }
}

/// TextKit provides native URL opening, selection and cursor rectangles for
/// wrapped links, which SwiftUI Text does not consistently expose on macOS.
private struct LinkedBalloonText: NSViewRepresentable {
    let text: AttributedString
    let color: NSColor

    func makeNSView(context: Context) -> LinkTextView {
        let view = LinkTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = false
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = false
        view.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        return view
    }

    func updateNSView(_ view: LinkTextView, context: Context) {
        let content = NSMutableAttributedString(attributedString: NSAttributedString(text))
        let baseFont = NSFont.systemFont(ofSize: 13.5)
        let font = baseFont.fontDescriptor.withDesign(.rounded)
            .flatMap { NSFont(descriptor: $0, size: 13.5) } ?? baseFont
        content.addAttributes([.font: font, .foregroundColor: color],
                              range: NSRange(location: 0, length: content.length))
        if view.attributedString() != content {
            view.textStorage?.setAttributedString(content)
            view.window?.invalidateCursorRects(for: view)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: LinkTextView,
                      context: Context) -> CGSize? {
        guard let container = view.textContainer, let layout = view.layoutManager else { return nil }
        let width = max(1, proposal.width ?? Metrics.content.width)
        container.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        return CGSize(width: min(width, ceil(used.maxX)), height: ceil(used.maxY))
    }

    final class LinkTextView: NSTextView {
        private var hoverArea: NSTrackingArea?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.acceptsMouseMovedEvents = true
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let hoverArea { removeTrackingArea(hoverArea) }
            // The pet is normally a nonactivating panel. Key-window-only
            // tracking misses hover events until the user focuses its input.
            let area = NSTrackingArea(rect: .zero,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self)
            addTrackingArea(area)
            hoverArea = area
        }

        override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            updateCursor(with: event)
        }

        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            updateCursor(with: event)
        }

        override func cursorUpdate(with event: NSEvent) {
            updateCursor(with: event)
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            NSCursor.arrow.set()
        }

        private func updateCursor(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            (linkRects.contains { $0.contains(point) } ? NSCursor.pointingHand : .iBeam).set()
        }

        var linkRects: [NSRect] {
            guard let storage = textStorage, let layout = layoutManager,
                  let container = textContainer else { return [] }
            layout.ensureLayout(for: container)
            var rects: [NSRect] = []
            storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) {
                value, range, _ in
                guard value != nil else { return }
                let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                layout.enumerateEnclosingRects(forGlyphRange: glyphs,
                    withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                    in: container) { rect, _ in
                        rects.append(rect.offsetBy(dx: self.textContainerOrigin.x,
                                                  dy: self.textContainerOrigin.y))
                    }
            }
            return rects
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            for rect in linkRects { addCursorRect(rect, cursor: .pointingHand) }
        }
    }
}
