import XCTest
@testable import GraphCore

final class SnippetReaderTests: XCTestCase {

    // A distinctive, obviously-fake sentinel: this is a synthetic fixture literal (never a
    // real message), used only to prove SnippetReader's own mechanics (limit/order/null-skip).
    // It is not the privacy test -- that lives in GuessEngineTests, and asserts this kind of
    // string never reaches the overrides store.
    private let sentinelPrefix = "SNIPPET-FIXTURE-TEXT"

    func testLimitIsRespected() throws {
        let fixture = try ChatDBFixture()
        defer { fixture.close() }
        try fixture.insertHandle(rowID: 1, id: "+14155550001", service: "iMessage")
        try fixture.insertChat(rowID: 1, guid: "g1", style: 45, chatIdentifier: "+14155550001")
        try fixture.insertChatHandleJoin(chatID: 1, handleID: 1)

        for i in 0..<5 {
            let messageID = Int64(i + 1)
            try fixture.insertMessage(
                rowID: messageID, text: "\(sentinelPrefix)-\(i)", handleID: 1, service: "iMessage",
                dateNanoseconds: Int64(i) * 1_000_000_000, isFromMe: false
            )
            try fixture.insertChatMessageJoin(chatID: 1, messageID: messageID)
        }
        fixture.close()

        let snippets = try SnippetReader.read(dbPath: fixture.url.path, chatRowIDs: [1], limit: 3)

        XCTAssertEqual(snippets.count, 3, "limit of 3 must cap the result at 3 rows")
    }

    func testNullTextIsSkipped() throws {
        let fixture = try ChatDBFixture()
        defer { fixture.close() }
        try fixture.insertHandle(rowID: 1, id: "+14155550002", service: "iMessage")
        try fixture.insertChat(rowID: 1, guid: "g1", style: 45, chatIdentifier: "+14155550002")
        try fixture.insertChatHandleJoin(chatID: 1, handleID: 1)

        // An attributedBody-only row whose blob is not a typedstream at all (no "streamtyped"
        // signature). attributedBody IS decoded now, but a blob AttributedBodyDecoder cannot
        // read must still leave the message invisible to SnippetReader rather than becoming an
        // error or garbage text -- the same intent this test always had, now covering the
        // decoder's fail-closed path instead of an outright-skipped column.
        try fixture.insertMessage(
            rowID: 1, text: nil, attributedBody: Data("not decoded".utf8), handleID: 1,
            service: "iMessage", dateNanoseconds: 0, isFromMe: false
        )
        try fixture.insertChatMessageJoin(chatID: 1, messageID: 1)
        try fixture.insertMessage(
            rowID: 2, text: "\(sentinelPrefix)-real", handleID: 1, service: "iMessage",
            dateNanoseconds: 1_000_000_000, isFromMe: false
        )
        try fixture.insertChatMessageJoin(chatID: 1, messageID: 2)
        fixture.close()

        let snippets = try SnippetReader.read(dbPath: fixture.url.path, chatRowIDs: [1])

        XCTAssertEqual(snippets.count, 1, "the NULL-text row must be skipped, only the real one survives")
    }

    func testOrderingIsNewestFirst() throws {
        let fixture = try ChatDBFixture()
        defer { fixture.close() }
        try fixture.insertHandle(rowID: 1, id: "+14155550003", service: "iMessage")
        try fixture.insertChat(rowID: 1, guid: "g1", style: 45, chatIdentifier: "+14155550003")
        try fixture.insertChatHandleJoin(chatID: 1, handleID: 1)

        try fixture.insertMessage(
            rowID: 1, text: "\(sentinelPrefix)-oldest", handleID: 1, service: "iMessage",
            dateNanoseconds: 0, isFromMe: false
        )
        try fixture.insertChatMessageJoin(chatID: 1, messageID: 1)
        try fixture.insertMessage(
            rowID: 2, text: "\(sentinelPrefix)-newest", handleID: 1, service: "iMessage",
            dateNanoseconds: 2_000_000_000, isFromMe: true
        )
        try fixture.insertChatMessageJoin(chatID: 1, messageID: 2)
        try fixture.insertMessage(
            rowID: 3, text: "\(sentinelPrefix)-middle", handleID: 1, service: "iMessage",
            dateNanoseconds: 1_000_000_000, isFromMe: false
        )
        try fixture.insertChatMessageJoin(chatID: 1, messageID: 3)
        fixture.close()

        let snippets = try SnippetReader.read(dbPath: fixture.url.path, chatRowIDs: [1])

        XCTAssertEqual(snippets.map(\.text), [
            "\(sentinelPrefix)-newest",
            "\(sentinelPrefix)-middle",
            "\(sentinelPrefix)-oldest",
        ])
        XCTAssertEqual(snippets.first?.isFromMe, true, "the newest message's isFromMe must round-trip too")
    }

    // MARK: - attributedBody fallback

