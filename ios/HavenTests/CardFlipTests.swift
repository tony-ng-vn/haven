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
            let front = CardFlip.opacity(angle: angle, isBack: false)
            let back = CardFlip.opacity(angle: angle, isBack: true)
            #expect(front + back == 1, "two faces are lit at \(angle) degrees")
        }
    }

    /// The card is turning or it is not. A partly opaque face is the defect:
    /// two opaque cards composite rather than dissolve, so the front's name
    /// prints straight through the code on the back.
    @Test("a face is never partly drawn, even past either end of the turn")
    func neverPartlyDrawn() {
        for angle in [-40.0, -0.5, 0, 45, 90, 135, 180, 180.5, 220.0] {
            for isBack in [true, false] {
                let value = CardFlip.opacity(angle: angle, isBack: isBack)
                #expect(value == 0 || value == 1, "opacity \(value) at \(angle), back: \(isBack)")
            }
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
}
