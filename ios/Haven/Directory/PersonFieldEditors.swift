import ConvexMobile
import SwiftUI

/// One field of a saved person, edited on its own.
///
/// The same shape My Card uses for the same reason: somebody fixing a typo in
/// a company name should not have to walk through a form to reach it. The
/// fields are not the card's, though -- a person you saved has no username and
/// owns no star, and the copy is about them rather than about you.
enum PersonField: String, CaseIterable, Identifiable {
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
        case .handles: return "Ways to reach them"
        case .company: return "Company"
        case .role: return "Role"
        }
    }

    /// What the row shows when the field is empty. It says what would go there,
    /// and sells nothing.
    var placeholder: String {
        switch self {
        case .name: return "Their name"
        case .photo: return "None yet"
        case .city: return "Where they are based"
        case .handles: return "None yet"
        case .company: return "Where they work"
        case .role: return "What they do"
        }
    }

    /// How much the server will store, and what it is called when it says so.
    ///
    /// The caps are `convex/fieldCaps.ts`, mirrored in `HavenFieldCaps`. They
    /// are enforced here rather than left to the server because the server
    /// throws, and a throw arrives as "check your connection" -- which is a lie
    /// about a problem sitting in front of somebody.
    var cap: (label: String, max: Int)? {
        switch self {
        case .name: return ("a name", HavenFieldCaps.name)
        case .company: return ("a company", HavenFieldCaps.line)
        case .role: return ("a role", HavenFieldCaps.line)
        case .photo, .city, .handles: return nil
        }
    }

    /// The `editPerson` field name, for the three fields that are just words.
    var storedKey: String? {
        switch self {
        case .name: return "name"
        case .company: return "company"
        case .role: return "role"
        case .photo, .city, .handles: return nil
        }
    }
}

extension Person {
    /// What the row for this field reads, or nil when there is nothing in it.
    func value(for field: PersonField) -> String? {
        switch field {
        case .name: return name.isEmpty ? nil : name
        case .photo: return photoUrl == nil ? nil : "Added"
        case .city: return city?.line
        case .handles:
            let handles = contactHandles ?? []
            guard !handles.isEmpty else { return nil }
            return handles.count == 1
                ? PersonReach.display(platform: handles[0].platform, value: handles[0].value)
                : "\(handles.count) ways"
        case .company: return company.flatMap { $0.isEmpty ? nil : $0 }
        case .role: return role.flatMap { $0.isEmpty ? nil : $0 }
        }
    }
}

