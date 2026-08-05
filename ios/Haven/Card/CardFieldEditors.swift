import PhotosUI
import SwiftUI

/// One field of the card, edited on its own.
///
/// Which field, what it is called, and how it is asked for. Editing is per
/// field on purpose: someone who wants to fix a typo in their role should not
/// have to walk back through onboarding to reach it.
enum CardField: String, CaseIterable, Identifiable {
    case name
    case photo
    case city
    case handles
    case company
    case role

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "Name"
        case .photo: return "Photo"
        case .city: return "City"
        case .handles: return "Ways to reach you"
        case .company: return "Company"
        case .role: return "Role"
        }
    }

    /// The star this field owns. Fixed, so an unlit star always points at the
    /// same missing thing.
    var slot: StarSlot {
        switch self {
        case .name: return .name
        case .photo: return .photo
        case .city: return .city
        case .handles: return .primaryContact
        case .company: return .company
        case .role: return .role
        }
    }

    /// What the row shows when the field is empty. Not a sales pitch: it says
    /// what would go there.
    var placeholder: String {
        switch self {
        case .name: return "Your name"
        case .photo: return "None yet"
        case .city: return "Where you are based"
        case .handles: return "None yet"
        case .company: return "Where you work"
        case .role: return "What you do"
        }
    }

    /// The Convex field name, for the plain text fields that share one editor.
    var storedKey: String? {
        switch self {
        case .name: return "name"
        case .company: return "company"
        case .role: return "role"
        case .photo, .city, .handles: return nil
        }
    }
}

extension MyCard {
    /// What the row for this field reads, or nil when there is nothing in it.
    func value(for field: CardField) -> String? {
        switch field {
        case .name: return name.flatMap { $0.isEmpty ? nil : $0 }
        case .photo: return hasPhoto ? "Added" : nil
        case .city: return city?.line
        case .handles:
            guard let handles, !handles.isEmpty else { return nil }
            return handles.count == 1
                ? handles[0].display
                : "\(handles.count) ways"
        case .company: return company.flatMap { $0.isEmpty ? nil : $0 }
        case .role: return role.flatMap { $0.isEmpty ? nil : $0 }
        }
    }
}

