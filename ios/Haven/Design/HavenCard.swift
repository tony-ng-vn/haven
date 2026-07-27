import SwiftUI

/// A person's card: their figure, their name, and the little that goes under
/// it. One component, because the reveal and My Card show the same thing and a
/// card that drifted between them would stop being an identity.
///
/// Bottom-aligned: the figure takes everything above the name block, and the
/// name, city and contacts sit at the foot of the card. It used to be the other
/// way round -- a fixed 340pt band with the name under it and whatever was left
/// below that -- which left dead space beneath the name on a tall card and gave
/// the figure a ceiling it did not need.
///
/// The layout never covers the constellation. The figure gets the space the
/// text does not use, measured rather than assumed, so a name at an
/// accessibility size takes room from the figure instead of colliding with it.
/// Empty fields simply do not render: the unlit star in the figure is the
/// nudge, so there is nothing for a placeholder to say.
///
/// The card fills the space it is given, because the sky has to reach the edges
/// of it. A caller that is not a whole screen has to hand it a definite size,
/// and an unbounded scroll view is not one.
struct HavenCard: View {
    let card: MyCard
    let sky: Sky
    /// Nil means the complete figure, which is what the reveal shows. My Card
    /// passes intensities so unfilled fields read as unlit stars, and the
    /// reveal animates them from dark.
    var majorIntensities: [Double]? = nil
    /// The imported profile photo. Nil until one exists, which is most cards.
    var photo: Image? = nil
    /// How strongly the nebulae read. A card-sized card is close to the width
    /// the generator's alphas were authored for, so it wants more of them than
    /// a full screen does.
    var nebulaDamping: Double = SkyView.fullScreenNebulaDamping

    /// Grows with the name it sits beside, or a large text size leaves a
    /// thumbnail floating against two lines of serif.
    @ScaledMetric(relativeTo: .title) private var photoDiameter: CGFloat = 40

    @State private var footHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // The sky fills the whole card and only the figure is held to
                // the band. Bounding the sky itself would give the nebulae and
                // the minor field a hard rectangular edge, which reads as a
                // rendering mistake rather than as a sky.
                SkyView(
                    sky: sky,
                    majorIntensities: intensities,
                    figureBand: figureBand(in: geo.size),
                    nebulaDamping: nebulaDamping
                )

