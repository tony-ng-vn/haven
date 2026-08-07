import SwiftUI
import UIKit

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
    @StateObject private var eventModel: PersonEventModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var photo: Image?
    @State private var isEditing = false
    /// Counts notes written, for the commit haptic. A count rather than a
    /// flag, because writing a second note is a second commit.
    @State private var notesSaved = 0

    init(personId: String) {
        _model = StateObject(wrappedValue: PersonModel(personId: personId))
        _eventModel = StateObject(wrappedValue: PersonEventModel(personId: personId))
    }

    init(model: PersonModel, events: [PersonEvent] = []) {
        _model = StateObject(wrappedValue: model)
        _eventModel = StateObject(wrappedValue: PersonEventModel(preview: events))
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
        // Light on commit. The note is the one thing on this screen that only
        // exists because somebody wrote it.
        .sensoryFeedback(.impact(weight: .light), trigger: notesSaved)
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
                if let connection = model.person?.connection {
                    ConnectionChip(connection: connection)
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

            if person.wasConnected {
                // Said once, plainly, where the fields it is about are. A row
                // that stopped following a card and does not say so reads as a
                // person who simply never changes anything.
                Text("This is the last thing their card said. It will not change again.")
                    .havenSecondary()
            }

            reach(person)

            if !eventModel.events.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Events")
                        .havenGroupLabel()
                    ForEach(eventModel.events) { event in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: "calendar")
                                .foregroundStyle(HavenColor.star)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                    .havenBody()
                                    .foregroundStyle(HavenColor.ink)
                                Text(event.startDate.formatted(date: .abbreviated, time: .shortened))
                                    .havenSecondary()
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                        .accessibilityElement(children: .combine)
                    }
                }
            }

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
    ///
    /// A LinkedIn handle old enough to be worth a second look
    /// (`HandleStaleness`) carries a quiet line under the row rather than a
    /// warning on it -- the link is still shown and still opens; the only
    /// thing being said is that it has not been checked in a while.
    private func reachRow(_ handle: Person.Handle) -> some View {
        let label = PersonReach.label(handle.platform)
        let display = PersonReach.display(platform: handle.platform, value: handle.value)
        let url = PersonReach.openURL(
            platform: handle.platform,
            value: handle.value,
            platformId: handle.platformId,
            canOpenAppURL: { UIApplication.shared.canOpenURL($0) }
        )
        var open: (() -> Void)?
        if let url { open = { openURL(url) } }
        let isStale = PersonReach.isLinkedIn(handle.platform) && HandleStaleness.isStale(addedAt: handle.addedAt)
        return VStack(alignment: .leading, spacing: 2) {
            HavenRow(
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
            if isStale {
                Text("Saved a while ago -- still the right link?")
                    .havenSecondary()
                    .padding(.horizontal, 4)
                    .padding(.bottom, 6)
                    .accessibilityLabel("Saved a while ago. Still the right link for \(label)?")
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if model.person != nil {
            PrimaryButton(title: model.isSaving ? "Saving..." : "Save note") {
                Task {
                    await model.saveNote()
                    if model.failure == nil { notesSaved += 1 }
                }
            }
            .disabled(!model.canSave)
        }
    }
}

/// Whether this row follows a live card, said quietly.
///
/// A chip rather than a banner: being connected is a fact about the person, not
/// an event, and the screen's subject is still them. The ended state is the one
/// that has to be legible, because a frozen row and a person who never changes
/// anything look identical otherwise.
private struct ConnectionChip: View {
    let connection: Person.Connection

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: connection.state == .connected ? "link" : "link.badge.plus")
                .font(.system(size: 9, weight: .semibold))
            Text(label)
                .font(.footnote)
        }
        // Muted, not faint: the ended state is the one that has to be read,
        // and it is also the one drawn dimmer. `faint` fails 4.5:1 over the
        // page's dusk end.
        .foregroundStyle(connection.state == .connected ? HavenColor.star : HavenColor.muted)
        .padding(.horizontal, 9)
        .frame(minHeight: 24)
        .background(
            connection.state == .connected
                ? HavenColor.star.opacity(0.14) : HavenColor.fill,
            in: Capsule()
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var label: String {
        connection.state == .connected ? "Connected" : "No longer connected"
    }

    /// The address is worth speaking here and not worth printing: on screen the
    /// chip sits under their name and the reach rows carry the address anyway.
    private var spoken: String {
        "\(label), \(BeaconAddress.display(for: connection.peerUsername))"
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

private var connectedPerson: Person {
    var person = previewPerson
    person.connection = Person.Connection(state: .connected, peerUsername: "adalovelace")
    return person
}

private var formerlyConnectedPerson: Person {
    var person = previewPerson
    person.connection = Person.Connection(state: .ended, peerUsername: "adalovelace")
    return person
}

#Preview("A person on Haven") {
    NavigationStack {
        PersonScreen(model: PersonModel(preview: .ready(connectedPerson)))
    }
}

// The state that has to be legible: everything here is the last thing their
// card said, and nothing about the fields alone says so.
#Preview("A person who left Haven") {
    NavigationStack {
        PersonScreen(model: PersonModel(preview: .ready(formerlyConnectedPerson)))
    }
}

#Preview("A person on Haven, accessibility XXXL") {
    NavigationStack {
        PersonScreen(model: PersonModel(preview: .ready(connectedPerson)))
    }
    .environment(\.dynamicTypeSize, .accessibility3)
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
