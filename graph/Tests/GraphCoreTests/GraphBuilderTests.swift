import XCTest
@testable import GraphCore

final class GraphBuilderTests: XCTestCase {

    // MARK: - Fixture helpers (pure Swift values; no SQLite fixture needed for pure logic)

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
        handleRowIDs: Set<Int64>,
        name: String? = nil,
        hasContactCard: Bool = false
    ) -> Person {
        Person(
            id: id,
            identifiers: [id],
            handleRowIDs: handleRowIDs,
            name: name,
            thumbnailImageData: nil,
            contactCardIDs: hasContactCard ? ["card-\(id)"] : [],
            hasContactCard: hasContactCard
        )
    }

    private func chat(rowID: Int64, guid: String, style: Int, members: [Int64], displayName: String? = nil) -> RawChat {
        RawChat(
            rowID: rowID,
            guid: guid,
            style: style,
            chatIdentifier: nil,
            serviceName: nil,
            displayName: displayName,
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

    private func groupNodeID(_ guid: String) -> String { "chat:\(guid)" }

    // MARK: - Test 1: one-to-one edge, strength = distinct active days

    func testKeptPersonWithRepliedTwoDayThreadGetsUserEdgeWithStrengthTwo() {
        let p = person(id: "+14155550001", handleRowIDs: [1])
        let c = chat(rowID: 1, guid: "c1", style: 45, members: [1])
        let messages = [
            message(rowID: 1, chatRowID: 1, handleRowID: 1, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 2, chatRowID: 1, handleRowID: nil, isFromMe: true, date: utcDate(2024, 1, 2)),
        ]
        let graph = GraphBuilder.build(extract: extract(chats: [c], messages: messages), keptPeople: [p], calendar: utc)

        let edge = graph.edges.first { $0.reason == .oneToOneThread }
        XCTAssertNotNil(edge)
        XCTAssertEqual(Set([edge?.nodeIDA, edge?.nodeIDB]), Set(["user", p.id]))
        XCTAssertEqual(edge?.strength, 2.0)
        XCTAssertEqual(edge?.involvesUser, true)
        XCTAssertEqual(edge?.source, .imessage)
    }

    // MARK: - Test 2: a roster of 2 raw handles where only ONE resolves to a kept person
    // stays one-to-one (the other handle belongs to nobody kept, so exactly 1 distinct
    // person is actually in the roster). This test used to be named and commented as if ANY
    // 2-raw-handle style-43 roster meant "the user plus one other" -- that assumption was
    // wrong: chat_handle_join never lists the user (see ChatClassification.swift). The
    // assertions below still hold, but for the corrected reason: distinct RESOLVED people,
    // not raw handle count.

    func testTwoRawHandleRosterWithOnlyOneResolvedPersonStaysOneToOne() {
        let p = person(id: "+14155550010", handleRowIDs: [10])
        // Handle 11 resolves to no kept Person at all (removed, or never a real contact) --
        // exactly one distinct person is actually in this roster, not two.
        let c = chat(rowID: 2, guid: "c2", style: 43, members: [10, 11])
        let messages = [
            message(rowID: 1, chatRowID: 2, handleRowID: 10, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 2, chatRowID: 2, handleRowID: 10, isFromMe: false, date: utcDate(2024, 1, 3)),
        ]
        let graph = GraphBuilder.build(extract: extract(chats: [c], messages: messages), keptPeople: [p], calendar: utc)

        XCTAssertFalse(graph.nodes.contains { $0.kind == .group })
        XCTAssertTrue(graph.edges.allSatisfy { $0.reason != .groupMembership && $0.reason != .userGroupMembership })

        let edge = graph.edges.first { $0.reason == .oneToOneThread }
        XCTAssertNotNil(edge)
        XCTAssertEqual(edge?.strength, 2.0)
    }

    // MARK: - Test 3: live 4-member group with a lurker

    func testLiveFourMemberGroupWithLurkerKeepsZeroStrengthEdge() {
        let a = person(id: "+14155550020", handleRowIDs: [20])
        let b = person(id: "+14155550021", handleRowIDs: [21])
        let c = person(id: "+14155550022", handleRowIDs: [22])
        let lurker = person(id: "+14155550023", handleRowIDs: [23])

        let group = chat(rowID: 3, guid: "g3", style: 43, members: [20, 21, 22, 23])
        let messages = [
            message(rowID: 1, chatRowID: 3, handleRowID: 20, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 2, chatRowID: 3, handleRowID: 21, isFromMe: false, date: utcDate(2024, 1, 2)),
        ]
        let graph = GraphBuilder.build(
            extract: extract(chats: [group], messages: messages),
            keptPeople: [a, b, c, lurker],
            calendar: utc
        )

        let groupNode = graph.nodes.first { $0.id == groupNodeID("g3") }
        XCTAssertEqual(groupNode?.kind, .group)
        XCTAssertEqual(groupNode?.isLive, true)

        let membershipEdges = graph.edges.filter { $0.reason == .groupMembership }
        XCTAssertEqual(membershipEdges.count, 4)

        let lurkerEdge = membershipEdges.first { $0.nodeIDA == lurker.id || $0.nodeIDB == lurker.id }
        XCTAssertEqual(lurkerEdge?.strength, 0.0)
    }

    // MARK: - Test 4: dead group still built

    func testDeadSingleDayGroupIsBuiltWithIsLiveFalse() {
        let e = person(id: "+14155550030", handleRowIDs: [30])
        let f = person(id: "+14155550031", handleRowIDs: [31])
        let g = person(id: "+14155550032", handleRowIDs: [32])

        let group = chat(rowID: 4, guid: "g4", style: 43, members: [30, 31, 32])
        let messages = [
            message(rowID: 1, chatRowID: 4, handleRowID: 30, isFromMe: false, date: utcDate(2024, 1, 1, hour: 9))
        ]
        let graph = GraphBuilder.build(
            extract: extract(chats: [group], messages: messages),
            keptPeople: [e, f, g],
            calendar: utc
        )

        let groupNode = graph.nodes.first { $0.id == groupNodeID("g4") }
        XCTAssertEqual(groupNode?.isLive, false)

        let membershipEdges = graph.edges.filter { $0.reason == .groupMembership }
        XCTAssertEqual(membershipEdges.count, 3, "edges are still built for a dead group")
    }

    // MARK: - Test 5: removed person in a live group roster

    func testRemovedPersonInLiveGroupRosterGetsNoNodeOrEdge() {
        let kept1 = person(id: "+14155550040", handleRowIDs: [40])
        let kept2 = person(id: "+14155550041", handleRowIDs: [41])
        // Handle 42 has no corresponding Person: simulates a removed member, still in the
        // raw roster (chat_handle_join is historical truth) and still able to post.
        let group = chat(rowID: 5, guid: "g5", style: 43, members: [40, 41, 42])
        let messages = [
            message(rowID: 1, chatRowID: 5, handleRowID: 40, isFromMe: false, date: utcDate(2024, 1, 1)),
            // The removed member's own message still counts toward the chat's liveness:
            // liveness is a property of the chat, not filtered by person humanness.
            message(rowID: 2, chatRowID: 5, handleRowID: 42, isFromMe: false, date: utcDate(2024, 1, 2)),
        ]
        let graph = GraphBuilder.build(
            extract: extract(chats: [group], messages: messages),
            keptPeople: [kept1, kept2],
            calendar: utc
        )

        let groupNode = graph.nodes.first { $0.id == groupNodeID("g5") }
        XCTAssertEqual(groupNode?.isLive, true, "the group is still live from the removed member's own message")

        let membershipEdges = graph.edges.filter { $0.reason == .groupMembership }
        XCTAssertEqual(membershipEdges.count, 2, "only the two kept members get a membership edge")
        XCTAssertFalse(graph.nodes.contains { $0.id == "42" })
    }

    // MARK: - Test 6: userGroupMembership edge strength = is_from_me distinct days

    func testUserGroupMembershipEdgeCountsIsFromMeDaysOnly() {
        let a = person(id: "+14155550050", handleRowIDs: [50])
        let b = person(id: "+14155550051", handleRowIDs: [51])
        let c = person(id: "+14155550052", handleRowIDs: [52])

        let group = chat(rowID: 6, guid: "g6", style: 43, members: [50, 51, 52])
        let messages = [
            message(rowID: 1, chatRowID: 6, handleRowID: 50, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 2, chatRowID: 6, handleRowID: nil, isFromMe: true, date: utcDate(2024, 1, 1)),
            message(rowID: 3, chatRowID: 6, handleRowID: nil, isFromMe: true, date: utcDate(2024, 1, 2)),
        ]
        let graph = GraphBuilder.build(
            extract: extract(chats: [group], messages: messages),
            keptPeople: [a, b, c],
            calendar: utc
        )

        let userGroupEdge = graph.edges.first { $0.reason == .userGroupMembership }
        XCTAssertNotNil(userGroupEdge)
        XCTAssertEqual(userGroupEdge?.strength, 2.0)
        XCTAssertEqual(userGroupEdge?.involvesUser, true)
        XCTAssertTrue(Set([userGroupEdge?.nodeIDA, userGroupEdge?.nodeIDB]).contains("user"))
        XCTAssertTrue(Set([userGroupEdge?.nodeIDA, userGroupEdge?.nodeIDB]).contains(groupNodeID("g6")))
    }

    // MARK: - Test 7: pruning, last-edge guard, involvesUser exemption, degree update

    func testPruneRemovesBelowThresholdEdgesExceptLastEdgeAndUserEdges() {
        // person100 is a lurker in TWO groups and has no one-to-one thread at all, so both
        // of its edges are non-user and prunable. This is the shape that actually exercises
        // the last-edge guard: a node whose only edges are two weak, non-user memberships.
        let lurker = person(id: "+14155550100", handleRowIDs: [100])
        let poster1 = person(id: "+14155550101", handleRowIDs: [101])
        let poster2 = person(id: "+14155550103", handleRowIDs: [103])

        let group1 = chat(rowID: 1001, guid: "g1", style: 43, members: [100, 101, 102])
        let group2 = chat(rowID: 1002, guid: "g2", style: 43, members: [100, 103, 104])

        let messages = [
            message(rowID: 1, chatRowID: 1001, handleRowID: 101, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 2, chatRowID: 1001, handleRowID: 101, isFromMe: false, date: utcDate(2024, 1, 2)),
            message(rowID: 3, chatRowID: 1002, handleRowID: 103, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 4, chatRowID: 1002, handleRowID: 103, isFromMe: false, date: utcDate(2024, 1, 2)),
        ]

        let built = GraphBuilder.build(
            extract: extract(chats: [group1, group2], messages: messages),
            keptPeople: [lurker, poster1, poster2],
            calendar: utc
        )

        // Before pruning: the lurker has exactly 2 edges (both group memberships, strength 0).
        let lurkerEdgesBefore = built.edges.filter { $0.nodeIDA == lurker.id || $0.nodeIDB == lurker.id }
        XCTAssertEqual(lurkerEdgesBefore.count, 2)
        XCTAssertEqual(built.nodes.first { $0.id == lurker.id }?.degree, 2)

        let pruned = GraphBuilder.prune(graph: built, minStrength: 1.0)

        // Deterministic, pinned result: exactly one of the lurker's two zero-strength edges
        // survives (the last-edge guard), the other is removed; the active posters' edges
        // and both userGroupMembership edges (involvesUser) are untouched.
        let lurkerEdgesAfter = pruned.edges.filter { $0.nodeIDA == lurker.id || $0.nodeIDB == lurker.id }
        XCTAssertEqual(lurkerEdgesAfter.count, 1, "the last-edge guard must keep exactly one")
        XCTAssertEqual(lurkerEdgesAfter.first?.strength, 0.0)

        XCTAssertEqual(pruned.edges.filter { $0.reason == .userGroupMembership }.count, 2, "user edges are exempt from pruning")
        XCTAssertTrue(pruned.edges.contains {
            $0.reason == .groupMembership && $0.strength == 2.0 && ($0.nodeIDA == poster1.id || $0.nodeIDB == poster1.id)
        })
        XCTAssertTrue(pruned.edges.contains {
            $0.reason == .groupMembership && $0.strength == 2.0 && ($0.nodeIDA == poster2.id || $0.nodeIDB == poster2.id)
        })

        XCTAssertEqual(pruned.edges.count, built.edges.count - 1)

        // Degree must be recomputed for the pruned graph, not carried over stale.
        XCTAssertEqual(pruned.nodes.first { $0.id == lurker.id }?.degree, 1)

        // Determinism: pin the exact surviving edge id, and confirm re-pruning is stable.
        XCTAssertEqual(lurkerEdgesAfter.first?.id, "+14155550100|chat:g2")
        let prunedAgain = GraphBuilder.prune(graph: built, minStrength: 1.0)
        XCTAssertEqual(pruned, prunedAgain)
    }

    // MARK: - Test 8: determinism of the full build

    func testGraphBuildIsDeterministicWithPinnedNodeAndEdgeOrder() {
        let a = person(id: "+14155550200", handleRowIDs: [200])
        let lurker = person(id: "+14155550201", handleRowIDs: [201])

        let oneToOne = chat(rowID: 7, guid: "c7", style: 45, members: [200])
        let group = chat(rowID: 8, guid: "g8", style: 43, members: [200, 201, 202])

        let messages = [
            message(rowID: 1, chatRowID: 7, handleRowID: 200, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 2, chatRowID: 7, handleRowID: nil, isFromMe: true, date: utcDate(2024, 1, 2)),
            message(rowID: 3, chatRowID: 8, handleRowID: 200, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 4, chatRowID: 8, handleRowID: 200, isFromMe: false, date: utcDate(2024, 1, 2)),
        ]
        let ext = extract(chats: [oneToOne, group], messages: messages)

        let first = GraphBuilder.build(extract: ext, keptPeople: [a, lurker], calendar: utc)
        let second = GraphBuilder.build(extract: ext, keptPeople: [a, lurker], calendar: utc)

        XCTAssertEqual(first, second)

        // Nodes: "+14155550200" < "+14155550201" < "chat:g8" < "user" (handle 202 has no
        // Person, so no node). Edges: canonical "smaller|larger" pair id, sorted.
        XCTAssertEqual(first.nodes.map(\.id), ["+14155550200", "+14155550201", "chat:g8", "user"])
        XCTAssertEqual(
            first.edges.map(\.id),
            [
                "+14155550200|chat:g8",
                "+14155550200|user",
                "+14155550201|chat:g8",
                "chat:g8|user",
            ]
        )
    }

    // MARK: - Test 9: degree computation, pinned on a small mixed fixture

    func testDegreeComputationPinnedOnMixedFixture() {
        // solo: one-to-one thread only (degree 1: edge to user).
        let solo = person(id: "+14155550300", handleRowIDs: [300])
        // both: one-to-one thread AND a group membership (degree 2).
        let both = person(id: "+14155550301", handleRowIDs: [301])
        // groupOnly: group membership only, no one-to-one thread (degree 1).
        let groupOnly = person(id: "+14155550302", handleRowIDs: [302])

        let solosChat = chat(rowID: 9, guid: "c9", style: 45, members: [300])
        let bothsChat = chat(rowID: 10, guid: "c10", style: 45, members: [301])
        let group = chat(rowID: 11, guid: "g11", style: 43, members: [301, 302, 303])

        let messages = [
            message(rowID: 1, chatRowID: 9, handleRowID: 300, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 2, chatRowID: 9, handleRowID: nil, isFromMe: true, date: utcDate(2024, 1, 2)),
            message(rowID: 3, chatRowID: 10, handleRowID: 301, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 4, chatRowID: 10, handleRowID: nil, isFromMe: true, date: utcDate(2024, 1, 2)),
            message(rowID: 5, chatRowID: 11, handleRowID: 301, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 6, chatRowID: 11, handleRowID: 302, isFromMe: false, date: utcDate(2024, 1, 2)),
        ]

        let graph = GraphBuilder.build(
            extract: extract(chats: [solosChat, bothsChat, group], messages: messages),
            keptPeople: [solo, both, groupOnly],
            calendar: utc
        )

        let degrees = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0.degree) })

        XCTAssertEqual(degrees[solo.id], 1)
        XCTAssertEqual(degrees[both.id], 2)
        XCTAssertEqual(degrees[groupOnly.id], 1)
        // g11's edges: groupMembership(both), groupMembership(groupOnly), userGroupMembership(user).
        XCTAssertEqual(degrees[groupNodeID("g11")], 3)
        // user's edges: oneToOneThread(solo), oneToOneThread(both), userGroupMembership(g11).
        XCTAssertEqual(degrees["user"], 3)
    }

    // MARK: - Roster reclassification: chat_handle_join lists only OTHER participants, never
    // the user, so a style-43 roster is classified by distinct RESOLVED PEOPLE, not raw
    // handle-row count (see ChatClassification.swift).

    // The headline regression: 2 raw handles belonging to 2 DIFFERENT kept people is a real
    // group, and its display name must survive onto the group node, not be silently dropped
    // because the roster was mistaken for "you plus one other."
    func testTwoHandleRosterOfTwoDifferentPeopleBecomesGroupNodeWithNamePreserved() {
        let a = person(id: "+14155550600", handleRowIDs: [600])
        let b = person(id: "+14155550601", handleRowIDs: [601])
        let c = chat(rowID: 60, guid: "g60", style: 43, members: [600, 601], displayName: "Ski cabin")
        let messages = [
            message(rowID: 1, chatRowID: 60, handleRowID: 600, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 2, chatRowID: 60, handleRowID: 601, isFromMe: false, date: utcDate(2024, 1, 2)),
        ]
        let graph = GraphBuilder.build(extract: extract(chats: [c], messages: messages), keptPeople: [a, b], calendar: utc)

        let groupNode = graph.nodes.first { $0.id == groupNodeID("g60") }
        XCTAssertEqual(groupNode?.kind, .group, "2 different resolved people is a real group, not one-to-one")
        XCTAssertEqual(groupNode?.name, "Ski cabin", "the real display name must survive onto the group node")

        let membershipEdges = graph.edges.filter { $0.reason == .groupMembership }
        XCTAssertEqual(membershipEdges.count, 2, "both a and b get a groupMembership edge")
        XCTAssertTrue(graph.edges.allSatisfy { $0.reason != .oneToOneThread }, "no bogus one-to-one edge to the user for either member")
    }

    // The contrasting case: 2 raw handles that resolve to the SAME merged person (their
    // phone and their email, say) is still exactly one distinct person -- one-to-one, no
    // group node at all.
    func testTwoHandleRosterResolvingToSamePersonProducesNoGroupNode() {
        let merged = person(id: "+14155550610", handleRowIDs: [610, 611]) // one person, two services
        let c = chat(rowID: 61, guid: "g61", style: 43, members: [610, 611], displayName: "Should never render as a group")
        let messages = [
            message(rowID: 1, chatRowID: 61, handleRowID: 610, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 2, chatRowID: 61, handleRowID: 611, isFromMe: false, date: utcDate(2024, 1, 2)),
        ]
        let graph = GraphBuilder.build(extract: extract(chats: [c], messages: messages), keptPeople: [merged], calendar: utc)

        XCTAssertFalse(graph.nodes.contains { $0.kind == .group }, "one merged person in the roster is one-to-one, not a group")

        let edge = graph.edges.first { $0.reason == .oneToOneThread }
        XCTAssertNotNil(edge)
        XCTAssertEqual(edge?.strength, 2.0)
    }

    // MARK: - Roster-based group deduplication: Apple gives one human group a separate chat
    // row per service (iMessage vs SMS/RCS). These merge chats whose RESOLVED rosters match.

    func testSameRosterSameNameChatsMergeIntoOneNode() {
        let a = person(id: "+14155550700", handleRowIDs: [700])
        let b = person(id: "+14155550701", handleRowIDs: [701])
        let imessageChat = chat(rowID: 70, guid: "z-imessage", style: 43, members: [700, 701], displayName: "Book club")
        let smsChat = chat(rowID: 71, guid: "a-sms", style: 43, members: [700, 701], displayName: "Book club")
        let messages = [
            message(rowID: 1, chatRowID: 70, handleRowID: 700, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 2, chatRowID: 71, handleRowID: 701, isFromMe: false, date: utcDate(2024, 1, 2)),
        ]
        let graph = GraphBuilder.build(extract: extract(chats: [imessageChat, smsChat], messages: messages), keptPeople: [a, b], calendar: utc)

        let groupNodes = graph.nodes.filter { $0.kind == .group }
        XCTAssertEqual(groupNodes.count, 1, "same roster + same name must merge into one node")
        // min-by-guid, not min-by-rowID: "a-sms" < "z-imessage" lexicographically even though
        // the imessage chat has the smaller rowID.
        XCTAssertEqual(groupNodes.first?.id, groupNodeID("a-sms"))
        XCTAssertEqual(groupNodes.first?.name, "Book club")
    }

    func testSameRosterTwoDifferentNamesStaySeparateNodes() {
        let a = person(id: "+14155550710", handleRowIDs: [710])
        let b = person(id: "+14155550711", handleRowIDs: [711])
        let chatOne = chat(rowID: 72, guid: "g72", style: 43, members: [710, 711], displayName: "Book club")
        let chatTwo = chat(rowID: 73, guid: "g73", style: 43, members: [710, 711], displayName: "Trivia night")
        let messages = [
            message(rowID: 1, chatRowID: 72, handleRowID: 710, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 2, chatRowID: 73, handleRowID: 711, isFromMe: false, date: utcDate(2024, 1, 2)),
        ]
        let graph = GraphBuilder.build(extract: extract(chats: [chatOne, chatTwo], messages: messages), keptPeople: [a, b], calendar: utc)

        let groupNodes = graph.nodes.filter { $0.kind == .group }
        XCTAssertEqual(groupNodes.count, 2, "two distinct real names on the same roster stay two nodes")
        XCTAssertEqual(Set(groupNodes.map(\.name)), Set(["Book club", "Trivia night"]))
    }

    // The mixed case: same roster, THREE competing names' worth of chats -- two chats sharing
    // "X" (which merge together), one chat named "Y" (its own node), and one unnamed chat
    // (stands alone, attributed to neither name). Also pins full-build determinism for this
    // shape, since it is the only one that partitions a roster bucket via dictionary/Set
    // iteration before the final sort washes the order out.
    func testSameRosterTwoNamesPlusUnnamedChatProducesThreeSeparateNodes() {
        let a = person(id: "+14155550715", handleRowIDs: [715])
        let b = person(id: "+14155550716", handleRowIDs: [716])
        let chatX1 = chat(rowID: 80, guid: "g80-x1", style: 43, members: [715, 716], displayName: "X")
        let chatX2 = chat(rowID: 81, guid: "g81-x2", style: 43, members: [715, 716], displayName: "X")
        let chatY = chat(rowID: 82, guid: "g82-y", style: 43, members: [715, 716], displayName: "Y")
        let chatUnnamed = chat(rowID: 83, guid: "g83-unnamed", style: 43, members: [715, 716], displayName: nil)
        let messages = [
            message(rowID: 1, chatRowID: 80, handleRowID: 715, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 2, chatRowID: 81, handleRowID: 716, isFromMe: false, date: utcDate(2024, 1, 2)),
            message(rowID: 3, chatRowID: 82, handleRowID: 715, isFromMe: false, date: utcDate(2024, 1, 3)),
            message(rowID: 4, chatRowID: 83, handleRowID: 716, isFromMe: false, date: utcDate(2024, 1, 4)),
        ]
        let ext = extract(chats: [chatX1, chatX2, chatY, chatUnnamed], messages: messages)

        let first = GraphBuilder.build(extract: ext, keptPeople: [a, b], calendar: utc)
        let second = GraphBuilder.build(extract: ext, keptPeople: [a, b], calendar: utc)
        XCTAssertEqual(first, second, "build must be deterministic even when a roster bucket is partitioned by name")

        let groupNodes = first.nodes.filter { $0.kind == .group }
        XCTAssertEqual(groupNodes.count, 3, "the two X chats merge; Y and the unnamed chat each stand alone")

        // min-by-guid within the X pair: "g80-x1" < "g81-x2".
        XCTAssertEqual(
            Set(groupNodes.map(\.id)),
            Set([groupNodeID("g80-x1"), groupNodeID("g82-y"), groupNodeID("g83-unnamed")])
        )
        let byID = Dictionary(uniqueKeysWithValues: groupNodes.map { ($0.id, $0) })
        XCTAssertEqual(byID[groupNodeID("g80-x1")]?.name, "X")
        XCTAssertEqual(byID[groupNodeID("g82-y")]?.name, "Y")
        XCTAssertNil(byID[groupNodeID("g83-unnamed")]?.name, "the unnamed chat cannot be attributed to X or Y")
    }

    func testSameRosterOneNamedOneUnnamedMergeCarryingTheName() {
        let a = person(id: "+14155550720", handleRowIDs: [720])
        let b = person(id: "+14155550721", handleRowIDs: [721])
        let namedChat = chat(rowID: 74, guid: "g74", style: 43, members: [720, 721], displayName: "Book club")
        let unnamedChat = chat(rowID: 75, guid: "g75", style: 43, members: [720, 721], displayName: nil)
        let messages = [
            message(rowID: 1, chatRowID: 74, handleRowID: 720, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 2, chatRowID: 75, handleRowID: 721, isFromMe: false, date: utcDate(2024, 1, 2)),
        ]
        let graph = GraphBuilder.build(extract: extract(chats: [namedChat, unnamedChat], messages: messages), keptPeople: [a, b], calendar: utc)

        let groupNodes = graph.nodes.filter { $0.kind == .group }
        XCTAssertEqual(groupNodes.count, 1, "named and unnamed chats on the same roster merge into one node")
        XCTAssertEqual(groupNodes.first?.name, "Book club")
    }

    func testDifferentRostersStaySeparateNodes() {
        let a = person(id: "+14155550730", handleRowIDs: [730])
        let b = person(id: "+14155550731", handleRowIDs: [731])
        let c = person(id: "+14155550732", handleRowIDs: [732])
        let chatAB = chat(rowID: 76, guid: "g76", style: 43, members: [730, 731], displayName: "Book club")
        let chatAC = chat(rowID: 77, guid: "g77", style: 43, members: [730, 732], displayName: "Book club")
        let messages = [
            message(rowID: 1, chatRowID: 76, handleRowID: 730, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 2, chatRowID: 77, handleRowID: 732, isFromMe: false, date: utcDate(2024, 1, 2)),
        ]
        let graph = GraphBuilder.build(extract: extract(chats: [chatAB, chatAC], messages: messages), keptPeople: [a, b, c], calendar: utc)

        let groupNodes = graph.nodes.filter { $0.kind == .group }
        XCTAssertEqual(groupNodes.count, 2, "different rosters never merge, name notwithstanding")
    }

    // The union test: each chat alone is dead (1 distinct day), but the merged node must be
    // live because the SAME human conversation spans both service-split chats.
    func testMergedGroupUnionsMessagesAcrossServiceSplitChatsForLivenessAndStrength() {
        let a = person(id: "+14155550740", handleRowIDs: [740])
        let b = person(id: "+14155550741", handleRowIDs: [741])
        let imessageChat = chat(rowID: 78, guid: "z-imessage2", style: 43, members: [740, 741], displayName: "Book club")
        let smsChat = chat(rowID: 79, guid: "a-sms2", style: 43, members: [740, 741], displayName: "Book club")
        let messages = [
            // imessage chat: only day 1, from a and from the user.
            message(rowID: 1, chatRowID: 78, handleRowID: 740, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 2, chatRowID: 78, handleRowID: nil, isFromMe: true, date: utcDate(2024, 1, 1)),
            // sms chat: only day 2, from b and from the user.
            message(rowID: 3, chatRowID: 79, handleRowID: 741, isFromMe: false, date: utcDate(2024, 1, 2)),
            message(rowID: 4, chatRowID: 79, handleRowID: nil, isFromMe: true, date: utcDate(2024, 1, 2)),
        ]
        let graph = GraphBuilder.build(extract: extract(chats: [imessageChat, smsChat], messages: messages), keptPeople: [a, b], calendar: utc)

        let groupNodes = graph.nodes.filter { $0.kind == .group }
        XCTAssertEqual(groupNodes.count, 1)
        XCTAssertEqual(groupNodes.first?.isLive, true, "each chat alone is a single day, but their union is 2 distinct days")

        let mergedID = groupNodeID("a-sms2")
        let aEdge = graph.edges.first { $0.reason == .groupMembership && ($0.nodeIDA == a.id || $0.nodeIDB == a.id) }
        let bEdge = graph.edges.first { $0.reason == .groupMembership && ($0.nodeIDA == b.id || $0.nodeIDB == b.id) }
        XCTAssertEqual(aEdge?.strength, 1.0, "a only posted on day 1 across the union")
        XCTAssertEqual(bEdge?.strength, 1.0, "b only posted on day 2 across the union")

        let userEdge = graph.edges.first { $0.reason == .userGroupMembership && ($0.nodeIDA == mergedID || $0.nodeIDB == mergedID) }
        XCTAssertEqual(userEdge?.strength, 2.0, "the user's own from-me messages span both days across the union")
    }

    // MARK: - First/last contact dates

    func testPersonWithMessagesInTwoServiceSplitOneToOneChatsGetsEarliestAndLatestAcrossTheUnion() {
        let p = person(id: "+14155550801", handleRowIDs: [801])
        // Same person, two separate one-to-one chats (e.g. iMessage vs SMS split).
        let imessageChat = chat(rowID: 1, guid: "c-imessage", style: 45, members: [801])
        let smsChat = chat(rowID: 2, guid: "c-sms", style: 45, members: [801])
        let messages = [
            message(rowID: 1, chatRowID: 1, handleRowID: 801, isFromMe: false, date: utcDate(2024, 3, 15)),
            message(rowID: 2, chatRowID: 1, handleRowID: 801, isFromMe: false, date: utcDate(2024, 6, 1)),
            // Earlier than the imessage chat's own earliest -- the person-level earliest must
            // reach across both chats, not stop at whichever chat happens to be iterated first.
            message(rowID: 3, chatRowID: 2, handleRowID: 801, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 4, chatRowID: 2, handleRowID: 801, isFromMe: false, date: utcDate(2024, 9, 30)),
        ]
        let graph = GraphBuilder.build(
            extract: extract(chats: [imessageChat, smsChat], messages: messages), keptPeople: [p], calendar: utc
        )

        let node = graph.nodes.first { $0.id == p.id }
        XCTAssertEqual(node?.firstMessageDate, utcDate(2024, 1, 1), "earliest across the union of both service-split chats")
        XCTAssertEqual(node?.lastMessageDate, utcDate(2024, 9, 30), "latest across the union of both service-split chats")
    }

    func testRosterOnlyLurkerWithNoMessagesGetsNilFirstAndLastContactDates() {
        let lurker = person(id: "+14155550802", handleRowIDs: [802])
        let active = person(id: "+14155550803", handleRowIDs: [803])
        // A live group where the lurker is in the roster (chat_handle_join) but never sends.
        let group = chat(rowID: 1, guid: "c-lurk", style: 43, members: [802, 803], displayName: "Trip")
        let messages = [
            message(rowID: 1, chatRowID: 1, handleRowID: 803, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 2, chatRowID: 1, handleRowID: nil, isFromMe: true, date: utcDate(2024, 1, 2)),
        ]
        let graph = GraphBuilder.build(
            extract: extract(chats: [group], messages: messages), keptPeople: [lurker, active], calendar: utc
        )

        // The lurker is present in the group roster, so their dates come from the group's own
        // activity, not nil -- true "no messages at all" requires no chat of either kind.
        let lurkerNode = graph.nodes.first { $0.id == lurker.id }
        XCTAssertEqual(lurkerNode?.firstMessageDate, utcDate(2024, 1, 1))

        // A person with no one-to-one thread and no group roster membership at all is the
        // actual nil case: build a second graph where the lurker isn't even in the roster.
        let soloGroup = chat(rowID: 2, guid: "c-solo", style: 43, members: [803, 804], displayName: "Solo trio")
        let third = person(id: "+14155550804", handleRowIDs: [804])
        let trulyAbsent = person(id: "+14155550805", handleRowIDs: [805])
        let soloMessages = [
            message(rowID: 3, chatRowID: 2, handleRowID: 803, isFromMe: false, date: utcDate(2024, 2, 1)),
            message(rowID: 4, chatRowID: 2, handleRowID: 804, isFromMe: false, date: utcDate(2024, 2, 2)),
        ]
        let graph2 = GraphBuilder.build(
            extract: extract(chats: [soloGroup], messages: soloMessages),
            keptPeople: [active, third, trulyAbsent],
            calendar: utc
        )
        let absentNode = graph2.nodes.first { $0.id == trulyAbsent.id }
        XCTAssertNil(absentNode?.firstMessageDate, "a person with no one-to-one thread and no group roster membership has no message evidence at all")
        XCTAssertNil(absentNode?.lastMessageDate)
    }

    func testGroupNodeGetsEarliestAndLatestAcrossItsMergedChats() {
        let a = person(id: "+14155550810", handleRowIDs: [810])
        let b = person(id: "+14155550811", handleRowIDs: [811])
        let imessageChat = chat(rowID: 1, guid: "z-merge", style: 43, members: [810, 811], displayName: "Book club")
        let smsChat = chat(rowID: 2, guid: "a-merge", style: 43, members: [810, 811], displayName: "Book club")
        let messages = [
            message(rowID: 1, chatRowID: 1, handleRowID: 810, isFromMe: false, date: utcDate(2024, 5, 1)),
            // Earliest of all, but in the OTHER merged chat -- the group's date must reach
            // across both chatRowIDs the same way combinedMessages already does for liveness.
            message(rowID: 2, chatRowID: 2, handleRowID: 811, isFromMe: false, date: utcDate(2024, 1, 1)),
            message(rowID: 3, chatRowID: 2, handleRowID: 811, isFromMe: false, date: utcDate(2024, 12, 31)),
        ]
        let graph = GraphBuilder.build(extract: extract(chats: [imessageChat, smsChat], messages: messages), keptPeople: [a, b], calendar: utc)

        let groupNode = graph.nodes.first { $0.kind == .group }
        XCTAssertEqual(groupNode?.firstMessageDate, utcDate(2024, 1, 1))
        XCTAssertEqual(groupNode?.lastMessageDate, utcDate(2024, 12, 31))
    }
}
