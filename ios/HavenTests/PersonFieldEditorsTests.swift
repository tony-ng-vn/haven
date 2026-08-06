import ConvexMobile
import Foundation
import Testing
@testable import Haven

// `contactHandles` is rewritten wholesale on every edit -- reordering,
// removing a different handle, or picking a new primary all resend every
// handle still on the person. If `convexArgument` dropped platformId, source
// or addedAt for a handle nothing about this edit touched, that edit would
// silently wipe metadata the server (and PersonReach/HandleStaleness) depend
// on -- see I1.
@Suite("What editPerson is sent for one handle")
struct HandleConvexArgumentTests {
    private func string(_ args: [String: ConvexEncodable?], _ key: String) -> String? {
        args[key].flatMap { $0 as? String }
    }

    @Test("a handle decoded with full metadata round-trips all of it")
    func roundTripsMetadata() {
        let handle = Person.Handle(
            platform: "x", value: "mai_makes", platformId: "1477479148", addedAt: 1_700_000_000_000
        )
        let args = handle.convexArgument
        #expect(string(args, "platform") == "x")
        #expect(string(args, "value") == "mai_makes")
        #expect(string(args, "platformId") == "1477479148")
        #expect(string(args, "source") == nil)
        #expect((args["addedAt"] as? Double) == 1_700_000_000_000)
    }

    // A value the user actually changed is a different account -- inheriting
    // the old one's metadata would be wrong, not merely careless. This is the
    // shape `PersonHandlesEditor.add` always builds.
    @Test("a freshly added handle carries no inherited metadata")
    func freshHandleCarriesNothing() {
        let handle = Person.Handle(platform: "instagram", value: "new.handle")
        let args = handle.convexArgument
        #expect(args.count == 2)
        #expect(string(args, "platform") == "instagram")
        #expect(string(args, "value") == "new.handle")
    }

    @Test("only the fields actually present are sent, never an explicit null")
    func partialMetadataOmitsTheRest() {
        let handle = Person.Handle(platform: "linkedin", value: "mai-tran", source: "typed")
        let args = handle.convexArgument
        #expect(args.keys.sorted() == ["platform", "source", "value"])
        #expect(string(args, "source") == "typed")
    }
}

// What `editPerson` answers besides a plain person -- see I5(a).
@Suite("Decoding what editPerson answers")
struct EditPersonOutcomeTests {
    @Test("an ordinary person payload decodes as saved")
    func savedPerson() throws {
        let json = """
            {"_id":"p1","_creationTime":1,"updatedAt":1,"name":"Mai Tran","photoUrl":null}
            """
        let outcome = try JSONDecoder().decode(EditPersonOutcome.self, from: Data(json.utf8))
        guard case .saved(let person) = outcome else {
            Issue.record("expected .saved")
            return
        }
        #expect(person.name == "Mai Tran")
    }

    @Test("a handle_taken payload decodes the conflicting owner")
    func handleTaken() throws {
        let json = """
            {"status":"handle_taken","personId":"p2","name":"Ada Lovelace"}
            """
        let outcome = try JSONDecoder().decode(EditPersonOutcome.self, from: Data(json.utf8))
        #expect(outcome == .handleTaken(personId: "p2", name: "Ada Lovelace"))
    }

    // A person can never actually carry a "status" field, but the check has
    // to be narrow on its own terms rather than assume that -- this pins it.
    @Test("a person payload is never mistaken for a conflict")
    func personNeverMistakenForConflict() throws {
        let json = """
            {"_id":"p1","_creationTime":1,"updatedAt":1,"name":"Status","photoUrl":null}
            """
        let outcome = try JSONDecoder().decode(EditPersonOutcome.self, from: Data(json.utf8))
        guard case .saved(let person) = outcome else {
            Issue.record("expected .saved")
            return
        }
        #expect(person.name == "Status")
    }
}
