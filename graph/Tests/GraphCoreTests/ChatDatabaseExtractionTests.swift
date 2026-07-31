import XCTest
@testable import GraphCore

final class ChatDatabaseExtractionTests: XCTestCase {

    // Test 1: basic extraction, both directions, every field round-trips.
    func testBasicExtractionRoundTripsEveryField() throws {
        let fixture = try ChatDBFixture()
        defer { fixture.close() }

        try fixture.insertHandle(rowID: 1, id: "+15551111111", service: "iMessage")
        try fixture.insertHandle(rowID: 2, id: "+15552222222", service: "SMS")

        try fixture.insertChat(
            rowID: 1,
            guid: "chat-guid-basic",
            style: 45,
            chatIdentifier: "+15551111111",
            serviceName: "iMessage",
            displayName: nil
        )
        try fixture.insertChatHandleJoin(chatID: 1, handleID: 1)

        let inboundDateNs: Int64 = 700_000_000_000_000_000
        let outboundDateNs: Int64 = 700_000_100_000_000_000

        try fixture.insertMessage(
            rowID: 1,
            handleID: 1,
            service: "iMessage",
            dateNanoseconds: inboundDateNs,
            isFromMe: false
        )
        try fixture.insertChatMessageJoin(chatID: 1, messageID: 1)

        try fixture.insertMessage(
            rowID: 2,
            handleID: nil,
            service: "iMessage",
            dateNanoseconds: outboundDateNs,
            isFromMe: true
        )
        try fixture.insertChatMessageJoin(chatID: 1, messageID: 2)

        fixture.close()

        let extract = try ChatDatabase.extract(path: fixture.url.path)

        XCTAssertEqual(extract.handles, [
            RawHandle(rowID: 1, identifier: "+15551111111", service: "iMessage"),
            RawHandle(rowID: 2, identifier: "+15552222222", service: "SMS"),
        ])

        XCTAssertEqual(extract.chats, [
            RawChat(
                rowID: 1,
                guid: "chat-guid-basic",
                style: 45,
                chatIdentifier: "+15551111111",
                serviceName: "iMessage",
                displayName: nil,
                memberHandleRowIDs: [1]
            )
        ])

        XCTAssertEqual(extract.messages.count, 2)
        XCTAssertEqual(extract.unjoinedMessageCount, 0)

        let inbound = try XCTUnwrap(extract.messages.first { $0.rowID == 1 })
        XCTAssertEqual(inbound.chatRowID, 1)
        XCTAssertEqual(inbound.handleRowID, 1)
        XCTAssertFalse(inbound.isFromMe)
        XCTAssertEqual(
            inbound.date.timeIntervalSinceReferenceDate,
            Double(inboundDateNs) / 1_000_000_000,
            accuracy: 0.000_001
        )

        let outbound = try XCTUnwrap(extract.messages.first { $0.rowID == 2 })
        XCTAssertEqual(outbound.chatRowID, 1)
        XCTAssertNil(outbound.handleRowID)
        XCTAssertTrue(outbound.isFromMe)
        XCTAssertEqual(
            outbound.date.timeIntervalSinceReferenceDate,
            Double(outboundDateNs) / 1_000_000_000,
            accuracy: 0.000_001
        )
    }

    // Test 2: an empty chat row (no chat_message_join rows) still appears, with zero messages.
    func testEmptyChatRowAppearsWithZeroMessages() throws {
        let fixture = try ChatDBFixture()
        defer { fixture.close() }

        try fixture.insertHandle(rowID: 1, id: "+15553334444", service: "iMessage")
        try fixture.insertChat(rowID: 1, guid: "chat-guid-empty", style: 45, chatIdentifier: "+15553334444")
        try fixture.insertChatHandleJoin(chatID: 1, handleID: 1)
        fixture.close()

        let extract = try ChatDatabase.extract(path: fixture.url.path)

        XCTAssertEqual(extract.chats.count, 1)
        XCTAssertEqual(extract.chats[0].memberHandleRowIDs, [1])
        XCTAssertTrue(extract.messages.isEmpty)

        let stats = ExtractStats.compute(extract)
        XCTAssertEqual(stats.emptyOneToOneChats, 1)
        XCTAssertEqual(stats.oneToOneChatsWithMessages, 0)
    }

