import XCTest
@testable import GraphCore

/// Decoded shapes mirroring the GraphJSON schema from the consumer's side. A plain decode,
/// not a reuse of GraphJSON's own private DTOs, so a bug in the encoder cannot hide behind
/// sharing code with whatever verifies it.
private struct DecodedNode: Decodable {
    let id: String
    let kind: String
    let name: String?
    let hasContactCard: Bool
    let isLive: Bool
    let degree: Int
    let firstMessageDate: String?
    let lastMessageDate: String?
}

private struct DecodedEdge: Decodable {
    let a: String
    let b: String
    let reason: String
    let strength: Double
}

private struct DecodedAcquaintanceEvidence: Decodable {
    let chatId: String
    let chatName: String?
    let memberCount: Int
    let coActiveDays: Int
    let interactionCount: Int
}

private struct DecodedAcquaintance: Decodable {
    let a: String
    let b: String
    let tier: String
    let score: Double
    let evidence: [DecodedAcquaintanceEvidence]
    let interactionCount: Int
}

private struct DecodedGraph: Decodable {
    let nodes: [DecodedNode]
    let edges: [DecodedEdge]
    let acquaintances: [DecodedAcquaintance]
    let fullyAcquaintedChatIds: [String]
    let hasHistory: Bool
}

final class GraphJSONTests: XCTestCase {

    // MARK: - Fixture helpers

    private func node(
        id: String,
        kind: NodeKind,
        name: String? = nil,
        thumbnailImageData: Data? = nil,
        hasContactCard: Bool = false,
        isLive: Bool = false,
        degree: Int = 0,
        firstMessageDate: Date? = nil,
        lastMessageDate: Date? = nil
    ) -> GraphNode {
        GraphNode(
            id: id,
            kind: kind,
            name: name,
            thumbnailImageData: thumbnailImageData,
            hasContactCard: hasContactCard,
            isLive: isLive,
            degree: degree,
            firstMessageDate: firstMessageDate,
            lastMessageDate: lastMessageDate
        )
    }

    private func edge(
        _ nodeIDA: String,
        _ nodeIDB: String,
        reason: EdgeReason,
        strength: Double = 0,
        involvesUser: Bool = false
    ) -> GraphEdge {
        GraphEdge(nodeIDA: nodeIDA, nodeIDB: nodeIDB, source: .imessage, reason: reason, strength: strength, involvesUser: involvesUser)
    }

    /// A Person whose id and identifiers are the same single value unless overridden --
    /// enough for encode's fullyAcquaintedRosterKeys/AcquaintanceRosterKey.resolve translation
    /// step; GraphJSON never reads handleRowIDs/contactCardIDs at all.
    private func person(id: String, identifiers: Set<String>? = nil) -> Person {
        Person(
            id: id,
            identifiers: identifiers ?? [id],
            handleRowIDs: [],
            name: nil,
            thumbnailImageData: nil,
            contactCardIDs: [],
            hasContactCard: false
        )
    }

    private func decode(_ data: Data) throws -> DecodedGraph {
        try JSONDecoder().decode(DecodedGraph.self, from: data)
    }

