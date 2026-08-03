import XCTest
@testable import GraphCore

final class GuessCandidateSelectionTests: XCTestCase {

    private func person(
        id: String,
        handleRowIDs: Set<Int64>,
        name: String? = nil
    ) -> Person {
        Person(
            id: id,
            identifiers: [id],
            handleRowIDs: handleRowIDs,
            name: name,
            thumbnailImageData: nil,
            contactCardIDs: [],
            hasContactCard: false
        )
    }

    private func oneToOneChat(rowID: Int64, guid: String, memberHandleRowID: Int64) -> RawChat {
        RawChat(
            rowID: rowID,
            guid: guid,
            style: 45,
            chatIdentifier: nil,
            serviceName: nil,
            displayName: nil,
            memberHandleRowIDs: [memberHandleRowID]
        )
    }

    private func groupChat(rowID: Int64, guid: String, memberHandleRowIDs: [Int64]) -> RawChat {
        RawChat(
            rowID: rowID,
            guid: guid,
            style: 43,
            chatIdentifier: nil,
            serviceName: nil,
            displayName: nil,
            memberHandleRowIDs: memberHandleRowIDs
        )
    }

    private func extract(chats: [RawChat]) -> ChatExtract {
        ChatExtract(handles: [], chats: chats, messages: [], unjoinedMessageCount: 0)
    }

    // MARK: - Person candidates

    func testUnnamedPersonWithOneToOneThreadBecomesACandidate() {
        let unnamed = person(id: "+15550001", handleRowIDs: [1])
        let chats = [oneToOneChat(rowID: 100, guid: "chat-1", memberHandleRowID: 1)]
        let graph = Graph(nodes: [], edges: [])

        let sources = GuessCandidateSelection.buildSources(graph: graph, keptPeople: [unnamed], extract: extract(chats: chats))

        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources[0].candidate.key, "+15550001")
        XCTAssertEqual(sources[0].chatRowIDs, [100])
        XCTAssertEqual(sources[0].candidate.context, .person(identifier: "+15550001"))
    }

    func testNamedPersonIsNeverACandidate() {
        let named = person(id: "+15550002", handleRowIDs: [2], name: "Ada Lovelace")
        let chats = [oneToOneChat(rowID: 200, guid: "chat-2", memberHandleRowID: 2)]
        let graph = Graph(nodes: [], edges: [])

        let sources = GuessCandidateSelection.buildSources(graph: graph, keptPeople: [named], extract: extract(chats: chats))

        XCTAssertTrue(sources.isEmpty, "a person who already has a real name must never be re-guessed")
    }

    func testUnnamedPersonWithNoOneToOneThreadIsNotACandidate() {
        // No thread at all, so there is nothing to build a prompt from -- this is the case
        // GuessCandidateSelection's own doc comment calls "guard !rowIDs.isEmpty else { continue }".
        let unnamed = person(id: "+15550003", handleRowIDs: [3])
        let graph = Graph(nodes: [], edges: [])

        let sources = GuessCandidateSelection.buildSources(graph: graph, keptPeople: [unnamed], extract: extract(chats: []))

        XCTAssertTrue(sources.isEmpty)
    }

    func testAlreadyGuessedPersonKeyIsStillReturnedAsACandidate() {
        // Cache-skipping is GuessEngine's job (see GuessEngineTests), not this pure selection
        // function's: it always returns every eligible unnamed person, and the caller (both
        // AppModel and graph-cli's `guess`) is the one that diffs against the cache to find
        // pending work. Pinning this here guards against that responsibility silently
        // creeping into selection, which would make the two callers' pending counts disagree
        // if one applied the cache filter and the other forgot to.
        let unnamed = person(id: "+15550004", handleRowIDs: [4])
        let chats = [oneToOneChat(rowID: 400, guid: "chat-4", memberHandleRowID: 4)]
        let graph = Graph(nodes: [], edges: [])

        let sources = GuessCandidateSelection.buildSources(graph: graph, keptPeople: [unnamed], extract: extract(chats: chats))

        XCTAssertEqual(sources.count, 1)
    }

    // MARK: - Group candidates

    func testUnnamedLiveGroupBecomesACandidateWithKnownMemberNames() {
        let alice = person(id: "+15550005", handleRowIDs: [5], name: "Alice")
        let bob = person(id: "+15550006", handleRowIDs: [6])
        let groupNode = GraphNode(
            id: "chat:group-guid",
            kind: .group,
            name: nil,
            thumbnailImageData: nil,
            hasContactCard: false,
            isLive: true,
            degree: 2
        )
        let aliceNode = GraphNode(
            id: "+15550005", kind: .person, name: "Alice", thumbnailImageData: nil,
            hasContactCard: false, isLive: false, degree: 1
        )
        let bobNode = GraphNode(
            id: "+15550006", kind: .person, name: nil, thumbnailImageData: nil,
            hasContactCard: false, isLive: false, degree: 1
        )
        let membershipEdgeAlice = GraphEdge(
            nodeIDA: "+15550005", nodeIDB: "chat:group-guid", source: .imessage,
            reason: .groupMembership, strength: 1, involvesUser: false
        )
        let membershipEdgeBob = GraphEdge(
            nodeIDA: "+15550006", nodeIDB: "chat:group-guid", source: .imessage,
            reason: .groupMembership, strength: 1, involvesUser: false
        )
        let graph = Graph(nodes: [groupNode, aliceNode, bobNode], edges: [membershipEdgeAlice, membershipEdgeBob])
        let chats = [groupChat(rowID: 500, guid: "group-guid", memberHandleRowIDs: [5, 6])]

        let sources = GuessCandidateSelection.buildSources(graph: graph, keptPeople: [alice, bob], extract: extract(chats: chats))

        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources[0].candidate.key, "group:group-guid")
        XCTAssertEqual(sources[0].chatRowIDs, [500])
        XCTAssertEqual(sources[0].candidate.context, .group(memberNames: ["Alice"]))
    }

    func testDeadGroupIsNeverACandidate() {
        let deadGroupNode = GraphNode(
            id: "chat:dead-guid", kind: .group, name: nil, thumbnailImageData: nil,
            hasContactCard: false, isLive: false, degree: 0
        )
        let graph = Graph(nodes: [deadGroupNode], edges: [])
        let chats = [groupChat(rowID: 600, guid: "dead-guid", memberHandleRowIDs: [7, 8])]

        let sources = GuessCandidateSelection.buildSources(graph: graph, keptPeople: [], extract: extract(chats: chats))

        XCTAssertTrue(sources.isEmpty, "a dead group is never worth a model call")
    }

    func testNamedGroupIsNeverACandidate() {
        let namedGroupNode = GraphNode(
            id: "chat:named-guid", kind: .group, name: "Ski cabin", thumbnailImageData: nil,
            hasContactCard: false, isLive: true, degree: 0
        )
        let graph = Graph(nodes: [namedGroupNode], edges: [])
        let chats = [groupChat(rowID: 700, guid: "named-guid", memberHandleRowIDs: [9, 10])]

        let sources = GuessCandidateSelection.buildSources(graph: graph, keptPeople: [], extract: extract(chats: chats))

        XCTAssertTrue(sources.isEmpty)
    }
}
