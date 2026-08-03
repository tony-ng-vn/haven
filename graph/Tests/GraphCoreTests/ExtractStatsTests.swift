import XCTest
@testable import GraphCore

final class ExtractStatsTests: XCTestCase {

    // Test 5: a 5-digit identifier is a shortcode, a 10-digit number is not,
    // and an alphanumeric sender id is not (it contains a letter).
    func testShortcodeDetection() throws {
        let fixture = try ChatDBFixture()
        defer { fixture.close() }

        try fixture.insertHandle(rowID: 1, id: "12345", service: "SMS")
        try fixture.insertHandle(rowID: 2, id: "1234567890", service: "SMS")
        try fixture.insertHandle(rowID: 3, id: "AB123", service: "SMS")
        fixture.close()

        let extract = try ChatDatabase.extract(path: fixture.url.path)
        let stats = ExtractStats.compute(extract)

        XCTAssertEqual(stats.shortcodeHandleCount, 1)
    }

    // Test 6: a one-to-one chat with inbound messages only is never-replied;
    // a chat with at least one outbound message is not.
    func testNeverRepliedOneToOneChats() throws {
        let fixture = try ChatDBFixture()
        defer { fixture.close() }

        try fixture.insertHandle(rowID: 1, id: "+15551110000", service: "iMessage")
        try fixture.insertHandle(rowID: 2, id: "+15552220000", service: "iMessage")

        // Chat 1: inbound only, never replied.
        try fixture.insertChat(rowID: 1, guid: "chat-never-replied", style: 45, chatIdentifier: "+15551110000")
        try fixture.insertChatHandleJoin(chatID: 1, handleID: 1)
        try fixture.insertMessage(
            rowID: 1, handleID: 1, service: "iMessage",
            dateNanoseconds: 700_000_000_000_000_000, isFromMe: false
        )
        try fixture.insertChatMessageJoin(chatID: 1, messageID: 1)

        // Chat 2: inbound plus a reply, not never-replied.
        try fixture.insertChat(rowID: 2, guid: "chat-replied", style: 45, chatIdentifier: "+15552220000")
        try fixture.insertChatHandleJoin(chatID: 2, handleID: 2)
        try fixture.insertMessage(
            rowID: 2, handleID: 2, service: "iMessage",
            dateNanoseconds: 700_000_000_000_000_000, isFromMe: false
        )
        try fixture.insertChatMessageJoin(chatID: 2, messageID: 2)
        try fixture.insertMessage(
            rowID: 3, handleID: nil, service: "iMessage",
            dateNanoseconds: 700_000_001_000_000_000, isFromMe: true
        )
        try fixture.insertChatMessageJoin(chatID: 2, messageID: 3)

        // Chat 3: a second never-replied chat. Counts are kept asymmetric (2 never-replied
        // vs 1 replied) so an inverted predicate cannot produce the same total.
        try fixture.insertHandle(rowID: 3, id: "+15553330000", service: "iMessage")
        try fixture.insertChat(rowID: 3, guid: "chat-never-replied-2", style: 45, chatIdentifier: "+15553330000")
        try fixture.insertChatHandleJoin(chatID: 3, handleID: 3)
        try fixture.insertMessage(
            rowID: 4, handleID: 3, service: "iMessage",
            dateNanoseconds: 700_000_002_000_000_000, isFromMe: false
        )
        try fixture.insertChatMessageJoin(chatID: 3, messageID: 4)

        fixture.close()

        let extract = try ChatDatabase.extract(path: fixture.url.path)
        let stats = ExtractStats.compute(extract)

        XCTAssertEqual(stats.oneToOneChatsWithMessages, 3)
        XCTAssertEqual(stats.neverRepliedOneToOneChats, 2)
    }

    func testGroupSizeDistributionIsNilWhenNoGroupChats() {
        let extract = ChatExtract(handles: [], chats: [], messages: [], unjoinedMessageCount: 0)
        let stats = ExtractStats.compute(extract)

        XCTAssertNil(stats.groupSizeDistribution.min)
        XCTAssertNil(stats.groupSizeDistribution.max)
        XCTAssertTrue(stats.groupSizeDistribution.countBySize.isEmpty)
    }

    func testGroupSizeDistributionTracksMinMaxAndCounts() {
        let extract = ChatExtract(
            handles: [],
            chats: [
                RawChat(rowID: 1, guid: "g1", style: 43, chatIdentifier: nil, serviceName: nil, displayName: nil, memberHandleRowIDs: [1, 2]),
                RawChat(rowID: 2, guid: "g2", style: 43, chatIdentifier: nil, serviceName: nil, displayName: nil, memberHandleRowIDs: [1, 2, 3]),
                RawChat(rowID: 3, guid: "g3", style: 43, chatIdentifier: nil, serviceName: nil, displayName: nil, memberHandleRowIDs: [1, 2]),
            ],
            messages: [],
            unjoinedMessageCount: 0
        )
        let stats = ExtractStats.compute(extract)

        XCTAssertEqual(stats.groupSizeDistribution.min, 2)
        XCTAssertEqual(stats.groupSizeDistribution.max, 3)
        XCTAssertEqual(stats.groupSizeDistribution.countBySize, [2: 2, 3: 1])
    }
}
