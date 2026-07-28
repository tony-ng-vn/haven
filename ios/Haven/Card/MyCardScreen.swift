import ClerkKit
import ConvexMobile
import SwiftUI

/// Screen 7 of `../../phase1-build-plan.md`: the card plus every field, filled
/// or empty, each editable on its own.
///
/// The card at the top is not decoration. Fields nobody has filled in read as
/// unlit stars in the figure, and the rows below say which star is which. That
/// is the whole nudge -- there is no progress bar, no percentage and nothing
/// congratulating anyone, because a card is a thing you have rather than a
/// score you are improving.
struct MyCardScreen: View {
    @StateObject private var model: MyCardModel

    @Environment(\.openURL) private var openURL

    /// Which side of the card is up.
    ///
    /// Owned by `HavenTabs` rather than by this screen, because the Lock Screen
    /// widget can ask for the code at any moment -- including while this screen
    /// is already open, showing the front. State seeded from an init parameter
    /// would miss that: SwiftUI can reuse a screen it is already showing, and
    /// `@State` seeded once never hears the second request.
    @Binding var showingCode: Bool

    @State private var editing: CardField?
    @State private var photo: Image?
    @State private var confirmingDelete = false

    init(showingCode: Binding<Bool>) {
        _model = StateObject(wrappedValue: MyCardModel())
        _showingCode = showingCode
    }

    /// A loaded screen that never opens a socket, for previews.
    init(preview load: MyCardLoad, showingCode: Binding<Bool>) {
        _model = StateObject(wrappedValue: MyCardModel(preview: load))
        _showingCode = showingCode
    }

