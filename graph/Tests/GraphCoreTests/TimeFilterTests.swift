import XCTest
@testable import GraphCore

final class TimeFilterTests: XCTestCase {

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func message(rowID: Int64, chatRowID: Int64, handleRowID: Int64?, isFromMe: Bool, date: Date) -> RawMessage {
        RawMessage(rowID: rowID, chatRowID: chatRowID, handleRowID: handleRowID, isFromMe: isFromMe, date: date)
    }

    private func chat(rowID: Int64, guid: String, style: Int, members: [Int64]) -> RawChat {
        RawChat(rowID: rowID, guid: guid, style: style, chatIdentifier: nil, serviceName: nil, displayName: nil, memberHandleRowIDs: members)
    }

    func testBoundaryDatesAreInclusiveAndOutsideDatesAreDropped() {
        let from = utcDate(2024, 6, 1)
        let to = utcDate(2024, 6, 30)
        let messages: [RawMessage] = [
            message(rowID: 1, chatRowID: 1, handleRowID: 100, isFromMe: false, date: utcDate(2024, 5, 31, hour: 23)), // just before
            message(rowID: 2, chatRowID: 1, handleRowID: 100, isFromMe: false, date: from), // exactly on the boundary
            message(rowID: 3, chatRowID: 1, handleRowID: 100, isFromMe: false, date: utcDate(2024, 6, 15)), // inside
            message(rowID: 4, chatRowID: 1, handleRowID: 100, isFromMe: false, date: to), // exactly on the boundary
            message(rowID: 5, chatRowID: 1, handleRowID: 100, isFromMe: false, date: utcDate(2024, 7, 1)), // just after
        ]
        let extract = ChatExtract(handles: [], chats: [], messages: messages, unjoinedMessageCount: 3)

        let filtered = TimeFilter.apply(extract: extract, from: from, to: to)

        XCTAssertEqual(filtered.messages.map(\.rowID), [2, 3, 4], "only the two boundary messages and the one inside should survive")
    }

    func testEmptyResultShapePreservesEverythingButMessages() {
        let handles = [RawHandle(rowID: 1, identifier: "+14155550100", service: "iMessage")]
        let chats = [chat(rowID: 1, guid: "g1", style: 45, members: [1])]
        let messages = [message(rowID: 1, chatRowID: 1, handleRowID: 1, isFromMe: false, date: utcDate(2024, 1, 1))]
        let extract = ChatExtract(handles: handles, chats: chats, messages: messages, unjoinedMessageCount: 7)

        // A range with no overlap at all.
        let filtered = TimeFilter.apply(extract: extract, from: utcDate(2025, 1, 1), to: utcDate(2025, 1, 31))

        XCTAssertEqual(filtered.messages, [])
        XCTAssertEqual(filtered.handles, handles)
        XCTAssertEqual(filtered.chats, chats)
        // unjoinedMessageCount is a diagnostic about the raw extraction, not something a
        // time window changes: it is carried through as-is, not recomputed or zeroed.
        XCTAssertEqual(filtered.unjoinedMessageCount, 7)
    }

    /// End to end: a person whose only activity falls entirely outside the applied window
    /// should be dropped by the existing PersonFilter+GraphBuilder pipeline, unmodified --
    /// proving TimeFilter is a drop-in stage, not something those two need to know about.
    func testTimeFilteredExtractDropsPersonWhoseOnlyActivityIsOutsideWindow() {
        // Person 100 stays kept: two in-window messages on distinct days (so their thread is
        // live) with at least one fromMe (so they don't also trip neverReplied). Person 200's
        // only message is outside the window; once filtered out, their chat has zero messages
        // left, which trips notLive downstream -- no new rule needed for that, exactly the
        // point of this test.
        let insideMessage1 = message(rowID: 1, chatRowID: 1, handleRowID: 100, isFromMe: false, date: utcDate(2024, 6, 10))
        let insideMessage2 = message(rowID: 2, chatRowID: 1, handleRowID: 100, isFromMe: true, date: utcDate(2024, 6, 15))
        let outsideMessage = message(rowID: 3, chatRowID: 2, handleRowID: 200, isFromMe: false, date: utcDate(2024, 1, 1))
        let handles = [
            RawHandle(rowID: 100, identifier: "+14155550100", service: "iMessage"),
            RawHandle(rowID: 200, identifier: "+14155550200", service: "iMessage"),
        ]
        let chats = [
            chat(rowID: 1, guid: "g1", style: 45, members: [100]),
            chat(rowID: 2, guid: "g2", style: 45, members: [200]),
        ]
        let extract = ChatExtract(
            handles: handles,
            chats: chats,
            messages: [insideMessage1, insideMessage2, outsideMessage],
            unjoinedMessageCount: 0
        )

        let filtered = TimeFilter.apply(extract: extract, from: utcDate(2024, 6, 1), to: utcDate(2024, 6, 30))

        let identity = IdentityResolution.resolve(handles: filtered.handles, contacts: [])
        let filterResult = PersonFilter.apply(extract: filtered, people: identity.people, calendar: utc)

        let keptIDs = Set(filterResult.kept.map(\.id))
        XCTAssertTrue(keptIDs.contains("+14155550100"), "the in-window person should survive")
        XCTAssertFalse(keptIDs.contains("+14155550200"), "the person whose only message fell outside the window should be dropped")

        let graph = GraphBuilder.build(extract: filtered, keptPeople: filterResult.kept)
        XCTAssertFalse(graph.nodes.contains { $0.id == "+14155550200" }, "the dropped person must not appear as a graph node either")
    }
}