/// The editor for a field that is just words: name, company, role.
///
/// One sheet for three fields rather than three nearly identical ones. They
/// differ in their title and their key and in nothing else, and a fourth
/// text field would otherwise mean a fourth copy.
struct TextFieldEditor: View {
    let field: CardField
    let initial: String
    /// Nil clears the field. Name has no clear, because a card with no name has
    /// nothing to show.
    let save: (String?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var working = false

    init(field: CardField, initial: String, save: @escaping (String?) async -> Void) {
        self.field = field
        self.initial = initial
        self.save = save
        _text = State(initialValue: initial)
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The server caps these, and a cap only the server enforces surfaces as
    /// "check your connection" -- see `HavenFieldCaps`.
    private var cap: (label: String, max: Int)? {
        switch field {
        case .name: return ("a name", HavenFieldCaps.name)
        case .company: return ("a company", HavenFieldCaps.line)
        case .role: return ("a role", HavenFieldCaps.line)
        case .photo, .city, .handles: return nil
        }
    }

    private var complaint: String? {
        guard let cap, !HavenFieldCaps.fits(trimmed, within: cap.max) else { return nil }
        return HavenFieldCaps.tooLong(cap.label, max: cap.max)
    }

    var body: some View {
        HavenScreen(question: field.title) {
            VStack(alignment: .leading, spacing: 8) {
                HavenField(
                    label: field.title,
                    placeholder: field.placeholder,
                    text: $text,
                    contentType: field == .name ? .name : nil,
                    capitalization: .words,
                    submitLabel: .done,
                    autofocus: true,
                    onSubmit: commit
                )
                if let complaint {
                    Text(complaint)
                        .havenSecondary(HavenColor.ember)
                }
            }
        } actions: {
            VStack(spacing: 8) {
                PrimaryButton(title: "Save", isLoading: working, action: commit)
                    .disabled(complaint != nil || (field == .name && trimmed.isEmpty))
                if field != .name, !initial.isEmpty {
                    GhostButton(title: "Remove") {
                        Task {
                            working = true
                            await save(nil)
                            dismiss()
                        }
                    }
                }
            }
        }
        .havenDismissable()
    }

    private func commit() {
        guard !working, complaint == nil else { return }
        // Emptying an optional field is removing it, which is a different
        // mutation from saving a blank the server would refuse.
        if field != .name, trimmed.isEmpty {
            Task { working = true; await save(nil); dismiss() }
            return
        }
        guard !trimmed.isEmpty else { return }
        Task { working = true; await save(trimmed); dismiss() }
    }
}

/// The editor for the address the card's code points at.
///
/// Its own editor rather than another `TextFieldEditor`, because this is the
/// one field on the card that can be refused. Every other one is stored as
/// typed; an address is a claim on a name at the root of the site, and somebody
/// else may already hold it. So it has a state the others do not -- taken, with
/// free alternatives -- and it has no Remove: a card with no address has no
/// code and no page.
struct AddressEditor: View {
    /// The address as it stands. Every profile has one: the server mints it
    /// silently when the card is created, so this screen changes an address
    /// rather than asking for a first one.
    let current: String
    /// Answers what the server made of the claim, or nil when the round trip
    /// never came back.
    let claim: (String) async -> HandleClaim?

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var working = false
    /// The alternatives the server offered, once it has refused one.
    @State private var suggestions: [String] = []
    @State private var refused: String?

    init(current: String, claim: @escaping (String) async -> HandleClaim?) {
        self.current = current
        self.claim = claim
        _text = State(initialValue: current)
    }

    private var candidate: String? { HavenHandle.candidate(from: text) }

    private var isUnchanged: Bool { candidate == current }

    var body: some View {
        HavenScreen(
            question: "Your address",
            // Said plainly and once. Changing it is not dangerous, but somebody
            // whose code is already on a business card deserves to know before
            // rather than after.
            hint: "This is the page your card's code opens. Change it and the old address stops working.",
            contentAlignment: .top
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HavenField(
                    label: "Your address",
                    placeholder: "yourname",
                    text: $text,
                    capitalization: .never,
                    submitLabel: .done,
                    autofocus: true,
                    onSubmit: commit
                )
                // What the address will actually be, as it is typed. The host
                // is shown because the address is a page, not a handle.
                Text(preview)
                    .havenSecondary(candidate == nil && !text.isEmpty ? HavenColor.ember : HavenColor.muted)

                if let refused {
                    Text("\(BeaconAddress.display(for: refused)) is taken.")
                        .havenSecondary(HavenColor.ember)
                }
                if !suggestions.isEmpty {
                    Text("Free right now")
                        .havenGroupLabel()
                        .padding(.top, 6)
                    ForEach(suggestions, id: \.self) { suggestion in
                        HavenRow(
                            title: BeaconAddress.display(for: suggestion),
                            action: { text = suggestion }
                        ) {
                            RowAccessory(text: "Use")
                        }
                    }
                }
            }
        } actions: {
            PrimaryButton(title: "Save", isLoading: working, action: commit)
                .disabled(candidate == nil || isUnchanged)
        }
        .havenDismissable()
    }

    /// The line under the field: the page this would be, or the rule it is
    /// breaking, or nothing at all while there is nothing to say.
    private var preview: String {
        if let candidate { return BeaconAddress.display(for: candidate) }
        return text.isEmpty ? BeaconAddress.display(for: current) : HavenHandle.help
    }

    private func commit() {
        guard let candidate, !isUnchanged, !working else { return }
        working = true
        refused = nil
        Task {
            let outcome = await claim(candidate)
            working = false
            guard let outcome else { return }
            guard outcome.isClaimed else {
                // Held open on a refusal, with somewhere to go. Closing here
                // would leave somebody on the old address with no idea why.
                refused = outcome.handle
                suggestions = outcome.suggestions
                return
            }
            dismiss()
        }
    }
}

/// The editor for the photo.
///
/// A sheet like every other field rather than a picker hung straight off the
/// row, for two reasons. A system picker has no way to say "remove", and this
/// was the one field with no way back. And a second sheet-style presentation on
/// the same view as the editor sheet does not open at all: the request is
/// swallowed, and the row reads as dead.
struct PhotoEditor: View {
    /// The photo as the card is drawing it, so the sheet shows the thing being
    /// replaced rather than describing it.
    let photo: Image?
    let choose: (Data) async -> Void
    let remove: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picked: PhotosPickerItem?
    @State private var working = false