    var body: some View {
        HavenScreen(
            contentAlignment: .top,
            header: { EmptyView() },
            content: { content },
            actions: { EmptyView() }
        )
        .navigationTitle("Your card")
        .navigationBarTitleDisplayMode(.inline)
        // The bar is transparent by default, so scrolling cut the card off
        // along a razor-straight line with nothing there to explain it, and an
        // object sliced by an invisible plane stops reading as an object.
        //
        // Dusk rather than a system material: the materials resolve to a
        // neutral grey that reads as foreign chrome against a blue-black page.
        // Part-opaque so the card dims under the bar instead of ending at it.
        // Set here rather than on the shared skeleton -- this is the only
        // screen with something solid sliding under the bar.
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(HavenColor.dusk.opacity(0.72), for: .navigationBar)
        // The card and its sky are both ambient loops running at display rate.
        // A sheet covers them completely, so they carry on redrawing something
        // nobody can see until it is dismissed. The code is the other reason to
        // stop: something being read by a camera should hold still.
        .havenAmbientPaused(editing != nil || confirmingDelete || showingCode)
        // Only while there is a card to turn back. The widget can land here
        // with the network down, and then the screen is a "could not load"
        // message with nothing on it to tap: raising the brightness there would
        // pin the phone at full and leave no way to lower it.
        .brightScreen(while: showingCode && model.load.isReady)
        .sheet(item: $editing) { field in
            editor(for: field)
        }
        .alert("Delete your account?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                Task {
                    if await model.deleteAccount() {
                        try? await Clerk.shared.auth.signOut()
                    }
                }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            // Says "your Haven account" now that the sign-in goes with it: the
            // old copy described the data only, and someone who read it as
            // "my login survives this" would have read it correctly.
            Text("Your card, everyone you have saved, and your Haven account itself. This cannot be undone.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.load {
        case .loading:
            ProgressView()
                .tint(HavenColor.ink)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        case .unreachable:
            VStack(spacing: 10) {
                Text("Haven could not load your card.")
                    .havenBody()
                Text("This is a connection problem. Nothing you have answered is lost.")
                    .havenSecondary()
                    .multilineTextAlignment(.center)
                GhostButton(title: "Try again") { model.retry() }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        case .ready(let card):
            loaded(card)
        }
    }

    private func loaded(_ card: MyCard) -> some View {
        // Seeded the way it is everywhere else: from the identity that survives
        // a name change.
        //
        // Built here rather than inside the drift closure below, which re-runs
        // every frame. Generating a sky is cheap, but it allocates a fresh
        // value each time, and SkyView's layers hold it as a stored property --
        // so rebuilding it per frame would defeat the caching the whole sky is
        // designed around.
        let sky = SkyGenerator.build(seed: card.username)
        let intensities = FigureIntensity.from(
            litMajors: StarSlot.litMajorIndices(
                filled: card.filledSlots,
                majorCount: sky.majors.count
            ),
            majorCount: sky.majors.count
        )

        return VStack(alignment: .leading, spacing: 0) {
            // The card is an object here, not a bleed. It has a real edge now,
            // so the four-sided fade that used to dissolve it into the night is
            // gone: a sky that stops at a printed rule is a card, and only a sky
            // that stops at nothing needed hiding.
            //
            // The card barely moves and its sky moves the other way. The offset
            // goes outside the padding, so it shifts the card and not the space
            // it sits in: everything below stays exactly where it is.
            CardDriftClock { drift in
                TwoSidedCard(showingBack: $showingCode) {
                    CardObject {
                        HavenCard(
                            card: card,
                            sky: sky,
                            majorIntensities: intensities,
                            photo: photo,
                            nebulaDamping: CardObjectMetrics.nebulaDamping,
                            sceneryOffset: drift.scenery
                        )
                    }
                    .overlay(alignment: .topTrailing) {
                        flipMark("qrcode", says: "Show your code")
                    }
                } back: {
                    CardObject { CardBack(card: card) }
                        .overlay(alignment: .topTrailing) {
                            flipMark("person.crop.circle", says: "Show your card")
                        }
                }
                .padding(.horizontal, MyCardMetrics.cardInset)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
                .offset(x: drift.card)
            }
            .cardPhoto(card.photoURL, into: $photo)

            if let failure = model.failure {
                // Tinted through the helper, not layered over it: the ember
                // used to sit outside `havenSecondary` and never reached the
                // text, so a save that failed said so in the same grey as a
                // hint.
                Text(failure)
                    .havenSecondary(HavenColor.ember)
                    .padding(.bottom, 8)
            }

            ForEach(CardField.allCases) { field in
                row(field, card: card)
            }

            Text("Account")
                .havenGroupLabel()
                .padding(.top, 26)
                .padding(.bottom, 6)
            // Warned rather than merely listed. It used to be one hairline
            // below "Role", in the same colour, on a screen people open to fix
            // a typo in their name.
            HavenRow(
                title: "Delete your account",
                isDestructive: true,
                action: { confirmingDelete = true }
            )

            // Guideline 5.1.1(i) wants the privacy policy reachable from inside
            // the app, not only from the App Store listing, and this screen is
            // where an account already lives. Built from Config.cardHost rather
            // than a literal, so the pages and the card's code can never point
            // at different sites.
            Text("Legal")
                .havenGroupLabel()
                .padding(.top, 26)
                .padding(.bottom, 6)
            ForEach(LegalDocument.allCases) { document in
                HavenRow(title: document.title, action: { openURL(document.url) }) {
                    RowMark.external
                }
            }
        }
    }

    /// The corner mark that says the card has another side, and the way to
    /// reach it without seeing the card at all.
    ///
    /// Retiring the toolbar's QR button took away the one place that announced
    /// a code exists, and a card that turns over with nothing to suggest it is
    /// a secret. Small and dim, because the target is the whole card and this
    /// only has to hint.
    ///
    /// It carries the label and the action rather than the card doing it,
    /// because this is now the only route to somebody's own code. A custom
    /// action on the card as a whole would depend on VoiceOver surfacing an
    /// action from a container nothing can focus; an element with a button
    /// trait is focusable by definition. Not a real `Button`: the whole card
    /// already owns a tap, and two tap handlers on the same pixels is how one
    /// turn becomes two.
    private func flipMark(_ symbol: String, says label: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(HavenColor.faint)
            .padding(MyCardMetrics.flipMarkInset)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { showingCode.toggle() }
    }

    /// A field, filled or not.
    ///
    /// The two used to look identical: "Where you work" and "San Francisco, CA"
    /// were the same weight and the same colour, so a filled field read like a
    /// prompt. VoiceOver was already told which was which -- it hears "Company,
    /// empty" -- and the eye was not, which is backwards. An empty field now
    /// says "Add" where a filled one shows the chevron.
    private func row(_ field: CardField, card: MyCard) -> some View {
        let value = card.value(for: field)
        return HavenRow(
            title: field.title,
            detail: value ?? field.placeholder,
            accessibilityText: spoken(field, value: value),
            action: { editing = field }
        ) {
            if value == nil {
                RowAccessory(text: "Add")
            } else {
                RowMark.chevron
            }
        }
    }

    /// An empty field says so out loud. The unlit star carries it visually and
    /// a screen reader gets nothing from a star.
    private func spoken(_ field: CardField, value: String?) -> String {
        guard let value else { return "\(field.title), empty" }
        return "\(field.title), \(value)"
    }

    @ViewBuilder
    private func editor(for field: CardField) -> some View {
        switch field {
        case .name, .company, .role:
            TextFieldEditor(
                field: field,
                initial: model.card?.value(for: field) ?? ""
            ) { value in
                guard let key = field.storedKey else { return }
                if let value {
                    await model.save([key: value])
                } else {
                    await model.clear(key)
                }
            }
        case .city:
            CityFieldEditor(initial: model.card?.city?.line ?? "") { city in
                if let city {
                    await model.save(["city": city.convexArgument])
                } else {
                    await model.clear("city")
                }
            }
        case .handles:
            HandlesEditor(
                handles: model.card?.handles ?? [],
                primary: model.card?.primaryPlatform
            ) { handles, primary in
                await model.save([
                    "handles": handles.map { $0.convexArgument } as [ConvexEncodable?],
                    "primaryPlatform": primary?.rawValue,
                ])
            }
        case .photo:
            PhotoEditor(photo: photo) { data in
                await model.setPhoto(data)
            } remove: {
                await model.clear("photoStorageId")
            }
        }
    }
}

enum MyCardMetrics {
    /// How far the card is held off the sides of this screen's own column.
    ///
    /// Sits on top of `HavenScreen`'s 24pt, so the card ends up
    /// `CardObjectMetrics.screenInset` from the edge of the display -- the same
    /// as the reveal, which has no column and applies that inset directly.
    /// Change one and change the other, or the card resizes between the two
    /// screens that show it.
    static let cardInset: CGFloat = CardObjectMetrics.screenInset - 24

