import Foundation
import Testing
@testable import Haven

// The card's ambient life. Position comes from a clock rather than from an
// animation between two endpoints, and every property worth having follows from
// that, so they are asserted here rather than trusted.

@Suite("Card float")
struct CardDriftTests {
    /// The whole reason for deriving position from time. "By default is in the
    /// center" is the requirement, and an endpoint animation cannot satisfy it:
    /// it oscillates between two edges and rest is whichever edge it stopped at.
    @Test("both layers are exactly centred at rest")
    func centredAtRest() {
        #expect(CardDrift.pose(at: 0) == .rest)
    }

    @Test("a full period returns to centre")
    func returnsToCentre() {
        for cycle in 1...3 {
            let pose = CardDrift.pose(at: CardDrift.period * Double(cycle))
            #expect(abs(pose.card) < 0.0001)
            #expect(abs(pose.scenery) < 0.0001)
        }
    }

    @Test("the swing reaches each amplitude and no further")
    func reachesAmplitude() {
        let quarter = CardDrift.pose(at: CardDrift.period / 4)
        #expect(abs(quarter.card - CardDrift.amplitude) < 0.0001)
        #expect(abs(quarter.scenery - CardDrift.sceneryAmplitude) < 0.0001)
    }

    /// The one rule parallax has, asserted where it is actually true.
    ///
    /// `card` is a screen offset and `scenery` is applied inside the card, so
    /// comparing the two raw numbers compares different coordinate spaces and
    /// proves nothing. On screen the scenery sits at `card + scenery`, and it
    /// is that sum which has to run the other way and travel less. Checked
    /// rather than assumed because the naive comparison passes happily on a
    /// scenery amplitude that inverts the effect.
    @Test("on screen the sky moves against the card, and less than it")
    func skyOpposesCard() {
        for step in 1...130 {
            let pose = CardDrift.pose(at: Double(step) / 10)
            guard abs(pose.card) > 0.0001 else { continue }
            let onScreen = pose.card + pose.scenery
            #expect(onScreen.sign != pose.card.sign, "the layers must oppose on screen")
            #expect(abs(onScreen) < abs(pose.card), "the far layer must travel less")
        }
    }

    /// Swept rather than spot-checked: an excursion past the amplitude is how a
    /// drift turns into a layout bug.
    @Test("neither layer travels further than its amplitude")
    func staysInBounds() {
        for step in 0...1100 {
            let pose = CardDrift.pose(at: Double(step) / 100)
            #expect(abs(pose.card) <= CardDrift.amplitude + 0.0001)
            #expect(abs(pose.scenery) <= abs(CardDrift.sceneryAmplitude) + 0.0001)
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
            let now = CardDrift.pose(at: t)
            let later = CardDrift.pose(at: t + CardDrift.period)
            #expect(abs(now.card - later.card) < 0.0001)
            #expect(abs(now.scenery - later.scenery) < 0.0001)
        }
    }

    /// Slow enough to be felt rather than watched. What the eye can track is
    /// the two layers pulling apart, not either one alone.
    ///
    /// The ceiling is the app's own fastest ambient motion: a drifting dust
    /// mote runs about 4.2 pt/s, and anything slower than that is already below
    /// the threshold where the screen looks busy.
    @Test("the layers separate too slowly to be tracked")
    func slowEnoughToIgnore() {
        let fastestAmbientPointsPerSecond = 4.2
        let separation = abs(CardDrift.amplitude - CardDrift.sceneryAmplitude)
        let peak = separation * 2 * .pi / CardDrift.period
        #expect(peak < fastestAmbientPointsPerSecond)
    }
}
