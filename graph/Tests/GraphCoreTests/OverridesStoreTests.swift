import XCTest
@testable import GraphCore

final class OverridesStoreTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        // A fresh temp dir per test: the store's designated init requires an explicit URL
        // precisely so this test suite never has any path to the user's real overrides file.
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OverridesStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testRoundTripsThroughDiskIncludingANestedNotYetCreatedDirectory() throws {
        // Nested one level deeper than tempDirectory itself, unlike defaultFileURL's own
        // ConnectionGraph subfolder: proves save() creates the directory, not just relies on
        // one that already happens to exist.
        let fileURL = tempDirectory.appendingPathComponent("nested/overrides.json")
        let store = OverridesStore(fileURL: fileURL)

        let overrides = Overrides(
            hiddenPersonIdentifiers: ["+14155550001"],
            hiddenGroupGUIDs: ["chat-guid-1"],
            removedPersonIdentifiers: ["+14155550002"],
            mergeAnswers: [MergeAnswer(identifierA: "b@example.com", identifierB: "a@example.com", decision: .merged)],
            nameGuesses: ["+14155550003": NameGuess(name: "Guessed Name", detail: "from group chat context")]
        )

        try store.save(overrides)
        let loaded = try store.load()

        XCTAssertEqual(loaded, overrides)
    }

    func testLoadingAMissingFileYieldsEmptyOverrides() throws {
        let store = OverridesStore(fileURL: tempDirectory.appendingPathComponent("does-not-exist.json"))

        let loaded = try store.load()

        XCTAssertEqual(loaded, Overrides())
    }

    func testLoadingCorruptJSONThrows() throws {
        let fileURL = tempDirectory.appendingPathComponent("corrupt.json")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try Data("not valid json at all { [ }".utf8).write(to: fileURL)
        let store = OverridesStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.load()) { error in
            // Not asserting on error type/message: the point is that it throws at all, i.e.
            // never silently resets user curation back to empty (PLAN.md).
            _ = error
        }
    }

    func testDecodingToleratesAMissingFieldWhileAnUnknownExtraFieldIsAlsoPresent() throws {
        // Simulates a file written by an OLDER version of this app (before nameGuesses
        // existed) that ALSO happens to carry a field this version doesn't know about yet
        // (a forward-compat scenario, e.g. rolled back after a newer version briefly ran).
        // Swift's synthesized Decodable already ignores unknown keys for free, so the
        // meaningful half of this test -- the one an unknown-key-only test would miss -- is
        // that a MISSING key (nameGuesses) still decodes instead of throwing.
        let json = """
        {
            "hiddenPersonIdentifiers": ["+14155550009"],
            "hiddenGroupGUIDs": [],
            "removedPersonIdentifiers": [],
            "mergeAnswers": [],
            "someFieldThisVersionHasNeverHeardOf": 42
        }
        """
        let fileURL = tempDirectory.appendingPathComponent("old-format.json")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: fileURL)
        let store = OverridesStore(fileURL: fileURL)

        let loaded = try store.load()

        XCTAssertEqual(loaded.hiddenPersonIdentifiers, ["+14155550009"])
        XCTAssertEqual(loaded.nameGuesses, [:], "a missing nameGuesses key must decode as empty, not throw")
    }
}
