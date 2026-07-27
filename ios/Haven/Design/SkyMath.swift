import CoreGraphics
import Foundation

/// Maps `SkyGenerator`'s fixed 384x560 space onto whatever space the view has.
///
/// Aspect fill with a centre crop, matching the web card's
/// `preserveAspectRatio="xMidYMid slice"`. Fitting instead of filling would
/// letterbox the sky and leave bare background along two edges.
struct SkyLayout {
    let scale: Double
    let offset: CGSize

    init(container: CGSize, source: CGSize = CGSize(width: SkyGenerator.width, height: SkyGenerator.height)) {
        guard source.width > 0, source.height > 0 else {
            scale = 0
            offset = .zero
            return
        }
        let s = max(container.width / source.width, container.height / source.height)
        scale = s
        offset = CGSize(
            width: (container.width - source.width * s) / 2,
            height: (container.height - source.height * s) / 2
        )
    }

    /// Fits the figure into a band of the view rather than filling the whole of
    /// it, for a screen whose top is already taken by a question.
    ///
    /// The scale is set by the figure's real extent, not the full source height:
    /// `placeMajors` never puts a star below 62% of it, so scaling by 560 would
    /// leave the bottom third of the band empty and push stars out past it.
    /// Whichever of the width or that band runs out first wins, which is what
    /// keeps the figure inside the space it was given.
    /// How far down the source the figure actually reaches. `placeMajors` never
    /// puts a star below this, so it, and not the full height, is what a band
    /// has to fit.
    static let figureExtent = 0.62

    init(band: CGRect, source: CGSize = CGSize(width: SkyGenerator.width, height: SkyGenerator.height)) {
        let extent = source.height * Self.figureExtent
        guard source.width > 0, extent > 0, band.width > 0, band.height > 0 else {
            scale = 0
            offset = .zero
            return
        }
        let s = min(band.width / source.width, band.height / extent)
        scale = s
        offset = CGSize(
            width: band.minX + (band.width - source.width * s) / 2,
            height: band.minY
        )
    }

    /// Band if there is one, whole view otherwise. Every figure layer resolves
    /// its layout through here so they cannot disagree about where the figure is.
    init(figureBand: CGRect?, container: CGSize) {
        if let figureBand, figureBand.height > 0 {
            self.init(band: figureBand)
        } else {
            self.init(container: container)
        }
    }

    func point(x: Double, y: Double) -> CGPoint {
        CGPoint(x: x * scale + offset.width, y: y * scale + offset.height)
    }

    /// Radii and stroke widths are authored in sky units and have to scale with
    /// the positions, or the figure gets hairline-thin on a large screen.
    func length(_ value: Double) -> Double {
        value * scale
    }
}

/// How brightly each figure star is drawn: 0 is the unlit faint dot, 1 is fully
/// lit, and everything between is an ignition part way through.
///
/// The renderer knew two states until the card reveal needed the space between
/// them. Brightness is a plain input here and animating it is the caller's job,
/// so one renderer serves the still figure, the reveal, and the edit screen's
/// nudges without knowing which of them it is drawing.
enum FigureIntensity {
    /// The two-state figure as intensities.
    static func from(litMajors: Set<Int>, majorCount: Int) -> [Double] {
        (0..<max(majorCount, 0)).map { litMajors.contains($0) ? 1 : 0 }
    }

    /// One star's brightness. A star the caller said nothing about is unlit:
    /// intensities are built by hand for the reveal, and lighting a star nobody
    /// asked for would be the worse guess.
    static func star(_ index: Int, in intensities: [Double]) -> Double {
        intensities.indices.contains(index) ? intensities[index] : 0
    }

    /// An edge is drawn at the dimmer of its two stars, so a line never
    /// outshines the star it comes from.
    static func edge(between a: Int, and b: Int, in intensities: [Double]) -> Double {
        min(star(a, in: intensities), star(b, in: intensities))
    }
}

/// The twinkle every star shares: opacity easing between `hi` and `lo`, its own
/// duration and phase, running forever and alternating direction. That is CSS
/// `animation: dur ease-in-out delay infinite alternate`, reproduced so the app
/// and the web card breathe at the same rate.
enum SkyTwinkle {
    /// Where a star sits when nothing is animating. The time-average of the
    /// twinkle, so a frozen sky reads as dense as a moving one. This is what
    /// Reduce Motion renders.
    static func resting(hi: Double, lo: Double) -> Double {
        (hi + lo) / 2
    }

    static func opacity(hi: Double, lo: Double, dur: Double, delay: Double, time: Double) -> Double {
        guard dur > 0 else { return hi }
        let elapsed = time - delay
        guard elapsed > 0 else { return hi }
        // One full round trip is two sweeps; fold the second half back on itself.
        let sweeps = (elapsed / dur).truncatingRemainder(dividingBy: 2)
        let progress = sweeps <= 1 ? sweeps : 2 - sweeps
        return hi + (lo - hi) * easeInOut(progress)
    }

    /// Smoothstep. Visually indistinguishable from CSS ease-in-out on a slow
    /// opacity fade, and it needs no bezier solve per star per frame.
    private static func easeInOut(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }
}
