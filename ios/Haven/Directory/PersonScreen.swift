import SwiftUI

/// One person: who they are, how to reach them, and the note you keep.
///
/// Money screen two. The note is not a field among fields, it is the point --
/// everything above it is theirs and came from a card or a capture, and the
/// note is the only part that is yours. What is new here is that the rest of
/// the screen finally shows what the server was already sending: their photo,
/// their handles, and a tap on any of them that opens the app they are actually
/// in. Reach is the fourth stroke of the loop, and it did not exist.
struct PersonScreen: View {
    @StateObject private var model: PersonModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var photo: Image?
    @State private var isEditing = false

    init(personId: String) {
        _model = StateObject(wrappedValue: PersonModel(personId: personId))
    }

    init(model: PersonModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        HavenScreen(
            contentAlignment: .top,
            header: { header },
            content: { content },
            actions: { actions }
        )
        // No navigation title: the header below is the name, and setting both
        // renders it twice on one screen.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .cardPhoto(model.person?.photoURL, into: $photo)
        .sheet(isPresented: $isEditing) {
            PersonEditor(model: model, photo: photo)
        }
        // A deleted person has no screen. Leaving is the whole receipt: there
        // is nothing left here to confirm it against.
        .onChange(of: model.isDeleted) { _, deleted in
            if deleted { dismiss() }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Edit") { isEditing = true }
                .font(HavenFont.ghostLabel)
                .foregroundStyle(HavenColor.muted)
                .disabled(model.person == nil)
        }
    }

    /// Their photo and their name, which is the one piece of serif text on the
    /// screen because it is a person's name.
    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            if let photo {
                photo
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: PersonMetrics.photoDiameter,
                        height: PersonMetrics.photoDiameter
                    )
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(HavenColor.hairline))
                    // The name beside it says who this is; announcing "photo"
                    // gives a screen reader nothing it can use.
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(model.person?.name ?? " ")
                    .personName(.card)
                    .foregroundStyle(HavenColor.ink)
                if let detail = model.person?.detail {
                    Text(detail)
                        .havenSecondary()
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The name is the heading of this screen, so it is announced as one
        // rather than as the first of three loose labels.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var content: some View {
        switch model.load {
        case .loading:
            ProgressView()
                .tint(HavenColor.faint)
                .frame(maxWidth: .infinity)
                .padding(.top, 32)
        case .unreachable:
            unreachable
        case .ready(let person):
            loaded(person)
        }
    }

    private var unreachable: some View {
        VStack(spacing: 12) {
            Text("Haven could not open this person.")
                .havenBody()
            Text("This is a connection problem. Nothing you saved is lost.")
                .havenSecondary()
                .multilineTextAlignment(.center)
            GhostButton(title: "Try again") { model.retry() }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }

    private func loaded(_ person: Person) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if let about = person.headline ?? person.bio, !about.isEmpty {
                Text(about)
                    .havenSecondary()
            }

            reach(person)

            VStack(alignment: .leading, spacing: 8) {
                Text("What you remember")
                    .havenGroupLabel()
                HavenNoteField(
                    label: "What you remember about \(person.name)",
                    placeholder: "Where you met, what they are working on, who introduced you.",
                    text: $model.draft
                )
                // Dated lines are what "who did I meet last month" reads, and
                // one line per entry is what makes each one findable on its
                // own -- so say that here rather than let one paragraph grow.
                Text("One line per thing. Each is searchable on its own.")
                    .havenSecondary()
            }

            if let failure = model.failure {
                Text(failure)
                    .havenSecondary(HavenColor.ember)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// How to reach them, and a tap that actually goes there.
    ///
    /// Drawn at all only when there is something to reach: a person with no
    /// handle gets no empty heading, the same way an unfilled field on a card
    /// draws nothing.
    private func reach(_ person: Person) -> some View {
        let handles = person.reachableHandles
        let link = person.standaloneLink
        return Group {
            if !handles.isEmpty || link != nil {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Ways to reach them")
                        .havenGroupLabel()
                        .padding(.bottom, 6)
                    ForEach(handles) { handle in
                        reachRow(handle)
                    }
                    if let link {
                        HavenRow(
                            title: "Their page",
                            detail: link.absoluteString,
                            accessibilityText:
                                "Their page, \(link.absoluteString), opens outside Haven",
                            action: { openURL(link) }
                        ) {
                            RowMark.external
                        }
                    }
                }
            }
        }
    }

    /// One handle. The row opens the app it names; a platform Haven cannot open
    /// still shows, because it is still how you reach them.
    private func reachRow(_ handle: Person.Handle) -> some View {
        let label = PersonReach.label(handle.platform)
        let display = PersonReach.display(platform: handle.platform, value: handle.value)
        let url = PersonReach.url(platform: handle.platform, value: handle.value)
        var open: (() -> Void)?
        if let url { open = { openURL(url) } }
        return HavenRow(
            title: label,
            detail: display,
            accessibilityText: url == nil
                ? "\(label), \(display)"
                : "\(label), \(display), opens \(label)",
            action: open
        ) {
            // The external mark rather than a chevron: a chevron promises a
            // back button that is not coming.
            if url != nil { RowMark.external }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if model.person != nil {
            PrimaryButton(title: model.isSaving ? "Saving..." : "Save note") {
                Task { await model.saveNote() }
            }
            .disabled(!model.canSave)
        }
    }
}

enum PersonMetrics {
    /// Big enough to recognise a face at a glance, small enough that the name
    /// beside it is still the first thing read.
    static let photoDiameter: CGFloat = 64
}

// MARK: - Previews

private let previewPerson = Person(
    _id: "p1",
    name: "Ada Lovelace",
    context: nil,
    headline: "Compiler engineer",
    bio: nil,
    company: "Analytical Engines",
    role: "Engineer",
    city: Person.City(name: "Sai Gon", country: "Vietnam"),
    link: "https://example.com/ada",
    contactHandles: [
        Person.Handle(platform: "instagram", value: "ada.builds"),
        Person.Handle(platform: "phone", value: "+84901234567"),
        // A platform Haven has never heard of, which is a real way to reach
        // somebody and shows as one.
        Person.Handle(platform: "signal", value: "ada.99"),
    ],
    preferredPlatform: "phone"
)

private let sparsePerson = Person(
    _id: "p2",
    name: "Mai Tran",
    context: "Met at the Hanoi meetup.\nBuilds ceramics.",
    headline: nil,
    bio: nil,
    company: nil,
    role: nil,
    city: nil
)

#Preview("A person, everything they have") {
    NavigationStack {
        PersonScreen(model: PersonModel(preview: .ready(previewPerson)))
    }
}

#Preview("A person, a name and a note") {
    NavigationStack {
        PersonScreen(model: PersonModel(preview: .ready(sparsePerson)))
    }
}

#Preview("Unreachable") {
    NavigationStack {
        PersonScreen(model: PersonModel(preview: .unreachable))
    }
}

#Preview("A person, accessibility XXXL") {
    NavigationStack {
        PersonScreen(model: PersonModel(preview: .ready(previewPerson)))
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("A person, Reduce Motion") {
    NavigationStack {
        PersonScreen(model: PersonModel(preview: .ready(previewPerson)))
    }
    .havenReduceMotion()
}