    // Test 3: a two-member style-43 chat preserves style and both members.
    func testTwoMemberStyle43ChatPreservesStyleAndMembers() throws {
        let fixture = try ChatDBFixture()
        defer { fixture.close() }

        try fixture.insertHandle(rowID: 1, id: "+15551000000", service: "iMessage")
        try fixture.insertHandle(rowID: 2, id: "+15552000000", service: "iMessage")
        try fixture.insertChat(rowID: 1, guid: "chat-guid-group2", style: 43, chatIdentifier: "chat-group-id")
        try fixture.insertChatHandleJoin(chatID: 1, handleID: 1)
        try fixture.insertChatHandleJoin(chatID: 1, handleID: 2)
        fixture.close()

        let extract = try ChatDatabase.extract(path: fixture.url.path)

        XCTAssertEqual(extract.chats.count, 1)
        XCTAssertEqual(extract.chats[0].style, 43)
        XCTAssertEqual(extract.chats[0].memberHandleRowIDs, [1, 2])

        let stats = ExtractStats.compute(extract)
        XCTAssertEqual(stats.twoMemberGroupStyleChats, 1)
        XCTAssertEqual(stats.groupChatCount, 1)
    }

    // Test 4: the same identifier as two handle rows on different services.
    func testMultiServiceDuplicateHandle() throws {
        let fixture = try ChatDBFixture()
        defer { fixture.close() }

        try fixture.insertHandle(rowID: 1, id: "+15559990000", service: "iMessage")
        try fixture.insertHandle(rowID: 2, id: "+15559990000", service: "SMS")
        fixture.close()

        let extract = try ChatDatabase.extract(path: fixture.url.path)
        let stats = ExtractStats.compute(extract)

        XCTAssertEqual(stats.handleRowCount, 2)
        XCTAssertEqual(stats.distinctIdentifierCount, 1)
        XCTAssertEqual(stats.serviceMix, ["iMessage": 1, "SMS": 1])
    }

    // Test 7: a 20-member group where only 3 members ever sent a message.
    func testLargeGroupKeepsAllMembersRegardlessOfMessageActivity() throws {
        let fixture = try ChatDBFixture()
        defer { fixture.close() }

        for i in 1...20 {
            try fixture.insertHandle(rowID: Int64(i), id: "+1555000\(String(format: "%04d", i))", service: "iMessage")
        }
        try fixture.insertChat(rowID: 1, guid: "chat-guid-large-group", style: 43, chatIdentifier: "large-group")
        for i in 1...20 {
            try fixture.insertChatHandleJoin(chatID: 1, handleID: Int64(i))
        }

        var messageRowID: Int64 = 1
        for i in 1...3 {
            try fixture.insertMessage(
                rowID: messageRowID,
                handleID: Int64(i),
                service: "iMessage",
                dateNanoseconds: 700_000_000_000_000_000,
                isFromMe: false
            )
            try fixture.insertChatMessageJoin(chatID: 1, messageID: messageRowID)
            messageRowID += 1
        }
        fixture.close()

        let extract = try ChatDatabase.extract(path: fixture.url.path)

        XCTAssertEqual(extract.chats.count, 1)
        XCTAssertEqual(extract.chats[0].memberHandleRowIDs.count, 20)
        XCTAssertEqual(Set(extract.chats[0].memberHandleRowIDs), Set((1...20).map(Int64.init)))
        XCTAssertEqual(extract.messages.count, 3)
    }

    // Test 10: a message with no chat_message_join row is skipped and counted, not fatal.
    func testUnjoinedMessageIsSkippedAndCounted() throws {
        let fixture = try ChatDBFixture()
        defer { fixture.close() }

        try fixture.insertHandle(rowID: 1, id: "+15557778888", service: "iMessage")
        try fixture.insertChat(rowID: 1, guid: "chat-guid-unjoined", style: 45, chatIdentifier: "+15557778888")
        try fixture.insertChatHandleJoin(chatID: 1, handleID: 1)

        // Joined message, should show up normally.
        try fixture.insertMessage(
            rowID: 1,
            handleID: 1,
            service: "iMessage",
            dateNanoseconds: 700_000_000_000_000_000,
            isFromMe: false
        )
        try fixture.insertChatMessageJoin(chatID: 1, messageID: 1)

        // Orphan message: exists in `message` but has no chat_message_join row at all.
        try fixture.insertMessage(
            rowID: 2,
            handleID: 1,
            service: "iMessage",
            dateNanoseconds: 700_000_000_100_000_000,
            isFromMe: false
        )
        fixture.close()

        let extract = try ChatDatabase.extract(path: fixture.url.path)

        XCTAssertEqual(extract.messages.count, 1)
        XCTAssertEqual(extract.messages[0].rowID, 1)
        XCTAssertEqual(extract.unjoinedMessageCount, 1)
    }
}
