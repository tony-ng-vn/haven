import SwiftUI

/// Writing somebody down who is not on Haven.
///
/// The fallback floor of Capture, and until scanning arrives the only way a
/// person gets into the directory without another app to share from. Three
/// fields, in the order somebody says them out loud: who, how to reach them,
/// and the line about them that no machine could have written.
///
/// It saves the way the share sheet saves -- to the queue, then closed -- so a
/// person written down in a basement with no signal is still a person written
/// down. The sheet closing is the receipt; there is no queue screen and no
/// badge, because a capture that landed is a row in the directory behind it.
struct AddPersonSheet: View {
    /// The app's last copy of the directory, or nil before it has ever synced.
    /// A cache, never the source of truth: the server settles who this is.
    let mirror: DirectoryMirror?
    let queue: CaptureQueue
    /// Called once the capture is on disk, so the directory can ask for a drain
    /// and show the person now rather than at the next launch.
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var draft = AddPersonDraft()
    @State private var attachTo: MirrorPerson?
    @State private var didFail = false
    /// Counts saves, so the haptic fires for a person who landed and never for
    /// state that merely arrived.
    @State private var saves = 0

    private var alreadyKnown: MirrorPerson? { draft.alreadyKnown(in: mirror) }
    private var nameMatches: [MirrorPerson] { draft.nameMatches(in: mirror) }

    var body: some View {
        HavenScreen(
            question: "Add someone",
            hint: "Their name, one way to reach them, and the line you want to remember.",
            contentAlignment: .top
        ) {
            VStack(alignment: .leading, spacing: 20) {
                nameField
                handleSection
                noteField
                attachSection
                if didFail {
                    Text("Haven could not save that. Your words are still here.")
                        .havenSecondary()
                        .foregroundStyle(HavenColor.star)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } actions: {
            VStack(spacing: 8) {
                PrimaryButton(title: "Save", action: save)
                    .disabled(!draft.canSave)
                GhostButton(title: "Cancel") { dismiss() }
            }
        }
        .havenDismissable()
        .presentationDragIndicator(.visible)
        // Light on commit, per the design tokens. Writing somebody down is a
        // commit; the sheet closing is the receipt, and this is what the
        // receipt feels like.
        .sensoryFeedback(.impact(weight: .light), trigger: saves)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .havenGroupLabel()
            HavenField(
                label: "Their name",
                placeholder: "Who is this?",
                text: $draft.name,
                contentType: .name,
                capitalization: .words,
                submitLabel: .next,
                autofocus: true
            )
        }
    }

    /// The platform and the handle together, because neither means anything
    /// without the other: "mai.makes" is not an identity until it says where.
    private var handleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How you reach them")
                .havenGroupLabel()
            PlatformPicker(platform: $draft.platform)
            HavenField(
                label: "Their \(draft.platform.label)",
                placeholder: draft.platform.placeholder,
                text: $draft.handleText,
                contentType: draft.platform.isPhoneNumber ? .telephoneNumber : nil,
                keyboard: draft.platform.isPhoneNumber ? .phonePad : .URL,
                capitalization: .never,
                submitLabel: .next
            )
            // What will actually be stored, as it is typed. A pasted URL
            // reducing to a handle in front of somebody is what stops the save
            // being a surprise.
            if let handle = draft.handle {
                Text(draft.platform.display(handle))
                    .havenSecondary()
            }
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Note")
                .havenGroupLabel()
            // Required here, unlike in a share: somebody sat down to write this
            // person out, and a row with no line about them is one search can
            // never hand back by memory.
            HavenField(
                label: "What you want to remember",
                placeholder: "How you met, what you talked about",
                text: $draft.note,
                submitLabel: .done,
                onSubmit: save
            )
        }
    }

    @ViewBuilder private var attachSection: some View {
        if let alreadyKnown {
            // Not a warning. The server files the note against whoever holds
            // this account, which is the right outcome and worth saying before
            // Save rather than after.
            Label(
                "Already saved as \(alreadyKnown.name). Your note will be added to them.",
                systemImage: "checkmark.circle"
            )
            .havenSecondary()
            .labelStyle(.titleAndIcon)
        } else if !nameMatches.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Same person?")
                    .havenGroupLabel()
                // Offered, never applied: a name is not a unique key, and two
                // people really can share one.
                ForEach(nameMatches) { person in
                    AttachRow(
                        person: person,
                        isPicked: attachTo?.id == person.id,
                        onTap: { attachTo = attachTo?.id == person.id ? nil : person }
                    )
                }
            }
        }
    }

    private func save() {
        guard let capture = draft.capture(attachTo: attachTo) else { return }
        // A failed write is the one thing somebody cannot fix from here and
        // must not be told a lie about, so the sheet stays open on it.
        guard (try? queue.enqueue(capture)) != nil else {
            didFail = true
            return
        }
        saves += 1
        onSaved()
        dismiss()
    }
}

// MARK: - Pieces

/// Which platform this handle is on.
///
/// A menu rather than a row of chips: six platforms do not fit on one line at
/// an accessibility text size, and a wrapped grid of them would be the loudest
/// thing on a screen whose subject is the person.
private struct PlatformPicker: View {
    @Binding var platform: AddPersonPlatform

    var body: some View {
        Menu {
            Picker("Platform", selection: $platform) {
                ForEach(AddPersonPlatform.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(platform.label)
                    .font(.footnote)
                    .foregroundStyle(HavenColor.ink)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(HavenColor.muted)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background(HavenColor.fill, in: Capsule())
            .overlay(Capsule().strokeBorder(HavenColor.hairline))
        }
        .accessibilityLabel("Platform")
        .accessibilityValue(platform.label)
        .accessibilityHint("Pick where you reach them")
    }
}

/// One person the typed name might already be.
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
            .frame(minHeight: 44)
            .background(
                isPicked ? HavenColor.fill : HavenColor.rowHighlight,
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isPicked ? [.isSelected] : [])
    }
}

// MARK: - Previews

private let previewQueue = CaptureQueue(
    directory: URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("haven-add-preview")
)

private let previewMirror = DirectoryMirror(
    refreshedAt: Date(timeIntervalSince1970: 0),
    people: [
        MirrorPerson(
            id: "p1",
            name: "Mai Tran",
            handles: [MirrorHandle(platform: "instagram", value: "mai.makes")]
        ),
        MirrorPerson(id: "p2", name: "Ada Lovelace", handles: []),
    ]
)

#Preview("Add someone") {
    AddPersonSheet(mirror: previewMirror, queue: previewQueue)
}

#Preview("Add someone, accessibility XXXL") {
    AddPersonSheet(mirror: previewMirror, queue: previewQueue)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Add someone, Reduce Motion") {
    AddPersonSheet(mirror: previewMirror, queue: previewQueue)
        .havenReduceMotion()
}
