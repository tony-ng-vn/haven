import SwiftUI

/// The ground every screen sits on: night at the top easing into dusk, with a
/// restrained ember glow rising off the bottom edge.
///
/// This is atmosphere, not a reward. It is identical on the welcome screen and
/// on the finished card -- it never swells or brightens with progress, because
/// the moment the background responds to how much you have filled in, the app
/// starts congratulating you.
struct NightBackground: View {
    var body: some View {
        // Dusk is layered over night by opacity rather than interpolated
        // between, which keeps the ramp weighted low (night holds through the
        // top third) without introducing a third hue.
        HavenColor.night
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: HavenColor.dusk.opacity(0), location: 0.26),
                        .init(color: HavenColor.dusk.opacity(0.5), location: 0.72),
                        .init(color: HavenColor.dusk, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay { EmberGlow() }
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// The horizon. An ellipse of ember centred just past the bottom edge, so only
/// its upper arc is on screen and the light has no visible source.
private struct EmberGlow: View {
    var body: some View {
        GeometryReader { geo in
            EllipticalGradient(
                stops: [
                    .init(color: HavenColor.ember.opacity(0.15), location: 0),
                    .init(color: HavenColor.ember.opacity(0.05), location: 0.45),
                    .init(color: HavenColor.ember.opacity(0), location: 0.74),
                ],
                center: UnitPoint(x: 0.5, y: 1.05)
            )
            // Wider than the screen so the arc reads as a horizon rather than
            // as a circle with two visible shoulders.
            .frame(width: geo.size.width * 1.4, height: geo.size.height * 0.5)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
        .allowsHitTesting(false)
    }
}

#Preview("Night background") {
    NightBackground()
}

#Preview("Night background with dust") {
    ZStack {
        NightBackground()
        DustLayer()
    }
}
