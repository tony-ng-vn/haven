import SwiftUI

/// About 28 motes drifting slowly across the screen.
///
/// Deliberately dim. This layer exists so the background is not dead, and it
/// must never compete with the person's own stars -- if you notice a mote, it is
/// too bright. Static under Reduce Motion.
struct DustLayer: View {
    @HavenReduceMotion private var reduceMotion

    // Static, not stored per instance: the field is seeded and identical every
    // time, and SwiftUI re-creates view structs freely.
    private static let motes = Mote.field()

    var body: some View {
        if reduceMotion {
            Canvas(rendersAsynchronously: true) { context, size in
                Mote.draw(Self.motes, in: &context, size: size, time: 0)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else {
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                Canvas(rendersAsynchronously: true) { context, size in
                    Mote.draw(Self.motes, in: &context, size: size, time: time)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private struct Mote {
    /// Start position in unit coordinates, so the field survives a rotation or a
    /// resize without being rebuilt.
    var x: Double
    var y: Double
    var radius: Double
    var baseOpacity: Double
    /// Points per second.
    var speed: Double
    /// Phase offset, so the field does not pulse in unison.
    var phase: Double

    static let count = 28

    /// Seeded, not random, so previews and screenshots are reproducible. Reuses
    /// the sky's PRNG rather than introducing a second one.
    static func field() -> [Mote] {
        var rand = SkyGenerator.Random(seed: SkyGenerator.hash("haven.dust"))
        return (0..<count).map { _ in
            // One draw decides size, brightness and speed together: nearer motes
            // are bigger, brighter and faster, which is what reads as depth.
            let depth = rand.next()
            return Mote(
                x: rand.next(),
                y: rand.next(),
                radius: 0.4 + depth * 0.8,
                baseOpacity: 0.05 + depth * 0.13,
                speed: 0.9 + depth * 3.3,
                phase: rand.next() * 2 * .pi
            )
        }
    }

    static func draw(_ motes: [Mote], in context: inout GraphicsContext, size: CGSize, time: Double) {
        guard size.width > 0, size.height > 0 else { return }
        let wrap = size.width + 4
        for mote in motes {
            // Motes drift right and wrap. Position is derived from time rather
            // than accumulated per frame, so a dropped frame cannot drift the
            // field out of step.
            let x = (mote.x * wrap + mote.speed * time).truncatingRemainder(dividingBy: wrap) - 2
            let breathe = 0.75 + 0.25 * sin(time * 1.05 + mote.phase)
            let rect = CGRect(
                x: x - mote.radius,
                y: mote.y * size.height - mote.radius,
                width: mote.radius * 2,
                height: mote.radius * 2
            )
            context.fill(
                Path(ellipseIn: rect),
                with: .color(HavenColor.muted.opacity(mote.baseOpacity * breathe))
            )
        }
    }
}

#Preview("Dust") {
    ZStack {
        NightBackground()
        DustLayer()
    }
}

#Preview("Dust, Reduce Motion") {
    ZStack {
        NightBackground()
        DustLayer()
    }
    .havenReduceMotion()
}
