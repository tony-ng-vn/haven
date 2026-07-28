import SwiftUI

/// One person, and the note you keep about them.
///
/// The note is not a field among fields, it is the screen. Everything above it
/// is theirs and came from a card or a capture; the note is the only part that
/// is yours, and until it exists, searching by what you remember has nothing
/// to search.
struct PersonScreen: View {
    @StateObject private var model: PersonModel

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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.person?.name ?? " ")
                .havenQuestion()
            if let detail = model.person?.detail {
                Text(detail)
                    .havenSecondary()
            }
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
                    .havenSecondary()
                    .foregroundStyle(HavenColor.star)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - Previews

private let previewPerson = Person(
    _id: "p1",
    name: "Ada Lovelace",
    context: nil,
    headline: "Compiler engineer",
    bio: nil,
    company: "Analytical Engines",
    role: "Engineer",
    city: Person.City(name: "Sai Gon")
)

#Preview("Nothing written yet") {
    NavigationStack {
        PersonScreen(model: PersonModel(preview: .ready(previewPerson)))
    }
}

#Preview("With a note") {
    NavigationStack {
        PersonScreen(
            model: PersonModel(
                preview: .ready(
                    Person(
                        _id: "p1",
                        name: "Ada Lovelace",
                        context: "Met at the Founder Inc dinner.\nWorks on an infinite-context database.",
                        headline: "Compiler engineer",
                        bio: nil,
                        company: "Analytical Engines",
                        role: "Engineer",
                        city: Person.City(name: "Sai Gon")
                    )
                )
            )
        )
    }
}

#Preview("Unreachable") {
    NavigationStack {
        PersonScreen(model: PersonModel(preview: .unreachable))
    }
}
