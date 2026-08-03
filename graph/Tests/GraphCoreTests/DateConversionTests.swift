import XCTest
@testable import GraphCore

final class DateConversionTests: XCTestCase {

    // message.date is nanoseconds since the Apple epoch (2001-01-01 00:00:00 UTC),
    // which is exactly Foundation's reference date, so 0 ns must convert to that instant.
    func testAppleEpochZeroConvertsToReferenceDate() throws {
        let extract = try extractSingleMessage(dateNanoseconds: 0)
        let message = try XCTUnwrap(extract.messages.first)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: message.date
        )

        XCTAssertEqual(components.year, 2001)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 1)
        XCTAssertEqual(components.hour, 0)
        XCTAssertEqual(components.minute, 0)
        XCTAssertEqual(components.second, 0)
    }

    // A nonzero, whole-second offset: 100 seconds past the Apple epoch.
    func testAppleEpochNonzeroWholeSecondConversion() throws {
        let extract = try extractSingleMessage(dateNanoseconds: 100_000_000_000)
        let message = try XCTUnwrap(extract.messages.first)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: message.date
        )

        XCTAssertEqual(components.year, 2001)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 1)
        XCTAssertEqual(components.hour, 0)
        XCTAssertEqual(components.minute, 1)
        XCTAssertEqual(components.second, 40)
    }

    private func extractSingleMessage(dateNanoseconds: Int64) throws -> ChatExtract {
        let fixture = try ChatDBFixture()
        defer { fixture.close() }

        try fixture.insertHandle(rowID: 1, id: "+15550001234", service: "iMessage")
        try fixture.insertChat(rowID: 1, guid: "chat-guid-date", style: 45, chatIdentifier: "+15550001234")
        try fixture.insertChatHandleJoin(chatID: 1, handleID: 1)
        try fixture.insertMessage(
            rowID: 1,
            handleID: 1,
            service: "iMessage",
            dateNanoseconds: dateNanoseconds,
            isFromMe: false
        )
        try fixture.insertChatMessageJoin(chatID: 1, messageID: 1)
        fixture.close()

        return try ChatDatabase.extract(path: fixture.url.path)
    }
}
