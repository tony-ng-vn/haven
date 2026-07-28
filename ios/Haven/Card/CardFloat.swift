import SwiftUI

/// The card's ambient life: the card barely moves, and the sky behind it moves
/// the other way.
///
/// Almost all of the motion is parallax rather than travel. The card itself
/// shifts two points, which is small enough that nothing on screen reads as
/// sliding, while the star field behind it goes three points the other way. The
/// relative movement is what sells depth -- you are looking through the card at
/// something further away, rather than watching a card cross the screen.
///
/// What moves is the ground only: nebulae and the minor star field. The figure
/// stays locked to the card, because the constellation is not a backdrop, it is
/// the person. Sliding it inside its own frame would be the one thing that
/// breaks the card as an object.
///
/// Position is read off a clock rather than animated between two endpoints, and
/// that is the whole design. `sin(0)` is zero, so the rest pose is exactly the
/// centre the card is meant to sit at, a still screenshot is always perfectly
/// centred, and Reduce Motion is the same pose rather than a special case that
/// can rot. An endpoint animation gives none of that: it oscillates between two
/// edges, so "at rest" is whichever edge it happened to stop at.
enum CardFloat {
    /// How far the card travels each side of centre.
    static let amplitude: CGFloat = 2

    /// How far the ground travels, and which way.
    ///
    /// Negative because it moves against the card: that opposition is the
    /// entire effect. Larger than the card's own travel because the nearer
    /// thing should move less, which is the one rule parallax has.
    static let backdropAmplitude: CGFloat = -3

    /// One full there-and-back. Long: the two layers are pulling apart and back
    /// together, and that reads as breathing only if it is unhurried.
    static let period: TimeInterval = 11

    /// Where both layers sit at a given moment.
    struct Pose: Equatable {
        var card: CGFloat
        var backdrop: CGFloat

        /// Dead centre. Both the starting pose and the Reduce Motion pose.
        static let rest = Pose(card: 0, backdrop: 0)
    }

    static func pose(at time: TimeInterval) -> Pose {
        let phase = sin(2 * .pi * time / period)
        return Pose(card: amplitude * phase, backdrop: backdropAmplitude * phase)
    }
}

/// Drives a card and its ground from one clock.
///
/// A view rather than a modifier because two different things move by two
/// different amounts, and a modifier can only offset what it wraps.
struct CardDrift<Content: View>: View {
    @ViewBuilder var content: (CardFloat.Pose) -> Content

    @HavenReduceMotion private var reduceMotion

    var body: some View {
        if reduceMotion {
            // Not a frozen frame of the animation: the resting pose IS zero, so
            // this is the same card, simply not moving.
            content(.rest)
        } else {
            TimelineView(.animation) { timeline in
                content(CardFloat.pose(at: timeline.date.timeIntervalSinceReferenceDate))
            }
        }
    }
}
