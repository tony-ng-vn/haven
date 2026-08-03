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

    // MARK: - Interaction extraction (tapback/reply evidence)

    // Test 11: a tapback ADD is resolved into one interaction naming actor and target.
    func testTapbackAddIsCountedAsAnInteraction() throws {
        let fixture = try ChatDBFixture()
        defer { fixture.close() }

        try fixture.insertHandle(rowID: 1, id: "+15551110001", service: "iMessage") // original sender
        try fixture.insertHandle(rowID: 2, id: "+15551110002", service: "iMessage") // reactor
        try fixture.insertChat(rowID: 1, guid: "chat-tapback", style: 43, chatIdentifier: "tapback-group")
        try fixture.insertChatHandleJoin(chatID: 1, handleID: 1)
        try fixture.insertChatHandleJoin(chatID: 1, handleID: 2)

        try fixture.insertMessage(
            rowID: 1, guid: "original-guid-1", handleID: 1, service: "iMessage",
            dateNanoseconds: 700_000_000_000_000_000, isFromMe: false
        )
        try fixture.insertChatMessageJoin(chatID: 1, messageID: 1)

        try fixture.insertMessage(
            rowID: 2, guid: "tapback-guid-1", handleID: 2, service: "iMessage",
            dateNanoseconds: 700_000_001_000_000_000, isFromMe: false,
            associatedMessageGuid: "original-guid-1", associatedMessageType: 2000
        )
        try fixture.insertChatMessageJoin(chatID: 1, messageID: 2)
        fixture.close()

        let extract = try ChatDatabase.extract(path: fixture.url.path)

        XCTAssertEqual(extract.interactions.count, 1)
        let interaction = try XCTUnwrap(extract.interactions.first)
        XCTAssertEqual(interaction.chatRowID, 1)
        XCTAssertEqual(interaction.actorHandleRowID, 2, "the reactor is the actor")
        XCTAssertEqual(interaction.targetHandleRowID, 1, "the original sender is the target")
    }

    // Test 12: a tapback REMOVE (type >= 3000) is not counted.
    func testTapbackRemoveIsNotCounted() throws {
        let fixture = try ChatDBFixture()
        defer { fixture.close() }

        try fixture.insertHandle(rowID: 1, id: "+15551120001", service: "iMessage")
        try fixture.insertHandle(rowID: 2, id: "+15551120002", service: "iMessage")
        try fixture.insertChat(rowID: 1, guid: "chat-tapback-remove", style: 43, chatIdentifier: "remove-group")
        try fixture.insertChatHandleJoin(chatID: 1, handleID: 1)
        try fixture.insertChatHandleJoin(chatID: 1, handleID: 2)

        try fixture.insertMessage(
            rowID: 1, guid: "original-guid-2", handleID: 1, service: "iMessage",
            dateNanoseconds: 700_000_000_000_000_000, isFromMe: false
        )
        try fixture.insertChatMessageJoin(chatID: 1, messageID: 1)

        try fixture.insertMessage(
            rowID: 2, guid: "tapback-remove-guid", handleID: 2, service: "iMessage",
            dateNanoseconds: 700_000_001_000_000_000, isFromMe: false,
            associatedMessageGuid: "original-guid-2", associatedMessageType: 3000
        )
        try fixture.insertChatMessageJoin(chatID: 1, messageID: 2)
        fixture.close()

        let extract = try ChatDatabase.extract(path: fixture.url.path)

        XCTAssertTrue(extract.interactions.isEmpty, "a retracted reaction (REMOVE, >= 3000) is not evidence")
    }

    // Test 13: a threaded reply (thread_originator_guid) is counted as an interaction.
    func testThreadedReplyIsCountedAsAnInteraction() throws {
        let fixture = try ChatDBFixture()
        defer { fixture.close() }

        try fixture.insertHandle(rowID: 1, id: "+15551130001", service: "iMessage")
        try fixture.insertHandle(rowID: 2, id: "+15551130002", service: "iMessage")
        try fixture.insertChat(rowID: 1, guid: "chat-reply", style: 43, chatIdentifier: "reply-group")
        try fixture.insertChatHandleJoin(chatID: 1, handleID: 1)
        try fixture.insertChatHandleJoin(chatID: 1, handleID: 2)

        try fixture.insertMessage(
            rowID: 1, guid: "original-guid-3", handleID: 1, service: "iMessage",
            dateNanoseconds: 700_000_000_000_000_000, isFromMe: false
        )
        try fixture.insertChatMessageJoin(chatID: 1, messageID: 1)

        try fixture.insertMessage(
            rowID: 2, guid: "reply-guid-1", handleID: 2, service: "iMessage",
            dateNanoseconds: 700_000_001_000_000_000, isFromMe: false,
            threadOriginatorGuid: "original-guid-3"
        )
        try fixture.insertChatMessageJoin(chatID: 1, messageID: 2)
        fixture.close()

        let extract = try ChatDatabase.extract(path: fixture.url.path)

        XCTAssertEqual(extract.interactions.count, 1)
        let interaction = try XCTUnwrap(extract.interactions.first)
        XCTAssertEqual(interaction.actorHandleRowID, 2)
        XCTAssertEqual(interaction.targetHandleRowID, 1)
    }

    // Test 14: all three of Apple's prefixed guid forms resolve to the same bare target.
    func testPrefixedGUIDFormsAllResolveToTheirBareTarget() throws {
        let fixture = try ChatDBFixture()
        defer { fixture.close() }

        try fixture.insertHandle(rowID: 1, id: "+15551140001", service: "iMessage")
        try fixture.insertHandle(rowID: 2, id: "+15551140002", service: "iMessage")
        try fixture.insertChat(rowID: 1, guid: "chat-prefix", style: 43, chatIdentifier: "prefix-group")
        try fixture.insertChatHandleJoin(chatID: 1, handleID: 1)
        try fixture.insertChatHandleJoin(chatID: 1, handleID: 2)

        try fixture.insertMessage(
            rowID: 1, guid: "bare-original", handleID: 1, service: "iMessage",
            dateNanoseconds: 700_000_000_000_000_000, isFromMe: false
        )
        try fixture.insertChatMessageJoin(chatID: 1, messageID: 1)

        let prefixedForms = ["p:0/bare-original", "p:1/bare-original", "bp:bare-original"]
        var nextRowID: Int64 = 2
        for prefixed in prefixedForms {
            try fixture.insertMessage(
                rowID: nextRowID, guid: "tapback-\(nextRowID)", handleID: 2, service: "iMessage",
                dateNanoseconds: 700_000_001_000_000_000, isFromMe: false,
                associatedMessageGuid: prefixed, associatedMessageType: 2000
            )
            try fixture.insertChatMessageJoin(chatID: 1, messageID: nextRowID)
            nextRowID += 1
        }
        fixture.close()

        let extract = try ChatDatabase.extract(path: fixture.url.path)

        XCTAssertEqual(extract.interactions.count, 3, "all three prefixed forms must resolve to the same bare-original target")
        for interaction in extract.interactions {
            XCTAssertEqual(interaction.targetHandleRowID, 1)
            XCTAssertEqual(interaction.actorHandleRowID, 2)
        }
    }

    // Test 15: a self-tapback (reacting to one's own message, same raw handle) is dropped.
    func testSelfTapbackIsDropped() throws {
        let fixture = try ChatDBFixture()
        defer { fixture.close() }

        try fixture.insertHandle(rowID: 1, id: "+15551150001", service: "iMessage")
        try fixture.insertChat(rowID: 1, guid: "chat-self", style: 43, chatIdentifier: "self-group")
        try fixture.insertChatHandleJoin(chatID: 1, handleID: 1)

        try fixture.insertMessage(
            rowID: 1, guid: "original-guid-self", handleID: 1, service: "iMessage",
            dateNanoseconds: 700_000_000_000_000_000, isFromMe: false
        )
        try fixture.insertChatMessageJoin(chatID: 1, messageID: 1)

        try fixture.insertMessage(
            rowID: 2, guid: "tapback-guid-self", handleID: 1, service: "iMessage",
            dateNanoseconds: 700_000_001_000_000_000, isFromMe: false,
            associatedMessageGuid: "original-guid-self", associatedMessageType: 2000
        )
        try fixture.insertChatMessageJoin(chatID: 1, messageID: 2)
        fixture.close()

        let extract = try ChatDatabase.extract(path: fixture.url.path)

        XCTAssertTrue(extract.interactions.isEmpty, "tapbacking one's own message is not evidence of knowing someone else")
    }

    // Test 16: an unresolvable target guid (no message in this db carries it) is skipped silently.
    func testUnresolvableTargetGUIDIsSkippedSilently() throws {
        let fixture = try ChatDBFixture()
        defer { fixture.close() }

        try fixture.insertHandle(rowID: 1, id: "+15551160001", service: "iMessage")
        try fixture.insertChat(rowID: 1, guid: "chat-unresolvable", style: 43, chatIdentifier: "unresolvable-group")
        try fixture.insertChatHandleJoin(chatID: 1, handleID: 1)

        try fixture.insertMessage(
            rowID: 1, guid: "tapback-guid-dangling", handleID: 1, service: "iMessage",
            dateNanoseconds: 700_000_000_000_000_000, isFromMe: false,
            associatedMessageGuid: "no-such-original-guid", associatedMessageType: 2000
        )
        try fixture.insertChatMessageJoin(chatID: 1, messageID: 1)
        fixture.close()

        let extract = try ChatDatabase.extract(path: fixture.url.path)

        XCTAssertTrue(extract.interactions.isEmpty)
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
