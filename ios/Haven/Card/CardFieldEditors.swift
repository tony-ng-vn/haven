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
        case .photo: return photoStorageId == nil ? nil : "Added"
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

    var body: some View {
        HavenScreen(question: field.title) {
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
        } actions: {
            VStack(spacing: 8) {
                PrimaryButton(title: "Save", isLoading: working, action: commit)
                    .disabled(field == .name && trimmed.isEmpty)
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
    }

    private func commit() {
        guard !working else { return }
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
