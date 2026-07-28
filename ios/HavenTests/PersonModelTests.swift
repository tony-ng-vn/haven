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
