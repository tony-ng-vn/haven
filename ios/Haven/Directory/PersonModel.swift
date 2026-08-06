import Combine
import ConvexMobile
import SwiftUI

/// One saved person as `people:getPerson` returns them.
///
/// Everything the query sends that this screen has a use for. It used to be a
/// good deal less: the photo, the handles, the preferred platform and the link
/// were all being sent and dropped on the floor, which is why the screen could
/// show you who somebody was and never how to reach them.
struct Person: Decodable, Equatable {
    let _id: String
    let name: String
    var context: String?
    var headline: String?
    var bio: String?
    var company: String?
    var role: String?
    var city: City?
    var link: String?
    /// Resolved server-side, because a storage id is not something a client can
    /// fetch. Null for a person with no photo, which is most of them.
    var photoUrl: String?
    var contactHandles: [Handle]?
    var preferredPlatform: String?
    /// The single platform and handle a person written before `contactHandles`
    /// existed carries. Read only to be shown; nothing here writes them.
    var platform: String?
    var handle: String?
    /// Whether this row follows a live Haven card, and whose.
    ///
    /// Null for an ordinary contact somebody saved by hand or off a share.
    /// The server derives it from the row alone, so a list read costs no extra
    /// lookups; `havenContactUserId` is deliberately not on the payload,
    /// because this answers every question a client has about it.
    var connection: Connection?

    /// Mirrors `connectionValidator` in `convex/people.ts`.
    struct Connection: Decodable, Equatable {
        let state: State
        /// Their Haven address. Live on this read; a snapshot on list reads.
        let peerUsername: String

        enum State: String, Decodable, Equatable {
            /// A live connection: their card's fields merge into this row on
            /// every read, and changing their job changes what you see.
            case connected
            /// It was a connection and is not any more, because they deleted
            /// their account or one of you disconnected. Everything here is
            /// the last thing their card said, and it will not change again.
            case ended
        }
    }

    var isConnected: Bool { connection?.state == .connected }
    var wasConnected: Bool { connection?.state == .ended }

    struct City: Decodable, Equatable {
        let name: String
        var admin: String?
        var country: String?

        /// The city as one line. A blank part is dropped rather than shown as a
        /// stray comma -- MapKit hands back an empty admin area for countries
        /// that have no states.
        var line: String {
            [name, admin, country]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }
    }

    /// One way to reach this person. `platform` is a plain string because a
    /// saved person can carry a handle on a platform Haven has never heard of.
    struct Handle: Decodable, Equatable, Identifiable {
        let platform: String
        let value: String
        /// The platform's own numeric id, when the server has resolved one --
        /// Instagram at save time, X shortly after. See
        /// `PersonReach.openURL` for what having one changes about where a
        /// tap on this row goes.
        let platformId: String?
        /// How this handle was captured -- "typed", "imported", "proven" or
        /// "guessed". See `handleSourceValidator` in `convex/peopleFields.ts`.
        let source: String?
        /// Milliseconds since epoch (`Date.now()` on the server): when this
        /// handle was first added, or nil for a row saved before this field
        /// existed. See `HandleStaleness`.
        let addedAt: Double?

        /// One handle per platform is the rule the server enforces, so the
        /// platform identifies the row.
        var id: String { platform }

        // Written out rather than the synthesized memberwise init: a `let`
        // property with a default value is dropped from that init entirely,
        // which would make platformId/source/addedAt impossible to pass at
        // all. The existing preview and test call sites that only ever set
        // platform/value keep compiling unchanged.
        init(
            platform: String, value: String,
            platformId: String? = nil, source: String? = nil, addedAt: Double? = nil
        ) {
            self.platform = platform
            self.value = value
            self.platformId = platformId
            self.source = source
            self.addedAt = addedAt
        }
    }

    /// The line under the name: what they do, then where they are.
    var detail: String? {
        let work = [role, company].compactMap { $0 }.filter { !$0.isEmpty }
        let parts = work.isEmpty ? [] : [work.joined(separator: ", ")]
        let all = parts + [city?.line].compactMap { $0 }
        return all.isEmpty ? nil : all.joined(separator: " | ")
    }

    /// Every way to reach them, with the one they chose first.
    ///
    /// The preferred platform leads, because that is what choosing it meant. A
    /// person written before `contactHandles` existed falls back to the single
    /// legacy pair, so a row saved by an early screenshot capture still says
    /// how to reach them rather than nothing at all.
    var reachableHandles: [Handle] {
        let handles = contactHandles ?? []
        guard handles.isEmpty else {
            guard let preferredPlatform else { return handles }
            return handles.filter { $0.platform == preferredPlatform }
                + handles.filter { $0.platform != preferredPlatform }
        }
        guard let platform, let handle, !platform.isEmpty, !handle.isEmpty else {
            return []
        }
        return [Handle(platform: platform, value: handle)]
    }

