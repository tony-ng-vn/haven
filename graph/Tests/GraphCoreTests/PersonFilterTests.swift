import XCTest
@testable import GraphCore

final class PersonFilterTests: XCTestCase {

    // MARK: - Fixture helpers (pure Swift values; no SQLite fixture needed for pure logic)

    /// Fixed UTC calendar so "distinct calendar day" tests are not host-timezone-dependent.
    /// Production code defaults to Calendar.current; tests inject this instead.
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

    private func person(
        id: String,
        identifiers: Set<String>,
        handleRowIDs: Set<Int64>,
        name: String? = nil,
        hasContactCard: Bool = false
    ) -> Person {
        Person(
            id: id,
            identifiers: identifiers,
            handleRowIDs: handleRowIDs,
            name: name,
            thumbnailImageData: nil,
            contactCardIDs: hasContactCard ? ["card-\(id)"] : [],
            hasContactCard: hasContactCard
        )
    }

    private func chat(rowID: Int64, style: Int, members: [Int64]) -> RawChat {
        RawChat(
            rowID: rowID,
            guid: "chat-\(rowID)",
            style: style,
            chatIdentifier: nil,
            serviceName: nil,
            displayName: nil,
            memberHandleRowIDs: members
        )
    }

    private func message(
        rowID: Int64,
        chatRowID: Int64,
        handleRowID: Int64?,
        isFromMe: Bool,
        date: Date
    ) -> RawMessage {
        RawMessage(rowID: rowID, chatRowID: chatRowID, handleRowID: handleRowID, isFromMe: isFromMe, date: date)
    }

    private func extract(chats: [RawChat], messages: [RawMessage]) -> ChatExtract {
        ChatExtract(handles: [], chats: chats, messages: messages, unjoinedMessageCount: 0)
    }

    // MARK: - Rule 1: shortcode

    func testShortcodeIsRemoved() {
        let p = person(id: "12345", identifiers: ["12345"], handleRowIDs: [1])
        let result = PersonFilter.apply(extract: extract(chats: [], messages: []), people: [p], calendar: utc)

        XCTAssertTrue(result.kept.isEmpty)
        XCTAssertEqual(result.removed.map(\.reason), [.shortcode])
    }

    // MARK: - Rule 2: alphanumeric sender

    func testAlphanumericSenderIsRemoved() {
        let p = person(id: "ALERT123", identifiers: ["ALERT123"], handleRowIDs: [2])
        let result = PersonFilter.apply(extract: extract(chats: [], messages: []), people: [p], calendar: utc)

        XCTAssertEqual(result.removed.map(\.reason), [.alphanumericSender])
    }

    // Required: an email-only person with a replied, live thread is kept (email never
    // trips the alphanumeric rule).
    func testEmailOnlyPersonWithRepliedLiveThreadIsKept() {
        let p = person(id: "alice@example.com", identifiers: ["alice@example.com"], handleRowIDs: [3])
        let c = chat(rowID: 100, style: 45, members: [3])
        let messages = [
            message(rowID: 1, chatRowID: 100, handleRowID: 3, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 2, chatRowID: 100, handleRowID: nil, isFromMe: true, date: utcDate(2024, 1, 5)),
        ]
        let result = PersonFilter.apply(extract: extract(chats: [c], messages: messages), people: [p], calendar: utc)

        XCTAssertEqual(result.kept.map(\.id), ["alice@example.com"])
        XCTAssertTrue(result.removed.isEmpty)
    }

    // Additional (beyond the required list): the stronger case the rule actually guards
    // against. "Every identifier is .other" must fail as soon as ANY identifier is an
    // email, even when merged with an alphanumeric-shaped identifier from another handle.
    func testMergedAlphanumericAndEmailIdentifierNeverTripsAlphanumericRule() {
        let p = person(
            id: "alice@example.com",
            identifiers: ["ALERT123", "alice@example.com"],
            handleRowIDs: [4, 5]
        )
        let c = chat(rowID: 101, style: 45, members: [4])
        let messages = [
            message(rowID: 1, chatRowID: 101, handleRowID: 4, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 2, chatRowID: 101, handleRowID: nil, isFromMe: true, date: utcDate(2024, 1, 5)),
        ]
        let result = PersonFilter.apply(extract: extract(chats: [c], messages: messages), people: [p], calendar: utc)

        XCTAssertTrue(result.removed.isEmpty, "an identifier being alphanumeric-shaped must not matter once the person also has an email")
        XCTAssertEqual(result.kept.count, 1)
    }

    // MARK: - Rule 3: never replied

