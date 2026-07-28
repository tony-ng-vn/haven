import SwiftUI

/// A person's card as a thing rather than a page: a slab of dark glass lying
/// flat, with a printed double rule around its edge.
///
/// It used to be held at an angle, with its thickness faked by slabs stacked
/// behind the face. That is gone. The angle was carrying the whole illusion,
/// and a card you are meant to read square-on should not be turned away from
/// you to prove it is an object. Worth knowing if the tilt is ever revisited:
/// at zero degrees `rotation3DEffect` is the identity transform, so those slabs
/// landed exactly under the opaque face and the gold edge vanished entirely.
/// Flat needs its own depth cue; it is not the tilt set to nothing.
///
/// The face inside is an ordinary `HavenCard` -- a real view hierarchy, not a
/// texture. That is the whole reason this is SwiftUI and not RealityKit: the
/// serif name has to scale with Dynamic Type and be read by VoiceOver, and both
/// die the moment the card face becomes something rendered into an image.
struct CardObject<Face: View>: View {
    @ViewBuilder var face: () -> Face

    var body: some View {
        face()
            // The glass is the substrate and the sky is drawn at full strength
            // on top of it -- not a scrim laid over the constellation, which
            // would mute the one thing on this card that is uniquely this
            // person.
            .background(glass)
            .clipShape(shape)
            .overlay(innerRule)
            .overlay(outerRule)
            .aspectRatio(CardObjectMetrics.aspect, contentMode: .fit)
        // Never rasterise. A drawingGroup here would flatten the face into a
        // bitmap and take the serif name's crispness and the sky's live canvas
        // with it, which is exactly the softness this is trying to avoid.
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CardObjectMetrics.corner, style: .continuous)
    }

    /// What the card is made of.
    ///
    /// Darker than the screen behind it, so the card reads as a solid held
    /// against the night rather than a window cut into it. The lift toward the
    /// top-left is where the light falls across the face.
    ///
    /// This carries more weight than it used to. The night background runs
    /// toward dusk as it descends, so a night-based card is lighter than its
    /// surround at the top and darker at the bottom, and that inversion is real
    /// depth costing nothing.
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

    /// The gold rule, on the silhouette.
    ///
    /// Held vertical rather than angled: the card no longer turns, so there is
    /// no motion for a diagonal highlight to track, and an angled gradient on a
    /// square-on card reads as a mistake rather than as light. Brighter at the
    /// top because that is where the light is.
    ///
    /// One point, and hard. A soft edge is what a shadow has; a real edge
    /// catching light has a hard one, and softening it here is the difference
    /// between glass and a sticker.
    private var outerRule: some View {
        shape.strokeBorder(
            LinearGradient(
                colors: [
                    HavenColor.star.opacity(CardObjectMetrics.ruleTopOpacity),
                    HavenColor.star.opacity(CardObjectMetrics.ruleBottomOpacity),
                ],
                startPoint: .top,
                endPoint: .bottom
            ),
            lineWidth: 1
        )
    }

    /// The hairline set inside it, with night between the two.
    ///
    /// A certificate border rather than a thicker rule. The pair does the work
    /// that weight would: two thin lines with a gap read as something printed
    /// deliberately, where one heavy line reads as a frame around a picture.
    private var innerRule: some View {
        RoundedRectangle(
            cornerRadius: CardObjectMetrics.corner - CardObjectMetrics.innerRuleInset,
            style: .continuous
        )
        .strokeBorder(HavenColor.hairline, lineWidth: 1)
        .padding(CardObjectMetrics.innerRuleInset)
    }
}

enum CardObjectMetrics {
    /// Width over height. Taller than a credit card: this one is read
    /// portrait, with a constellation above the name.
    static let aspect: CGFloat = 0.64
    static let corner: CGFloat = 26

    /// How far the hairline sits inside the gold rule. Wide enough that the two
    /// read as a pair with night between them rather than as one thick edge.
    static let innerRuleInset: CGFloat = 4

    static let ruleTopOpacity: Double = 0.46
    static let ruleBottomOpacity: Double = 0.22
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

private func previewFace(backdropOffset: CGFloat = 0) -> some View {
    HavenCard(
        card: previewCard,
        sky: previewSky,
        nebulaDamping: 0.5,
        backdropOffset: backdropOffset
    )
}

/// The card as My Card drives it: drifting, with its ground drifting against it.
private struct DriftingPreview: View {
    var body: some View {
        CardDrift { drift in
            CardObject { previewFace(backdropOffset: drift.backdrop) }
                .padding(.horizontal, 68)
                .offset(x: drift.card)
        }
    }
}

// Padded to 68pt, which is the screen's own 24 plus the card's 44. A preview at
// the bare inset shows a card wider than the one that ships, which is how a
// wrapping name goes unnoticed until it is on a phone.
#Preview("Card object, still") {
    ZStack {
        NightBackground()
        CardObject { previewFace() }
            .padding(.horizontal, 68)
    }
    .ignoresSafeArea()
}

#Preview("Card object, drifting") {
    ZStack {
        NightBackground()
        DriftingPreview()
    }
    .ignoresSafeArea()
}

// Should be indistinguishable from the still preview above: the drift's rest
// pose is zero for both layers, so there is nothing to freeze.
#Preview("Card object, Reduce Motion") {
    ZStack {
        NightBackground()
        DriftingPreview()
    }
    .ignoresSafeArea()
    .havenReduceMotion()
}

#Preview("Card object, accessibility XXXL") {
    ZStack {
        NightBackground()
        CardObject { previewFace() }
            .padding(.horizontal, 68)
    }
    .ignoresSafeArea()
    .environment(\.dynamicTypeSize, .accessibility3)
}