    /// The photo, ready to hand to a loader. Nil covers both "no photo" and a
    /// url that does not parse, because the screen shows the same thing either
    /// way.
    var photoURL: URL? {
        photoUrl.flatMap(URL.init(string:))
    }

    /// Their own page, when a capture recorded one and it is openable.
    var linkURL: URL? {
        guard let link, !link.trimmedLikeJS.isEmpty else { return nil }
        return URL(string: link)
    }

    /// The link, but only when it is not one of the handles already on screen.
    ///
    /// A profile shared into Haven stores both: the handle it dedups on and the
    /// URL it came from. Showing both would be one way to reach somebody listed
    /// twice, differently worded, with the second one adding nothing. Folded
    /// the way the server folds a handle, so "@Mai.Makes" and "mai.makes" are
    /// recognised as the same account.
    var standaloneLink: URL? {
        guard let linkURL, let link else { return nil }
        guard let parsed = ProfileURL.parse(link) else { return linkURL }
        let covered = reachableHandles.contains { handle in
            handle.platform.trimmedLikeJS.lowercased() == parsed.platform.rawValue
                && MirrorHandle.valueKey(handle.value) == MirrorHandle.valueKey(parsed.handle)
        }
        return covered ? nil : linkURL
    }
}

/// What `profiles:disconnect` answers.
struct DisconnectOutcome: Decodable, Equatable {
    let status: String
}

/// What `editPerson` answers: the updated person on an ordinary edit, or
/// "handle_taken" when a `contactHandles` edit named an account that already,
/// provably, belongs to somebody else on this list.
///
/// A person payload carries no `status` key at all, so the check below is
/// narrow and only ever matches the one other shape this mutation can return.
enum EditPersonOutcome: Decodable, Equatable {
    case saved(Person)
    case handleTaken(personId: String, name: String)

    private enum CodingKeys: String, CodingKey {
        case status
    }

    private struct HandleTaken: Decodable, Equatable {
        let personId: String
        let name: String
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
            let status = try? container.decode(String.self, forKey: .status),
            status == "handle_taken"
        {
            let taken = try HandleTaken(from: decoder)
            self = .handleTaken(personId: taken.personId, name: taken.name)
            return
        }
        self = .saved(try Person(from: decoder))
    }
}

/// What the handles editor does with an `editPerson` result: applied, or
/// refused with the name of whoever already holds the handle -- shown inline,
/// with the form left open to try something else.
enum HandleEditOutcome: Equatable {
    case saved
    case handleTaken(name: String)
    case failed
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
/// theirs and arrives from a card or a capture; the note is the part only you
/// can write, and the part search and ask have nothing to work with until you
/// do.
///
/// One model for the whole screen rather than one per field: every edit is the
/// same partial update against the same row, and splitting them would mean six
/// subscriptions to one document.
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
    /// True once this person has been deleted, so the screen showing them can
    /// leave rather than sit on a row that no longer exists.
    @Published private(set) var isDeleted = false

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
    ///
    /// Bounded like every other write in this file: `defer { isSaving = false }`
    /// only fires once this function's own scope exits, and the client
    /// reconnects rather than failing, so an unbounded call with no network
    /// would suspend here forever -- Save stuck disabled and the note trapped
    /// in an editor nobody could dismiss without losing it.
    func saveNote() async {
        guard canSave else { return }
        isSaving = true
        failure = nil
        guard isLive else {
            isSaving = false
            return
        }
        let arguments = Self.noteArguments(id: personId, draft: draft)
        let work = Task { () throws -> Bool in
            let _: Person? = try await convex.mutation("people:editPerson", with: arguments)
            return true
        }
        let saved = await work.value(within: .seconds(HavenNetwork.deadline)) ?? false
        isSaving = false
        guard saved else {
            // Said out loud and the draft left alone: a note someone typed is
            // the one thing on this screen that exists nowhere else yet. A
            // timeout lands here too, the same way a thrown error always did.
            failure = "Haven could not save that note. Your words are still here."
            return
        }
    }

    // MARK: - Editing

    /// Changes some of this person's fields and leaves the rest alone.
    ///
    /// A dictionary rather than a whole person, because `editPerson` is a
    /// partial contract: an omitted key is untouched and an explicit null
    /// clears the field. Sending a whole person would mean deciding, for every
    /// empty field, whether "nothing here" meant "leave it" or "remove it", and
    /// getting that backwards erases somebody's work in silence.
    func edit(_ fields: [String: ConvexEncodable?]) async {
        var arguments = fields
        arguments["id"] = personId
        await write { try await convex.mutation("people:editPerson", with: arguments) }
    }

    /// Removes a field. Convex tells an absent key from an explicit null, and
    /// only the second one means "take this away".
    func clear(_ field: String) async {
        await edit([field: nil as String?])
    }

