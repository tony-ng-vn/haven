import SwiftUI

/// The card's ambient life: the card barely moves, and the sky behind it moves
/// the other way.
///
/// Almost all of the motion is parallax rather than travel. The card itself
/// shifts two points, which is small enough that nothing on screen reads as
/// sliding, while the sky's scenery goes the other way behind it. The relative
/// movement is what sells depth -- you are looking through the card at
/// something further away, rather than watching a card cross the screen.
///
/// What moves is scenery only: nebulae, the minor field, the coloured giants
/// and the shooting star. The figure stays locked to the card, because the
/// constellation is not a backdrop, it is the person. Sliding it inside its own
/// frame would be the one thing that breaks the card as an object.
///
/// Position is read off a clock rather than animated between two endpoints, and
/// that is the whole design. `sin(0)` is zero, so the rest pose is exactly the
/// centre the card is meant to sit at, a still screenshot is always perfectly
/// centred, and Reduce Motion is the same pose rather than a special case that
/// can rot. An endpoint animation gives none of that: it oscillates between two
/// edges, so "at rest" is whichever edge it happened to stop at.
enum CardDrift {
    /// How far the card travels each side of centre, on screen.
    static let amplitude: CGFloat = 2

    /// How far the scenery travels, in the card's own coordinates.
    ///
    /// Negative because it moves against the card, and that opposition is the
    /// entire effect. The two coordinate spaces are what make this easy to get
    /// wrong: `amplitude` is on screen, this is inside the card, so on screen
    /// the scenery ends up at `amplitude + sceneryAmplitude`. For that sum to
    /// invert direction without overshooting -- the far layer going the other
    /// way, but travelling less than the near one -- this has to land strictly
    /// between `-amplitude` and `-2 * amplitude`. `CardDriftTests` pins it.
    static let sceneryAmplitude: CGFloat = -3

    /// One full there-and-back. Long: the two layers are pulling apart and back
    /// together, and that reads as breathing only if it is unhurried.
    ///
    /// Deliberately not 11, which is `ShimmerField`'s dimming period. Two
    /// oscillators at the same rate on the same layer beat against each other,
    /// at whatever phase the screen happened to appear at.
    static let period: TimeInterval = 13

    /// Where both layers sit at a given moment.
    struct Pose: Equatable {
        /// The card, on screen.
        var card: CGFloat
        /// The scenery, inside the card.
        var scenery: CGFloat

        /// Dead centre. Both the starting pose and the Reduce Motion pose.
        static let rest = Pose(card: 0, scenery: 0)
    }

    static func pose(at time: TimeInterval) -> Pose {
        let phase = sin(2 * .pi * time / period)
        return Pose(card: amplitude * phase, scenery: sceneryAmplitude * phase)
    }
}

/// Hands out the current pose, once per frame.
///
/// A view rather than a `ViewModifier` because two things move by two different
/// amounts, and a modifier can only offset what it wraps. It applies nothing
/// itself: the caller decides what each half of the pose moves, which is why
/// this is named for the clock rather than for the motion.
struct CardDriftClock<Content: View>: View {
    @ViewBuilder var content: (CardDrift.Pose) -> Content

    @HavenReduceMotion private var reduceMotion

    var body: some View {
        if reduceMotion {
            // Not a frozen frame of the animation: the resting pose IS zero, so
            // this is the same card, simply not moving.
            content(.rest)
        } else {
            TimelineView(.animation) { timeline in
                content(CardDrift.pose(at: timeline.date.timeIntervalSinceReferenceDate))
            }
        }
    }
}
