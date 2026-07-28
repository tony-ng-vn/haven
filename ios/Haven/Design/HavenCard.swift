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
/// accessibility size takes room from the figure instead of colliding with it
/// -- down to a floor, past which the name shrinks and the city leaves rather
/// than the sky quietly going missing.
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
    /// Slides the sky's ground against the card, for My Card's parallax. The
    /// figure does not move: it is the person, not scenery.
    var sceneryOffset: CGFloat = 0

    /// Grows with the name it sits beside, or a large text size leaves a
    /// thumbnail floating against two lines of serif.
    @ScaledMetric(relativeTo: .title) private var photoDiameter: CGFloat = 40

    /// The platform marks grow with the text too. What the row can actually
    /// hold is decided in `contacts`, against the card's real width.
    @ScaledMetric(relativeTo: .footnote) private var markDiameter: CGFloat =
        CardMetrics.contactDiameter

    @Environment(\.dynamicTypeSize) private var typeSize

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
                    nebulaDamping: nebulaDamping,
                    sceneryOffset: sceneryOffset
                )

                // The measurement wraps the text and nothing else. A `.frame`
                // between the two would be what got measured: a frame with a
                // `maxHeight` takes the whole proposal up to that cap, so the
                // reported height is the cap rather than the text, and the
                // band below it computes to its floor on every card at every
                // text size. Measured with a hosting probe, not guessed.
                foot(inWidth: geo.size.width - 2 * CardMetrics.footInset)
                    .background {
                        GeometryReader { text in
                            Color.clear.preference(
                                key: CardFootHeightKey.self,
                                value: text.size.height
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, CardMetrics.footInset)
                    .padding(.bottom, CardMetrics.footInset)
            }
        }
        .onPreferenceChange(CardFootHeightKey.self) { footHeight = $0 }
    }

    /// Everything the text does not need. Measured, so a name that wraps at an
    /// accessibility size pushes the figure up rather than through it -- down
    /// to the floor `figureBandHeight` keeps, past which the name shrinks
    /// instead.
    private func figureBand(in size: CGSize) -> CGRect {
        CGRect(
            x: 0,
            y: 0,
            width: size.width,
            height: CardMetrics.figureBandHeight(
                cardHeight: size.height,
                footHeight: footHeight
            )
        )
    }

    private var intensities: [Double] {
        majorIntensities ?? FigureIntensity.complete(majorCount: sky.majors.count)
    }

    private func foot(inWidth width: CGFloat) -> some View {
        VStack(spacing: CardMetrics.lineGap) {
            identity
            // The city goes at accessibility sizes rather than shrinking,
            // because text cannot shrink to fit a height -- `minimumScaleFactor`
            // only ever fits a width -- so something has to actually leave, and
            // of the three things here the city is the one that costs least.
            //
            // It leaves the drawing, not the card: when it is not shown the
            // name speaks it instead, because the reveal shows this card with
            // nothing else on screen and no rows underneath repeating it.
            if let city = card.city?.line, !city.isEmpty, !typeSize.isAccessibilitySize {
                Text(city)
                    .havenSecondary()
                    .multilineTextAlignment(.center)
            }
            if !handles.isEmpty {
                contacts(inWidth: width)
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
                        // Where the pressure goes once the figure has stopped
                        // giving up room. "Maria Fernanda Rodriguez" at an
                        // accessibility size wants five lines in a 201pt
                        // column; two and a shrink keeps the whole name and
                        // leaves the constellation somewhere to be.
                        .lineLimit(CardMetrics.nameLineLimit)
                        .minimumScaleFactor(CardMetrics.nameMinimumScale)
                        .accessibilityLabel(spokenIdentity(name))
                }
            }
        }
    }

    /// What the name reads as aloud.
    ///
    /// It carries the city too on the sizes that do not draw it, so nothing is
    /// lost to a screen reader that a sighted reader would still find in the
    /// rows below -- and on the reveal, where there are no rows, nothing is
    /// lost at all.
    private func spokenIdentity(_ name: String) -> String {
        guard typeSize.isAccessibilitySize,
              let city = card.city?.line, !city.isEmpty
        else { return name }
        return "\(name), \(city)"
    }

    /// One circle per way this person can be reached, and only the ways they
    /// actually have. A fixed set of four would put an Instagram mark on a card
    /// with no Instagram, which is a card telling a small lie about someone.
    private func contacts(inWidth width: CGFloat) -> some View {
        let diameter = CardMetrics.fittedContactDiameter(scaled: markDiameter, fitting: width)
        return HStack(spacing: CardMetrics.contactGap) {
            ForEach(handles, id: \.platform) { handle in
                PlatformMark(platform: handle.platform, diameter: diameter)
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
    /// No default: what fits is decided against the card's real width, and a
    /// mark drawn at the designed size regardless is the bug this replaced.
    let diameter: CGFloat

    var body: some View {
        Group {
            switch platform {
            case .linkedin:
                Text("in").font(.system(size: glyph, weight: .semibold))
            case .x:
                Text("X").font(.system(size: glyph, weight: .semibold))
            case .instagram:
                Image(systemName: "camera").font(.system(size: glyph * 0.92, weight: .medium))
            case .phone:
                Image(systemName: "phone.fill").font(.system(size: glyph * 0.86, weight: .medium))
            }
        }
        .foregroundStyle(HavenColor.star)
        .frame(width: diameter, height: diameter)
        .overlay(Circle().strokeBorder(HavenColor.hairlineStrong))
    }

    /// Read off the circle rather than off the text size, so the mark keeps its
    /// proportions once the circle has stopped growing. Sizing it from Dynamic
    /// Type directly is how a glyph ends up bigger than the ring around it.
    private var glyph: CGFloat { diameter * 0.42 }
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

    /// A platform mark, at the usual text size.
    ///
    /// Was 44, which is the tap-target minimum -- a size that promised these
    /// were buttons when they do nothing, and that four of them plus their gaps
    /// could not fit inside the card's own foot on any phone Haven supports.
    static let contactDiameter: CGFloat = 36
    /// Small enough to be tight, big enough to still read as a mark rather than
    /// a speck. No card on a real phone is narrow enough to reach it; it is
    /// here so a card with no width yet cannot hand `frame` a negative one.
    static let contactDiameterFloor: CGFloat = 22

    /// The least of the card the figure keeps, whatever the name does.
    ///
    /// A long name at an accessibility size can want more room than the card
    /// has. Without this the figure gives up all of it, and a person's own
    /// constellation quietly is not there -- which reads as a bug in the sky
    /// rather than as text that did not fit.
    static let figureBandFloor: CGFloat = 0.34

    /// A name is allowed two lines and then has to shrink. Truncating is not an
    /// option -- half a name is the wrong person -- and neither is unlimited
    /// wrapping, which is what took the figure's room in the first place.
    static let nameLineLimit = 2
    static let nameMinimumScale: CGFloat = 0.55

    /// How big the platform marks can actually be here.
    ///
    /// `@ScaledMetric` grows them with the text, and the card does not grow
    /// with anything: at an accessibility size the designed 36 becomes 60 or
    /// more, and four of those never fit. This takes the smaller of what the
    /// text size asked for and what the row can hold.
    ///
    /// Sized against a full row of platforms rather than against how many this
    /// person happens to have, or a card with one handle would show a mark
    /// three times the size of the same mark on a card with four. A mark is a
    /// mark; how many you have is not a reason for it to be bigger.
    static func fittedContactDiameter(scaled: CGFloat, fitting width: CGFloat) -> CGFloat {
        let count = CGFloat(MyCard.Platform.allCases.count)
        let share = (width - contactGap * (count - 1)) / count
        return max(min(scaled, share), contactDiameterFloor)
    }

    /// The band the figure draws in: everything the text does not need, down to
    /// a floor.
    ///
    /// The floor is where the sky stops giving way. Past it the text carries on
    /// and prints over the figure, which is why the card sheds its city line at
    /// accessibility sizes rather than relying on this alone -- a frame cannot
    /// shrink text, and capping the foot's height only hides how tall it got.
    static func figureBandHeight(cardHeight: CGFloat, footHeight: CGFloat) -> CGFloat {
        let taken = footHeight + footInset + figureGap
        return max(cardHeight - taken, figureBandFloor * cardHeight)
    }
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

/// The name that finds the collision. "Maya Chen" fits at every text size, so
/// an accessibility preview built on it proves only that short names are short.
private let longNameCard: MyCard = {
    var card = completeCard
    card.name = "Maria Fernanda Rodriguez"
    return card
}()

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

// The name block is what grows, and it takes its room from the figure rather
// than from the bottom of the card -- down to the floor, past which the name
// shrinks instead and the city leaves.
//
// Sized like the card that ships rather than filling the screen: this view
// fills whatever it is handed, and at full width there is room for any name, so
// a full-bleed preview cannot show the one failure worth looking at here.
#Preview("Card, accessibility XXXL") {
    ZStack {
        NightBackground()
        HavenCard(card: longNameCard, sky: previewSky, photo: previewPhoto)
            .aspectRatio(CardObjectMetrics.aspect, contentMode: .fit)
            .frame(maxWidth: CardObjectMetrics.maxWidth)
            .padding(.horizontal, CardObjectMetrics.screenInset)
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
