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

    func point(x: Double, y: Double) -> CGPoint {
        CGPoint(x: x * scale + offset.width, y: y * scale + offset.height)
    }

    /// Radii and stroke widths are authored in sky units and have to scale with
    /// the positions, or the figure gets hairline-thin on a large screen.
    func length(_ value: Double) -> Double {
        value * scale
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