    private func jsonString(_ data: Data) throws -> String {
        try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    // MARK: - Test 1: full fixture round trip, including nil name as JSON null (not "nil")

    func testFixtureGraphRoundTripsEveryField() throws {
        let user = node(id: "user", kind: .user, degree: 2)
        let named = node(id: "+15550001", kind: .person, name: "Ada Lovelace", hasContactCard: true, degree: 3)
        let unnamed = node(id: "+15550002", kind: .person, degree: 1)
        let group = node(id: "chat:cabin", kind: .group, name: "Ski cabin", isLive: true, degree: 5)

        let userEdge = edge("user", "+15550001", reason: .oneToOneThread, strength: 12.0, involvesUser: true)
        let membershipEdge = edge("+15550002", "chat:cabin", reason: .groupMembership, strength: 4.0)

        let graph = Graph(nodes: [user, named, unnamed, group], edges: [userEdge, membershipEdge])
        let data = try GraphJSON.encode(graph: graph)
        let decoded = try decode(data)

        XCTAssertEqual(decoded.nodes.count, 4)
        XCTAssertEqual(decoded.edges.count, 2)

        let decodedUser = try XCTUnwrap(decoded.nodes.first { $0.id == "user" })
        XCTAssertEqual(decodedUser.kind, "user")
        XCTAssertNil(decodedUser.name)
        XCTAssertEqual(decodedUser.hasContactCard, false)
        XCTAssertEqual(decodedUser.isLive, false)
        XCTAssertEqual(decodedUser.degree, 2)

        let decodedNamed = try XCTUnwrap(decoded.nodes.first { $0.id == "+15550001" })
        XCTAssertEqual(decodedNamed.kind, "person")
        XCTAssertEqual(decodedNamed.name, "Ada Lovelace")
        XCTAssertEqual(decodedNamed.hasContactCard, true)
        XCTAssertEqual(decodedNamed.isLive, false)
        XCTAssertEqual(decodedNamed.degree, 3)

        let decodedUnnamed = try XCTUnwrap(decoded.nodes.first { $0.id == "+15550002" })
        XCTAssertEqual(decodedUnnamed.kind, "person")
        XCTAssertNil(decodedUnnamed.name)
        XCTAssertEqual(decodedUnnamed.hasContactCard, false)
        XCTAssertEqual(decodedUnnamed.degree, 1)

        let decodedGroup = try XCTUnwrap(decoded.nodes.first { $0.id == "chat:cabin" })
        XCTAssertEqual(decodedGroup.kind, "group")
        XCTAssertEqual(decodedGroup.name, "Ski cabin")
        XCTAssertEqual(decodedGroup.isLive, true)
        XCTAssertEqual(decodedGroup.degree, 5)

        let decodedUserEdge = try XCTUnwrap(decoded.edges.first { $0.reason == "oneToOneThread" })
        XCTAssertEqual(Set([decodedUserEdge.a, decodedUserEdge.b]), Set(["user", "+15550001"]))
        XCTAssertEqual(decodedUserEdge.strength, 12.0)

        let decodedMembershipEdge = try XCTUnwrap(decoded.edges.first { $0.reason == "groupMembership" })
        XCTAssertEqual(Set([decodedMembershipEdge.a, decodedMembershipEdge.b]), Set(["+15550002", "chat:cabin"]))
        XCTAssertEqual(decodedMembershipEdge.strength, 4.0)

        // JSONDecoder into String? cannot tell an absent key from an explicit null, so the
        // assertions above would pass either way -- this is the one check that actually
        // pins "null", ruling out both an omitted key and the literal string "nil".
        let raw = try jsonString(data)
        XCTAssertTrue(
            raw.contains("\"name\":null"),
            "unnamed node must encode name as JSON null, not omit the key or write the string \"nil\""
        )
        XCTAssertFalse(raw.contains("\"name\":\"nil\""))
    }

    // MARK: - Test 2: thumbnailImageData is never emitted

    func testThumbnailImageDataNeverAppearsInOutput() throws {
        let photoData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]) // arbitrary bytes, not a real image
        let withPhoto = node(id: "p1", kind: .person, name: "Photo Person", thumbnailImageData: photoData, hasContactCard: true)
        let graph = Graph(nodes: [withPhoto], edges: [])

        let data = try GraphJSON.encode(graph: graph)
        let raw = try jsonString(data)

