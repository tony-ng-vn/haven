import ConvexMobile
import SwiftUI

/// Everything about a saved person that you can change, and the one thing you
/// can undo by doing.
///
/// A screen of its own rather than editable rows on the person: reading who
/// somebody is and rewriting them are different jobs, and mixing them made the
/// tappable handle -- the point of the screen -- one row among six. This is the
/// platform's own shape, and people already know it.
///
/// The note is deliberately not here. It lives on the person, where it is the
/// subject rather than a field, and moving it in would demote the only part of
/// a person that is yours.
struct PersonEditor: View {
    @ObservedObject var model: PersonModel
    /// The photo as the person screen is already drawing it, so the editor
    /// shows the thing being replaced rather than describing it.
    let photo: Image?

    @Environment(\.dismiss) private var dismiss
    @State private var editing: PersonField?
    @State private var confirmingDelete = false
    @State private var confirmingDisconnect = false

    var body: some View {
        HavenScreen(
            question: "Details",
            hint: "All of this is theirs. What you remember stays on their screen.",
            contentAlignment: .top
        ) {
            content
        } actions: {
            GhostButton(title: "Done") { dismiss() }
        }
        .havenDismissable()
        .sheet(item: $editing) { field in
            editor(for: field)
        }
        .alert("Stop following their card?", isPresented: $confirmingDisconnect) {
            Button("Disconnect", role: .destructive) {
                Task { _ = await model.disconnect() }
            }
            Button("Stay connected", role: .cancel) {}
        } message: {
            // Names what goes and what stays, because the difference between
            // this and Delete is the whole reason both exist.
            Text("You keep them and everything you wrote. Their card stops updating here, and the note the two of you wrote together goes.")
        }
        .alert("Delete this person?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                Task {
                    if await model.delete() { dismiss() }
                }
            }
            Button("Keep them", role: .cancel) {}
        } message: {
            // Names what actually goes, because the note is the part nobody
            // else has a copy of.
            Text("Everything you wrote about them goes too. This cannot be undone.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let person = model.person {
            VStack(alignment: .leading, spacing: 0) {
                if let failure = model.failure {
                    Text(failure)
                        .havenSecondary(HavenColor.ember)
                        .padding(.bottom, 8)
                }

                if person.isConnected {
                    // Their card is the source for these, and the server
                    // overwrites this row from it. An edit here would look
                    // like it took and be gone by the next read.
                    Text("Their name, photo, city, company and role come from their card. What you write about them is yours.")
                        .havenSecondary()
                        .padding(.bottom, 14)
                }
                ForEach(PersonField.allCases) { field in
                    row(field, person: person)
                }

                Text("Person")
                    .havenGroupLabel()
                    .padding(.top, 26)
                    .padding(.bottom, 6)
                // Offered only while there is a connection to end. A frozen row
                // has nothing left to disconnect from, and the server would
                // answer "notConnected" to a tap nobody should have been given.
                if person.isConnected {
                    HavenRow(
                        title: "Disconnect",
                        detail: "Keep them, stop following their card",
                        action: { confirmingDisconnect = true }
                    )
                }
                // Warned rather than merely listed, the way account deletion is
                // on My Card: this is a screen people open to fix a typo.
                HavenRow(
                    title: "Delete this person",
                    isDestructive: true,
                    action: { confirmingDelete = true }
                )
            }
        } else {
            ProgressView()
                .tint(HavenColor.faint)
                .frame(maxWidth: .infinity)
                .padding(.top, 32)
        }
    }

    /// A field, filled or not. An empty one says "Add" where a filled one shows
    /// the chevron, so an unfilled field does not read like a prompt.
    private func row(_ field: PersonField, person: Person) -> some View {
        let value = person.value(for: field)
        return HavenRow(
            title: field.title,
            detail: value ?? field.placeholder,
            accessibilityText: value == nil
                ? "\(field.title), empty"
                : "\(field.title), \(value ?? "")",
            action: { editing = field }
        ) {
            if value == nil {
                RowAccessory(text: "Add")
            } else {
                RowMark.chevron
            }
        }
    }

    @ViewBuilder
    private func editor(for field: PersonField) -> some View {
        switch field {
        case .name, .company, .role:
            PersonTextEditor(
                field: field,
                initial: model.person?.value(for: field) ?? ""
            ) { value in
                guard let key = field.storedKey else { return }
                if let value {
                    await model.edit([key: value])
                } else {
                    await model.clear(key)
                }
            }
        case .city:
            CityFieldEditor(initial: model.person?.city?.line ?? "") { city in
                if let city {
                    await model.edit(["city": city.convexArgument])
                } else {
                    await model.clear("city")
                }
            }
        case .handles:
            PersonHandlesEditor(
                handles: model.person?.contactHandles ?? [],
                preferred: model.person?.preferredPlatform
            ) { handles, preferred in
                await model.editHandles(handles, preferred: preferred)
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

// MARK: - Previews

private let editablePerson = Person(
    _id: "p1",
    name: "Ada Lovelace",
    context: "Met at the Hanoi meetup.",
    headline: nil,
    bio: nil,
    company: "Analytical Engines",
    role: nil,
    city: Person.City(name: "Sai Gon", country: "Vietnam"),
    contactHandles: [Person.Handle(platform: "instagram", value: "ada.builds")],
    preferredPlatform: "instagram"
)

#Preview("Details") {
    PersonEditor(model: PersonModel(preview: .ready(editablePerson)), photo: nil)
}

#Preview("Details, a person on Haven") {
    var connected = editablePerson
    connected.connection = Person.Connection(state: .connected, peerUsername: "adalovelace")
    return PersonEditor(model: PersonModel(preview: .ready(connected)), photo: nil)
}

#Preview("Details, accessibility XXXL") {
    PersonEditor(model: PersonModel(preview: .ready(editablePerson)), photo: nil)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Details, Reduce Motion") {
    PersonEditor(model: PersonModel(preview: .ready(editablePerson)), photo: nil)
        .havenReduceMotion()
}
