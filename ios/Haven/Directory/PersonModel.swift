import Combine
import ConvexMobile
import SwiftUI

/// One saved person as `people:getPerson` returns them.
///
/// A subset of what the query sends: this screen shows who they are and what
/// you wrote about them, and an unknown key is ignored.
struct Person: Decodable, Equatable {
    let _id: String
    let name: String
    var context: String?
    var headline: String?
    var bio: String?
    var company: String?
    var role: String?
    var city: City?

    struct City: Decodable, Equatable {
        let name: String
    }

    /// The line under the name: what they do, then where they are.
    var detail: String? {
        let work = [role, company].compactMap { $0 }.filter { !$0.isEmpty }
        let parts = work.isEmpty ? [] : [work.joined(separator: ", ")]
        let all = parts + [city?.name].compactMap { $0 }
        return all.isEmpty ? nil : all.joined(separator: " | ")
    }
}

enum PersonLoad: Equatable {
    case loading
    case ready(Person)
    /// Either the read never came back, or the person is gone. Both end the
    /// same way for someone looking at the screen.
    case unreachable
}

/// One person, and the note you keep about them.
///
/// The note is the whole reason this screen exists. Everything else here is
/// theirs and arrives from the card; the note is the part only you can write,
/// and the part search and ask have nothing to work with until you do.
@MainActor
final class PersonModel: ObservableObject {
    @Published private(set) var load: PersonLoad = .loading
    @Published private(set) var isSaving = false
    @Published var failure: String?
    /// What is in the editor right now. Seeded from the stored note the first
    /// time one arrives, and left alone after that: a live subscription that
    /// overwrote the field would delete what someone is in the middle of
    /// typing.
    @Published var draft = ""

    private let personId: String
    private let isLive: Bool
    private var seeded = false
    private var cancellable: AnyCancellable?

    init(personId: String) {
        self.personId = personId
        isLive = true
        subscribe()
    }

    /// A loaded person that never opens a socket, for previews and tests.
    init(preview load: PersonLoad, draft: String = "") {
        personId = ""
        isLive = false
        self.load = load
        self.draft = draft
        if case .ready(let person) = load, draft.isEmpty {
            self.draft = person.context ?? ""
            seeded = true
        }
    }

    var person: Person? {
        if case .ready(let person) = load { return person }
        return nil
    }

    /// True when the editor holds something other than what is saved, which is
    /// the only time saving would change anything.
    var isDirty: Bool {
        guard let person else { return false }
        return draft.trimmed != (person.context ?? "").trimmed
    }

    var canSave: Bool { isDirty && !isSaving }

    func retry() {
        load = .loading
        seeded = false
        subscribe()
    }

    /// What `people:editPerson` is sent for a note.
    ///
    /// That mutation leaves an omitted field alone and clears an explicit
    /// null, so an emptied editor has to send null rather than "" -- otherwise
    /// clearing a note would store a blank one, and a blank note is a memory
    /// row of nothing.
    nonisolated static func noteArguments(
        id: String,
        draft: String
    ) -> [String: ConvexEncodable?] {
        let trimmed = draft.trimmed
        return ["id": id, "context": trimmed.isEmpty ? nil : trimmed]
    }

    /// Writes the note, or clears it when the editor is empty.
    func saveNote() async {
        guard canSave else { return }
        isSaving = true
        failure = nil
        defer { isSaving = false }
        guard isLive else { return }
        do {
            let _: Person? = try await convex.mutation(
                "people:editPerson",
                with: Self.noteArguments(id: personId, draft: draft)
            )
        } catch {
            // Said out loud and the draft left alone: a note someone typed is
            // the one thing on this screen that exists nowhere else yet.
            failure = "Haven could not save that note. Your words are still here."
        }
    }

    private func subscribe() {
        guard isLive else { return }
        cancellable = HavenNetwork.subscribe(
            to: "people:getPerson",
            with: ["id": personId],
            yielding: Person?.self
        ) { [weak self] person in
            guard let self else { return }
            guard let person else {
                self.load = .unreachable
                return
            }
            self.load = .ready(person)
            // Only ever seeded once. Later values arrive from this device's own
            // save or another device's edit, and neither is a reason to throw
            // away what is in the editor.
            if !self.seeded {
                self.draft = person.context ?? ""
                self.seeded = true
            }
        } onSilence: { [weak self] in
            guard let self, self.load == .loading else { return }
            self.load = .unreachable
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