    /// The common shape on a real database: `text` is NULL and the words live only in the
    /// archived attributed string. The blob is synthetic (TypedstreamFixture), never captured.
    func testAttributedBodyOnlyRowIsDecodedIntoASnippet() throws {
        let fixture = try ChatDBFixture()
        defer { fixture.close() }
        try fixture.insertHandle(rowID: 1, id: "+14155550005", service: "iMessage")
        try fixture.insertChat(rowID: 1, guid: "g1", style: 45, chatIdentifier: "+14155550005")
        try fixture.insertChatHandleJoin(chatID: 1, handleID: 1)

        let expected = "\(sentinelPrefix)-from-attributed-body"
        try fixture.insertMessage(
            rowID: 1, text: nil, attributedBody: TypedstreamFixture.blob(text: expected),
            handleID: 1, service: "iMessage", dateNanoseconds: 0, isFromMe: true
        )
        try fixture.insertChatMessageJoin(chatID: 1, messageID: 1)
        fixture.close()

        let snippets = try SnippetReader.read(dbPath: fixture.url.path, chatRowIDs: [1])

        XCTAssertEqual(snippets.map(\.text), [expected])
        XCTAssertEqual(snippets.first?.isFromMe, true, "isFromMe must still round-trip past the new blob column")
    }

    /// Plain text wins when both columns are populated: the decoder is a fallback, not a
    /// replacement.
    func testPlainTextIsPreferredOverTheBlobWhenBothArePresent() throws {
        let fixture = try ChatDBFixture()
        defer { fixture.close() }
        try fixture.insertHandle(rowID: 1, id: "+14155550006", service: "iMessage")
        try fixture.insertChat(rowID: 1, guid: "g1", style: 45, chatIdentifier: "+14155550006")
        try fixture.insertChatHandleJoin(chatID: 1, handleID: 1)

        try fixture.insertMessage(
            rowID: 1, text: "\(sentinelPrefix)-plain",
            attributedBody: TypedstreamFixture.blob(text: "\(sentinelPrefix)-blob"),
            handleID: 1, service: "iMessage", dateNanoseconds: 0, isFromMe: false
        )
        try fixture.insertChatMessageJoin(chatID: 1, messageID: 1)
        fixture.close()

        let snippets = try SnippetReader.read(dbPath: fixture.url.path, chatRowIDs: [1])

        XCTAssertEqual(snippets.map(\.text), ["\(sentinelPrefix)-plain"])
    }

    /// An empty (or whitespace-only) decode is not evidence. Dropping it here is what keeps
    /// GuessEngine's "no evidence, no prompt" rule honest: an attachment-only message must not
    /// make a candidate look like it has something to read.
    func testAnAttributedBodyThatDecodesToBlankTextIsDropped() throws {
        let fixture = try ChatDBFixture()
        defer { fixture.close() }
        try fixture.insertHandle(rowID: 1, id: "+14155550007", service: "iMessage")
        try fixture.insertChat(rowID: 1, guid: "g1", style: 45, chatIdentifier: "+14155550007")
        try fixture.insertChatHandleJoin(chatID: 1, handleID: 1)

        try fixture.insertMessage(
            rowID: 1, text: nil, attributedBody: TypedstreamFixture.blob(text: ""),
            handleID: 1, service: "iMessage", dateNanoseconds: 0, isFromMe: false
        )
        try fixture.insertChatMessageJoin(chatID: 1, messageID: 1)
        try fixture.insertMessage(
            rowID: 2, text: nil, attributedBody: TypedstreamFixture.blob(text: "   \n  "),
            handleID: 1, service: "iMessage", dateNanoseconds: 1_000_000_000, isFromMe: false
        )
        try fixture.insertChatMessageJoin(chatID: 1, messageID: 2)
        fixture.close()

        let snippets = try SnippetReader.read(dbPath: fixture.url.path, chatRowIDs: [1])

        XCTAssertTrue(snippets.isEmpty, "an empty or whitespace-only decode is not a snippet")
    }

    // Test 8-style, part 1: extracting from a nonexistent path throws and never creates a file.
    func testExtractingFromNonexistentPathThrowsAndCreatesNoFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("graph-core-snippetreader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let missingPath = dir.appendingPathComponent("does-not-exist.db").path

        XCTAssertThrowsError(try SnippetReader.read(dbPath: missingPath, chatRowIDs: [1]))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: missingPath),
            "a read-only open must never create the database file"
        )
    }

    // Test 8-style, part 2: a successful read leaves the fixture file's bytes unchanged.
    func testSuccessfulReadLeavesFixtureBytesUnchanged() throws {
        let fixture = try ChatDBFixture()
        defer { fixture.close() }
        try fixture.insertHandle(rowID: 1, id: "+14155550004", service: "iMessage")
        try fixture.insertChat(rowID: 1, guid: "g1", style: 45, chatIdentifier: "+14155550004")
        try fixture.insertChatHandleJoin(chatID: 1, handleID: 1)
        try fixture.insertMessage(
            rowID: 1, text: "\(sentinelPrefix)-bytes", handleID: 1, service: "iMessage",
            dateNanoseconds: 0, isFromMe: false
        )
        try fixture.insertChatMessageJoin(chatID: 1, messageID: 1)
        fixture.close()

        let bytesBefore = try Data(contentsOf: fixture.url)
        _ = try SnippetReader.read(dbPath: fixture.url.path, chatRowIDs: [1])
        let bytesAfter = try Data(contentsOf: fixture.url)

        XCTAssertEqual(bytesBefore, bytesAfter, "a read-only snippet read must not modify the database file")
    }
}