        XCTAssertFalse(raw.lowercased().contains("thumbnail"), "no key or value derived from thumbnailImageData may appear in the export")
    }

    // MARK: - Test 3: quote and non-ASCII name round trips exactly (the escaping regression test)

    func testNameWithQuoteAndNonASCIICharacterRoundTripsExactly() throws {
        let tricky = "Chị \"B\" Bông"
        let person = node(id: "p2", kind: .person, name: tricky, hasContactCard: true)
        let graph = Graph(nodes: [person], edges: [])

        let data = try GraphJSON.encode(graph: graph)
        let decoded = try decode(data)

        XCTAssertEqual(decoded.nodes.first?.name, tricky)
    }

    // MARK: - Test 4: determinism regardless of input order

    func testEncodingIsByteIdenticalRegardlessOfInputOrder() throws {
        let a = node(id: "a-user", kind: .user, degree: 2)
        let b = node(id: "b-person", kind: .person, name: "B Person", degree: 2)
        let c = node(id: "chat:c-group", kind: .group, name: "C Group", isLive: true, degree: 2)

        let edgeAB = edge("a-user", "b-person", reason: .oneToOneThread, strength: 3.0, involvesUser: true)
        let edgeBC = edge("b-person", "chat:c-group", reason: .groupMembership, strength: 1.0)

        let forward = Graph(nodes: [a, b, c], edges: [edgeAB, edgeBC])
        let shuffled = Graph(nodes: [c, a, b], edges: [edgeBC, edgeAB])

        let dataForward = try GraphJSON.encode(graph: forward)
        let dataShuffled = try GraphJSON.encode(graph: shuffled)

        XCTAssertEqual(dataForward, dataShuffled)
    }

    // MARK: - Test 5: every EdgeReason maps to a distinct, non-empty, expected string

    func testEveryEdgeReasonMapsToItsExpectedDistinctString() throws {
        var seenReasonStrings: Set<String> = []

        for reason in EdgeReason.allCases {
            // Exhaustive, no default: adding an EdgeReason case without adding it here is a
            // compile error, the same guard the real encoder relies on in GraphJSON.swift.
            let expected: String
            switch reason {
            case .oneToOneThread: expected = "oneToOneThread"
            case .groupMembership: expected = "groupMembership"
            case .userGroupMembership: expected = "userGroupMembership"
            }

            let a = node(id: "user", kind: .user)
            let b = node(id: "target", kind: .person, name: "Target")
            let graph = Graph(nodes: [a, b], edges: [edge("user", "target", reason: reason)])

            let data = try GraphJSON.encode(graph: graph)
            let decoded = try decode(data)

            XCTAssertEqual(decoded.edges.count, 1)
            let actual = try XCTUnwrap(decoded.edges.first).reason
            XCTAssertFalse(actual.isEmpty)
            XCTAssertEqual(actual, expected)
            seenReasonStrings.insert(actual)
        }

        XCTAssertEqual(
            seenReasonStrings.count,
            EdgeReason.allCases.count,
            "two EdgeReason cases must never collapse to the same string"
        )
    }

    // MARK: - Test 6: a cached model guess fills in for a node with no real name

    func testUnnamedPersonNodeGetsGuessedNameTildePrefixed() throws {
        let unnamed = node(id: "+15550003", kind: .person, degree: 1)
        let graph = Graph(nodes: [unnamed], edges: [])
        let guesses: [String: NameGuess] = ["+15550003": NameGuess(name: "Sam", detail: "gym buddy")]

        let data = try GraphJSON.encode(graph: graph, guesses: guesses)
        let decoded = try decode(data)

        // NodeLabel.resolve's own tilde-prefix convention: the exported name must carry the
        // same "this is a guess, not a real name" marker the on-screen renderer uses, so a
        // downstream consumer (Polygres sync) can tell the two apart without a second field.
        XCTAssertEqual(decoded.nodes.first?.name, "~Sam")
    }

    // MARK: - Test 7: a real name always wins over a cached guess

    func testRealNameWinsOverGuess() throws {
        let named = node(id: "+15550004", kind: .person, name: "Real Name", degree: 1)
        let graph = Graph(nodes: [named], edges: [])
        let guesses: [String: NameGuess] = ["+15550004": NameGuess(name: "Wrong Guess")]

        let data = try GraphJSON.encode(graph: graph, guesses: guesses)
        let decoded = try decode(data)

        XCTAssertEqual(decoded.nodes.first?.name, "Real Name")
    }

    // MARK: - Acquaintance layer helpers

    private func decodeWithAcquaintances(_ data: Data) throws -> DecodedGraph {
        try JSONDecoder().decode(DecodedGraph.self, from: data)
    }

    // MARK: - Test 7b: encode must not crash on a hand-built Graph with a duplicate node id.
    // GraphBuilder's own output never repeats an id, but encode is a public entry point taking
    // an arbitrary Graph -- a caller's malformed input must degrade the export, never trap.

    func testEncodeDoesNotCrashOnAGraphWithADuplicateNodeId() throws {
        let firstCopy = node(id: "dup", kind: .person, name: "First")
        let secondCopy = node(id: "dup", kind: .person, name: "Second")
        let graph = Graph(nodes: [firstCopy, secondCopy], edges: [])

        let data = try GraphJSON.encode(graph: graph)
        let decoded = try decode(data)

        XCTAssertEqual(decoded.nodes.count, 2, "encode still emits both node entries, it just cannot resolve a unique name lookup for the shared id")
    }

    // MARK: - Test 8: full acquaintance shape, including an unnamed chat's null chatName

    func testAcquaintancesEncodeFullShapeIncludingNullChatNameForAnUnnamedChat() throws {
        let user = node(id: "user", kind: .user)
        let a = node(id: "+15550101", kind: .person, name: "A")
        let b = node(id: "+15550102", kind: .person, name: "B")
        let unnamedGroup = node(id: "chat:unnamed", kind: .group) // name: nil
        let graph = Graph(nodes: [user, a, b, unnamedGroup], edges: [])
        let activity = [
            GroupChatActivity(chatId: "chat:unnamed", name: nil, roster: ["+15550101", "+15550102"], activeDaysByPersonID: [:])
        ]

        let data = try GraphJSON.encode(graph: graph, groupChatActivity: activity, fullyAcquaintedRosterKeys: [])
        let decoded = try decodeWithAcquaintances(data)

        XCTAssertEqual(decoded.acquaintances.count, 1)
        let pair = try XCTUnwrap(decoded.acquaintances.first)
        XCTAssertEqual(pair.a, "+15550101")
        XCTAssertEqual(pair.b, "+15550102")
        XCTAssertEqual(pair.tier, "strong")
        XCTAssertEqual(pair.score, 1.0, accuracy: 1e-9)
        XCTAssertEqual(pair.evidence.count, 1)
        XCTAssertEqual(pair.evidence[0].chatId, "chat:unnamed")
        XCTAssertNil(pair.evidence[0].chatName)
        XCTAssertEqual(pair.evidence[0].memberCount, 2)
        XCTAssertEqual(pair.evidence[0].coActiveDays, 0)

        // Pins true JSON null the same way testFixtureGraphRoundTripsEveryField does for a
        // node's name: rules out both an omitted key and the literal string "nil".
        let raw = try jsonString(data)
        XCTAssertTrue(raw.contains("\"chatName\":null"))
    }

    // MARK: - Test 9: evidence.chatName is the SAME resolved name the nodes array exports for
    // that chat (guess and tilde-prefix included), not GroupChatActivity's own raw name.

    func testEvidenceChatNameMatchesTheGuessedNameTheNodesArrayExportsNotTheRawName() throws {
        let user = node(id: "user", kind: .user)
        let a = node(id: "+15550201", kind: .person, name: "A")
        let b = node(id: "+15550202", kind: .person, name: "B")
        let guessedGroup = node(id: "chat:guessed", kind: .group) // raw name: nil
        let graph = Graph(nodes: [user, a, b, guessedGroup], edges: [])
        let activity = [
            // GroupChatActivity's own name is nil, matching the node -- the guess is layered
            // on top by GraphJSON's existing NodeLabel.resolve step, same as any other node.
            GroupChatActivity(chatId: "chat:guessed", name: nil, roster: ["+15550201", "+15550202"], activeDaysByPersonID: [:])
        ]
        let guesses: [String: NameGuess] = ["group:guessed": NameGuess(name: "Study group")]

        let data = try GraphJSON.encode(graph: graph, groupChatActivity: activity, fullyAcquaintedRosterKeys: [], guesses: guesses)
        let decoded = try decodeWithAcquaintances(data)

        let decodedGroupNode = try XCTUnwrap(decoded.nodes.first { $0.id == "chat:guessed" })
        XCTAssertEqual(decodedGroupNode.name, "~Study group")

        let pair = try XCTUnwrap(decoded.acquaintances.first)
        XCTAssertEqual(pair.evidence.first?.chatName, "~Study group", "evidence must echo the exact name the nodes array already resolved")
    }

    // MARK: - Test 10: a < b within every pair, and the acquaintances array itself is sorted
    // by (a, b), regardless of the roster's own insertion/iteration order.

    func testAcquaintancesArrayIsSortedByPairRegardlessOfRosterInputOrder() throws {
        let user = node(id: "user", kind: .user)
        let p1 = node(id: "+15550301", kind: .person, name: "One")
        let p2 = node(id: "+15550302", kind: .person, name: "Two")
        let p3 = node(id: "+15550303", kind: .person, name: "Three")
        let group = node(id: "chat:trio-of-three", kind: .group, name: "Trio")
        let graph = Graph(nodes: [user, p1, p2, p3, group], edges: [])
        let activity = [
            // Roster built in a deliberately non-sorted order.
            GroupChatActivity(
                chatId: "chat:trio-of-three",
                name: "Trio",
                roster: ["+15550303", "+15550301", "+15550302"],
                activeDaysByPersonID: [:]
            )
        ]

        let data = try GraphJSON.encode(graph: graph, groupChatActivity: activity, fullyAcquaintedRosterKeys: [])
        let decoded = try decodeWithAcquaintances(data)

        XCTAssertEqual(decoded.acquaintances.count, 3, "C(3,2) = 3 pairs")
        for pair in decoded.acquaintances {
            XCTAssertLessThan(pair.a, pair.b, "a < b within every pair")
        }
        XCTAssertEqual(
            decoded.acquaintances.map { [$0.a, $0.b] },
            [["+15550301", "+15550302"], ["+15550301", "+15550303"], ["+15550302", "+15550303"]],
            "the array itself must be sorted by (a, b)"
        )
    }

    // MARK: - Test 11: determinism, now including acquaintances/fullyAcquaintedChatIds AND the
    // roster-key translation step (people passed in two different array orders).

    func testAcquaintanceEncodingIsByteIdenticalRegardlessOfInputOrder() throws {
        let user = node(id: "user", kind: .user)
        let a = node(id: "+15550401", kind: .person, name: "A")
        let b = node(id: "+15550402", kind: .person, name: "B")
        let groupOne = node(id: "chat:det-one", kind: .group, name: "One")
        let groupTwo = node(id: "chat:det-two", kind: .group, name: "Two")
        let markedRoster: Set<String> = ["+15550401", "+15550402"]
        let key = AcquaintanceRosterKey.canonicalize(markedRoster)
        let peopleForward = [person(id: "+15550401"), person(id: "+15550402")]
        let peopleShuffled = [person(id: "+15550402"), person(id: "+15550401")]

        let activityForward = [
            GroupChatActivity(chatId: "chat:det-one", name: "One", roster: markedRoster, activeDaysByPersonID: [:]),
            GroupChatActivity(chatId: "chat:det-two", name: "Two", roster: markedRoster, activeDaysByPersonID: [:]),
        ]
        let activityShuffled = [activityForward[1], activityForward[0]]

        let forward = Graph(nodes: [user, a, b, groupOne, groupTwo], edges: [])
        let shuffled = Graph(nodes: [groupTwo, groupOne, b, a, user], edges: [])

        let dataForward = try GraphJSON.encode(
            graph: forward, groupChatActivity: activityForward, fullyAcquaintedRosterKeys: [key], people: peopleForward
        )
        let dataShuffled = try GraphJSON.encode(
            graph: shuffled, groupChatActivity: activityShuffled, fullyAcquaintedRosterKeys: [key], people: peopleShuffled
        )

        XCTAssertEqual(dataForward, dataShuffled)
        XCTAssertTrue(try jsonString(dataForward).contains("\"tier\":\"confirmed\""), "sanity: the marking actually resolved and took effect")
    }

    // MARK: - Test 12: acquaintances/evidence never reference a node id absent from the
    // exported nodes array (hidden or removed people) -- checked in the general form: every id
    // referenced anywhere in the acquaintances output (a, b, and every evidence chatId) must be
    // one of the ids actually present in the exported nodes array.

    func testAcquaintancesNeverReferenceANodeIdAbsentFromTheExportedNodesArray() throws {
        // personC and one of the two chats are deliberately left OUT of `nodes`, simulating a
        // caller that already excluded them (e.g. Graph.excludingNodes) before calling encode.
        let user = node(id: "user", kind: .user)
        let a = node(id: "+15550501", kind: .person, name: "A")
        let b = node(id: "+15550502", kind: .person, name: "B")
        let visibleGroup = node(id: "chat:visible", kind: .group, name: "Visible Group")
        let graph = Graph(nodes: [user, a, b, visibleGroup], edges: [])

        let activity = [
            GroupChatActivity(chatId: "chat:visible", name: "Visible Group", roster: ["+15550501", "+15550502"], activeDaysByPersonID: [:]),
            // Same pair, a SECOND chat that never made it into `nodes` -- its evidence must be
            // dropped, but the pair (A, B) must survive since both people are still exported.
            GroupChatActivity(chatId: "chat:hidden-evidence", name: "Hidden Group", roster: ["+15550501", "+15550502"], activeDaysByPersonID: [:]),
            // A pair involving personC, who never made it into `nodes` at all -- the WHOLE
            // pair must be dropped, not merely trimmed.
            GroupChatActivity(chatId: "chat:with-c", name: "With C", roster: ["+15550501", "+15550503"], activeDaysByPersonID: [:]),
        ]

        let data = try GraphJSON.encode(graph: graph, groupChatActivity: activity, fullyAcquaintedRosterKeys: [])
        let decoded = try decodeWithAcquaintances(data)

        XCTAssertEqual(decoded.acquaintances.count, 1, "the C pair must be dropped entirely, not partially")
        let pair = try XCTUnwrap(decoded.acquaintances.first)
        XCTAssertEqual(pair.a, "+15550501")
        XCTAssertEqual(pair.b, "+15550502")
        XCTAssertEqual(pair.score, 2.0, accuracy: 1e-9, "score stays the full observed sum across BOTH chats, even the hidden one")
        XCTAssertEqual(pair.evidence.map(\.chatId), ["chat:visible"], "evidence lists only chats present in this export")

        // The general form of the invariant: no id anywhere in the acquaintances output -- a,
        // b, or any evidence chatId -- may be missing from the exported nodes array.
        let exportedNodeIDs = Set(decoded.nodes.map(\.id))
        for acquaintance in decoded.acquaintances {
            XCTAssertTrue(exportedNodeIDs.contains(acquaintance.a))
            XCTAssertTrue(exportedNodeIDs.contains(acquaintance.b))
            for evidence in acquaintance.evidence {
                XCTAssertTrue(exportedNodeIDs.contains(evidence.chatId))
            }
        }
    }

    // MARK: - Test 13: fullyAcquaintedChatIds excludes a chat id absent from the exported
    // nodes array, same invariant as acquaintances/evidence, applied to the echo list itself.

    func testFullyAcquaintedChatIdsExcludesIdsAbsentFromTheExportedNodesArray() throws {
        let user = node(id: "user", kind: .user)
        let a = node(id: "+15550601", kind: .person, name: "A")
        let b = node(id: "+15550602", kind: .person, name: "B")
        let visibleGroup = node(id: "chat:visible-marked", kind: .group, name: "Visible Marked")
        // chat:hidden-marked has no corresponding node in `graph.nodes` at all.
        let graph = Graph(nodes: [user, a, b, visibleGroup], edges: [])
        let roster: Set<String> = ["+15550601", "+15550602"]
        let key = AcquaintanceRosterKey.canonicalize(roster)
        let people = [person(id: "+15550601"), person(id: "+15550602")]

        let activity = [
            GroupChatActivity(chatId: "chat:visible-marked", name: "Visible Marked", roster: roster, activeDaysByPersonID: [:]),
            GroupChatActivity(chatId: "chat:hidden-marked", name: "Hidden Marked", roster: roster, activeDaysByPersonID: [:]),
        ]

        let data = try GraphJSON.encode(graph: graph, groupChatActivity: activity, fullyAcquaintedRosterKeys: [key], people: people)
        let decoded = try decodeWithAcquaintances(data)

        XCTAssertEqual(decoded.fullyAcquaintedChatIds, ["chat:visible-marked"], "the excluded chat id must not appear even though its roster is marked")
    }

    // MARK: - Test 14: a marking survives a resync that hands a member a new, smaller
    // Person.id -- the stored key still names the CURRENT person via AcquaintanceRosterKey.
    // resolve, not the stale one exact set-equality would have required.

    func testMarkingSurvivesAMemberGainingANewSmallerPersonIDAcrossResync() throws {
        // Marked when the chat's FULL roster was {A, B} and A's id was "+15551002" -- a stored
        // key is always a whole chat's roster (PLAN.md: marking a chat, not an arbitrary
        // sub-pair), so the stale key must match the roster's SIZE, not just contain A and B.
        let staleKey = AcquaintanceRosterKey.canonicalize(["+15551002", "+15551003"])

        // Simulated resync: A merged with a new handle and now has a smaller id, but
        // "+15551002" is still in A's identifier set (identifiers only ever get added).
        let aAfter = person(id: "+15551000", identifiers: ["+15551000", "+15551002"])
        let bAfter = person(id: "+15551003", identifiers: ["+15551003"])

        let user = node(id: "user", kind: .user)
        let nodeA = node(id: "+15551000", kind: .person, name: "A")
        let nodeB = node(id: "+15551003", kind: .person, name: "B")
        let group = node(id: "chat:resynced", kind: .group, name: "Old Friends")
        let graph = Graph(nodes: [user, nodeA, nodeB, group], edges: [])

        // Same 2-person roster after the resync, just under A's new id -- score alone (n=2,
        // base 1.0) would already read "strong" even if translation silently failed, which is
        // exactly what makes "confirmed" (not "strong") a meaningful, discriminating assertion.
        let currentRoster: Set<String> = ["+15551000", "+15551003"]
        let activity = [
            GroupChatActivity(chatId: "chat:resynced", name: "Old Friends", roster: currentRoster, activeDaysByPersonID: [:])
        ]

        let data = try GraphJSON.encode(
            graph: graph,
            groupChatActivity: activity,
            fullyAcquaintedRosterKeys: [staleKey],
            people: [aAfter, bAfter]
        )
        let decoded = try decodeWithAcquaintances(data)

        let pair = try XCTUnwrap(decoded.acquaintances.first { $0.a == "+15551000" && $0.b == "+15551003" })
        XCTAssertEqual(pair.tier, "confirmed", "the stale-keyed mark must still confirm this pair after A's Person.id shifted")
        XCTAssertTrue(decoded.fullyAcquaintedChatIds.contains("chat:resynced"), "the echo list must include the chat even though the stored key predates A's current id")
    }

    // MARK: - Test 15: firstMessageDate/lastMessageDate encode as ISO 8601 strings, and
    // hasHistory flips true once at least one node carries a real date.

    func testDatedNodeEncodesFirstAndLastMessageDateAsISO8601AndSetsHasHistoryTrue() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let first = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        let last = calendar.date(from: DateComponents(year: 2024, month: 6, day: 15))!
        let dated = node(id: "+15550701", kind: .person, name: "Dated", firstMessageDate: first, lastMessageDate: last)
        let graph = Graph(nodes: [dated], edges: [])

        let data = try GraphJSON.encode(graph: graph)
        let decoded = try decode(data)

        let decodedNode = try XCTUnwrap(decoded.nodes.first)
        let expectedFirst = ISO8601DateFormatter().string(from: first)
        let expectedLast = ISO8601DateFormatter().string(from: last)
        XCTAssertEqual(decodedNode.firstMessageDate, expectedFirst)
        XCTAssertEqual(decodedNode.lastMessageDate, expectedLast)
        XCTAssertTrue(decoded.hasHistory, "at least one node has a real firstMessageDate")
    }

    // MARK: - Test 15b: interactionCount encodes on both the acquaintance (total) and its
    // evidence (per-chat), and stays 0 -- never omitted -- for a pair with no interaction
    // evidence at all (the ordinary co-membership-only case every earlier test here exercises).

    func testInteractionCountEncodesTotalAndPerChatAndDefaultsToZero() throws {
        let user = node(id: "user", kind: .user)
        let a = node(id: "+15550801", kind: .person, name: "A")
        let b = node(id: "+15550802", kind: .person, name: "B")
        let groupWithInteractions = node(id: "chat:with-interactions", kind: .group, name: "With interactions")
        let groupWithout = node(id: "chat:without-interactions", kind: .group, name: "Without interactions")
        let graph = Graph(nodes: [user, a, b, groupWithInteractions, groupWithout], edges: [])
        let activity = [
            GroupChatActivity(
                chatId: "chat:with-interactions", name: "With interactions",
                roster: ["+15550801", "+15550802"], activeDaysByPersonID: [:],
                interactionCountByPair: [PersonPairKey.make("+15550801", "+15550802"): 4]
            ),
        ]

        let data = try GraphJSON.encode(graph: graph, groupChatActivity: activity, fullyAcquaintedRosterKeys: [])
        let decoded = try decodeWithAcquaintances(data)

        let pair = try XCTUnwrap(decoded.acquaintances.first)
        XCTAssertEqual(pair.interactionCount, 4, "total across every shared chat")
        XCTAssertEqual(pair.evidence.count, 1)
        XCTAssertEqual(pair.evidence[0].interactionCount, 4, "the one chat's own per-chat count")

        // Now the zero-safe case: the same pair, same score-earning chat, but no interaction
        // evidence recorded at all -- interactionCount must still be present and equal to 0,
        // never an omitted key (the same convention memberCount/coActiveDays already follow).
        let zeroActivity = [
            GroupChatActivity(
                chatId: "chat:without-interactions", name: "Without interactions",
                roster: ["+15550801", "+15550802"], activeDaysByPersonID: [:]
            ),
        ]
        let zeroData = try GraphJSON.encode(graph: graph, groupChatActivity: zeroActivity, fullyAcquaintedRosterKeys: [])
        let zeroDecoded = try decodeWithAcquaintances(zeroData)
        let zeroPair = try XCTUnwrap(zeroDecoded.acquaintances.first)
        XCTAssertEqual(zeroPair.interactionCount, 0)
        XCTAssertEqual(zeroPair.evidence[0].interactionCount, 0)
        XCTAssertTrue(try jsonString(zeroData).contains("\"interactionCount\":0"), "the key must be present, not omitted, when the count is zero")
    }

    // MARK: - Test 16: a node with no dates encodes explicit JSON null (not an omitted key),
    // same convention as name -- and hasHistory stays false when nothing in the graph is dated.

    func testUndatedNodeEncodesExplicitNullForBothDateFieldsAndHasHistoryStaysFalse() throws {
        let undated = node(id: "+15550702", kind: .person, name: "Undated")
        let graph = Graph(nodes: [undated], edges: [])

        let data = try GraphJSON.encode(graph: graph)
        let decoded = try decode(data)
        let raw = try jsonString(data)

        let decodedNode = try XCTUnwrap(decoded.nodes.first)
        XCTAssertNil(decodedNode.firstMessageDate)
        XCTAssertNil(decodedNode.lastMessageDate)
        XCTAssertTrue(raw.contains("\"firstMessageDate\":null"), "must encode explicit null, not omit the key")
        XCTAssertTrue(raw.contains("\"lastMessageDate\":null"))
        XCTAssertFalse(decoded.hasHistory, "no node in this graph carries a real date")
    }
}
