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

    @State private var editing: CardField?
    @State private var photo: Image?
    @State private var confirmingDelete = false

    init() {
        _model = StateObject(wrappedValue: MyCardModel())
    }

    /// A loaded screen that never opens a socket, for previews.
    init(preview load: MyCardLoad) {
        _model = StateObject(wrappedValue: MyCardModel(preview: load))
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
            Text("Your card, everyone you have saved, and everything attached to them. This cannot be undone.")
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
        VStack(alignment: .leading, spacing: 0) {
            // The card is an object here, not a bleed. It has a real edge now,
            // so the four-sided fade that used to dissolve it into the night is
            // gone: a sky that stops at a lit rim is a card, and only a sky
            // that stops at nothing needed hiding.
            CardObject {
                HavenCard(
                    card: card,
                    sky: sky(for: card),
                    majorIntensities: intensities(for: card),
                    photo: photo,
                    nebulaDamping: MyCardMetrics.cardNebulaDamping
                )
            }
            .padding(.horizontal, MyCardMetrics.cardInset)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
            .cardPhoto(card.photoURL, into: $photo)

            if let failure = model.failure {
                Text(failure)
                    .havenSecondary()
                    .foregroundStyle(HavenColor.ember)
                    .padding(.bottom, 8)
            }

            ForEach(CardField.allCases) { field in
                row(field, card: card)
            }

            Text("Account")
                .havenGroupLabel()
                .padding(.top, 26)
                .padding(.bottom, 6)
            HavenRow(title: "Delete your account") {
                confirmingDelete = true
            } leading: {
                EmptyView()
            } trailing: {
                EmptyView()
            }
        }
    }

    private func row(_ field: CardField, card: MyCard) -> some View {
        let value = card.value(for: field)
        return HavenRow(
            title: field.title,
            detail: value ?? field.placeholder,
            accessibilityText: spoken(field, value: value)
        ) {
            editing = field
        } leading: {
            EmptyView()
        } trailing: {
            EmptyView()
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

    /// The figure, seeded the way it is everywhere else: from the identity that
    /// survives a name change.
    private func sky(for card: MyCard) -> Sky {
        SkyGenerator.build(seed: card.username)
    }

    private func intensities(for card: MyCard) -> [Double] {
        let sky = sky(for: card)
        return FigureIntensity.from(
            litMajors: StarSlot.litMajorIndices(
                filled: card.filledSlots,
                majorCount: sky.majors.count
            ),
            majorCount: sky.majors.count
        )
    }
}

enum MyCardMetrics {
    /// How far the card object is held off the sides of the screen. Its height
    /// follows from its aspect, so this is the only size the screen chooses.
    static let cardInset: CGFloat = 44

    /// A card crops far less of each nebula's core than a full screen, so it
    /// can carry more of the wash than the full-screen 0.4. Not much more: at
    /// 0.85 a person whose hues land on green and teal gets a card washed in
    /// colours the dusk palette does not contain, which is the exact failure
    /// the full-screen damping exists to prevent.
    static let cardNebulaDamping: Double = 0.5
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

#Preview("My card, filled") {
    NavigationStack {
        MyCardScreen(preview: .ready(filledCard))
    }
}

// Everything empty but the name, which is what the unlit stars are for.
#Preview("My card, mostly empty") {
    NavigationStack {
        MyCardScreen(preview: .ready(bareCard))
    }
}

#Preview("My card, accessibility XXXL") {
    NavigationStack {
        MyCardScreen(preview: .ready(filledCard))
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("My card, Reduce Motion") {
    NavigationStack {
        MyCardScreen(preview: .ready(filledCard))
    }
    .havenReduceMotion()
}