/// The editor for a field that is just words: name, company, role.
///
/// One sheet for three fields rather than three nearly identical ones. They
/// differ in their title and their key and in nothing else.
struct PersonTextEditor: View {
    let field: PersonField
    let initial: String
    /// Nil clears the field. Name has no clear, because a person with no name
    /// is a row nobody could ever pick out of a list.
    let save: (String?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var working = false

    init(field: PersonField, initial: String, save: @escaping (String?) async -> Void) {
        self.field = field
        self.initial = initial
        self.save = save
        _text = State(initialValue: initial)
    }

    private var trimmed: String { text.trimmed }

    /// What is wrong with what is typed, or nil while nothing is.
    private var complaint: String? {
        guard let cap = field.cap, !HavenFieldCaps.fits(trimmed, within: cap.max) else {
            return nil
        }
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

/// Every way to reach one person, with one of them marked primary.
///
/// The card's editor next door does the same job over a closed list of four
/// platforms. This one is open: a person you saved can carry a handle on
/// anything, and a platform Haven does not know is kept and shown rather than
/// refused.
struct PersonHandlesEditor: View {
    let handles: [Person.Handle]
    let preferred: String?
    let save: ([Person.Handle], String?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var adding: AddingPlatform?
    @State private var working = false

    /// The offerable platforms with no handle yet. One per platform, the rule
    /// the server enforces, because `preferredPlatform` points at a platform
    /// rather than at a row and two would make that pointer ambiguous.
    private var available: [String] {
        let taken = Set(handles.map { $0.platform.trimmedLikeJS.lowercased() })
        return PersonReach.offerable.filter { !taken.contains($0) }
    }

    var body: some View {
        HavenScreen(
            question: PersonField.handles.title,
            hint: "The one marked Primary is the one Haven leads with.",
            contentAlignment: .top
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(handles) { handle in
                    HavenRow(
                        title: PersonReach.display(platform: handle.platform, value: handle.value),
                        detail: isPreferred(handle) ? "Primary" : nil,
                        accessibilityText: spoken(handle)
                    ) {
                        makePrimary(handle)
                    } leading: {
                        EmptyView()
                    } trailing: {
                        Button {
                            remove(handle)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(HavenColor.faint)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressScaleStyle())
                        .accessibilityLabel(
                            "Remove \(PersonReach.display(platform: handle.platform, value: handle.value))"
                        )
                    }
                }

                if !available.isEmpty {
                    Text("Add another")
                        .havenGroupLabel()
                        .padding(.top, 20)
                        .padding(.bottom, 6)
                    ForEach(available, id: \.self) { platform in
                        HavenRow(title: PersonReach.label(platform)) {
                            adding = AddingPlatform(name: platform)
                        } leading: {
                            EmptyView()
                        } trailing: {
                            RowAccessory(text: "Add")
                        }
                    }
                }
            }
        } actions: {
            GhostButton(title: "Done") { dismiss() }
        }
        .sheet(item: $adding) { platform in
            PersonHandleValueEditor(platform: platform.name) { value in
                await add(platform.name, value: value)
            }
        }
        .disabled(working)
    }

    /// A platform being added, wrapped so it can drive an `item:` sheet.
    private struct AddingPlatform: Identifiable {
        let name: String
        var id: String { name }
    }

    private func isPreferred(_ handle: Person.Handle) -> Bool {
        guard let preferred else { return false }
        return handle.platform.trimmedLikeJS.lowercased()
            == preferred.trimmedLikeJS.lowercased()
    }

    private func spoken(_ handle: Person.Handle) -> String {
        let role = isPreferred(handle) ? "primary" : "make primary"
        let display = PersonReach.display(platform: handle.platform, value: handle.value)
        return "\(PersonReach.label(handle.platform)), \(display), \(role)"
    }

    private func makePrimary(_ handle: Person.Handle) {
        guard !isPreferred(handle) else { return }
        commit(handles, preferred: handle.platform)
    }

    private func remove(_ handle: Person.Handle) {
        let remaining = handles.filter { $0.platform != handle.platform }
        // Removing the primary hands the role to whatever is left, rather than
        // leaving a pointer at a platform this person no longer has.
        let stillPreferred = isPreferred(handle) ? remaining.first?.platform : preferred
        commit(remaining, preferred: stillPreferred)
    }

    private func add(_ platform: String, value: String) async {
        let entry = Person.Handle(platform: platform, value: value)
        // The first one added is the one Haven leads with, because a person
        // with a way to reach them and no primary would lead with nothing.
        await save(handles + [entry], preferred ?? platform)
    }

    private func commit(_ next: [Person.Handle], preferred nextPreferred: String?) {
        working = true
        Task {
            await save(next, nextPreferred)
            working = false
        }
    }
}

/// Typing one handle on one platform.
private struct PersonHandleValueEditor: View {
    let platform: String
    let save: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var working = false

    private var parsed: String? { PersonReach.parse(platform: platform, from: text) }

    var body: some View {
        HavenScreen(
            question: PersonReach.label(platform),
            hint: PersonReach.isPhoneNumber(platform)
                ? "Only you see this."
                : "Paste a link or type the handle."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HavenField(
                    label: PersonReach.label(platform),
                    placeholder: PersonReach.placeholder(platform),
                    text: $text,
                    contentType: PersonReach.isPhoneNumber(platform) ? .telephoneNumber : nil,
                    keyboard: PersonReach.isPhoneNumber(platform) ? .phonePad : .URL,
                    capitalization: .never,
                    submitLabel: .done,
                    autofocus: true,
                    onSubmit: commit
                )
                // What will actually be stored, as it is typed. A pasted URL
                // reducing to a handle in front of somebody is what stops the
                // save being a surprise.
                if let parsed {
                    Text(PersonReach.display(platform: platform, value: parsed))
                        .havenSecondary()
                }
            }
        } actions: {
            PrimaryButton(title: "Save", isLoading: working, action: commit)
                .disabled(parsed == nil)
        }
    }

    private func commit() {
        guard let parsed, !working else { return }
        working = true
        Task {
            await save(parsed)
            dismiss()
        }
    }
}

extension Person.Handle {
    /// What `editPerson` is sent for one handle.
    var convexArgument: [String: ConvexEncodable?] {
        ["platform": platform, "value": value]
    }
}
