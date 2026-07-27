import Foundation
import Testing
@testable import Haven

// The reveal's timing, which is the part that can be wrong in a way an eye
// would not catch until it was too late: a run that never reaches full
// brightness, or one star that never starts. Whether it feels right is judged
// on a device.

@Suite("Card reveal")
struct RevealTests {
    @Test("the run is long enough for every star to finish")
    func totalCoversEveryStar() {
        // The last star starts after all the staggers and still needs its own
        // full ignition.
        let seven = RevealMotion.total(starCount: 7)
        #expect(seven == RevealMotion.stagger * 6 + HavenMotion.starIgnitionDuration)
        #expect(RevealMotion.total(starCount: 8) > seven)

        // A figure of one has nothing to stagger against, and one of none must
        // not produce a negative duration.
        #expect(RevealMotion.total(starCount: 1) == HavenMotion.starIgnitionDuration)
        #expect(RevealMotion.total(starCount: 0) == HavenMotion.starIgnitionDuration)
    }

    @Test("a star starts dark, ends lit, and only rises")
    func easeOutIsMonotonic() {
        #expect(RevealMotion.easeOut(0) == 0)
        #expect(RevealMotion.easeOut(1) == 1)
        // Out of range on either side clamps rather than overshooting: a star
        // brighter than lit would be a different colour, not a brighter one.
        #expect(RevealMotion.easeOut(-1) == 0)
        #expect(RevealMotion.easeOut(2) == 1)

        var last = 0.0
        for step in 0...20 {
            let value = RevealMotion.easeOut(Double(step) / 20)
            #expect(value >= last)
            last = value
        }
    }

    // Quickly then slowly, the shape everything in Haven decelerates on. Half
    // way through the time is well past half way through the brightness.
    @Test("a star brightens fast and finishes slow")
    func easeOutDecelerates() {
        #expect(RevealMotion.easeOut(0.5) > 0.75)
        #expect(RevealMotion.easeOut(0.25) > 0.5)
    }
}
