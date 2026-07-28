import Foundation
import ConvexMobile
import Testing

@testable import Haven

private func person(context: String?) -> Person {
    Person(
        _id: "p1",
        name: "Ada Lovelace",
        context: context,
        headline: nil,
        bio: nil,
        company: nil,
        role: nil,
        city: nil
    )
}

/// Reads a string out of the argument dictionary, which holds an existential
/// and so cannot simply be compared.
private func string(_ args: [String: ConvexEncodable?], _ key: String) -> String? {
    guard let value = args[key] else { return nil }
    return value as? String
}

@Suite("What a person shows")
struct PersonFieldTests {
    // The choice somebody made about how to reach this person is the whole
    // meaning of a preferred platform, so it leads.
    @Test("the preferred way to reach them comes first")
    func preferredLeads() {
        let person = Person(
            _id: "p1",
            name: "Mai Tran",
            contactHandles: [
                Person.Handle(platform: "instagram", value: "mai.makes"),
                Person.Handle(platform: "phone", value: "+84901234567"),
            ],
            preferredPlatform: "phone"
        )
        #expect(person.reachableHandles.map(\.platform) == ["phone", "instagram"])
    }

    @Test("with no preference the stored order stands")
    func noPreference() {
        let person = Person(
            _id: "p1",
            name: "Mai Tran",
            contactHandles: [
                Person.Handle(platform: "instagram", value: "mai.makes"),
                Person.Handle(platform: "phone", value: "+84901234567"),
            ]
        )
        #expect(person.reachableHandles.map(\.platform) == ["instagram", "phone"])
    }

    // A row saved by an early screenshot capture carries the single legacy
    // pair and no contactHandles. Showing nothing would say Haven has no way
    // to reach somebody it plainly does.
    @Test("a person written before contactHandles still shows their one handle")
    func legacyHandle() {
        let person = Person(
            _id: "p1",
            name: "Mai Tran",
            platform: "instagram",
            handle: "mai.makes"
        )
        #expect(person.reachableHandles == [Person.Handle(platform: "instagram", value: "mai.makes")])
    }

    @Test("a person with nothing to reach has nothing to show")
    func noHandles() {
        #expect(Person(_id: "p1", name: "Mai Tran").reachableHandles.isEmpty)
    }

    // A shared profile stores the handle and the URL it came from. Listing
    // both would be one way to reach somebody, twice, worded differently.
    @Test("a link that is already one of the handles is not repeated")
    func linkFoldedIntoHandles() {
        let person = Person(
            _id: "p1",
            name: "Mai Tran",
            link: "https://instagram.com/Mai.Makes",
            contactHandles: [Person.Handle(platform: "instagram", value: "mai.makes")]
        )
        #expect(person.standaloneLink == nil)
    }

    @Test("a link that points somewhere else is shown")
    func standaloneLink() {
        let person = Person(
            _id: "p1",
            name: "Mai Tran",
            link: "https://maitran.example",
            contactHandles: [Person.Handle(platform: "instagram", value: "mai.makes")]
        )
        #expect(person.standaloneLink?.absoluteString == "https://maitran.example")
    }

    @Test("the line under the name reads work then place")
    func detailLine() {
        let person = Person(
            _id: "p1",
            name: "Mai Tran",
            company: "Haven",
            role: "Founder",
            city: Person.City(name: "Da Nang", country: "Vietnam")
        )
        #expect(person.detail == "Founder, Haven | Da Nang, Vietnam")
        #expect(Person(_id: "p1", name: "Mai Tran").detail == nil)
    }

    // An empty field says so out loud, because the row shows a placeholder and
    // a screen reader would otherwise hear the placeholder as the value.
    @Test("an edit row reads the value, or nothing")
    func editRowValues() {
        let person = Person(
            _id: "p1",
            name: "Mai Tran",
            company: "Haven",
            city: Person.City(name: "Da Nang"),
            contactHandles: [Person.Handle(platform: "instagram", value: "mai.makes")]
        )
        #expect(person.value(for: .name) == "Mai Tran")
        #expect(person.value(for: .company) == "Haven")
        #expect(person.value(for: .role) == nil)
        #expect(person.value(for: .city) == "Da Nang")
        #expect(person.value(for: .handles) == "instagram.com/mai.makes")
        #expect(person.value(for: .photo) == nil)
    }

    @Test("more than one handle is counted rather than listed")
    func manyHandles() {
        let person = Person(
            _id: "p1",
            name: "Mai Tran",
            contactHandles: [
                Person.Handle(platform: "instagram", value: "mai.makes"),
                Person.Handle(platform: "phone", value: "+84901234567"),
            ]
        )
        #expect(person.value(for: .handles) == "2 ways")
    }
}

@Suite("Note arguments")
struct NoteArgumentTests {
    @Test("a written note is sent as text")
    func writtenNote() {
        let args = PersonModel.noteArguments(id: "p1", draft: "  met at the meetup  ")
        #expect(string(args, "id") == "p1")
        #expect(string(args, "context") == "met at the meetup")
    }

