import CoreGraphics
import Foundation
import Testing
@testable import Haven

// The pure logic behind the sky renderer: which figure stars a field owns, how
// the fixed 384x560 sky space maps onto a real screen, and the twinkle curve
// every star shares. What the sky looks like is judged by a human against the
// SwiftUI previews.

private let tolerance = 1e-9

private func expectClose(_ actual: Double, _ expected: Double, _ label: String) {
    #expect(abs(actual - expected) < tolerance, "\(label): got \(actual), want \(expected)")
}

// MARK: - Star slots

@Suite("Fixed star slots")
struct StarSlotTests {
    @Test("the mapping is the one the plan fixed")
    func rawValues() {
        #expect(StarSlot.name.rawValue == 0)
        #expect(StarSlot.city.rawValue == 1)
        #expect(StarSlot.primaryContact.rawValue == 2)
        #expect(StarSlot.photo.rawValue == 3)
        #expect(StarSlot.company.rawValue == 4)
        #expect(StarSlot.role.rawValue == 5)
        #expect(StarSlot.allCases.count == 6)
    }

    // The generator makes 7 or 8 majors, so both counts have to behave.
    @Test("majors past the last slot are ambient and always lit", arguments: [7, 8])
    func ambientMajorsAlwaysLit(majorCount: Int) {
        let none = StarSlot.litMajorIndices(filled: [], majorCount: majorCount)
        #expect(none == Set(6..<majorCount))

        let all = StarSlot.litMajorIndices(filled: Set(StarSlot.allCases), majorCount: majorCount)
        #expect(all == Set(0..<majorCount))
    }

    @Test("a filled field lights its own slot and no other")
    func filledLightsItsSlot() {
        let lit = StarSlot.litMajorIndices(filled: [.name, .role], majorCount: 7)
        #expect(lit == [0, 5, 6])
    }

    // Nothing today produces a short figure, but the lookup must not index blindly.
    @Test("a figure shorter than the slot list does not overrun")
    func shortFigure() {
        #expect(StarSlot.litMajorIndices(filled: [], majorCount: 4).isEmpty)
        #expect(StarSlot.litMajorIndices(filled: [.name, .role], majorCount: 4) == [0])
        #expect(StarSlot.litMajorIndices(filled: [.name], majorCount: 0).isEmpty)
    }
}

// MARK: - Figure intensity

/// How bright each figure star is drawn. The renderer used to know two states;
/// the reveal needs everything between them, so the two states became the ends
/// of a range and this is the mapping that keeps them identical.
@Suite("Figure intensity")
struct FigureIntensityTests {
    @Test("a lit major is full and everything else is dark")
    func fromLitMajors() {
        #expect(FigureIntensity.from(litMajors: [0, 2], majorCount: 4) == [1, 0, 1, 0])
        #expect(FigureIntensity.from(litMajors: [], majorCount: 3) == [0, 0, 0])
        #expect(FigureIntensity.from(litMajors: [0, 1], majorCount: 2) == [1, 1])
        #expect(FigureIntensity.from(litMajors: [0], majorCount: 0).isEmpty)
    }

    @Test("the complete figure is every star lit")
    func complete() {
        #expect(FigureIntensity.complete(majorCount: 3) == [1, 1, 1])
        #expect(FigureIntensity.complete(majorCount: 0).isEmpty)
        #expect(
            FigureIntensity.complete(majorCount: 7)
                == FigureIntensity.from(litMajors: Set(0..<7), majorCount: 7)
        )
    }

    // A caller builds intensities by hand for the reveal, so an array that does
    // not match the figure is a real case, not a hypothetical one. Missing is
    // unlit: drawing a star nobody asked to light would be the worse guess.
    @Test("a star the caller said nothing about stays unlit")
    func shortArray() {
        #expect(FigureIntensity.star(0, in: [0.5]) == 0.5)
        #expect(FigureIntensity.star(3, in: [0.5]) == 0)
        #expect(FigureIntensity.star(-1, in: [0.5]) == 0)
        #expect(FigureIntensity.star(0, in: []) == 0)
    }

    // A line brighter than the star it comes from reads as a diagram drawn over
    // the sky rather than as the figure lighting up.
    @Test("an edge is only as bright as its dimmer star")
    func edgeTakesTheDimmer() {
        let intensities: [Double] = [1, 0.4, 0]
        #expect(FigureIntensity.edge(between: 0, and: 1, in: intensities) == 0.4)
        #expect(FigureIntensity.edge(between: 1, and: 0, in: intensities) == 0.4)
        #expect(FigureIntensity.edge(between: 0, and: 2, in: intensities) == 0)
        #expect(FigureIntensity.edge(between: 0, and: 9, in: intensities) == 0)
    }

    // The two-state figure has to come out of the new path pixel-identical, or
    // every screen already shipped changes appearance.
    @Test("the two-state figure survives the round trip")
    func twoStateIsUnchanged() {
        let lit = StarSlot.litMajorIndices(filled: [.name, .city], majorCount: 7)
        let intensities = FigureIntensity.from(litMajors: lit, majorCount: 7)

        for index in 0..<7 {
            #expect(FigureIntensity.star(index, in: intensities) == (lit.contains(index) ? 1 : 0))
        }
        // An edge between two lit stars is drawn in full; one dark end kills it.
        #expect(FigureIntensity.edge(between: 0, and: 1, in: intensities) == 1)
        #expect(FigureIntensity.edge(between: 0, and: 2, in: intensities) == 0)
    }
}

