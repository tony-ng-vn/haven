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

    // MARK: - fullyAcquaintedRosterKeys (the acquaintance layer's "everyone here knows each
    // other" marker): same backward-compat contract as every other field above, pinned on its
    // own since it was added after all the others.

    func testDecodingAFileWrittenBeforeFullyAcquaintedRosterKeysExistedStillLoads() throws {
        // A file from before this field existed: none of the other fields are new to it, only
        // this one is missing entirely.
        let json = """
        {
            "hiddenPersonIdentifiers": [],
            "hiddenGroupGUIDs": [],
            "removedPersonIdentifiers": [],
            "mergeAnswers": [],
            "nameGuesses": {}
        }
        """
        let fileURL = tempDirectory.appendingPathComponent("pre-acquaintance-layer.json")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: fileURL)
        let store = OverridesStore(fileURL: fileURL)

        let loaded = try store.load()

        XCTAssertEqual(loaded.fullyAcquaintedRosterKeys, [], "a missing fullyAcquaintedRosterKeys key must decode as empty, not throw")
    }

    func testFullyAcquaintedRosterKeysRoundTripsThroughDiskUnchanged() throws {
        let fileURL = tempDirectory.appendingPathComponent("acquaintance-roundtrip.json")
        let store = OverridesStore(fileURL: fileURL)
        let overrides = Overrides(fullyAcquaintedRosterKeys: [["+14155550001", "+14155550002"], ["+14155550003", "+14155550004"]])

        try store.save(overrides)
        let loaded = try store.load()

        XCTAssertEqual(loaded.fullyAcquaintedRosterKeys, overrides.fullyAcquaintedRosterKeys)
    }

    /// AcquaintanceRosterKey.resolve translates stored keys against CURRENT people only at
    /// match time (GraphJSON, the CLI, AppModel) -- it never runs anywhere near save()/load(),
    /// so a key that would resolve to nothing right now (nobody currently owns its
    /// identifiers) must still round-trip through disk byte-for-byte, exactly as marked. User
    /// data is never silently mutated or cleaned up just because it is temporarily dormant.
    func testADormantRosterKeyRoundTripsThroughDiskUnchanged() throws {
        let fileURL = tempDirectory.appendingPathComponent("dormant-key-roundtrip.json")
        let store = OverridesStore(fileURL: fileURL)
        let dormantKey = ["+14155559999"] // belongs to nobody in any current people list
        let overrides = Overrides(fullyAcquaintedRosterKeys: [dormantKey])

        try store.save(overrides)
        let loaded = try store.load()

        XCTAssertEqual(loaded.fullyAcquaintedRosterKeys, [dormantKey], "a dormant key is stored curation, not cleaned up or rewritten by anything in the load/save path")
    }
}
