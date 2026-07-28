import Foundation
import Testing

@testable import Haven

// The card has two sides and SwiftUI has no backface culling: without a rule
// about which side is facing you, the front renders mirrored through the back
// and both are live at once. That rule is a pure function of the angle, so it
// is pinned here rather than judged by looking at a rotating card.

@Suite("Card flip")
struct CardFlipTests {
    @Test("at rest the front faces you, and at the far end the back does")
    func restPoses() {
        #expect(CardFlip.showsBack(angle: 0) == false)
        #expect(CardFlip.showsBack(angle: CardFlip.backAngle) == true)
    }

    /// The one thing that must not happen: both faces drawn at once, which is
    /// what "the front renders mirrored through the back" looks like.
    @Test("exactly one face is visible at every angle of the turn")
    func oneFaceAtATime() {
        for step in 0...180 {
            let angle = Double(step)
            let front = CardFlip.opacity(angle: angle, isBack: false, crossFading: false)
            let back = CardFlip.opacity(angle: angle, isBack: true, crossFading: false)
            #expect(front + back == 1, "two faces are lit at \(angle) degrees")
        }
    }

    /// Edge-on, so neither face has any area to show. Swapping anywhere else
    /// would mean a face turning away from you while still drawn.
    @Test("the faces swap at the halfway point, where the card is edge-on")
    func swapsEdgeOn() {
        #expect(CardFlip.showsBack(angle: 89.9) == false)
        #expect(CardFlip.showsBack(angle: 90) == true)
    }

    /// The failure this prevents: the back's gradients and rules painting
    /// mirrored, because the container turned it 180 and nothing turned it
    /// back. A whole turn is the identity, so the back paints as authored.
    @Test("the back arrives at a whole turn, so it paints as it was drawn")
    func backLandsUnmirrored() {
        #expect(CardFlip.faceAngle(CardFlip.backAngle, isBack: true) == 360)
        #expect(CardFlip.faceAngle(0, isBack: false) == 0)
    }

    // MARK: - Reduce Motion

    // Reduce Motion cannot mean "no flip" the way it means "no drift": the
    // drift is ambient and nobody asked for it, but the flip is how a person
    // reaches their own code. It cross-fades instead of turning.

    @Test("the cross-fade starts on the front and ends on the back")
    func crossFadeEnds() {
        #expect(CardFlip.opacity(angle: 0, isBack: false, crossFading: true) == 1)
        #expect(CardFlip.opacity(angle: 0, isBack: true, crossFading: true) == 0)
        #expect(CardFlip.opacity(angle: CardFlip.backAngle, isBack: false, crossFading: true) == 0)
        #expect(CardFlip.opacity(angle: CardFlip.backAngle, isBack: true, crossFading: true) == 1)
    }

    /// A cross-fade that summed above one would show the two faces printed
    /// through each other, which is the same defect the cull exists to stop.
    @Test("the cross-fade never lights more than one card's worth")
    func crossFadeNeverDoubles() {
        for step in 0...180 {
            let angle = Double(step)
            let front = CardFlip.opacity(angle: angle, isBack: false, crossFading: true)
            let back = CardFlip.opacity(angle: angle, isBack: true, crossFading: true)
            #expect(abs(front + back - 1) < 0.0001, "the faces sum to \(front + back) at \(angle)")
        }
    }

    /// The angle is animated, so it can be handed values past either end while
    /// a spring settles. Neither face may go negative or above full.
    @Test("an overshooting angle still asks for a drawable opacity")
    func toleratesOvershoot() {
        for angle in [-40.0, -0.5, 180.5, 220.0] {
            for isBack in [true, false] {
                let value = CardFlip.opacity(angle: angle, isBack: isBack, crossFading: true)
                #expect(value >= 0 && value <= 1, "opacity \(value) at \(angle), back: \(isBack)")
            }
        }
    }
}
