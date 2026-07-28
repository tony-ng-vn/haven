import SwiftUI

/// What the sheet has to show.
enum ShareSheetState {
    case ready(ShareSheetModel, CaptureQueue)
    /// Shared something that is not one person's profile -- a post, a link to
    /// somewhere else.
    case unsupported
    /// No App Group container, so a capture would have nowhere to go.
    case unavailable
}

/// The sheet that opens when somebody shares a profile to Haven.
///
/// Compact on purpose. This is a person's attention borrowed mid-conversation:
/// a name to confirm, one line about them if they have one, done. There is no
/// queue, no count and no confirmation screen -- the sheet closing is the
/// receipt.
struct ShareSheet: View {
    let state: ShareSheetState
    let onFinish: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            NightBackground()
            switch state {
            case .ready(let model, let queue):
                ShareForm(model: model, queue: queue, onFinish: onFinish, onCancel: onCancel)
            case .unsupported:
                DeadEnd(
                    title: "Not a profile",
                    detail:
                        "Share somebody's profile from Instagram, LinkedIn or X, or share a screenshot of one.",
                    onCancel: onCancel
                )
            case .unavailable:
                DeadEnd(
                    title: "Haven cannot save this",
                    detail: "Open Haven once and try again.",
                    onCancel: onCancel
                )
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - The form

private struct ShareForm: View {
    let model: ShareSheetModel
    let queue: CaptureQueue
    let onFinish: () -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var note = ""
    @State private var attachTo: MirrorPerson?
    @State private var query = ""
    @State private var isSearching = false
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    nameField
                    noteField
                    attachSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            PrimaryButton(title: "Save", action: save)
                .disabled(!model.canSave(name: name))
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .task {
            // Once: the prefill is a starting point, and reapplying it would
            // undo what somebody had already typed.
            guard !didLoad else { return }
            didLoad = true
            name = model.namePrefill
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.alreadyKnown == nil ? "Save to Haven" : "Already in Haven")
                    .havenQuestion()
                if let line = model.identityLine {
                    Text(line)
                        .havenSecondary()
                        // The account is the part that is known rather than
                        // guessed, so it is never truncated to a guess.
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 12)
            Button("Cancel", action: onCancel)
                .font(HavenFont.ghostLabel)
                .foregroundStyle(HavenColor.muted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .havenGroupLabel()
            HavenField(
                label: "Name",
                placeholder: "Who is this?",
                text: $name,
                contentType: .name,
                capitalization: .words,
                submitLabel: .done,
                // Focused when there is nothing to confirm, which is every
                // Instagram and X share. Focusing a filled field instead would
                // put a cursor in a name that only needed reading.
                autofocus: model.namePrefill.isEmpty
            )
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Note")
                .havenGroupLabel()
            // The one field no machine can ever fill, asked at the one moment
            // it is still in somebody's head. On iOS it is also the only way a
            // memory gets created at all.
            HavenField(
                label: "Note",
                placeholder: "How you met, what you talked about",
                text: $note,
                submitLabel: .done
            )
        }
    }

    @ViewBuilder private var attachSection: some View {
        if let known = model.alreadyKnown {
            Label(
                "Saved as \(known.name). Your note will be added to them.",
                systemImage: "checkmark.circle"
            )
            .havenSecondary()
            .labelStyle(.titleAndIcon)
        } else if isSearching {
            searchField
        } else if !model.nameMatches.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Same person?")
                    .havenGroupLabel()
                // Offered, never applied: a name is not a unique key, and two
                // people really can share one.
                ForEach(model.nameMatches) { person in
                    AttachRow(
                        person: person,
                        isPicked: attachTo?.id == person.id,
                        onTap: { attachTo = attachTo?.id == person.id ? nil : person }
                    )
                }
                searchToggle("Someone else")
            }
        } else {
            searchToggle("Add to someone I know")
        }
    }

    private func searchToggle(_ title: String) -> some View {
        GhostButton(title: title) { isSearching = true }
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add to someone I know")
                .havenGroupLabel()
            HavenField(
                label: "Search your directory",
                placeholder: "Search by name",
                text: $query,
                capitalization: .words,
                submitLabel: .search,
                autofocus: true
            )
            ForEach(model.search(query)) { person in
                AttachRow(
                    person: person,
                    isPicked: attachTo?.id == person.id,
                    onTap: { attachTo = attachTo?.id == person.id ? nil : person }
                )
            }
        }
    }

    private func save() {
        guard let capture = model.capture(name: name, note: note, attachTo: attachTo) else {
            return
        }
        // A failed write is the one thing the user cannot fix from here and
        // must not be told a lie about, so the sheet stays open on it.
        guard (try? queue.enqueue(capture)) != nil else { return }
        onFinish()
    }
}

// MARK: - Pieces

private struct AttachRow: View {
    let person: MirrorPerson
    let isPicked: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isPicked ? HavenColor.star : HavenColor.faint)
                Text(person.name)
                    .havenBody()
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                isPicked ? HavenColor.fill : HavenColor.rowHighlight,
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isPicked ? [.isSelected] : [])
    }
}

private struct DeadEnd: View {
    let title: String
    let detail: String
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(title).havenQuestion()
            Text(detail)
                .havenSecondary()
                .multilineTextAlignment(.center)
            GhostButton(title: "Close", action: onCancel)
                .padding(.top, 4)
        }
        .padding(28)
    }
}

#Preview("Share sheet, new person") {
    ShareSheet(
        state: .ready(
            ShareSheetModel(
                subject: ShareSubject(sharedURL: "https://instagram.com/mai.makes")!,
                mirror: DirectoryMirror(
                    refreshedAt: Date(timeIntervalSince1970: 0),
                    people: [MirrorPerson(id: "p1", name: "Mai Tran", handles: [])]
                )
            ),
            CaptureQueue(directory: URL(fileURLWithPath: NSTemporaryDirectory()))
        ),
        onFinish: {},
        onCancel: {}
    )
}

#Preview("Share sheet, not a profile") {
    ShareSheet(state: .unsupported, onFinish: {}, onCancel: {})
}
