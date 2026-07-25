import SwiftUI

/// Renders a person's `Sky`: nebulae, the minor field, the coloured giants, the
/// figure with its connecting lines, diffraction flares and a shooting star.
///
/// Decorative, so it is hidden from VoiceOver entirely. A screen reader user
/// gets nothing from "a field of 150 dots"; the person's name and fields carry
/// all the meaning.
///
/// The renderer draws the sky at rest. It deliberately knows nothing about
/// ignition order or the card reveal -- that sequencing is milestone 1 and is
/// judged on a device.
struct SkyView: View {
    let sky: Sky
    /// Indices into `sky.majors` that render as lit. Use
    /// `StarSlot.litMajorIndices` to derive it from filled fields; the default
    /// is the complete figure, which is what the card and the beacon show.
    let litMajors: Set<Int>

    @HavenReduceMotion private var reduceMotion

    init(sky: Sky, litMajors: Set<Int>? = nil) {
        self.sky = sky
        self.litMajors = litMajors ?? Set(sky.majors.indices)
    }

    var body: some View {
        ZStack {
            // Three layers, split by how often each has to repaint.
            SkyBackdrop(sky: sky)
            ShimmerField(sky: sky)
            AnimatedSky(sky: sky, litMajors: litMajors, animating: !reduceMotion)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Static layers

/// Nebulae. Never animated, so this canvas paints once.
private struct SkyBackdrop: View {
    let sky: Sky

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let layout = SkyLayout(container: size)
            for nebula in sky.nebulae {
                let colour = Color(skyHue: nebula.hue, saturation: 0.82, lightness: 0.58)
                context.drawLayer { layer in
                    // Radial gradients are circular, so the ellipse is drawn in a
                    // scaled space instead of being stretched afterwards.
                    let centre = layout.point(x: nebula.cx, y: nebula.cy)
                    layer.translateBy(x: centre.x, y: centre.y)
                    layer.scaleBy(x: layout.length(nebula.rx), y: layout.length(nebula.ry))
                    layer.fill(
                        Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
                        with: .radialGradient(
                            Gradient(colors: [colour.opacity(nebula.alpha), colour.opacity(0)]),
                            center: .zero,
                            startRadius: 0,
                            endRadius: 1
                        )
                    )
                }
            }
        }
    }
}

/// The ~128 minors that are not featured: drawn once at their resting
/// brightness, then breathed as a single group.
///
/// This is the whole reason the sky is cheap. One opacity animation on one layer
/// replaces 128 independent timelines, so the sky animates roughly 30 nodes
/// instead of 150. Do not move these into the animated canvas.
private struct ShimmerField: View {
    let sky: Sky

    @HavenReduceMotion private var reduceMotion
    @State private var dimmed = false

    private static let shimmerPeriod: TimeInterval = 11

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let layout = SkyLayout(container: size)
            for star in sky.minors where !star.featured {
                context.fill(
                    circle(at: layout.point(x: star.x, y: star.y), radius: layout.length(star.r)),
                    with: .color(.white.opacity(SkyTwinkle.resting(hi: star.hi, lo: star.lo)))
                )
            }
        }
        .opacity(dimmed ? 0.88 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: Self.shimmerPeriod).repeatForever(autoreverses: true)
            ) {
                dimmed = true
            }
        }
    }
}

// MARK: - Animated layer

/// Everything that moves, in one canvas: the featured minors, the giants, the
/// figure and its lines, the flares and the shooting star. Roughly 45 draw calls
/// per frame in a single render pass.
private struct AnimatedSky: View {
    let sky: Sky
    let litMajors: Set<Int>
    let animating: Bool

    var body: some View {
        if animating {
            TimelineView(.animation) { timeline in
                canvas(time: timeline.date.timeIntervalSinceReferenceDate)
            }
        } else {
            // Reduce Motion freezes at the resting midpoint rather than at t=0.
            // At t=0 every star sits at its brightest with its delay unexpired,
            // which is a visibly different sky from the one motion users see.
            canvas(time: nil)
        }
    }

