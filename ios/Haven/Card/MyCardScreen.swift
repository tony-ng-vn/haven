import ClerkKit
import ConvexMobile
import PhotosUI
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
    @State private var photoItem: PhotosPickerItem?
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
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                // Loaded as data rather than an Image: what goes to storage is
                // the file, and re-encoding a SwiftUI Image would lose the
                // original and its orientation.
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await model.setPhoto(data)
                }
                photoItem = nil
            }
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
            // Handed a definite height, because HavenCard fills whatever space
            // it is given and this one is inside a scroll view.
            //
            // Bounding it puts an edge back around the sky, which is the one
            // thing the card was built to avoid, so the mask lets all four
            // sides dissolve instead of stopping. A sky that ends in a line
            // reads as a panel somebody forgot to style; one that fades reads
            // as a sky you are seeing part of.
            HavenCard(card: card, sky: sky(for: card), majorIntensities: intensities(for: card))
                .frame(height: MyCardMetrics.cardHeight)
                .mask(MyCardMetrics.edgeFade)
                .padding(.bottom, 8)

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

    @ViewBuilder
    private func row(_ field: CardField, card: MyCard) -> some View {
        let value = card.value(for: field)
        if field == .photo {
            // The only row that opens a system picker rather than a sheet of
            // ours, so it is a PhotosPicker rather than a HavenRow action.
            PhotosPicker(selection: $photoItem, matching: .images) {
                rowContent(field, value: value)
            }
            .buttonStyle(PressScaleStyle())
        } else {
            HavenRow(
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
    }

    private func rowContent(_ field: CardField, value: String?) -> some View {
        HavenRow(
            title: field.title,
            detail: value ?? field.placeholder,
            accessibilityText: spoken(field, value: value),
            leading: { EmptyView() },
            trailing: { EmptyView() }
        )
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
            // Handled by the PhotosPicker on the row itself.
            EmptyView()
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
    /// The figure's band plus room for the name block under it. Fixed, because
    /// the card is the header of a scrolling screen rather than the screen.
    static let cardHeight: CGFloat = CardMetrics.figureBandHeight + 140

    /// Dissolves all four edges of the card into the night.
    ///
    /// Two gradients multiplied, because one alone leaves the other pair of
    /// sides cut square. The bottom gets the longest fade: it is the edge that
    /// meets the rows, and the sky has to be gone by the time the first one
    /// starts. Full bleed would be the other answer, but `HavenScreen` puts its
    /// content inside a scroll view that clips, so there is no reaching past
    /// the margin from in here.
    static var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.06),
                .init(color: .black, location: 0.82),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.08),
                    .init(color: .black, location: 0.92),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
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
