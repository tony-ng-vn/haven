import XCTest
@testable import GraphCore

final class ReadOnlyDisciplineTests: XCTestCase {

    // Test 8, part 1: extracting from a nonexistent path throws and never creates a file.
    func testExtractingFromNonexistentPathThrowsAndCreatesNoFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("graph-core-readonly-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let missingPath = dir.appendingPathComponent("does-not-exist.db").path

        XCTAssertFalse(FileManager.default.fileExists(atPath: missingPath))
        XCTAssertThrowsError(try ChatDatabase.extract(path: missingPath))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: missingPath),
            "a read-only open must never create the database file"
        )
    }

    // Test 8, part 2: a successful extraction leaves the fixture file's bytes unchanged.
    func testSuccessfulExtractionLeavesFixtureBytesUnchanged() throws {
        let fixture = try ChatDBFixture()
        defer { fixture.close() }

        try fixture.insertHandle(rowID: 1, id: "+15551234567", service: "iMessage")
        try fixture.insertChat(rowID: 1, guid: "chat-guid-hash", style: 45, chatIdentifier: "+15551234567")
        try fixture.insertChatHandleJoin(chatID: 1, handleID: 1)
        try fixture.insertMessage(
            rowID: 1, handleID: 1, service: "iMessage",
            dateNanoseconds: 700_000_000_000_000_000, isFromMe: false
        )
        try fixture.insertChatMessageJoin(chatID: 1, messageID: 1)
        fixture.close()

        let bytesBefore = try Data(contentsOf: fixture.url)

        _ = try ChatDatabase.extract(path: fixture.url.path)

        let bytesAfter = try Data(contentsOf: fixture.url)
        XCTAssertEqual(bytesBefore, bytesAfter, "a read-only extraction must not modify the database file")
    }
}