// MARK: - Sky layout

@Suite("Sky layout")
struct SkyLayoutTests {
    private let source = CGSize(width: SkyGenerator.width, height: SkyGenerator.height)

    @Test("an exact-size container maps one to one")
    func identity() {
        let layout = SkyLayout(container: source)
        expectClose(layout.scale, 1, "scale")
        expectClose(layout.offset.width, 0, "offset.width")
        expectClose(layout.offset.height, 0, "offset.height")
    }

    // Aspect fill with a centre crop, matching the web card's
    // preserveAspectRatio="xMidYMid slice". A min() here would letterbox
    // the sky and leave bare background at the edges.
    @Test("a container taller than the sky fills on height and crops the sides")
    func tallerContainer() {
        let layout = SkyLayout(container: CGSize(width: 384, height: 1120))
        expectClose(layout.scale, 2, "scale")
        expectClose(layout.offset.width, (384 - 768) / 2, "offset.width")
        expectClose(layout.offset.height, 0, "offset.height")
    }

    @Test("a container wider than the sky fills on width and crops top and bottom")
    func widerContainer() {
        let layout = SkyLayout(container: CGSize(width: 768, height: 560))
        expectClose(layout.scale, 2, "scale")
        expectClose(layout.offset.width, 0, "offset.width")
        expectClose(layout.offset.height, (560 - 1120) / 2, "offset.height")
    }

    @Test("points land inside the cropped frame")
    func pointMapping() {
        let layout = SkyLayout(container: CGSize(width: 384, height: 1120))
        let centre = layout.point(x: SkyGenerator.width / 2, y: SkyGenerator.height / 2)
        expectClose(centre.x, 192, "centre.x")
        expectClose(centre.y, 560, "centre.y")

        let origin = layout.point(x: 0, y: 0)
        expectClose(origin.x, -192, "origin.x")
        expectClose(origin.y, 0, "origin.y")
    }

    @Test("a zero container does not divide by zero")
    func zeroContainer() {
        let layout = SkyLayout(container: .zero)
        #expect(layout.scale.isFinite)
        #expect(layout.offset.width.isFinite)
        #expect(layout.offset.height.isFinite)
    }
}

// MARK: - Twinkle

@Suite("Twinkle curve")
struct SkyTwinkleTests {
    @Test("a star rests at hi before its delay expires")
    func beforeDelay() {
        expectClose(SkyTwinkle.opacity(hi: 0.8, lo: 0.3, dur: 4, delay: 2, time: 0), 0.8, "t=0")
        expectClose(SkyTwinkle.opacity(hi: 0.8, lo: 0.3, dur: 4, delay: 2, time: 2), 0.8, "t=delay")
    }

    // CSS "infinite alternate": hi at the start of every even sweep, lo at the
    // end of the first, and hi again a full round trip later.
    @Test("the curve alternates between hi and lo")
    func alternates() {
        expectClose(SkyTwinkle.opacity(hi: 0.8, lo: 0.3, dur: 4, delay: 2, time: 6), 0.3, "one sweep")
        expectClose(SkyTwinkle.opacity(hi: 0.8, lo: 0.3, dur: 4, delay: 2, time: 10), 0.8, "round trip")
        expectClose(SkyTwinkle.opacity(hi: 0.8, lo: 0.3, dur: 4, delay: 2, time: 14), 0.3, "second sweep")
    }

