import Foundation
import Testing
@testable import Haven

// The card's ambient life. Position comes from a clock rather than from an
// animation between two endpoints, and every property worth having follows from
// that, so they are asserted here rather than trusted.

@Suite("Card float")
struct CardFloatTests {
    /// The whole reason for deriving position from time. "By default is in the
    /// center" is the requirement, and an endpoint animation cannot satisfy it:
    /// it oscillates between two edges and rest is whichever edge it stopped at.
    @Test("both layers are exactly centred at rest")
    func centredAtRest() {
        #expect(CardFloat.pose(at: 0) == .rest)
    }

    @Test("a full period returns to centre")
    func returnsToCentre() {
        for cycle in 1...3 {
            let pose = CardFloat.pose(at: CardFloat.period * Double(cycle))
            #expect(abs(pose.card) < 0.0001)
            #expect(abs(pose.backdrop) < 0.0001)
        }
    }

    @Test("the swing reaches each amplitude and no further")
    func reachesAmplitude() {
        let quarter = CardFloat.pose(at: CardFloat.period / 4)
        #expect(abs(quarter.card - CardFloat.amplitude) < 0.0001)
        #expect(abs(quarter.backdrop - CardFloat.backdropAmplitude) < 0.0001)
    }

    /// The one rule parallax has. If the ground moved with the card, or moved
    /// less than it, there would be no depth to read -- the card would simply
    /// be sliding and taking its sky along.
    @Test("the ground moves against the card, and further")
    func groundOpposesCard() {
        for step in 1...60 {
            let pose = CardFloat.pose(at: Double(step) / 10)
            guard abs(pose.card) > 0.0001 else { continue }
            #expect(pose.card.sign != pose.backdrop.sign, "the layers must oppose")
            #expect(abs(pose.backdrop) > abs(pose.card), "the nearer layer moves less")
        }
    }

    /// Swept rather than spot-checked: an excursion past the amplitude is how a
    /// drift turns into a layout bug.
    @Test("neither layer travels further than its amplitude")
    func staysInBounds() {
        for step in 0...1100 {
            let pose = CardFloat.pose(at: Double(step) / 100)
            #expect(abs(pose.card) <= CardFloat.amplitude + 0.0001)
            #expect(abs(pose.backdrop) <= abs(CardFloat.backdropAmplitude) + 0.0001)
        }
    }

    /// A clock that never resets is the point: the phase cannot drift out of
    /// step when the scroll view invalidates layout, or restart on every push.
    @Test("the drift is periodic, so it cannot desync")
    func periodic() {
        // Compared with a tolerance rather than exactly: a sine one period on
        // agrees to about 1e-15, and asserting bit equality would be testing
        // floating point rather than the drift.
        for step in 0...50 {
            let t = Double(step) / 10
            let now = CardFloat.pose(at: t)
            let later = CardFloat.pose(at: t + CardFloat.period)
            #expect(abs(now.card - later.card) < 0.0001)
            #expect(abs(now.backdrop - later.backdrop) < 0.0001)
        }
    }

    /// Slow enough to be felt rather than watched. What the eye can track is
    /// the relative speed of the two layers, not either one alone.
    @Test("the layers separate too slowly to be tracked")
    func slowEnoughToIgnore() {
        let separation = abs(CardFloat.amplitude - CardFloat.backdropAmplitude)
        let peak = separation * 2 * .pi / CardFloat.period
        #expect(peak < 3)
    }
}
