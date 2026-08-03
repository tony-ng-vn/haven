import XCTest
@testable import GraphCore

final class NameDisambiguationTests: XCTestCase {

    // MARK: - Test 1: a unique name gets no entry at all

    func testUniqueNameIsAbsentFromTheResult() {
        let result = NameDisambiguation.disambiguators(namesByID: [
            ("+inventedA0001", "Ana Vray"),
            ("+inventedB0002", "Bo Marrow"),
        ])

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Test 2: two ids sharing the exact same name both get a disambiguator

    func testTwoIdsSharingTheSameNameBothGetADisambiguator() {
        let result = NameDisambiguation.disambiguators(namesByID: [
            ("+invented5550001111", "Jon Ashwick"),
            ("+invented5559998888", "Jon Ashwick"),
            ("+invented5551112222", "Ana Vray"),
        ])

        XCTAssertEqual(result.count, 2, "only the two colliding ids get an entry, the unique name does not")
        XCTAssertEqual(result["+invented5550001111"], "...1111")
        XCTAssertEqual(result["+invented5559998888"], "...8888")
        XCTAssertNil(result["+invented5551112222"])
    }

    // MARK: - Test 3: comparison is case-insensitive

    func testCollisionDetectionIsCaseInsensitive() {
        let result = NameDisambiguation.disambiguators(namesByID: [
            ("+invented1110001111", "Robin Alder"),
            ("+invented2220002222", "ROBIN ALDER"),
        ])

        XCTAssertEqual(result.count, 2)
    }

    // MARK: - Test 4: a guess-derived tilde name collides with another identical tilde name,
    // but never with a real (non-tilde) name that only differs by the marker.

    func testGuessDerivedTildeNamesCollideOnlyWithAnIdenticalTildeName() {
        let result = NameDisambiguation.disambiguators(namesByID: [
            ("+invented3330003333", "~Alex"),
            ("+invented4440004444", "~Alex"),
            ("+invented5550005555", "Alex"), // a REAL name, not a guess -- must not join the tilde group
        ])

        XCTAssertEqual(result.count, 2, "the two tilde guesses collide with each other, the real 'Alex' stays unique")
        XCTAssertNotNil(result["+invented3330003333"])
        XCTAssertNotNil(result["+invented4440004444"])
        XCTAssertNil(result["+invented5550005555"])
    }

    // MARK: - Test 5: within a colliding group, two ids whose base short suffix would
    // otherwise be IDENTICAL (two invented emails on the same provider) get a distinguishing
    // tiebreak instead of an identical, non-distinguishing badge.

    func testDisambiguatorsAreDistinctWithinAGroupEvenWhenBaseSuffixesCollide() {
        // Both invented addresses share the domain AND end in the same 4 local-part characters
        // ("rson"), so the plain shortSuffix alone would give both people the identical
        // "...rson" badge -- exactly the failure mode a disambiguator must never have.
        let result = NameDisambiguation.disambiguators(namesByID: [
            ("anderson@example.com", "Sam Rivers"),
            ("patterson@example.com", "Sam Rivers"),
        ])

        XCTAssertEqual(result.count, 2)
        let values = Set(result.values)
        XCTAssertEqual(values.count, 2, "both disambiguators must be distinct, even though their base suffixes collide")
    }

    // MARK: - Test 6: the tiebreak is deterministic regardless of input order (sorted by id,
    // never by whatever order the caller happened to iterate in).

    func testTiebreakOrderIsDeterministicRegardlessOfInputOrder() {
        let forward = NameDisambiguation.disambiguators(namesByID: [
            ("anderson@example.com", "Sam Rivers"),
            ("patterson@example.com", "Sam Rivers"),
        ])
        let reversed = NameDisambiguation.disambiguators(namesByID: [
            ("patterson@example.com", "Sam Rivers"),
            ("anderson@example.com", "Sam Rivers"),
        ])

        XCTAssertEqual(forward, reversed, "the same input set must tie-break identically regardless of iteration order")
    }

    // MARK: - Test 7: a three-way collision group all get distinguishing entries (mirrors the
    // brief's own "first names collide up to 3 ways" scale note).

    func testThreeWayCollisionGroupEachGetsAnEntry() {
        let result = NameDisambiguation.disambiguators(namesByID: [
            ("+invented1000000001", "Casey Fen"),
            ("+invented2000000002", "Casey Fen"),
            ("+invented3000000003", "Casey Fen"),
        ])

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(Set(result.values).count, 3, "a three-way collision must still produce three DISTINCT badges")
    }

    // MARK: - Test 8: an empty or missing name never participates in collision grouping (there
    // is no text to disambiguate against).

    func testEmptyNameNeverParticipates() {
        let result = NameDisambiguation.disambiguators(namesByID: [
            ("+invented1230000000", ""),
            ("+invented4560000000", ""),
        ])

        XCTAssertTrue(result.isEmpty)
    }
}