    @Test("mid sweep sits at the resting midpoint")
    func midSweep() {
        let mid = SkyTwinkle.opacity(hi: 0.8, lo: 0.3, dur: 4, delay: 2, time: 4)
        expectClose(mid, SkyTwinkle.resting(hi: 0.8, lo: 0.3), "midpoint")
        expectClose(mid, 0.55, "midpoint value")
    }

    // Reduce Motion freezes the sky at this value rather than at hi, so the
    // still sky reads as dense as the animated one.
    @Test("resting is the average brightness")
    func restingIsAverage() {
        expectClose(SkyTwinkle.resting(hi: 1, lo: 0.62), 0.81, "major")
        expectClose(SkyTwinkle.resting(hi: 0.25, lo: 0.08), 0.165, "faintest minor")
    }

    @Test("a zero duration does not divide by zero")
    func zeroDuration() {
        let value = SkyTwinkle.opacity(hi: 0.8, lo: 0.3, dur: 0, delay: 0, time: 1)
        #expect(value.isFinite)
    }
}

// MARK: - Figure band

/// A question screen owns its top, so the figure takes the gap between the
/// header and the content instead. These assert the figure actually stays in
/// that gap, because a star drawn over the question is the one thing that reads
/// as a mistake rather than as atmosphere.
@Suite("Figure band layout")
struct FigureBandTests {
    private let source = CGSize(width: SkyGenerator.width, height: SkyGenerator.height)

    /// The lowest a star can be placed: placeMajors caps y at 62% of the source.
    private func figureBottom(_ layout: SkyLayout) -> Double {
        layout.point(x: 0, y: SkyGenerator.height * 0.62).y
    }

    @Test("the figure stays inside the band it was given")
    func staysInBand() {
        for height in [90.0, 140.0, 260.0, 420.0] {
            let band = CGRect(x: 0, y: 210, width: 393, height: height)
            let layout = SkyLayout(band: band)
            #expect(layout.point(x: 0, y: 0).y >= band.minY - 0.001,
                    "band \(height): figure starts above the band")
            #expect(figureBottom(layout) <= band.maxY + 0.001,
                    "band \(height): figure reaches past the band")
        }
    }

    @Test("a thin band shrinks the figure rather than overflowing it")
    func thinBandShrinks() {
        let thin = SkyLayout(band: CGRect(x: 0, y: 200, width: 393, height: 120))
        let roomy = SkyLayout(band: CGRect(x: 0, y: 200, width: 393, height: 600))
        #expect(thin.scale < roomy.scale)
        // Width is the other limit, so a roomy band is capped at 1:1-ish rather
        // than growing without bound.
        #expect(roomy.scale == 393.0 / SkyGenerator.width)
    }

    @Test("the figure is centred horizontally when the band limits by height")
    func centredWhenHeightLimited() {
        let band = CGRect(x: 0, y: 100, width: 393, height: 150)
        let layout = SkyLayout(band: band)
        let drawnWidth = SkyGenerator.width * layout.scale
        let left = layout.point(x: 0, y: 0).x
        let right = layout.point(x: SkyGenerator.width, y: 0).x
        #expect(abs(left - (band.midX - drawnWidth / 2)) < 0.001)
        #expect(abs(right - (band.midX + drawnWidth / 2)) < 0.001)
    }

    @Test("a degenerate band collapses to nothing instead of dividing by zero")
    func degenerateBand() {
        #expect(SkyLayout(band: CGRect(x: 0, y: 0, width: 0, height: 100)).scale == 0)
        #expect(SkyLayout(band: CGRect(x: 0, y: 0, width: 393, height: 0)).scale == 0)
    }

    @Test("no band falls back to filling the view")
    func noBandFills() {
        let container = CGSize(width: 393, height: 852)
        let banded = SkyLayout(figureBand: CGRect(x: 0, y: 0, width: 393, height: 300), container: container)
        let filled = SkyLayout(figureBand: nil, container: container)
        #expect(filled.scale == SkyLayout(container: container).scale)
        #expect(banded.scale != filled.scale)
    }
}
