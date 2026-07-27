import SwiftUI

/// A person's card as a thing rather than a page: a slab of dark glass with a
/// lit edge, sitting at a slight angle in the dark.
///
/// The face inside it is an ordinary `HavenCard` -- a real view hierarchy, not
/// a texture. That is the whole reason this is SwiftUI and not RealityKit: the
/// serif name has to scale with Dynamic Type and be read by VoiceOver, and both
/// die the moment the card face becomes something rendered into an image.
struct CardObject<Face: View>: View {
    /// How far the card is turned, in degrees. Positive tips the right edge
    /// away from the viewer.
    var tilt: CardTilt = .resting
    @ViewBuilder var face: () -> Face

    @HavenReduceMotion private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Past this, the card stops being an object and becomes a panel.
    ///
    /// Both accessibility settings land on the same path on purpose: a flat
    /// card is the real implementation and the tilt is a layer over it, so the
    /// fallback cannot rot from disuse.
    private var isFlat: Bool {
        dynamicTypeSize >= .accessibility3
    }

    private var angle: CardTilt {
        isFlat ? .flat : tilt
    }

    var body: some View {
        ZStack {
            if !isFlat {
                edge
            }
            face()
                // The glass is the substrate and the sky is drawn at full
                // strength on top of it -- not a scrim laid over the
                // constellation, which would mute the one thing on this card
                // that is uniquely this person.
                //
                // It also has to be opaque. A card face with nothing behind it
                // lets the rim slabs show through, and seven stacked gold
                // rectangles read as a card made of amber.
                .background(glass)
                .clipShape(RoundedRectangle(cornerRadius: CardObjectMetrics.corner, style: .continuous))
                .overlay(specular)
                .turned(angle, depth: 0)
        }
        .aspectRatio(CardObjectMetrics.aspect, contentMode: .fit)
        // Never rasterise. A drawingGroup here would flatten the face into a
        // bitmap and take the serif name's crispness and the sky's live canvas
        // with it, which is exactly the softness this is trying to avoid.
    }

    /// The card's thickness, built as slabs stacked behind the face.
    ///
    /// They are pushed back along z inside the same rotation, not offset in x
    /// and y. An offset copy does not foreshorten: it keeps a constant width
    /// whatever the angle, and a constant-width band down one side is the tell
    /// that makes a fake-3D card read as a sticker with a drop shadow. Moving
    /// the rotation's anchor along z sends each slab through the same
    /// projection as the face, so the near corner widens and the far one
    /// narrows the way a real extrusion does.
    private var edge: some View {
        ForEach(0..<CardObjectMetrics.slabCount, id: \.self) { slab in
            RoundedRectangle(cornerRadius: CardObjectMetrics.corner, style: .continuous)
                .fill(rim)
                .turned(angle, depth: CardObjectMetrics.slabDepth * Double(slab + 1))
        }
    }

