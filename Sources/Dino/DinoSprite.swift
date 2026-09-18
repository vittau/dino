import AppKit
import SwiftUI

/// The dino's pose: one breathing frame, plus the blink overlay when the eyes
/// are shut.
///
/// Frames are swapped outright rather than cross-faded. Blending them produced
/// a ghosted double image - the frames are independent drawings, so the
/// silhouettes never sit exactly on top of each other.
struct DinoFrames: View {
    var frame: Int
    var blinking = false

    var body: some View {
        ZStack {
            sprite(Sprites.idle.indices.contains(frame)
                   ? Sprites.idle[frame]
                   : Sprites.idle.first)
            if blinking {
                sprite(Sprites.blink)
            }
        }
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
    @State private var blinking = false

    private static let holdFull = 0.5
    private static let holdEmpty = 2.0
    /// Dwell on a mid-breath frame: brisk through the middle, settled at the ends.
    private static let stepFast = 0.35
    private static let stepSlow = 0.45
    private static let blinkLength = 0.13

    private var side: CGFloat { 124 * scale }

    var body: some View {
        DinoFrames(frame: frame, blinking: blinking)
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
        for index in (peak + 1)..<count {
            steps.append((index, index == count - 1 ? Self.stepSlow : Self.stepFast))
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
    /// so the eyelid overlay lines up with the eye underneath it.
    private func restEmpty(for seconds: Double) async -> Bool {
        var remaining = seconds
        let step = 0.6
        while remaining > 0 {
            guard await pause(min(step, remaining)) else { return false }
            remaining -= step
            if Double.random(in: 0..<1) < 0.4 {
                await blink()
            }
        }
        return true
    }

    private func blink() async {
        blinking = true
        _ = await pause(Self.blinkLength)
        blinking = false
    }

    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        return !Task.isCancelled
    }
}
