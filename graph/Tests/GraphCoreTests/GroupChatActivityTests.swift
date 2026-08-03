import XCTest
@testable import GraphCore

/// GraphBuilder.buildDetailed's GroupChatActivity output: the acquaintance layer's day-set data
/// (PLAN.md, "The acquaintance layer"). GraphBuilderTests already covers Graph/GraphEdge itself
/// in this exact fixture style; these tests cover the second half of buildDetailed's result.
final class GroupChatActivityTests: XCTestCase {

    // MARK: - Fixture helpers (same shapes as GraphBuilderTests)

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

    private func person(id: String, handleRowIDs: Set<Int64>) -> Person {
        Person(
            id: id,
            identifiers: [id],
            handleRowIDs: handleRowIDs,
            name: nil,
            thumbnailImageData: nil,
            contactCardIDs: [],
            hasContactCard: false
        )
    }

    private func chat(rowID: Int64, guid: String, members: [Int64], displayName: String? = nil) -> RawChat {
        RawChat(rowID: rowID, guid: guid, style: 43, chatIdentifier: nil, serviceName: nil, displayName: displayName, memberHandleRowIDs: members)
    }

    private func message(rowID: Int64, chatRowID: Int64, handleRowID: Int64?, isFromMe: Bool, date: Date) -> RawMessage {
        RawMessage(rowID: rowID, chatRowID: chatRowID, handleRowID: handleRowID, isFromMe: isFromMe, date: date)
    }

    private func extract(chats: [RawChat], messages: [RawMessage]) -> ChatExtract {
        ChatExtract(handles: [], chats: chats, messages: messages, unjoinedMessageCount: 0)
    }

    // MARK: - Test 1: a dead group (isLive == false) still gets a GroupChatActivity entry

    func testDeadGroupStillProducesGroupChatActivityEntry() {
        let a = person(id: "+14155551000", handleRowIDs: [1000])
        let b = person(id: "+14155551001", handleRowIDs: [1001])
        let c = person(id: "+14155551002", handleRowIDs: [1002])
        let group = chat(rowID: 900, guid: "dead-group", members: [1000, 1001, 1002])
        let messages = [
            // A single day of activity: isLive requires 2+, so this group's GraphNode is dead.
            message(rowID: 1, chatRowID: 900, handleRowID: 1000, isFromMe: false, date: utcDate(2024, 1, 1))
        ]

        let built = GraphBuilder.buildDetailed(extract: extract(chats: [group], messages: messages), keptPeople: [a, b, c], calendar: utc)

        let groupNode = built.graph.nodes.first { $0.id == "chat:dead-group" }
        XCTAssertEqual(groupNode?.isLive, false, "sanity check: this group really is dead")

        let activity = built.groupChatActivity.first { $0.chatId == "chat:dead-group" }
        XCTAssertNotNil(activity, "a dead group's activity must still be produced -- acquaintance evidence does not expire with liveness (PLAN.md)")
        XCTAssertEqual(activity?.roster, ["+14155551000", "+14155551001", "+14155551002"])
        XCTAssertEqual(activity?.activeDaysByPersonID["+14155551000"]?.count, 1)
        XCTAssertEqual(activity?.activeDaysByPersonID["+14155551001"], [], "a roster member who never posted still has an entry, just an empty day set")
    }

    // MARK: - Test 2: two service-split chat rows (same roster, same name) produce exactly ONE
    // GroupChatActivity entry with unioned per-member day sets -- pairs must never be double
    // counted across the pre-merge rows GraphBuilder's own roster merge already folded together.

    func testServiceSplitChatsProduceOneUnionedGroupChatActivityEntry() throws {
        let a = person(id: "+14155552000", handleRowIDs: [2000])
        let b = person(id: "+14155552001", handleRowIDs: [2001])
        // Same roster, same name, different guid/service -- GraphBuilder's roster-based merge
        // (mergedGroupChats) already folds these into one group node; min-by-guid picks "a-sms".
        let imessageChat = chat(rowID: 901, guid: "z-imessage", members: [2000, 2001], displayName: "Book club")
        let smsChat = chat(rowID: 902, guid: "a-sms", members: [2000, 2001], displayName: "Book club")
        let messages = [
            // a posts only on the imessage row, on day 1.
            message(rowID: 1, chatRowID: 901, handleRowID: 2000, isFromMe: false, date: utcDate(2024, 1, 1)),
            // b posts only on the sms row, on day 1 too -- co-active if and only if the union
            // is computed at the message level, matching GraphBuilder's own edge-strength rule.
            message(rowID: 2, chatRowID: 902, handleRowID: 2001, isFromMe: false, date: utcDate(2024, 1, 1)),
        ]

        let built = GraphBuilder.buildDetailed(
            extract: extract(chats: [imessageChat, smsChat], messages: messages),
            keptPeople: [a, b],
            calendar: utc
        )

        XCTAssertEqual(built.groupChatActivity.count, 1, "one human group, one GroupChatActivity entry, not one per service-split row")
        let activity = try XCTUnwrap(built.groupChatActivity.first)
        XCTAssertEqual(activity.chatId, "chat:a-sms", "min-by-guid, matching the group node id GraphBuilder already picked")
        XCTAssertEqual(activity.roster, ["+14155552000", "+14155552001"])
        XCTAssertEqual(activity.activeDaysByPersonID["+14155552000"]?.count, 1)
        XCTAssertEqual(activity.activeDaysByPersonID["+14155552001"]?.count, 1)

        // The pay-off: derived over this ONE entry, the pair's co-active-day bonus counts the
        // union's shared day exactly once (+0.1), not twice across two pre-merge rows.
        let acquaintances = AcquaintanceDerivation.derive(groupChatActivity: built.groupChatActivity, fullyAcquaintedRosterKeys: [])
        let pair = try XCTUnwrap(acquaintances.first { $0.a == "+14155552000" && $0.b == "+14155552001" })
        XCTAssertEqual(pair.score, 1.1, accuracy: 1e-9, "n=2 base 1.0 + one shared day * 0.1, counted once across the merged chat")
        XCTAssertEqual(pair.evidence.count, 1, "one shared chat, one evidence entry -- never one per pre-merge row")
    }
}