    /// What the card is made of.
    ///
    /// Darker than the screen behind it, so the card reads as a solid held
    /// against the night rather than a window cut into it. The lift toward the
    /// top-left is where the same light that catches the rim falls across the
    /// face.
    private var glass: some View {
        HavenColor.night
            .overlay {
                LinearGradient(
                    colors: [
                        HavenColor.dusk.opacity(0.55),
                        HavenColor.night.opacity(0.2),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
    }

    /// The lit edge.
    ///
    /// Held in world space, not card space. Real metal catches light from a
    /// fixed direction, so the highlight has to stay where it is while the card
    /// turns under it; a gradient authored in the card's own coordinates
    /// rotates with the card and the whole illusion goes with it.
    private var rim: LinearGradient {
        LinearGradient(
            colors: [
                HavenColor.star.opacity(0.55),
                HavenColor.star.opacity(0.16),
                HavenColor.star.opacity(0.34),
            ],
            startPoint: angle.lightStart,
            endPoint: angle.lightEnd
        )
    }

    /// The sharp line along the silhouette.
    ///
    /// One point, never a glow. A soft edge is what a shadow has; a real edge
    /// catching light has a hard one, and softening it here is the difference
    /// between glass and a sticker. Kept at 1pt rather than a hairline because
    /// a half-point stroke crawls and sparkles as the angle changes.
    private var specular: some View {
        RoundedRectangle(cornerRadius: CardObjectMetrics.corner, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [HavenColor.star.opacity(0.5), HavenColor.hairline],
                    startPoint: angle.lightEnd,
                    endPoint: angle.lightStart
                ),
                lineWidth: 1
            )
    }
}

/// How far the card is turned, and where its light comes from.
struct CardTilt: Equatable {
    /// Degrees about the vertical axis. Positive sends the right edge away,
    /// which is the direction that puts the lit edge down the right side.
    /// Checked on a device rather than reasoned about: the sign is easy to get
    /// backwards and the only tell is which side the rim lands on.
    var y: Double
    /// Degrees about the horizontal axis. Negative tips the top away.
    var x: Double

    static let flat = CardTilt(y: 0, x: 0)

    /// Where the card sits when nothing is touching it.
    ///
    /// Shallow on purpose. The fake thickness holds up while the far edge is
    /// still nearly parallel to the near one, and starts reading as cardboard
    /// well before the angle looks dramatic.
    static let resting = CardTilt(y: 13, x: -5)

    /// The light stays put while the card moves, so these counter-rotate.
    var lightStart: UnitPoint {
        UnitPoint(x: 0.5 - Double(y) / 90, y: 0.0)
    }

    var lightEnd: UnitPoint {
        UnitPoint(x: 0.5 + Double(y) / 90, y: 1.0)
    }
}

enum CardObjectMetrics {
    /// Width over height. Taller than a credit card: this one is read
    /// portrait, with a constellation above the name.
    static let aspect: CGFloat = 0.64
    static let corner: CGFloat = 26

    /// Enough slabs to read as a solid edge, few enough that the compositor is
    /// not paying to hide banding that belongs to the gradient.
    static let slabCount = 7
    /// How far apart the slabs sit along z. Small: the card is a card, not a
    /// book.
    static let slabDepth: Double = 1.6

    /// Lower is a longer lens and a flatter card. Shallow enough that the
    /// perspective is felt rather than noticed.
    static let perspective: CGFloat = 0.32
}

private extension View {
    /// One turn, applied about both axes at a fixed depth.
    ///
    /// `anchorZ` is the whole trick. Every slab shares one angle and differs
    /// only in how far back it sits, which is what makes them foreshorten
    /// together instead of sliding apart.
    func turned(_ tilt: CardTilt, depth: Double) -> some View {
        rotation3DEffect(
            .degrees(tilt.y),
            axis: (x: 0, y: 1, z: 0),
            anchorZ: -depth,
            perspective: CardObjectMetrics.perspective
        )
        .rotation3DEffect(
            .degrees(tilt.x),
            axis: (x: 1, y: 0, z: 0),
            anchorZ: -depth,
            perspective: CardObjectMetrics.perspective
        )
    }
}

// MARK: - Previews

private let previewSky = SkyGenerator.build(seed: "user_2abcDEF123")

private let previewCard = MyCard(
    username: "tonybuildd",
    name: "Tony Nguyen",
    city: MyCard.City(name: "San Francisco", admin: "CA"),
    handles: [
        MyCard.Handle(platform: .linkedin, value: "tony-nguyen", verified: true),
        MyCard.Handle(platform: .instagram, value: "tonybuildd", verified: false),
        MyCard.Handle(platform: .x, value: "tonybuildd", verified: false),
        MyCard.Handle(platform: .phone, value: "+14155550123", verified: false),
    ],
    primaryPlatform: .x
)

private var previewFace: some View {
    HavenCard(card: previewCard, sky: previewSky, nebulaDamping: 0.5)
}

#Preview("Card object") {
    ZStack {
        NightBackground()
        CardObject { previewFace }
            .padding(.horizontal, 44)
    }
    .ignoresSafeArea()
}

#Preview("Card object, flat") {
    ZStack {
        NightBackground()
        CardObject(tilt: .flat) { previewFace }
            .padding(.horizontal, 44)
    }
    .ignoresSafeArea()
}

// Past accessibility3 the card stops being an object, so this should render as
// a square-on panel with no edge at all.
#Preview("Card object, accessibility XXXL") {
    ZStack {
        NightBackground()
        CardObject { previewFace }
            .padding(.horizontal, 44)
    }
    .ignoresSafeArea()
    .environment(\.dynamicTypeSize, .accessibility3)
}