    func testNeverRepliedIsRemovedWithoutCard() {
        let p = person(id: "+14155550001", identifiers: ["+14155550001"], handleRowIDs: [10])
        let c = chat(rowID: 200, style: 45, members: [10])
        let messages = [
            message(rowID: 1, chatRowID: 200, handleRowID: 10, isFromMe: false, date: utcDate(2024, 1, 1))
        ]
        let result = PersonFilter.apply(extract: extract(chats: [c], messages: messages), people: [p], calendar: utc)

        XCTAssertEqual(result.removed.map(\.reason), [.neverReplied])
    }

    func testNeverRepliedSparedByContactCard() {
        let p = person(id: "+14155550001", identifiers: ["+14155550001"], handleRowIDs: [11], hasContactCard: true)
        let c = chat(rowID: 201, style: 45, members: [11])
        let messages = [
            message(rowID: 1, chatRowID: 201, handleRowID: 11, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 2, chatRowID: 201, handleRowID: 11, isFromMe: false, date: utcDate(2024, 1, 5)),
        ]
        let result = PersonFilter.apply(extract: extract(chats: [c], messages: messages), people: [p], calendar: utc)

        XCTAssertTrue(result.removed.isEmpty)
        XCTAssertEqual(result.kept.count, 1)
    }

    func testNeverRepliedSparedBySharingThreeMemberGroupWithCardMatchedPerson() {
        let personA = person(id: "+14155550002", identifiers: ["+14155550002"], handleRowIDs: [20])
        let personB = person(id: "+14155550003", identifiers: ["+14155550003"], handleRowIDs: [21], hasContactCard: true)
        let personC = person(id: "+14155550009", identifiers: ["+14155550009"], handleRowIDs: [22])

        let oneToOne = chat(rowID: 300, style: 45, members: [20])
        let group = chat(rowID: 301, style: 43, members: [20, 21, 22]) // 3 members: a true group

        let messages = [
            // Never-replied, but live (2 distinct days) so rule 4 is not what saves this person.
            message(rowID: 1, chatRowID: 300, handleRowID: 20, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 2, chatRowID: 300, handleRowID: 20, isFromMe: false, date: utcDate(2024, 1, 5)),
        ]

        let result = PersonFilter.apply(
            extract: extract(chats: [oneToOne, group], messages: messages),
            people: [personA, personB, personC],
            calendar: utc
        )

        // personB and personC's own fates are not the point of this test (personB has zero
        // activity of its own and would independently trip rule 4); only personA's outcome
        // -- spared from never-replied by sharing a group with a carded person -- matters here.
        XCTAssertFalse(result.removed.contains { $0.person.id == personA.id }, "sharing a 3-member group with a carded person must spare never-replied")
        XCTAssertTrue(result.kept.contains { $0.id == personA.id })
    }

    func testNeverRepliedNotSparedByTwoMemberStyle43ChatWithCardMatchedPerson() {
        let personA = person(id: "+14155550004", identifiers: ["+14155550004"], handleRowIDs: [30])
        let personB = person(id: "+14155550005", identifiers: ["+14155550005"], handleRowIDs: [31], hasContactCard: true)

        let oneToOne = chat(rowID: 400, style: 45, members: [30])
        // Exactly 2 members: reclassified as one-to-one, does NOT count as a group for the override.
        let twoMemberGroupStyle = chat(rowID: 401, style: 43, members: [30, 31])

        let messages = [
            message(rowID: 1, chatRowID: 400, handleRowID: 30, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 2, chatRowID: 400, handleRowID: 30, isFromMe: false, date: utcDate(2024, 1, 5)),
        ]

        let result = PersonFilter.apply(
            extract: extract(chats: [oneToOne, twoMemberGroupStyle], messages: messages),
            people: [personA, personB],
            calendar: utc
        )

        XCTAssertEqual(result.removed.first { $0.person.id == personA.id }?.reason, .neverReplied)
    }

    // MARK: - Rule 4: liveness

    func testSingleDayThreadPersonIsRemovedNotLive() {
        let p = person(id: "+14155550006", identifiers: ["+14155550006"], handleRowIDs: [40])
        let c = chat(rowID: 500, style: 45, members: [40])
        let messages = [
            message(rowID: 1, chatRowID: 500, handleRowID: 40, isFromMe: false, date: utcDate(2024, 1, 1, hour: 9)),
            message(rowID: 2, chatRowID: 500, handleRowID: nil, isFromMe: true, date: utcDate(2024, 1, 1, hour: 14)),
        ]
        let result = PersonFilter.apply(extract: extract(chats: [c], messages: messages), people: [p], calendar: utc)

        XCTAssertEqual(result.removed.map(\.reason), [.notLive])
    }