    var body: some View {
        HavenScreen(question: CardField.photo.title) {
            preview
        } actions: {
            VStack(spacing: 8) {
                PhotosPicker(selection: $picked, matching: .images) {
                    PrimaryLabel(
                        title: photo == nil ? "Choose a photo" : "Choose a different photo",
                        isLoading: working
                    )
                }
                .buttonStyle(PressScaleStyle())
                .disabled(working)
                if photo != nil {
                    GhostButton(title: "Remove") {
                        Task {
                            working = true
                            await remove()
                            dismiss()
                        }
                    }
                }
            }
        }
        .havenDismissable()
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                working = true
                // Loaded as data rather than an Image: what goes to storage is
                // the file, and re-encoding a SwiftUI Image would lose the
                // original and its orientation.
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await choose(data)
                }
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let photo {
            photo
                .resizable()
                .scaledToFill()
                .frame(width: PhotoEditorMetrics.diameter, height: PhotoEditorMetrics.diameter)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(HavenColor.hairline))
                // The buttons below say what can be done with it; announcing
                // "photo" twice adds nothing.
                .accessibilityHidden(true)
        } else {
            Text(CardField.photo.placeholder)
                .havenSecondary()
        }
    }
}

private enum PhotoEditorMetrics {
    /// Big enough to judge a crop by, which is the only reason to show it here.
    static let diameter: CGFloat = 132
}

/// The editor for the city, which is a picker rather than a field: the card
/// stores a real locality, admin area and country, not whatever was typed.
struct CityFieldEditor: View {
    let initial: String
    let save: (CityInput?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var completer = CityCompleter()
    @State private var text = ""
    @State private var working = false

    var body: some View {
        HavenScreen(
            question: "City",
            hint: "City only. Never your street address.",
            contentAlignment: .top
        ) {
            VStack(alignment: .leading, spacing: 0) {
                HavenField(
                    label: "Your city",
                    placeholder: "Start typing a city",
                    text: $text,
                    capitalization: .words,
                    autofocus: true
                )
                .padding(.bottom, 8)
                .onChange(of: text) { _, value in completer.search(value) }

                ForEach(completer.suggestions) { suggestion in
                    HavenRow(title: suggestion.title, detail: suggestion.subtitle) {
                        choose(suggestion)
                    } leading: {
                        EmptyView()
                    } trailing: {
                        EmptyView()
                    }
                }
            }
        } actions: {
            VStack(spacing: 8) {
                // A city MapKit has never heard of is still where someone
                // lives, so a typed answer is accepted rather than refused.
                PrimaryButton(title: "Use what I typed", isLoading: working) {
                    let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !typed.isEmpty else { return }
                    Task { working = true; await save(CityInput(name: typed)); dismiss() }
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !initial.isEmpty {
                    GhostButton(title: "Remove") {
                        Task { working = true; await save(nil); dismiss() }
                    }
                }
            }
        }
        .havenDismissable()
    }

    private func choose(_ suggestion: CitySuggestion) {
        guard !working else { return }
        working = true
        Task {
            // The completion is two display strings; resolving turns it into
            // the structured city the card stores.
            let resolved = await completer.resolve(suggestion)
            await save(resolved ?? CityInput(name: suggestion.title))
            dismiss()
        }
    }
}

// MARK: - Previews

#Preview("Your address") {
    AddressEditor(current: "mayachen") { _ in
        HandleClaim(status: "claimed", handle: "mayachen", suggestions: [])
    }
}

// What a refusal looks like: the name that is taken, and free alternatives
// built from the person's own name.
#Preview("Your address, taken") {
    AddressEditor(current: "mayachen") { handle in
        HandleClaim(
            status: "taken",
            handle: handle,
            suggestions: ["maya_chen", "maya_chen2", "mayac"]
        )
    }
}

#Preview("Your address, accessibility XXXL") {
    AddressEditor(current: "mayachen") { _ in
        HandleClaim(status: "claimed", handle: "mayachen", suggestions: [])
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Your address, Reduce Motion") {
    AddressEditor(current: "mayachen") { _ in
        HandleClaim(status: "claimed", handle: "mayachen", suggestions: [])
    }
    .havenReduceMotion()
}
