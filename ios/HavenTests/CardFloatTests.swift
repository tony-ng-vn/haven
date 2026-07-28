import Foundation
import Testing
@testable import Haven

// The card's ambient drift. Position comes from a clock rather than from an
// animation between two endpoints, and every property worth having follows from
// that, so they are asserted here rather than trusted.

@Suite("Card float")
struct CardFloatTests {
    /// The whole reason for deriving position from time. "By default is in the
    /// center" is the requirement, and an endpoint animation cannot satisfy it:
    /// it oscillates between two edges and rest is whichever edge it stopped at.
    @Test("the card is exactly centred at rest")
    func centredAtRest() {
        #expect(CardFloat.offset(at: 0) == 0)
    }

    @Test("a full period returns to centre")
    func returnsToCentre() {
        #expect(abs(CardFloat.offset(at: CardFloat.period)) < 0.0001)
        #expect(abs(CardFloat.offset(at: CardFloat.period * 2)) < 0.0001)
    }

    @Test("the swing reaches the amplitude and no further")
    func reachesAmplitude() {
        #expect(abs(CardFloat.offset(at: CardFloat.period / 4) - CardFloat.amplitude) < 0.0001)
        #expect(abs(CardFloat.offset(at: CardFloat.period * 3 / 4) + CardFloat.amplitude) < 0.0001)
    }

    /// Swept rather than spot-checked: the card sits 44pt off each side, and an
    /// excursion past the amplitude is how a drift turns into a layout bug.
    @Test("the card never travels further than the amplitude")
    func staysInBounds() {
        for step in 0...700 {
            let offset = CardFloat.offset(at: Double(step) / 100)
            #expect(abs(offset) <= CardFloat.amplitude + 0.0001)
        }
    }

    /// A clock that never resets is the point: the phase cannot drift out of
    /// step when the scroll view invalidates layout, or restart on every push.
    @Test("the drift is periodic, so it cannot desync")
    func periodic() {
        for step in 0...50 {
            let t = Double(step) / 10
            let now = CardFloat.offset(at: t)
            let later = CardFloat.offset(at: t + CardFloat.period)
            #expect(abs(now - later) < 0.0001)
        }
    }

    /// Slow enough to be felt rather than watched. Peak speed is amplitude
    /// times 2 pi over the period; above roughly 6pt/s the eye starts tracking
    /// it and the card reads as sliding.
    @Test("the drift stays below the speed the eye tracks")
    func slowEnoughToIgnore() {
        let peak = CardFloat.amplitude * 2 * .pi / CardFloat.period
        #expect(peak < 6)
    }
}
