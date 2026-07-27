import SwiftUI

/// Screen 4 of `../../phase1-build-plan.md`: the moment the questions turn into
/// a person.
///
/// Everything before this was a form. This is the first time someone sees the
/// thing they were filling in, so it is the one screen in Phase 1 that is paced
/// rather than instant: the figure comes on star by star, the card settles, and
/// only then is there anything to tap.
///
/// Shown once, at the end of onboarding, and never again. It is a moment, not a
/// place you can go back to -- My Card is the place.
struct CardRevealScreen: View {
    let card: MyCard
    let sky: Sky
    /// Into the app.
    let confirm: () -> Void
    /// Into My Card, for someone who wants to add more before they go.
    let addMore: () -> Void

    @HavenReduceMotion private var reduceMotion
    /// Runs 0 to 1 across the whole ignition. One animatable value drives every
    /// star, because SwiftUI interpolates a Double and would not interpolate an
    /// array of them.
    @State private var progress: Double = 0
    /// The card arriving. Separate from the ignition because it is a different
    /// gesture on a different curve: the stars come up, the card comes to rest.
    @State private var settled = false
    @State private var photo: Image?

    var body: some View {
        ZStack {
            NightBackground()
            DustLayer()

            VStack(spacing: 0) {
                HavenCard(card: card, sky: sky, majorIntensities: intensities, photo: photo)
                    .scaleEffect(settled ? 1 : RevealMotion.arrivingScale)
                    .cardPhoto(card.photoURL, into: $photo)

                actions
                    .opacity(settled ? 1 : 0)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
        }
        .ignoresSafeArea()
        // Medium, and the only one in the flow: every commit before this was a
        // light tap, and this is not another commit.
        .sensoryFeedback(.impact(weight: .medium), trigger: settled)
        .onAppear(perform: begin)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            PrimaryButton(title: "This is me", action: confirm)
            GhostButton(title: "Add another way to reach me", action: addMore)
        }
    }

    /// Every star's brightness at this instant.
    ///
    /// Each one owns a window of the run, offset by its index, so they come on
    /// in the order the fields were asked for rather than all at once or in a
    /// shuffle. Edges look after themselves: `SkyView` draws a line at the
    /// dimmer of its two stars, so a connection grows in as its second end
    /// does.
    private var intensities: [Double] {
        let count = sky.majors.count
        let total = RevealMotion.total(starCount: count)
        return (0..<count).map { index in
            let start = Double(index) * RevealMotion.stagger / total
            let end = start + HavenMotion.starIgnitionDuration / total
            guard end > start else { return 1 }
            return RevealMotion.easeOut((progress - start) / (end - start))
        }
    }

    private func begin() {
        guard !reduceMotion else {
            // Complete and still, instantly. The state change still happens;
            // it just does not take any time.
            progress = 1
            settled = true
            return
        }
        withAnimation(.linear(duration: RevealMotion.total(starCount: sky.majors.count))) {
            progress = 1
        }
        withAnimation(HavenMotion.revealSettle) {
            settled = true
        }
    }
}

enum RevealMotion {
    /// The gap between one star coming on and the next.
    ///
    /// Short enough that the figure reads as one event rather than a queue,
    /// long enough that you can see it happening in order.
    static let stagger: TimeInterval = 0.1

    /// Where the card starts before it comes to rest. Barely over one: the card
    /// should look like it is settling, not like it is being thrown.
    static let arrivingScale: CGFloat = 1.03

    static func total(starCount: Int) -> TimeInterval {
        stagger * Double(max(starCount - 1, 0)) + HavenMotion.starIgnitionDuration
    }

    /// A star brightens quickly and finishes slowly, the same shape everything
    /// else in Haven decelerates on.
    static func easeOut(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return 1 - pow(1 - x, 3)
    }
}

// MARK: - Previews

private let previewSky = SkyGenerator.build(seed: "user_2abcDEF123")

private let previewCard = MyCard(
    username: "mayachen",
    name: "Maya Chen",
    city: MyCard.City(name: "Ho Chi Minh City", country: "Vietnam"),
    handles: [MyCard.Handle(platform: .x, value: "mayachen", verified: true)],
    primaryPlatform: .x
)

#Preview("Card reveal") {
    CardRevealScreen(card: previewCard, sky: previewSky, confirm: {}, addMore: {})
}

#Preview("Card reveal, accessibility XXXL") {
    CardRevealScreen(card: previewCard, sky: previewSky, confirm: {}, addMore: {})
        .environment(\.dynamicTypeSize, .accessibility3)
}

// The whole screen with nothing moving: the card is simply already there.
#Preview("Card reveal, Reduce Motion") {
    CardRevealScreen(card: previewCard, sky: previewSky, confirm: {}, addMore: {})
        .havenReduceMotion()
}
