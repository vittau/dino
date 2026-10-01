import AppKit
import SwiftUI

/// The dino's pose: one breathing frame or a resting frame with an eyelid.
///
/// Frames are swapped outright rather than cross-faded. Blending them produced
/// a ghosted double image - the frames are independent drawings, so the
/// silhouettes never sit exactly on top of each other.
struct DinoFrames: View {
    var frame: Int
    var blinkPhase = 0

    var body: some View {
        sprite(blinkPhase == 2 ? (Sprites.blink ?? Sprites.idle.last)
               : blinkPhase == 1 ? (Sprites.blinkHalf ?? Sprites.idle.last)
               : Sprites.idle.indices.contains(frame)
                   ? Sprites.idle[frame] : Sprites.idle.first)
    }

    @ViewBuilder
    private func sprite(_ image: NSImage?) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        }
    }
}

/// The dino itself: a relaxed breathing cycle, and a blink now and then.
struct DinoSprite: View {
    var scale: Double = 1
    var isThinking = false

    @State private var frame = 0
    @State private var blinkPhase = 0

    private static let holdFull = 0.32
    private static let holdEmpty = 1.25
    /// Shorter, even frame steps keep the five-drawing breath from stalling.
    private static let stepFast = 0.27
    private static let stepSlow = 0.33

    private var side: CGFloat { 124 * scale }

    var body: some View {
        DinoFrames(frame: frame, blinkPhase: blinkPhase)
            .frame(width: side, height: side)
            // No extra lift or scale on top of the frames. The artwork already
            // inflates from planted feet (every frame's feet land on the same
            // row), and shifting the whole sprite would float them off the
            // ground.
            .offset(y: isThinking ? -2 : 0)
            .animation(.easeInOut(duration: 0.25), value: isThinking)
            .task { await breathe() }
    }

    /// One breath as (frame, how long to hold it), in sheet order.
    ///
    /// The sheet is already a whole cycle: idle_1 and idle_N are the same
    /// resting pose and the fullest frame sits in the middle, so this just
    /// walks it up and back down. Measured from the artwork, the belly area
    /// goes 9977 -> 13197 -> 15097 -> 10243 -> 9914 px, which is why the ends
    /// can simply be joined.
    private var schedule: [(frame: Int, dwell: Double)] {
        let count = Sprites.idle.count
        guard count > 2 else {
            return (0..<max(1, count)).map { ($0, 0.6) }
        }
        let peak = count / 2
        var steps: [(Int, Double)] = []
        for index in 0..<peak {
            steps.append((index, index == 0 ? Self.stepSlow : Self.stepFast))
        }
        steps.append((peak, Self.holdFull))                 // lungs full
        for index in (peak + 1)..<(count - 1) {
            steps.append((index, Self.stepFast))
        }
        steps.append((count - 1, Self.holdEmpty))           // lungs empty
        return steps
    }

    private func breathe() async {
        let plan = schedule
        var step = 0
        while !Task.isCancelled {
            let (next, dwell) = plan[step]
            frame = next
            let isResting = next == Sprites.idle.count - 1
            let ok = isResting ? await restEmpty(for: dwell) : await pause(dwell)
            guard ok else { return }
            step = (step + 1) % plan.count
        }
    }

    /// The long empty-lung pause. Blinks only happen here: the pose is still,
    /// so the eyelid frames line up with the body underneath them.
    private func restEmpty(for seconds: Double) async -> Bool {
        var remaining = seconds
        let step = 0.5
        while remaining > 0 {
            guard await pause(min(step, remaining)) else { return false }
            remaining -= step
            if Double.random(in: 0..<1) < 0.32 {
                await blink()
            }
        }
        return true
    }

    private func blink() async {
        blinkPhase = 1
        guard await pause(0.07) else { return }
        blinkPhase = 2
        guard await pause(0.12) else { return }
        blinkPhase = 1
        guard await pause(0.07) else { return }
        blinkPhase = 0
    }

    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        return !Task.isCancelled
    }
}