    /// Clears the card's double rule, so the mark reads as printed on the card
    /// rather than as something caught in its edge.
    static let flipMarkInset: CGFloat = 12
}

// MARK: - Previews

private let filledCard = MyCard(
    username: "mayachen",
    name: "Maya Chen",
    city: MyCard.City(name: "Ho Chi Minh City", country: "Vietnam"),
    handles: [
        MyCard.Handle(platform: .x, value: "mayachen", verified: true),
        MyCard.Handle(platform: .linkedin, value: "maya-chen", verified: false),
    ],
    primaryPlatform: .x,
    company: "Haven",
    role: "Founder"
)

private let bareCard = MyCard(username: "mayachen", name: "Maya Chen")

/// Somewhere for the flip state to live, which in the app is `HavenTabs`.
private struct CardPreview: View {
    let load: MyCardLoad
    @State private var showingCode: Bool

    init(_ load: MyCardLoad = .ready(filledCard), showingCode: Bool = false) {
        self.load = load
        _showingCode = State(initialValue: showingCode)
    }

    var body: some View {
        NavigationStack {
            MyCardScreen(preview: load, showingCode: $showingCode)
        }
    }
}

#Preview("My card, filled") {
    CardPreview()
}

// Everything empty but the name, which is what the unlit stars are for.
#Preview("My card, mostly empty") {
    CardPreview(.ready(bareCard))
}

#Preview("My card, accessibility XXXL") {
    CardPreview()
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("My card, Reduce Motion") {
    CardPreview()
        .havenReduceMotion()
}

// Where the Lock Screen widget lands: the card already turned over, which is
// the one state of this screen `CardBack`'s own previews cannot show, because
// the hint, the raised brightness and the stopped drift all live out here.
#Preview("My card, turned over") {
    CardPreview(showingCode: true)
}
