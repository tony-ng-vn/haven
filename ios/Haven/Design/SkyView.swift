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
    /// How brightly each of `sky.majors` is drawn, from 0 for the unlit faint
    /// dot to 1 for fully lit. See `FigureIntensity`.
    let majorIntensities: [Double]
    /// The band the figure may occupy, in this view's own coordinate space.
    ///
    /// Nil fills the whole view, which is what the card and the beacon want:
    /// they have no header competing for the top. A question screen passes the
    /// gap between its header and its content, because a figure drawn over the
    /// question is the one thing that reads as a mistake.
    let figureBand: CGRect?

    /// How far the generator's nebula alphas are pulled back. The alphas were
    /// authored against a 384-wide space, so a full phone screen crops deep
    /// into each nebula's core and needs them held back; a card-sized card
    /// crops far less and can carry more.
    var nebulaDamping: Double = SkyView.fullScreenNebulaDamping

    /// What a full-screen sky uses.
    static let fullScreenNebulaDamping: Double = 0.4

    /// Slides the ground sideways, leaving the figure where it is.
    ///
    /// Only the card uses this, for its parallax. The split is deliberate: the
    /// nebulae and the minor field are scenery and may move, but the figure is
    /// the person and stays put. Moving it inside its own frame is what would
    /// stop the card reading as one object.
    var backdropOffset: CGFloat = 0

    @HavenReduceMotion private var reduceMotion

    /// The figure part way lit. Intensities are a plain input: animating them
    /// is the caller's job, and a Reduce Motion caller passes final values with
    /// no animation, as everywhere else.
    init(
        sky: Sky,
        majorIntensities: [Double],
        figureBand: CGRect? = nil,
        nebulaDamping: Double = SkyView.fullScreenNebulaDamping,
        backdropOffset: CGFloat = 0
    ) {
        self.sky = sky
        self.majorIntensities = majorIntensities
        self.figureBand = figureBand
        self.nebulaDamping = nebulaDamping
        self.backdropOffset = backdropOffset
    }

    /// The figure at rest, where a star is either lit or a faint dot. Use
    /// `StarSlot.litMajorIndices` to derive the set from filled fields; the
    /// default is the complete figure, which is what the card and the beacon
    /// show.
    init(
        sky: Sky,
        litMajors: Set<Int>? = nil,
        figureBand: CGRect? = nil,
        nebulaDamping: Double = SkyView.fullScreenNebulaDamping,
        backdropOffset: CGFloat = 0
    ) {
        let count = sky.majors.count
        self.init(
            sky: sky,
            majorIntensities: litMajors.map { FigureIntensity.from(litMajors: $0, majorCount: count) }
                ?? FigureIntensity.complete(majorCount: count),
            figureBand: figureBand,
            nebulaDamping: nebulaDamping,
            backdropOffset: backdropOffset
        )
    }

    var body: some View {
        ZStack {
            // Three layers, split by how often each has to repaint.
            // The nebulae stay full bleed whatever the figure does. They are
            // the ground, not the person, and cropping them to a band would
            // leave the rest of the screen flat.
            // The first two are ground and may slide; the third is the figure
            // and may not.
            SkyBackdrop(sky: sky, nebulaDamping: nebulaDamping)
                .offset(x: backdropOffset)
            ShimmerField(sky: sky, figureBand: figureBand)
                .offset(x: backdropOffset)
            AnimatedSky(
                sky: sky,
                majorIntensities: majorIntensities,
                animating: !reduceMotion,
                figureBand: figureBand
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Static layers

/// Nebulae. Never animated, so this canvas paints once.
private struct SkyBackdrop: View {
    let sky: Sky

    let nebulaDamping: Double

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let layout = SkyLayout(container: size)
            for nebula in sky.nebulae {
                let colour = Color(skyHue: nebula.hue, saturation: 0.82, lightness: 0.58)
                // Damped well below the alpha the generator carries. Those
                // values were authored for a 384-wide card, where you see a
                // whole soft ellipse. Filling a phone screen crops to the
                // middle, and the middle of a radial gradient is its core --
                // undamped, a person whose hues land on green and teal gets a
                // screen washed in colours the dusk palette does not contain.
                let alpha = nebula.alpha * nebulaDamping
                context.drawLayer { layer in
                    // Radial gradients are circular, so the ellipse is drawn in a
                    // scaled space instead of being stretched afterwards.
                    let centre = layout.point(x: nebula.cx, y: nebula.cy)
                    layer.translateBy(x: centre.x, y: centre.y)
                    layer.scaleBy(x: layout.length(nebula.rx), y: layout.length(nebula.ry))
                    layer.fill(
                        Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
                        with: .radialGradient(
                            Gradient(colors: [colour.opacity(alpha), colour.opacity(0)]),
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
    let figureBand: CGRect?

    @HavenReduceMotion private var reduceMotion
    @State private var dimmed = false

    private static let shimmerPeriod: TimeInterval = 11

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let layout = SkyLayout(figureBand: figureBand, container: size)
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
    let majorIntensities: [Double]
    let animating: Bool
    let figureBand: CGRect?

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
            let layout = SkyLayout(figureBand: figureBand, container: size)
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

    /// A line is drawn at the dimmer of its two stars, so it fades in with the
    /// second one rather than arriving whole, and a half-filled profile reads
    /// as separate lights instead of as a broken diagram.
    private func drawEdges(_ context: inout GraphicsContext, _ layout: SkyLayout) {
        for (a, b) in sky.edges {
            guard sky.majors.indices.contains(a), sky.majors.indices.contains(b) else { continue }
            let intensity = FigureIntensity.edge(between: a, and: b, in: majorIntensities)
            guard intensity > 0 else { continue }
            var path = Path()
            path.move(to: layout.point(x: sky.majors[a].x, y: sky.majors[a].y))
            path.addLine(to: layout.point(x: sky.majors[b].x, y: sky.majors[b].y))
            context.stroke(
                path,
                with: .color(HavenColor.star.opacity(0.24 * intensity)),
                lineWidth: layout.length(0.8)
            )
        }
    }

    /// A major crossfades between its two states: the faint dot fades out as
    /// the lit glow and core fade in. At 0 and at 1 that is exactly the two
    /// states the sky has always drawn.
    private func drawMajors(_ context: inout GraphicsContext, _ layout: SkyLayout, _ time: Double?) {
        for (index, major) in sky.majors.enumerated() {
            let intensity = FigureIntensity.star(index, in: majorIntensities)
            let centre = layout.point(x: major.x, y: major.y)
            let radius = layout.length(major.r)
            if intensity < 1 {
                // An unlit slot is a legible gap, not an absence: the star stays
                // on screen in Faint so the edit screen can point at it.
                context.fill(
                    circle(at: centre, radius: radius),
                    with: .color(HavenColor.faint.opacity(0.45 * (1 - intensity)))
                )
            }
            guard intensity > 0 else { continue }
            let a = alpha(hi: major.hi, lo: major.lo, dur: major.dur, delay: major.delay, time: time)
            let glow = radius * 2.6
            context.fill(
                circle(at: centre, radius: glow),
                with: .radialGradient(
                    Gradient(colors: [
                        HavenColor.star.opacity(0.22 * a * intensity),
                        HavenColor.star.opacity(0),
                    ]),
                    center: centre,
                    startRadius: 0,
                    endRadius: glow
                )
            )
            context.fill(
                circle(at: centre, radius: radius),
                with: .color(HavenColor.star.opacity(a * intensity))
            )
        }
    }

    /// Two diffraction spikes crossed at the figure's brightest stars. The detail
    /// that makes the sky read as photographed rather than as plotted.
    ///
    /// A flare fades with its own star, for the same reason an edge does: it is
    /// the signature of a very bright star, so one blazing out of a star that is
    /// still an unlit dot contradicts the dot.
    private func drawFlares(_ context: inout GraphicsContext, _ layout: SkyLayout, _ time: Double?) {
        for flare in sky.flares {
            let intensity = FigureIntensity.star(flare.major, in: majorIntensities)
            guard intensity > 0 else { continue }
            let a = alpha(hi: 0.8, lo: 0.35, dur: flare.dur, delay: flare.delay, time: time) * intensity
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

// One frame of the reveal: the first star up, the second most of the way, the
// third just catching. The line between the first two sits at the dimmer of
// them.
#Preview("Sky, mid ignition") {
    ZStack {
        NightBackground()
        SkyView(sky: previewSky, majorIntensities: [1, 0.65, 0.2])
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