    func testTwoDayThreadPersonIsKept() {
        let p = person(id: "+14155550006", identifiers: ["+14155550006"], handleRowIDs: [41])
        let c = chat(rowID: 501, style: 45, members: [41])
        let messages = [
            message(rowID: 1, chatRowID: 501, handleRowID: 41, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 2, chatRowID: 501, handleRowID: nil, isFromMe: true, date: utcDate(2024, 1, 2)),
        ]
        let result = PersonFilter.apply(extract: extract(chats: [c], messages: messages), people: [p], calendar: utc)

        XCTAssertTrue(result.removed.isEmpty)
        XCTAssertEqual(result.kept.count, 1)
    }

    func testZeroMessageLurkerInLiveThreeMemberGroupIsKept() {
        let lurker = person(id: "+14155550007", identifiers: ["+14155550007"], handleRowIDs: [50])
        let poster1 = person(id: "+14155550010", identifiers: ["+14155550010"], handleRowIDs: [51])
        let poster2 = person(id: "+14155550011", identifiers: ["+14155550011"], handleRowIDs: [52])

        // Roster from chat_handle_join, not message activity: the lurker is a member with
        // zero messages, and still gets the group's liveness.
        let group = chat(rowID: 600, style: 43, members: [50, 51, 52])
        let messages = [
            message(rowID: 1, chatRowID: 600, handleRowID: 51, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 2, chatRowID: 600, handleRowID: 52, isFromMe: false, date: utcDate(2024, 1, 5)),
        ]

        let result = PersonFilter.apply(
            extract: extract(chats: [group], messages: messages),
            people: [lurker, poster1, poster2],
            calendar: utc
        )

        XCTAssertTrue(result.kept.contains { $0.id == lurker.id })
        XCTAssertFalse(result.removed.contains { $0.person.id == lurker.id })
    }

    // MARK: - Ambiguity resolves toward keeping

    func testRepliedOnceAmbiguousPersonIsKept() {
        let p = person(id: "+14155550008", identifiers: ["+14155550008"], handleRowIDs: [60])
        let c = chat(rowID: 700, style: 45, members: [60])
        let messages = [
            message(rowID: 1, chatRowID: 700, handleRowID: 60, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 2, chatRowID: 700, handleRowID: 60, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 3, chatRowID: 700, handleRowID: nil, isFromMe: true, date: utcDate(2024, 1, 2)),
        ]
        let result = PersonFilter.apply(extract: extract(chats: [c], messages: messages), people: [p], calendar: utc)

        XCTAssertTrue(result.removed.isEmpty)
        XCTAssertEqual(result.kept.count, 1)
    }

    // MARK: - Reason precedence

    func testReasonPrecedenceShortcodeAlsoNeverRepliedReportsShortcode() {
        let p = person(id: "12345", identifiers: ["12345"], handleRowIDs: [70])
        let c = chat(rowID: 800, style: 45, members: [70])
        let messages = [
            message(rowID: 1, chatRowID: 800, handleRowID: 70, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 2, chatRowID: 800, handleRowID: 70, isFromMe: false, date: utcDate(2024, 1, 5)),
        ]
        let result = PersonFilter.apply(extract: extract(chats: [c], messages: messages), people: [p], calendar: utc)

        XCTAssertEqual(result.removed.map(\.reason), [.shortcode])
    }

    // Overrides outrank rules 1-3, but never rule 4: a carded, shortcode-shaped person with
    // only a single-day thread still gets removed, and for the liveness reason specifically,
    // not silently kept and not reported as .shortcode.
    func testCardedShortcodePersonWithSingleDayThreadFallsThroughToNotLive() {
        let p = person(id: "12345", identifiers: ["12345"], handleRowIDs: [80], hasContactCard: true)
        let c = chat(rowID: 900, style: 45, members: [80])
        let messages = [
            message(rowID: 1, chatRowID: 900, handleRowID: 80, isFromMe: false, date: utcDate(2024, 1, 1, hour: 9)),
            message(rowID: 2, chatRowID: 900, handleRowID: nil, isFromMe: true, date: utcDate(2024, 1, 1, hour: 14)),
        ]
        let result = PersonFilter.apply(extract: extract(chats: [c], messages: messages), people: [p], calendar: utc)

        XCTAssertEqual(result.removed.map(\.reason), [.notLive])
    }
}