                foot
                    .frame(maxWidth: .infinity)
                    .background {
                        GeometryReader { text in
                            Color.clear.preference(
                                key: CardFootHeightKey.self,
                                value: text.size.height
                            )
                        }
                    }
                    .padding(.horizontal, CardMetrics.footInset)
                    .padding(.bottom, CardMetrics.footInset)
            }
        }
        .onPreferenceChange(CardFootHeightKey.self) { footHeight = $0 }
    }

    /// Everything the text does not need. Measured, so a name that wraps at an
    /// accessibility size pushes the figure up rather than through it.
    private func figureBand(in size: CGSize) -> CGRect {
        let taken = footHeight + CardMetrics.footInset + CardMetrics.figureGap
        return CGRect(
            x: 0,
            y: 0,
            width: size.width,
            height: max(size.height - taken, 0)
        )
    }

    private var intensities: [Double] {
        majorIntensities ?? FigureIntensity.complete(majorCount: sky.majors.count)
    }

    private var foot: some View {
        VStack(spacing: CardMetrics.lineGap) {
            identity
            if let city = card.city?.line, !city.isEmpty {
                Text(city)
                    .havenSecondary()
                    .multilineTextAlignment(.center)
            }
            if !handles.isEmpty {
                contacts
                    .padding(.top, CardMetrics.contactsGap)
            }
        }
    }

    /// The photo is decoration beside the name, never a substitute for it, so a
    /// card with a photo and no name shows the photo alone rather than a gap.
    @ViewBuilder
    private var identity: some View {
        let name = card.name ?? ""
        if !name.isEmpty || photo != nil {
            HStack(spacing: CardMetrics.photoGap) {
                if let photo {
                    photo
                        .resizable()
                        .scaledToFill()
                        .frame(width: photoDiameter, height: photoDiameter)
                        .clipShape(Circle())
                        // A photo whose edges match the night would otherwise
                        // dissolve into it.
                        .overlay(Circle().strokeBorder(HavenColor.hairline))
                        // Nothing a screen reader can use; the name carries it.
                        .accessibilityHidden(true)
                }
                if !name.isEmpty {
                    Text(name)
                        .personName(.card)
                        .foregroundStyle(HavenColor.ink)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    /// One circle per way this person can be reached, and only the ways they
    /// actually have. A fixed set of four would put an Instagram mark on a card
    /// with no Instagram, which is a card telling a small lie about someone.
    private var contacts: some View {
        HStack(spacing: CardMetrics.contactGap) {
            ForEach(handles, id: \.platform) { handle in
                PlatformMark(platform: handle.platform)
            }
        }
        // On your own card these say which platforms are on it and nothing
        // more. Tapping your own Instagram to open your own Instagram is not
        // something anyone wants, and editing lives in the rows below.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(contactsLabel)
    }

    private var handles: [MyCard.Handle] { card.handles ?? [] }

    private var contactsLabel: String {
        let names = handles.map { $0.platform.label }
        return names.isEmpty ? "" : "On \(names.joined(separator: ", "))"
    }
}

/// One platform, drawn as a mark in a circle.
///
/// The marks are stand-ins. Instagram, X and LinkedIn each own a trademarked
/// glyph that SF Symbols does not carry, and their brand guidelines forbid
/// recolouring or altering it -- so the only compliant version is their
/// unaltered full-colour asset, which is a decision to take deliberately rather
/// than a detail to slip in. Until then a letterform stands in, which is at
/// least honestly Haven's drawing rather than a bad copy of theirs.
struct PlatformMark: View {
    let platform: MyCard.Platform

    var body: some View {
        Group {
            switch platform {
            case .linkedin:
                Text("in").font(.system(size: 15, weight: .semibold))
            case .x:
                Text("X").font(.system(size: 15, weight: .semibold))
            case .instagram:
                Image(systemName: "camera").font(.system(size: 14, weight: .medium))
            case .phone:
                Image(systemName: "phone.fill").font(.system(size: 13, weight: .medium))
            }
        }
        .foregroundStyle(HavenColor.star)
        .frame(width: CardMetrics.contactDiameter, height: CardMetrics.contactDiameter)
        .overlay(Circle().strokeBorder(HavenColor.hairlineStrong))
    }
}

private struct CardFootHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Free-standing because the metrics are about the card, not about one view's
/// internals, and the reveal wants the figure's band to animate against.
enum CardMetrics {
    /// The gap the figure keeps above the name block, so a star never sits on
    /// a letter.
    static let figureGap: CGFloat = 20
    /// How far the text block is held off the card's edges.
    static let footInset: CGFloat = 28
    static let lineGap: CGFloat = 8
    static let photoGap: CGFloat = 10
    static let contactsGap: CGFloat = 14
    static let contactGap: CGFloat = 12
    static let contactDiameter: CGFloat = 44
}

// MARK: - Previews

private let previewSky = SkyGenerator.build(seed: "user_2abcDEF123")

private let completeCard = MyCard(
    username: "mayachen",
    name: "Maya Chen",
    photoStorageId: "kg700xyz",
    city: MyCard.City(name: "Ho Chi Minh City", country: "Vietnam"),
    handles: [
        MyCard.Handle(platform: .linkedin, value: "maya-chen", verified: true),
        MyCard.Handle(platform: .instagram, value: "mayachen", verified: false),
        MyCard.Handle(platform: .x, value: "mayachen", verified: true),
    ],
    primaryPlatform: .x,
    company: "Haven",
    role: "Founder"
)

/// Stands in for an imported photo. Previews cannot reach Convex storage.
private let previewPhoto = Image(systemName: "person.crop.square.fill")

#Preview("Card, complete") {
    ZStack {
        NightBackground()
        HavenCard(card: completeCard, sky: previewSky, photo: previewPhoto)
    }
    .ignoresSafeArea()
}

// Everything but the name is missing, which is what a card looks like after the
// first question. Nothing renders a placeholder; the dark stars are the nudge.
#Preview("Card, name only") {
    ZStack {
        NightBackground()
        HavenCard(
            card: MyCard(username: "mayachen", name: "Maya Chen"),
            sky: previewSky,
            majorIntensities: FigureIntensity.from(
                litMajors: StarSlot.litMajorIndices(
                    filled: [.name],
                    majorCount: previewSky.majors.count
                ),
                majorCount: previewSky.majors.count
            )
        )
    }
    .ignoresSafeArea()
}

// The name block is what grows, and it now takes its room from the figure
// rather than from the bottom of the card.
#Preview("Card, accessibility XXXL") {
    ZStack {
        NightBackground()
        HavenCard(card: completeCard, sky: previewSky, photo: previewPhoto)
    }
    .ignoresSafeArea()
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Card, Reduce Motion") {
    ZStack {
        NightBackground()
        HavenCard(card: completeCard, sky: previewSky, photo: previewPhoto)
    }
    .ignoresSafeArea()
    .havenReduceMotion()
}
