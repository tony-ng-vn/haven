import XCTest
@testable import GraphCore

final class RemovedPeopleOverrideTests: XCTestCase {

    private func person(id: String, identifiers: Set<String>) -> Person {
        Person(
            id: id,
            identifiers: identifiers,
            handleRowIDs: [],
            name: nil,
            thumbnailImageData: nil,
            contactCardIDs: [],
            hasContactCard: false
        )
    }

    func testPersonWhoseIdentifierIsRemovedIsDropped() {
        let people = [
            person(id: "+14155550001", identifiers: ["+14155550001"]),
            person(id: "+14155550002", identifiers: ["+14155550002"]),
        ]

        let kept = RemovedPeopleOverride.apply(people, removedPersonIdentifiers: ["+14155550001"])

        XCTAssertEqual(kept.map(\.id), ["+14155550002"])
    }

    func testMatchOnAnyIdentifierNotJustTheCurrentIDDropsTheWholePerson() {
        // A person whose CURRENT id (min identifier) is not the removed identifier, but who
        // still owns it among their other identifiers: same person the user removed, still
        // dropped. This is the intersection semantics the brief calls for, not exact-id match.
        let people = [
            person(id: "+14155550003", identifiers: ["+14155550003", "old-removed-identifier"]),
        ]

        let kept = RemovedPeopleOverride.apply(people, removedPersonIdentifiers: ["old-removed-identifier"])

        XCTAssertTrue(kept.isEmpty)
    }

    func testEmptyRemovedSetKeepsEveryone() {
        let people = [person(id: "+14155550004", identifiers: ["+14155550004"])]

        let kept = RemovedPeopleOverride.apply(people, removedPersonIdentifiers: [])

        XCTAssertEqual(kept, people)
    }
}
