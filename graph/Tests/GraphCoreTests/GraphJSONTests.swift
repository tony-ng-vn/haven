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
}

private struct DecodedEdge: Decodable {
    let a: String
    let b: String
    let reason: String
    let strength: Double
}

private struct DecodedGraph: Decodable {
    let nodes: [DecodedNode]
    let edges: [DecodedEdge]
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
        degree: Int = 0
    ) -> GraphNode {
        GraphNode(
            id: id,
            kind: kind,
            name: name,
            thumbnailImageData: thumbnailImageData,
            hasContactCard: hasContactCard,
            isLive: isLive,
            degree: degree
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
}
