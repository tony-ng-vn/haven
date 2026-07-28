import SwiftUI

/// The card's ambient drift: a slow sway that never leaves the centre for long
/// and always comes back to it.
///
/// Position is read off a clock rather than animated between two endpoints, and
/// that is the whole design. `sin(0)` is zero, so the rest position is exactly
/// the centre the card is meant to sit at, a still screenshot is always
/// perfectly centred, and Reduce Motion is the same value rather than a special
/// case that can rot. An endpoint animation gives none of that: it oscillates
/// between two edges, so "at rest" is whichever edge it happened to stop at.
enum CardFloat {
    /// How far the card travels each side of centre.
    ///
    /// The card sits 44pt off each side of the screen, so this is nowhere near
    /// clipping. The constraint is perceptual, not spatial: see the speed note
    /// on `period`.
    static let amplitude: CGFloat = 6

    /// One full there-and-back.
    ///
    /// Peak speed works out at about 5.4 pt/s, which sits just above the
    /// fastest drifting dust mote. Fast enough that the card is not dead,
    /// slow enough that the eye does not follow it while reading the name.
    static let period: TimeInterval = 7

    static func offset(at time: TimeInterval) -> CGFloat {
        amplitude * sin(2 * .pi * time / period)
    }
}

extension View {
    /// Sets this view drifting.
    ///
    /// Applied by the screen rather than baked into `CardObject`, which is a
    /// presentation primitive: the card is the same object whether it is
    /// floating on My Card or arriving on the reveal.
    func cardFloat() -> some View {
        modifier(CardFloatModifier())
    }
}

private struct CardFloatModifier: ViewModifier {
    @HavenReduceMotion private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            // Not a frozen frame of the animation: the resting position IS
            // zero, so this is the same card, simply not moving.
            content
        } else {
            TimelineView(.animation) { timeline in
                content.offset(
                    x: CardFloat.offset(
                        at: timeline.date.timeIntervalSinceReferenceDate
                    )
                )
            }
        }
    }
}
