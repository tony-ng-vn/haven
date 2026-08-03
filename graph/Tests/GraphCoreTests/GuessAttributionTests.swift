import XCTest
@testable import GraphCore

/// GuessAttribution enforces "two distinct handles must not carry the same guessed name" as a
/// final, order-independent correction over the whole cache. All fixture identifiers/names
/// below are invented.
final class GuessAttributionTests: XCTestCase {

    func testNoCollisionLeavesEverythingUnchanged() {
        let guesses: [String: NameGuess] = [
            "+14155551001": NameGuess(name: "Fixture One"),
            "+14155551002": NameGuess(name: "Fixture Two"),
        ]

        let (resolved, dropped) = GuessAttribution.resolvingDuplicatePersonNames(in: guesses)

        XCTAssertEqual(resolved, guesses)
        XCTAssertTrue(dropped.isEmpty)
    }

    func testTwoHandlesWithTheExactSameNameAreBothDropped() {
        let guesses: [String: NameGuess] = [
            "+14155551001": NameGuess(name: "Fixture Name"),
            "+14155551002": NameGuess(name: "Fixture Name"),
            "+14155551003": NameGuess(name: "Someone Else"),
        ]

        let (resolved, dropped) = GuessAttribution.resolvingDuplicatePersonNames(in: guesses)

        XCTAssertEqual(dropped, ["+14155551001", "+14155551002"])
        XCTAssertNil(resolved["+14155551001"])
        XCTAssertNil(resolved["+14155551002"])
        XCTAssertEqual(resolved["+14155551003"], NameGuess(name: "Someone Else"))
    }

    /// Collisions are detected case- and whitespace-insensitively: the same underlying name,
    /// differently cased or padded across two model calls, is still one name shared by two
    /// distinct handles.
    func testCollisionDetectionIsCaseAndWhitespaceInsensitive() {
        let guesses: [String: NameGuess] = [
            "+14155551001": NameGuess(name: "  Fixture Name"),
            "+14155551002": NameGuess(name: "fixture name  "),
        ]

        let (resolved, dropped) = GuessAttribution.resolvingDuplicatePersonNames(in: guesses)

        XCTAssertEqual(dropped, ["+14155551001", "+14155551002"])
        XCTAssertTrue(resolved.isEmpty)
    }

    /// Every member of a colliding cluster is dropped, not just the second one seen: nothing in
    /// a NameGuess distinguishes a correct guess from a misattributed one once both have already
    /// passed grounding, so there is no defensible way to pick a "winner" among three or more.
    func testAllMembersOfAThreeWayCollisionAreDropped() {
        let guesses: [String: NameGuess] = [
            "+14155551001": NameGuess(name: "Fixture Name"),
            "+14155551002": NameGuess(name: "Fixture Name"),
            "+14155551003": NameGuess(name: "Fixture Name"),
        ]

        let (resolved, dropped) = GuessAttribution.resolvingDuplicatePersonNames(in: guesses)

        XCTAssertEqual(dropped, ["+14155551001", "+14155551002", "+14155551003"])
        XCTAssertTrue(resolved.isEmpty)
    }

    /// Group guesses ("group:"-prefixed keys) are not "distinct handles" in the sense this rule
    /// is about: a group sharing a display name with a person, or with another group, is not
    /// the misattribution this guards against.
    func testGroupKeysAreExcludedFromTheUniquenessCheck() {
        let guesses: [String: NameGuess] = [
            "+14155551001": NameGuess(name: "Fixture Name"),
            "group:chat-guid-1": NameGuess(name: "Fixture Name"),
            "group:chat-guid-2": NameGuess(name: "Fixture Name"),
        ]

        let (resolved, dropped) = GuessAttribution.resolvingDuplicatePersonNames(in: guesses)

        XCTAssertTrue(dropped.isEmpty, "a lone person guess sharing a name with group guesses is not a person-vs-person collision")
        XCTAssertEqual(resolved, guesses)
    }

    func testEmptyCacheIsANoOp() {
        let (resolved, dropped) = GuessAttribution.resolvingDuplicatePersonNames(in: [:])

        XCTAssertTrue(resolved.isEmpty)
        XCTAssertTrue(dropped.isEmpty)
    }

    /// A collision that pre-dates this rule (already sitting in a cache written by an older
    /// version) is cleaned up exactly the same as one produced in the current pass: the
    /// function only looks at the final map, never at how or when an entry was added.
    func testPreExistingHistoricalCollisionIsCleanedUpTheSameWay() {
        let guesses: [String: NameGuess] = [
            "+14155551001": NameGuess(name: "Old Poisoned Guess", detail: "from a much earlier run"),
            "+14155551002": NameGuess(name: "Old Poisoned Guess"),
        ]

        let (resolved, dropped) = GuessAttribution.resolvingDuplicatePersonNames(in: guesses)

        XCTAssertEqual(dropped.count, 2)
        XCTAssertTrue(resolved.isEmpty)
    }
}
