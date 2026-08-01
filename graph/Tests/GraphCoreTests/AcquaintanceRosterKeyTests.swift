import XCTest
@testable import GraphCore

final class AcquaintanceRosterKeyTests: XCTestCase {

    func testCanonicalizeSortsRegardlessOfInputOrder() {
        XCTAssertEqual(AcquaintanceRosterKey.canonicalize(["+15550002", "+15550001"]), ["+15550001", "+15550002"])
        XCTAssertEqual(AcquaintanceRosterKey.canonicalize(["+15550001", "+15550002"]), ["+15550001", "+15550002"])
    }

    func testCanonicalizeDeduplicatesRepeatedIdentifiers() {
        XCTAssertEqual(
            AcquaintanceRosterKey.canonicalize(["+15550001", "+15550001", "+15550002"]),
            ["+15550001", "+15550002"]
        )
    }

    func testCanonicalizeOfASetIsOrderInsensitive() {
        // A Set's own iteration order is unspecified, so this only proves the guarantee if it
        // holds regardless of what Swift's hashing happens to produce this run.
        let fromSet = AcquaintanceRosterKey.canonicalize(Set(["+15550003", "+15550001", "+15550002"]))
        XCTAssertEqual(fromSet, ["+15550001", "+15550002", "+15550003"])
    }

    // MARK: - resolve() fixture helper

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

    // MARK: - Test: a stale Person.id captured at mark time still translates to whoever
    // currently owns it, after that person gains a new, smaller identifier (simulated resync).

    func testResolveTranslatesAStaleIdentifierToTheMembersCurrentPersonID() {
        // Marked when A's id was "+15551002".
        let storedKey = AcquaintanceRosterKey.canonicalize(["+15551002", "+15551003"])

        // After a resync, A gained a smaller identifier and A.id shifted -- but "+15551002"
        // is still in A's identifier set (identifiers only ever get added, never removed).
        let aAfter = person(id: "+15551000", identifiers: ["+15551000", "+15551002"])
        let bAfter = person(id: "+15551003", identifiers: ["+15551003"])

        let translated = AcquaintanceRosterKey.resolve(stored: [storedKey], people: [aAfter, bAfter])

        XCTAssertEqual(translated, [["+15551000", "+15551003"]], "the stored key must follow A to A's CURRENT id, not stay pinned to the old one")
    }

    // MARK: - Test: a stored identifier belonging to nobody current is dormant -- matches
    // nothing, never crashes.

    func testResolveDropsADormantKeyWhoseIdentifierBelongsToNoCurrentPerson() {
        let storedKey = ["+15559999"] // belongs to nobody in `people` below
        let someoneElse = person(id: "+15550001", identifiers: ["+15550001"])

        let translated = AcquaintanceRosterKey.resolve(stored: [storedKey], people: [someoneElse])

        XCTAssertEqual(translated, [], "a stored identifier with no current owner must translate to nothing, not crash or fall back to the raw key")
    }

    // MARK: - Test: two stored identifiers that now belong to the SAME (merged) person
    // collapse to the correspondingly smaller, merged roster.

    func testResolveCollapsesTwoStoredIdentifiersThatNowResolveToOneMergedPerson() {
        // Marked when A and B were two separate people.
        let storedKey = AcquaintanceRosterKey.canonicalize(["+15551010", "+15551011", "+15551012"])

        // A and B have since merged into one person (smaller of the two ids wins); C unchanged.
        let mergedAB = person(id: "+15551010", identifiers: ["+15551010", "+15551011"])
        let c = person(id: "+15551012", identifiers: ["+15551012"])

        let translated = AcquaintanceRosterKey.resolve(stored: [storedKey], people: [mergedAB, c])

        let currentShrunkenRoster = AcquaintanceRosterKey.canonicalize([mergedAB.id, c.id])
        XCTAssertEqual(translated, [currentShrunkenRoster], "two identifiers folding into one person must shrink the key to match the now-smaller roster")
    }

    // MARK: - Test: translation is deterministic regardless of the `people` array's own order

    func testResolveIsDeterministicRegardlessOfPeopleArrayOrder() {
        let storedKey = AcquaintanceRosterKey.canonicalize(["+15551002", "+15551003"])
        let aAfter = person(id: "+15551000", identifiers: ["+15551000", "+15551002"])
        let bAfter = person(id: "+15551003", identifiers: ["+15551003"])

        let forward = AcquaintanceRosterKey.resolve(stored: [storedKey], people: [aAfter, bAfter])
        let reversed = AcquaintanceRosterKey.resolve(stored: [storedKey], people: [bAfter, aAfter])

        XCTAssertEqual(forward, reversed)
        // Not just self-consistent -- actually translated, so a broken "always echo the input"
        // implementation cannot pass this by being trivially stable.
        XCTAssertEqual(forward, [["+15551000", "+15551003"]])
    }
}
