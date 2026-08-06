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
    /// Who the typed name might already be, exact or a close typo away.
    /// Debounced -- see `havenSuggestionSection` -- rather than a computed
    /// property re-read on every keystroke, the same reason the contacts
    /// section below does not search on every keystroke either.
    @State private var suggestions: [NameSuggestion] = []
    /// Drives the "in your contacts" section. Built from the same mirror
    /// snapshot this sheet already reads, at the same presentation-time
    /// moment -- see the doc comment on `mirror` above.
    @StateObject private var contactMatch: ContactMatchModel

    init(mirror: DirectoryMirror?, queue: CaptureQueue, onSaved: @escaping () -> Void = {}) {
        self.mirror = mirror
        self.queue = queue
        self.onSaved = onSaved
        // The same queue this sheet's own draft writes to, not
        // ContactMatchModel's `.forApp()` default -- a preview or a test
        // that points `queue` at an isolated directory must not have a
        // contact import quietly land in the real App Group container
        // instead.
        _contactMatch = StateObject(wrappedValue: ContactMatchModel(queue: queue, mirror: mirror))
    }

    private var alreadyKnown: MirrorPerson? { draft.alreadyKnown(in: mirror) }

    /// What drives the contacts section: the name field first, since it is
    /// always in play, and the handle field when it is a phone number being
    /// typed -- "a name or phone number," per the product spec, and a
    /// platform picked as Instagram or LinkedIn has no device-contact
    /// equivalent worth searching for.
    private var contactQuery: String {
        let name = draft.name.trimmedLikeJS
        if !name.isEmpty { return name }
        return draft.platform.isPhoneNumber ? draft.handleText.trimmedLikeJS : ""
    }

    var body: some View {
        // One scrolling piece, not HavenScreen's pinned slots. The pinned
        // question and pinned actions exist for onboarding's ceremony -- a
        // question that owns the top of the screen while answers move under
        // it. This sheet is a form, and a form reads as one object: title,
        // fields and buttons travel together, and with the keyboard up the
        // Save button is the end of the form rather than a layer the Note
        // field slides beneath.
        HavenScreen(
            contentAlignment: .top,
            header: { EmptyView() },
            content: {
                VStack(alignment: .leading, spacing: 0) {
                    titleBlock
                    VStack(alignment: .leading, spacing: 20) {
                        nameField
                        handleSection
                        // One coherent "who is this?" area: Haven's own
                        // people first, since they are the stronger signal
                        // and the one an attach can act on, then the device
                        // contacts nobody has saved yet.
                        havenSuggestionSection
                        contactMatchSection
                        noteField
                        if didFail {
                            Text("Haven could not save that. Your words are still here.")
                                .havenSecondary()
                                .foregroundStyle(HavenColor.star)
                        }
                    }
                    // A paragraph break, not a line break: the title block
                    // introduces the form, and the first field starting too
                    // close reads as part of the sentence above it.
                    .padding(.top, 28)
                    VStack(spacing: 8) {
                        PrimaryButton(title: "Save", action: save)
                            .disabled(!draft.canSave)
                        GhostButton(title: "Cancel") { dismiss() }
                    }
                    .padding(.top, 28)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            },
            actions: { EmptyView() }
        )
        .havenDismissable()
        .presentationDragIndicator(.visible)
        // Light on commit, per the design tokens. Writing somebody down is a
        // commit; the sheet closing is the receipt, and this is what the
        // receipt feels like.
        .sensoryFeedback(.impact(weight: .light), trigger: saves)
        // One settled name, not one lookup per keystroke: `.task(id:)`
        // cancels the sleep the moment another character lands, so only the
        // name somebody stopped typing on ever reaches the mirror.
        .task(id: SuggestionRefreshKey(draft: draft)) {
            do {
                try await Task.sleep(for: SearchModel.debounce)
            } catch {
                return
            }
            suggestions = alreadyKnown == nil ? (mirror?.nameSuggestions(for: draft.name) ?? []) : []
        }
    }

    /// The title and its one-line introduction, scrolling with the form.
    ///
    /// Six points between them, not QuestionHeader's four: the hint wraps to
    /// two lines here, and a gap tighter than the hint's own line spacing
    /// makes the title read as the hint's first line rather than its heading.
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add someone")
                .havenQuestion()
            Text("Their name, one way to reach them, and the line you want to remember.")
                .havenHint()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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

    /// "Where does this person live today": device contacts that are not
    /// already in Haven, for the name or phone number just typed above.
    ///
    /// Only ever shown once there is something to search for -- an empty
    /// query is not "everyone in your contacts," the same way an empty
    /// search field in `SearchScreen` is not either.
    @ViewBuilder private var contactMatchSection: some View {
        if !contactQuery.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("In your contacts")
                    .havenGroupLabel()
                ContactMatchSection(
                    model: contactMatch, query: contactQuery, onImported: onContactImported
                )
            }
        }
    }

    /// A contact import is the same kind of commit a typed Save is: the
    /// sheet closes and the closing is the receipt, so there is no reason
    /// for this to behave differently just because the tap landed on a
    /// device-contact row instead of the Save button.
    private func onContactImported() {
        saves += 1
        onSaved()
        dismiss()
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

    /// "Do I already know this person?" -- the informational exact-handle
    /// answer when there is one, otherwise every exact or close name match
    /// the mirror can offer, each with whatever the mirror actually stores
    /// to tell two same-named people apart.
    @ViewBuilder private var havenSuggestionSection: some View {
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
        } else if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Same person?")
                    .havenGroupLabel()
                // Offered, never applied: a name is not a unique key, and two
                // people really can share one -- true of an exact match and
                // even more true of a close one.
                ForEach(suggestions) { suggestion in
                    AttachRow(
                        person: suggestion.person,
                        detail: disambiguator(for: suggestion.person),
                        isPicked: attachTo?.id == suggestion.person.id,
                        onTap: {
                            attachTo = attachTo?.id == suggestion.person.id ? nil : suggestion.person
                        }
                    )
                }
            }
        }
    }

    /// What the mirror actually stores beyond a name to tell two people
    /// apart: their handles, formatted the same way `PersonScreen` already
    /// shows them.
    ///
    /// Nothing else -- no note snippet, no company, no photo: `MirrorPerson`
    /// carries none of those (see its own doc comment), and this shows
    /// exactly what exists rather than promising more.
    private func disambiguator(for person: MirrorPerson) -> String? {
        let shown = person.handles.prefix(2).map {
            PersonReach.display(platform: $0.platform, value: $0.value)
        }
        return shown.isEmpty ? nil : shown.joined(separator: " \u{00b7} ")
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

/// Every draft field that changes whether a name suggestion should appear.
/// The note is deliberately absent: typing context must not restart the name
/// debounce, but changing the handle or platform can remove a direct match.
private struct SuggestionRefreshKey: Equatable {
    let name: String
    let platform: AddPersonPlatform
    let handleText: String

    init(draft: AddPersonDraft) {
        name = draft.name
        platform = draft.platform
        handleText = draft.handleText
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
    /// What the mirror can offer to tell two same-named people apart, or nil
    /// when it has nothing but the name -- see `AddPersonSheet.disambiguator`.
    var detail: String?
    let isPicked: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isPicked ? HavenColor.star : HavenColor.faint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(person.name)
                        .havenBody()
                    if let detail {
                        Text(detail)
                            .havenSecondary()
                    }
                }
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
        // One spoken element with a real label, not the default "Mai Tran,
        // button" VoiceOver would otherwise assemble from the visible parts
        // -- the detail line is content a screen reader user needs exactly
        // as much as a sighted one does to tell two "Mai Tran"s apart.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([person.name, detail].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isPicked ? [.isButton, .isSelected] : [.isButton])
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