    /// Saves a full replacement of this person's contact handles, and says
    /// whether it actually took.
    ///
    /// Its own method rather than a call through `edit(_:)`: `editPerson` can
    /// answer "handle_taken" for this one field alone, and only the handles
    /// editor -- not the generic failure banner every other field on this
    /// screen shares -- knows how to say that in a way that leaves the form
    /// open to try something else, rather than reading as a connection
    /// problem.
    func editHandles(_ handles: [Person.Handle], preferred: String?) async -> HandleEditOutcome {
        guard !isSaving, isLive else { return .failed }
        isSaving = true
        failure = nil
        let arguments: [String: ConvexEncodable?] = [
            "id": personId,
            "contactHandles": handles.map { $0.convexArgument } as [ConvexEncodable?],
            "preferredPlatform": preferred,
        ]
        let work = Task { () throws -> EditPersonOutcome in
            try await convex.mutation("people:editPerson", with: arguments)
        }
        let outcome = await work.value(within: .seconds(HavenNetwork.deadline))
        isSaving = false
        switch outcome {
        case .saved(let person):
            // The subscription brings this too, a moment later. Publishing it
            // now is what makes the edit feel like it took rather than like
            // it is being considered.
            load = .ready(person)
            return .saved
        case .handleTaken(_, let name):
            // Nothing was written -- the row stays exactly as it was, and the
            // handles editor is what says why.
            return .handleTaken(name: name)
        case nil:
            failure = "That did not save. Check your connection and try again."
            return .failed
        }
    }

    /// Uploads a photo and attaches it in one go.
    ///
    /// Two round trips that have to read as one action: a blob uploaded and
    /// never attached is an orphan the sweep eventually reclaims, and the
    /// person would have watched a spinner for nothing.
    func setPhoto(_ data: Data) async {
        let id = personId
        await write {
            let url: String = try await convex.mutation("profiles:generateUploadUrl")
            let storageId = try await PhotoUpload.send(data, to: url)
            return try await convex.mutation(
                "people:editPerson",
                with: ["id": id, "photoStorageId": storageId]
            )
        }
    }

    /// Ends the connection without forgetting the person.
    ///
    /// The gentler of the two: both sides keep their own notes, photo and
    /// memory of each other as a frozen snapshot, and the shared note goes
    /// with the edge. Connecting again later thaws this same row rather than
    /// making a second contact for the same human, which is why the row is
    /// kept at all.
    ///
    /// A second tap answers `notConnected` rather than failing, and the screen
    /// treats that as done: it is the same request and it deserves the same
    /// answer.
    func disconnect() async -> Bool {
        guard !isSaving, isLive else { return false }
        isSaving = true
        failure = nil
        let id = personId
        let work = Task { () throws -> String in
            let outcome: DisconnectOutcome = try await convex.mutation(
                "profiles:disconnect", with: ["personId": id]
            )
            return outcome.status
        }
        let status = await work.value(within: .seconds(HavenNetwork.deadline))
        isSaving = false
        guard status != nil else {
            failure = "That did not go through. Check your connection and try again."
            return false
        }
        return true
    }

    /// Forgets this person entirely: their row, their handles, their memories,
    /// and the photo Haven was holding for them.
    ///
    /// Answers whether it went through, so the screen showing them can leave
    /// rather than sit on somebody who is gone. A failure says so and stays put:
    /// being returned to the list with the person still in it, and no
    /// explanation, is the worst of the three outcomes.
    func delete() async -> Bool {
        guard !isSaving, isLive else { return false }
        isSaving = true
        failure = nil
        let id = personId
        let work = Task { () throws -> Bool in
            let _: String? = try await convex.mutation(
                "people:deletePerson",
                with: ["personId": id]
            )
            return true
        }
        let done = await work.value(within: .seconds(HavenNetwork.deadline)) ?? false
        isSaving = false
        if done {
            isDeleted = true
        } else {
            failure = "That did not go through. Check your connection and try again."
        }
        return done
    }

    /// Runs an edit with the bounded wait and the one failure message every
    /// field on this screen shares.
    private func write(_ body: @escaping () async throws -> Person) async {
        guard !isSaving, isLive else { return }
        isSaving = true
        failure = nil
        let work = Task { try await body() }
        let saved = await work.value(within: .seconds(HavenNetwork.deadline))
        isSaving = false
        guard let saved else {
            failure = "That did not save. Check your connection and try again."
            return
        }
        // The subscription brings this too, a moment later. Publishing it now
        // is what makes an edit feel like it took rather than like it is being
        // considered.
        load = .ready(saved)
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
                // Not after a delete: the read answering null is exactly what a
                // successful delete looks like, and the screen is already
                // leaving on its own.
                if !self.isDeleted { self.load = .unreachable }
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
