import SwiftUI

/// A person's card: their figure, their name, and the little that goes under
/// it. One component, because the reveal, My Card and the beacon all show the
/// same thing and a card that drifted between them would stop being an identity.
///
/// The layout never covers the constellation. The figure owns the top, the
/// serif name sits below it, and an imported photo is small and inline beside
/// the name. Empty fields simply do not render: the unlit star in the figure is
/// the nudge, so there is nothing for a placeholder to say.
///
/// The card fills the space it is given, because the sky has to reach the edges
/// of it. On the reveal and the beacon that space is the screen. A caller that
/// is not a whole screen has to hand it a definite height, and an unbounded
/// scroll view is not one.
struct HavenCard: View {
    let card: MyCard
    let sky: Sky
    /// Nil means the complete figure, which is what the reveal and the beacon
    /// show. My Card passes intensities so unfilled fields read as unlit stars,
    /// and the reveal animates them from dark.
    var majorIntensities: [Double]? = nil
    /// The imported profile photo. Nil until one exists, which is most cards.
    var photo: Image? = nil

    /// Grows with the name it sits beside, or a large text size leaves a
    /// thumbnail floating against two lines of serif.
    @ScaledMetric(relativeTo: .title) private var photoDiameter: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // The sky fills the whole card, and only the figure is held to
                // the band. Bounding the sky itself instead would give the
                // nebulae and the minor field a hard rectangular edge, which
                // reads as a rendering mistake rather than as a sky.
                SkyView(
                    sky: sky,
                    majorIntensities: intensities,
                    figureBand: CGRect(
                        x: 0,
                        y: 0,
                        width: geo.size.width,
                        height: CardMetrics.figureBandHeight
                    )
                )

                VStack(spacing: CardMetrics.lineGap) {
                    identity
                    if let city = card.city?.line, !city.isEmpty {
                        Text(city)
                            .havenSecondary()
                            .multilineTextAlignment(.center)
                    }
                    if let handle = card.primaryHandle {
                        contactChip(handle)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, CardMetrics.figureBandHeight + CardMetrics.figureGap)
            }
        }
    }

    private var intensities: [Double] {
        majorIntensities ?? FigureIntensity.complete(majorCount: sky.majors.count)
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

    private func contactChip(_ handle: MyCard.Handle) -> some View {
        Text(handle.display)
            .havenSecondary()
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(HavenColor.fill, in: Capsule())
    }
}

/// Free-standing because the metrics are about the card, not about one view's
/// internals, and the reveal will want the figure's band to animate against.
enum CardMetrics {
    /// The band the figure gets at the top of the card.
    ///
    /// Chosen so that on every iPhone the figure runs out of width and band at
    /// about the same moment: it fills the card's width without leaving a
    /// stretch of empty band under it. Short enough to leave the name block and
    /// a screen's actions room on the shortest phone Haven supports.
    static let figureBandHeight: CGFloat = 340

    static let figureGap: CGFloat = 20
    static let lineGap: CGFloat = 8
    static let photoGap: CGFloat = 10
}

// MARK: - Previews

private let previewSky = SkyGenerator.build(seed: "user_2abcDEF123")

private let completeCard = MyCard(
    username: "mayachen",
    name: "Maya Chen",
    photoStorageId: "kg700xyz",
    city: MyCard.City(name: "Ho Chi Minh City", country: "Vietnam"),
    handles: [MyCard.Handle(platform: .x, value: "mayachen", verified: true)],
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

// The name block is the part that grows and the figure's band above it is not,
// so this is where the card runs out of screen first.
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