    /// editPerson leaves an omitted key alone and clears an explicit null, so
    /// an emptied editor must send the key holding nil. Sending "" instead
    /// would store a blank note, which memories would then split into nothing.
    @Test("an emptied note is sent as an explicit null, not a blank string")
    func clearedNote() {
        let args = PersonModel.noteArguments(id: "p1", draft: "   \n  ")
        #expect(args.keys.contains("context"))
        #expect(string(args, "context") == nil)
    }
}

@MainActor
@Suite("Note editing")
struct NoteEditingTests {
    @Test("the editor opens holding what was already saved")
    func seedsFromStoredNote() {
        let model = PersonModel(preview: .ready(person(context: "met at the meetup")))
        #expect(model.draft == "met at the meetup")
        #expect(model.isDirty == false)
        #expect(model.canSave == false)
    }

    @Test("a person with no note opens on an empty editor")
    func seedsEmpty() {
        let model = PersonModel(preview: .ready(person(context: nil)))
        #expect(model.draft == "")
        #expect(model.canSave == false)
    }

    @Test("saving turns on once the text actually differs")
    func dirtyTracking() {
        let model = PersonModel(preview: .ready(person(context: "met at the meetup")))
        // Whitespace alone is not a change: the note is trimmed on the way to
        // the server, so offering to save it would be offering to save nothing.
        model.draft = "  met at the meetup \n "
        #expect(model.canSave == false)
        model.draft = "met at the meetup\nworks on databases"
        #expect(model.canSave)
    }

    @Test("clearing a note that exists is a change worth saving")
    func clearingIsDirty() {
        let model = PersonModel(preview: .ready(person(context: "met at the meetup")))
        model.draft = ""
        #expect(model.canSave)
    }

    @Test("nothing can be saved before the person has loaded")
    func noSaveBeforeLoad() {
        let model = PersonModel(preview: .loading, draft: "typed too early")
        #expect(model.canSave == false)
    }
}

@Suite("A person who is on Haven")
struct ConnectedPersonTests {
    private func person(_ connection: Person.Connection?) -> Person {
        var person = Person(_id: "p1", name: "Mai Tran")
        person.connection = connection
        return person
    }

    // Three states, and the middle one is the one that has to be legible: a row
    // that stopped following a card looks exactly like a person who never
    // changes anything unless it says so.
    @Test("connected, ended and neither are three different answers")
    func threeStates() {
        let live = person(Person.Connection(state: .connected, peerUsername: "mayachen"))
        #expect(live.isConnected)
        #expect(!live.wasConnected)

        let frozen = person(Person.Connection(state: .ended, peerUsername: "mayachen"))
        #expect(!frozen.isConnected)
        #expect(frozen.wasConnected)

        let ordinary = person(nil)
        #expect(!ordinary.isConnected)
        #expect(!ordinary.wasConnected)
    }

    // The payload the server actually sends, including the null that means
    // "somebody you saved yourself".
    @Test("the connection decodes, and its absence is an ordinary contact")
    func decodesConnection() throws {
        let connected = try JSONDecoder().decode(Person.self, from: Data("""
        {"_id":"p1","_creationTime":1,"updatedAt":1,"name":"Mai Tran","photoUrl":null,
         "connection":{"state":"connected","peerUsername":"mayachen"}}
        """.utf8))
        #expect(connected.connection?.state == .connected)
        #expect(connected.connection?.peerUsername == "mayachen")

        let ended = try JSONDecoder().decode(Person.self, from: Data("""
        {"_id":"p1","_creationTime":1,"updatedAt":1,"name":"Mai Tran","photoUrl":null,
         "connection":{"state":"ended","peerUsername":"mayachen"}}
        """.utf8))
        #expect(ended.connection?.state == .ended)

        let plain = try JSONDecoder().decode(Person.self, from: Data("""
        {"_id":"p1","_creationTime":1,"updatedAt":1,"name":"Mai Tran","photoUrl":null,
         "connection":null}
        """.utf8))
        #expect(plain.connection == nil)
    }

    // The server merges a connected peer's own handles into contactHandles on
    // the detail read, so reach needs no special case -- this pins that it does
    // not grow one.
    @Test("a connected person's handles are read the same way anybody's are")
    func mergedHandlesNeedNoSpecialCase() {
        var person = Person(
            _id: "p1",
            name: "Mai Tran",
            contactHandles: [
                Person.Handle(platform: "instagram", value: "mai.makes"),
                Person.Handle(platform: "x", value: "mai_makes"),
            ],
            preferredPlatform: "x"
        )
        person.connection = Person.Connection(state: .connected, peerUsername: "maitran")
        #expect(person.reachableHandles.map(\.platform) == ["x", "instagram"])
    }
}
