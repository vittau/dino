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
            } else {
                Text(message.text)
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
                .fill(isUser ? AnyShapeStyle(userFill) : AnyShapeStyle(Palette.cream))
        }
        .overlay {
            if message.isError {
                BalloonShape(tail: isUser ? .trailing : .leading)
                    .stroke(Palette.blush.opacity(0.85), lineWidth: 1.5)
            }
        }
    }

    private var userFill: LinearGradient {
        LinearGradient(colors: [Palette.skin, Palette.skinDeep],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
