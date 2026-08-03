import XCTest
@testable import GraphCore

/// GuessCacheRepair backs graph-cli's `guess --reguess` flag: it must clear only the stored
/// name guesses and leave every other piece of the owner's curation untouched. All fixture
/// identifiers/names below are invented.
final class GuessCacheRepairTests: XCTestCase {

    private func fullOverrides(nameGuesses: [String: NameGuess]) -> Overrides {
        Overrides(
            hiddenPersonIdentifiers: ["+14155550001"],
            hiddenGroupGUIDs: ["chat-guid-1"],
            removedPersonIdentifiers: ["+14155550002"],
            mergeAnswers: [MergeAnswer(identifierA: "a@example.com", identifierB: "b@example.com", decision: .merged)],
            nameGuesses: nameGuesses,
            fullyAcquaintedRosterKeys: [["+14155550003", "+14155550004"]]
        )
    }

    func testPurgingDropsEveryNameGuess() {
        let overrides = fullOverrides(nameGuesses: [
            "+14155559001": NameGuess(name: "Fixture One"),
            "+14155559002": NameGuess(name: "Fixture Two"),
            "group:chat-guid-9": NameGuess(name: "Fixture Group"),
        ])

        let (result, droppedCount) = GuessCacheRepair.purgingNameGuesses(from: overrides)

        XCTAssertEqual(droppedCount, 3)
        XCTAssertTrue(result.nameGuesses.isEmpty)
    }

    /// The core guarantee: hidden/removed identifiers, merge answers, and acquaintance roster
    /// markers must survive byte-identical -- proven here via full value equality on every
    /// other field (Overrides is Equatable), combined with OverridesStoreTests' own proof that
    /// save/load round-trips an Overrides value without loss.
    func testPurgingTouchesNothingButNameGuesses() {
        let overrides = fullOverrides(nameGuesses: ["+14155559001": NameGuess(name: "Fixture One")])

        let (result, _) = GuessCacheRepair.purgingNameGuesses(from: overrides)

        XCTAssertEqual(result.hiddenPersonIdentifiers, overrides.hiddenPersonIdentifiers)
        XCTAssertEqual(result.hiddenGroupGUIDs, overrides.hiddenGroupGUIDs)
        XCTAssertEqual(result.removedPersonIdentifiers, overrides.removedPersonIdentifiers)
        XCTAssertEqual(result.mergeAnswers, overrides.mergeAnswers)
        XCTAssertEqual(result.fullyAcquaintedRosterKeys, overrides.fullyAcquaintedRosterKeys)
    }

    func testPurgingAnEmptyCacheDropsNothing() {
        let overrides = fullOverrides(nameGuesses: [:])

        let (result, droppedCount) = GuessCacheRepair.purgingNameGuesses(from: overrides)

        XCTAssertEqual(droppedCount, 0)
        XCTAssertEqual(result, overrides)
    }
}
