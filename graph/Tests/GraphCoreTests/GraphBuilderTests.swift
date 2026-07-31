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

    // MARK: - Test 2: two-member style-43 is a one-to-one edge, not a group node

    func testTwoMemberStyle43ChatProducesOneToOneEdgeNotGroupNode() {
        let p = person(id: "+14155550010", handleRowIDs: [10])
        // Handle 11 has no corresponding kept Person (the other roster slot).
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
}
