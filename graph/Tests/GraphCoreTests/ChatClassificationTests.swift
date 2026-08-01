import XCTest
@testable import GraphCore

final class ChatClassificationTests: XCTestCase {

    private func chat(rowID: Int64, guid: String, style: Int, members: [Int64]) -> RawChat {
        RawChat(rowID: rowID, guid: guid, style: style, chatIdentifier: nil, serviceName: nil, displayName: nil, memberHandleRowIDs: members)
    }

    // Requirement 1 (classifier half): 2 raw handles resolving to 2 different people is a
    // real group. chat_handle_join never lists the user, so "2" here means two OTHER people.
    func testTwoHandleRosterOfTwoDifferentPeopleClassifiesAsGroup() {
        let c = chat(rowID: 1, guid: "g1", style: 43, members: [10, 11])
        let kinds = ChatClassification.classify(chats: [c], handleToPersonID: [10: "personA", 11: "personB"])
        XCTAssertEqual(kinds[1], .group)
    }

    // Requirement 2: 2 raw handles that both resolve to ONE merged person (their phone and
    // their email, say) are still exactly one distinct person -- one-to-one, not a group.
    func testTwoHandleRosterResolvingToSamePersonClassifiesAsOneToOne() {
        let c = chat(rowID: 2, guid: "g2", style: 43, members: [20, 21])
        let kinds = ChatClassification.classify(chats: [c], handleToPersonID: [20: "personA", 21: "personA"])
        XCTAssertEqual(kinds[2], .oneToOne)
    }

    // Requirement 3: a style-43 chat with a raw roster of 1 can only ever resolve to at most
    // one distinct person -- one-to-one, same as if it were style 45.
    func testSingleHandleRosterStyle43ClassifiesAsOneToOne() {
        let c = chat(rowID: 3, guid: "g3", style: 43, members: [30])
        let kinds = ChatClassification.classify(chats: [c], handleToPersonID: [30: "personA"])
        XCTAssertEqual(kinds[3], .oneToOne)
    }

    // Requirement 4: style 45 is always one-to-one, independent of resolution -- unaffected
    // by this fix (it never inspects handleToPersonID at all for this style).
    func testStyle45SingleHandleRosterIsAlwaysOneToOneRegardlessOfResolution() {
        let resolved = chat(rowID: 4, guid: "g4", style: 45, members: [40])
        let unresolved = chat(rowID: 5, guid: "g5", style: 45, members: [41])
        let kinds = ChatClassification.classify(chats: [resolved, unresolved], handleToPersonID: [40: "personA"])
        XCTAssertEqual(kinds[4], .oneToOne)
        XCTAssertEqual(kinds[5], .oneToOne, "style 45 does not even require the handle to resolve to anyone")
    }

    // Requirement 6: 3+ distinct resolved people is unchanged behavior -- still a group.
    func testThreeDistinctResolvedPeopleClassifiesAsGroupUnchanged() {
        let c = chat(rowID: 6, guid: "g6", style: 43, members: [60, 61, 62])
        let kinds = ChatClassification.classify(
            chats: [c],
            handleToPersonID: [60: "personA", 61: "personB", 62: "personC"]
        )
        XCTAssertEqual(kinds[6], .group)
    }

    // Degenerate: an empty roster, or a roster where every handle is unresolved, is left
    // unclassified -- same as before this fix, never miscounted as either kind.
    func testEmptyOrFullyUnresolvedRosterIsNotClassified() {
        let empty = chat(rowID: 7, guid: "g7", style: 43, members: [])
        let unresolved = chat(rowID: 8, guid: "g8", style: 43, members: [80, 81])
        let kinds = ChatClassification.classify(chats: [empty, unresolved], handleToPersonID: [:])
        XCTAssertNil(kinds[7])
        XCTAssertNil(kinds[8])
    }

    // A handle resolving to nobody (removed, or never a real contact) contributes nothing to
    // the distinct-people count -- this is what makes "one resolved, one unresolved" one-to-one.
    func testOneResolvedPlusOneUnresolvedHandleStillClassifiesAsOneToOne() {
        let c = chat(rowID: 9, guid: "g9", style: 43, members: [90, 91])
        let kinds = ChatClassification.classify(chats: [c], handleToPersonID: [90: "personA"])
        XCTAssertEqual(kinds[9], .oneToOne)
    }
}