    /// `time` is nil when nothing is animating, which is the Reduce Motion path.
    private func canvas(time: Double?) -> some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let layout = SkyLayout(container: size)
            drawMinors(&context, layout, time)
            drawGiants(&context, layout, time)
            drawEdges(&context, layout)
            drawMajors(&context, layout, time)
            drawFlares(&context, layout, time)
            drawShootingStar(&context, layout, time)
        }
    }

    private func alpha(hi: Double, lo: Double, dur: Double, delay: Double, time: Double?) -> Double {
        guard let time else { return SkyTwinkle.resting(hi: hi, lo: lo) }
        return SkyTwinkle.opacity(hi: hi, lo: lo, dur: dur, delay: delay, time: time)
    }

    private func drawMinors(_ context: inout GraphicsContext, _ layout: SkyLayout, _ time: Double?) {
        for star in sky.minors where star.featured {
            let a = alpha(hi: star.hi, lo: star.lo, dur: star.dur, delay: star.delay, time: time)
            context.fill(
                circle(at: layout.point(x: star.x, y: star.y), radius: layout.length(star.r)),
                with: .color(.white.opacity(a))
            )
        }
    }

    private func drawGiants(_ context: inout GraphicsContext, _ layout: SkyLayout, _ time: Double?) {
        for giant in sky.giants {
            let a = alpha(hi: giant.hi, lo: giant.lo, dur: giant.dur, delay: giant.delay, time: time)
            context.fill(
                circle(at: layout.point(x: giant.x, y: giant.y), radius: layout.length(giant.r)),
                with: .color(Color(skyHue: giant.hue, saturation: 0.8, lightness: 0.75, opacity: a))
            )
        }
    }

    /// A line shows only when both of its stars are lit, so a half-filled
    /// profile reads as separate lights rather than as a broken diagram.
    private func drawEdges(_ context: inout GraphicsContext, _ layout: SkyLayout) {
        for (a, b) in sky.edges {
            guard sky.majors.indices.contains(a), sky.majors.indices.contains(b) else { continue }
            guard litMajors.contains(a), litMajors.contains(b) else { continue }
            var path = Path()
            path.move(to: layout.point(x: sky.majors[a].x, y: sky.majors[a].y))
            path.addLine(to: layout.point(x: sky.majors[b].x, y: sky.majors[b].y))
            context.stroke(
                path,
                with: .color(HavenColor.star.opacity(0.24)),
                lineWidth: layout.length(0.8)
            )
        }
    }

    private func drawMajors(_ context: inout GraphicsContext, _ layout: SkyLayout, _ time: Double?) {
        for (index, major) in sky.majors.enumerated() {
            let centre = layout.point(x: major.x, y: major.y)
            let radius = layout.length(major.r)
            guard litMajors.contains(index) else {
                // An unlit slot is a legible gap, not an absence: the star stays
                // on screen in Faint so the edit screen can point at it.
                context.fill(
                    circle(at: centre, radius: radius),
                    with: .color(HavenColor.faint.opacity(0.45))
                )
                continue
            }
            let a = alpha(hi: major.hi, lo: major.lo, dur: major.dur, delay: major.delay, time: time)
            let glow = radius * 2.6
            context.fill(
                circle(at: centre, radius: glow),
                with: .radialGradient(
                    Gradient(colors: [
                        HavenColor.star.opacity(0.22 * a),
                        HavenColor.star.opacity(0),
                    ]),
                    center: centre,
                    startRadius: 0,
                    endRadius: glow
                )
            )
            context.fill(
                circle(at: centre, radius: radius),
                with: .color(HavenColor.star.opacity(a))
            )
        }
    }

    /// Two diffraction spikes crossed at the figure's brightest stars. The detail
    /// that makes the sky read as photographed rather than as plotted.
    private func drawFlares(_ context: inout GraphicsContext, _ layout: SkyLayout, _ time: Double?) {
        for flare in sky.flares {
            let a = alpha(hi: 0.8, lo: 0.35, dur: flare.dur, delay: flare.delay, time: time)
            let centre = layout.point(x: flare.x, y: flare.y)
            let len = layout.length(flare.len)
            let waist = layout.length(1.1)
            context.fill(
                spike(centre: centre, length: len, waist: waist, vertical: true),
                with: .color(HavenColor.star.opacity(0.5 * a))
            )
            context.fill(
                spike(centre: centre, length: len, waist: waist, vertical: false),
                with: .color(HavenColor.star.opacity(0.4 * a))
            )
        }
    }

    private func drawShootingStar(_ context: inout GraphicsContext, _ layout: SkyLayout, _ time: Double?) {
        // A frozen sky has no shooting star. Painting it parked mid-flight would
        // read as a stray scratch on the screen.
        guard let time else { return }
        let cycle = 13.0
        let elapsed = time - sky.shoot.delay
        guard elapsed > 0 else { return }
        let progress = elapsed.truncatingRemainder(dividingBy: cycle) / cycle
        // Visible for six percent of the cycle. It should feel like something you
        // might have imagined.
        guard progress > 0.91, progress < 0.97 else { return }
        let travel = (progress - 0.91) / 0.06
        let fade = travel < 0.25 ? travel / 0.25 : 1 - (travel - 0.25) / 0.75
        var path = Path()
        path.move(to: layout.point(x: sky.shoot.x1, y: sky.shoot.y1))
        path.addLine(to: layout.point(x: sky.shoot.x2, y: sky.shoot.y2))
        context.stroke(
            path.offsetBy(dx: layout.length(150 * travel), dy: layout.length(84 * travel)),
            with: .color(.white.opacity(0.9 * fade)),
            style: StrokeStyle(lineWidth: layout.length(1.6), lineCap: .round)
        )
    }
}

