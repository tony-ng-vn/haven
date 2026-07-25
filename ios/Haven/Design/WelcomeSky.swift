import SwiftUI

/// The welcome screen's ambient layer: a deep starfield with other people's
/// constellations drifting through it.
///
/// This is the one screen that departs from `DustLayer`, and it does so on
/// purpose. Everywhere else the ambient field must stay below notice so it
/// cannot compete with the person's own stars -- but before sign-in there is no
/// personal sky to compete with, and the tagline is a promise about other
/// people. Strangers' figures passing overhead is that promise, made ambient.
///
/// The figures are real: `SkyGenerator.build(seed:)` mints them the same way it
/// mints a person's own, so what drifts past is the same kind of object the
/// card reveals at the end of onboarding.
struct WelcomeSky: View {
    @HavenReduceMotion private var reduceMotion

    private static let stars = StarField.build()
    private static let figures = PassingFigure.all()

    var body: some View {
        if reduceMotion {
            Canvas(rendersAsynchronously: true) { context, size in
                draw(&context, size: size, time: 0)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else {
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                Canvas(rendersAsynchronously: true) { context, size in
                    draw(&context, size: size, time: time)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, time: Double) {
        guard size.width > 0, size.height > 0 else { return }
        StarField.draw(Self.stars, in: &context, size: size, time: time, still: reduceMotion)
        for figure in Self.figures {
            figure.draw(in: &context, size: size, time: time, still: reduceMotion)
        }
    }
}

// MARK: - Star field

/// Three parallax layers. Depth comes from the difference in rate, not from the
/// count: far stars are smaller, dimmer and slower, and that is the whole trick.
private struct StarField {
    var x: Double
    var y: Double
    var radius: Double
    var opacity: Double
    var phase: Double
    var twinkle: Double
    /// Points per second, downward.
    var speed: Double

    private struct Layer {
        let count: Int
        let radius: ClosedRange<Double>
        let opacity: ClosedRange<Double>
        let speed: Double
    }

    private static let layers = [
        Layer(count: 150, radius: 0.35...0.75, opacity: 0.10...0.26, speed: 1.2),
        Layer(count: 70, radius: 0.6...1.1, opacity: 0.20...0.44, speed: 2.6),
        Layer(count: 28, radius: 0.9...1.6, opacity: 0.34...0.68, speed: 4.4),
    ]

    /// Seeded off the sky's own PRNG rather than a second one, so the field is
    /// identical on every launch and in every screenshot.
    static func build() -> [StarField] {
        var rand = SkyGenerator.Random(seed: SkyGenerator.hash("haven.welcome.stars"))
        var stars: [StarField] = []
        for layer in layers {
            for _ in 0..<layer.count {
                stars.append(StarField(
                    x: rand.next(),
                    y: rand.next(),
                    radius: lerp(layer.radius, rand.next()),
                    opacity: lerp(layer.opacity, rand.next()),
                    phase: rand.next() * 2 * .pi,
                    twinkle: 0.5 + rand.next() * 1.4,
                    speed: layer.speed
                ))
            }
        }
        return stars
    }

    private static func lerp(_ range: ClosedRange<Double>, _ t: Double) -> Double {
        range.lowerBound + t * (range.upperBound - range.lowerBound)
    }

    static func draw(
        _ stars: [StarField],
        in context: inout GraphicsContext,
        size: CGSize,
        time: Double,
        still: Bool
    ) {
        let wrap = size.height + 8
        for star in stars {
            // Derived from time rather than accumulated per frame, so a dropped
            // frame cannot walk the field out of step.
            let y = still
                ? star.y * size.height
                : (star.y * size.height + star.speed * time).truncatingRemainder(dividingBy: wrap)
            let breathe = still ? 1 : 0.72 + 0.28 * sin(time * star.twinkle + star.phase)
            let rect = CGRect(
                x: star.x * size.width - star.radius,
                y: y - star.radius,
                width: star.radius * 2,
                height: star.radius * 2
            )
            context.fill(
                Path(ellipseIn: rect),
                with: .color(HavenColor.ink.opacity(star.opacity * breathe))
            )
        }
    }
}

// MARK: - Passing figures

/// One stranger's constellation, crossing the screen and leaving.
private struct PassingFigure {
    let sky: Sky
    /// Width as a fraction of the screen.
    let scale: Double
    /// Vertical position as a fraction of the screen.
    let y: Double
    /// Seconds for one full crossing.
    let duration: Double
    /// Offset into that crossing, so the five are never in step.
    let delay: Double
    let tilt: Double
    /// Nearer figures are larger and brighter together, which is what reads as
    /// depth rather than as inconsistent opacity.
    let depth: Double
    /// Where this figure is held under Reduce Motion. Set per figure and kept
    /// clear of the ends: freezing them all at the same point would stack every
    /// figure at the same x, which the moving sky never does. Chosen inside
    /// 0.25...0.75 so none of them lands in an edge fade and disappears.
    let restProgress: Double

    /// Five different people. Every seed produces a different figure, and the
    /// scale, tilt, speed and depth differ too, so no two passes read as the
    /// same sky coming round again.
    static func all() -> [PassingFigure] {
        [
            PassingFigure(sky: SkyGenerator.build(seed: "haven.welcome.1"),
                          scale: 0.30, y: 0.14, duration: 46, delay: 0, tilt: -0.22,
                          depth: 1.00, restProgress: 0.30),
            PassingFigure(sky: SkyGenerator.build(seed: "haven.welcome.2"),
                          scale: 0.19, y: 0.31, duration: 74, delay: 22, tilt: 0.34,
                          depth: 0.62, restProgress: 0.55),
            PassingFigure(sky: SkyGenerator.build(seed: "haven.welcome.3"),
                          scale: 0.36, y: 0.47, duration: 38, delay: 44, tilt: 0.11,
                          depth: 1.15, restProgress: 0.42),
            PassingFigure(sky: SkyGenerator.build(seed: "haven.welcome.4"),
                          scale: 0.23, y: 0.63, duration: 62, delay: 12, tilt: -0.40,
                          depth: 0.74, restProgress: 0.68),
            PassingFigure(sky: SkyGenerator.build(seed: "haven.welcome.5"),
                          scale: 0.28, y: 0.79, duration: 52, delay: 33, tilt: 0.19,
                          depth: 0.90, restProgress: 0.36),
        ]
    }

    func draw(in context: inout GraphicsContext, size: CGSize, time: Double, still: Bool) {
        // Held part-way across under Reduce Motion, so a still screen still
        // shows what this screen is about.
        let progress = still
            ? restProgress
            : ((time + delay).truncatingRemainder(dividingBy: duration)) / duration

        // Fades in and out at the edges, so nothing appears mid-screen. Every
        // resting position sits clear of both fades, so the still sky renders
        // at the same brightness as the moving one at its midpoint.
        let alpha = min(1, min(progress, 1 - progress) / 0.18) * depth
        guard alpha > 0.004 else { return }

        // Travels further than one screen width, so a figure is fully gone
        // before it comes round again.
        let width = scale * size.width
        let unit = width / SkyGenerator.width

        var layer = context
        layer.translateBy(x: (1.25 - progress * 1.7) * size.width, y: y * size.height)
        layer.rotate(by: .radians(tilt))

        var path = Path()
        for (a, b) in sky.edges {
            guard sky.majors.indices.contains(a), sky.majors.indices.contains(b) else { continue }
            path.move(to: CGPoint(x: sky.majors[a].x * unit, y: sky.majors[a].y * unit))
            path.addLine(to: CGPoint(x: sky.majors[b].x * unit, y: sky.majors[b].y * unit))
        }
        layer.stroke(
            path,
            with: .color(HavenColor.star.opacity(0.1 * alpha)),
            lineWidth: 0.8
        )

        let dot = 1.3 * min(1.2, depth)
        for major in sky.majors {
            let rect = CGRect(
                x: major.x * unit - dot,
                y: major.y * unit - dot,
                width: dot * 2,
                height: dot * 2
            )
            layer.fill(Path(ellipseIn: rect), with: .color(HavenColor.star.opacity(0.34 * alpha)))
        }
    }
}

#Preview("Welcome sky") {
    ZStack {
        NightBackground()
        WelcomeSky()
    }
}

#Preview("Welcome sky, Reduce Motion") {
    ZStack {
        NightBackground()
        WelcomeSky()
    }
    .havenReduceMotion()
}