// MARK: - Shapes

private func circle(at centre: CGPoint, radius: Double) -> Path {
    Path(ellipseIn: CGRect(
        x: centre.x - radius,
        y: centre.y - radius,
        width: radius * 2,
        height: radius * 2
    ))
}

private func spike(centre: CGPoint, length: Double, waist: Double, vertical: Bool) -> Path {
    var path = Path()
    if vertical {
        path.move(to: CGPoint(x: centre.x, y: centre.y - length))
        path.addLine(to: CGPoint(x: centre.x + waist, y: centre.y))
        path.addLine(to: CGPoint(x: centre.x, y: centre.y + length))
        path.addLine(to: CGPoint(x: centre.x - waist, y: centre.y))
    } else {
        path.move(to: CGPoint(x: centre.x - length, y: centre.y))
        path.addLine(to: CGPoint(x: centre.x, y: centre.y + waist))
        path.addLine(to: CGPoint(x: centre.x + length, y: centre.y))
        path.addLine(to: CGPoint(x: centre.x, y: centre.y - waist))
    }
    path.closeSubpath()
    return path
}

// MARK: - Previews

private let previewSky = SkyGenerator.build(seed: "user_2abcDEF123")

#Preview("Sky, complete figure") {
    ZStack {
        NightBackground()
        SkyView(sky: previewSky)
    }
}

#Preview("Sky, name only") {
    ZStack {
        NightBackground()
        SkyView(
            sky: previewSky,
            litMajors: StarSlot.litMajorIndices(filled: [.name], majorCount: previewSky.majors.count)
        )
    }
}

#Preview("Sky, everything but photo and role") {
    ZStack {
        NightBackground()
        SkyView(
            sky: previewSky,
            litMajors: StarSlot.litMajorIndices(
                filled: [.name, .city, .primaryContact, .company],
                majorCount: previewSky.majors.count
            )
        )
    }
}

#Preview("Sky, Reduce Motion") {
    ZStack {
        NightBackground()
        SkyView(sky: previewSky)
    }
    .havenReduceMotion()
}

// The sky is authored at 384x560 and has to fill anything it is given without
// letterboxing or stretching.
#Preview("Sky in a short wide frame") {
    ZStack {
        NightBackground()
        SkyView(sky: previewSky)
    }
    .frame(width: 360, height: 200)
    .clipShape(RoundedRectangle(cornerRadius: 20))
    .padding()
}
