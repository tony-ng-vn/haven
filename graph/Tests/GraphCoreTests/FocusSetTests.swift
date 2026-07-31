import XCTest
@testable import GraphCore

final class FocusSetTests: XCTestCase {

    private func node(id: String, kind: NodeKind) -> GraphNode {
        GraphNode(id: id, kind: kind, name: nil, thumbnailImageData: nil, hasContactCard: false, isLive: true, degree: 0)
    }

    private func edge(_ a: String, _ b: String, reason: EdgeReason, involvesUser: Bool) -> GraphEdge {
        GraphEdge(nodeIDA: a, nodeIDB: b, source: .imessage, reason: reason, strength: 1, involvesUser: involvesUser)
    }

    /// user + 2 persons (each with a one-to-one thread) + 1 group with both persons as
    /// members + a third person who is only in the group, not a direct one-to-one contact.
    private func fixtureGraph() -> Graph {
        let nodes: [GraphNode] = [
            node(id: "user", kind: .user),
            node(id: "alice", kind: .person),
            node(id: "bob", kind: .person),
            node(id: "carol", kind: .person),
            node(id: "chat:g1", kind: .group),
        ]
        let edges: [GraphEdge] = [
            edge("user", "alice", reason: .oneToOneThread, involvesUser: true),
            edge("user", "bob", reason: .oneToOneThread, involvesUser: true),
            edge("alice", "chat:g1", reason: .groupMembership, involvesUser: false),
            edge("bob", "chat:g1", reason: .groupMembership, involvesUser: false),
            edge("carol", "chat:g1", reason: .groupMembership, involvesUser: false),
            edge("user", "chat:g1", reason: .userGroupMembership, involvesUser: true),
        ]
        return Graph(nodes: nodes, edges: edges)
    }

    func testFocusingPersonIncludesOwnUserEdgeAndTheirGroupButNotOtherMembers() {
        let focus = FocusSet.compute(graph: fixtureGraph(), focusedNodeID: "alice")

        XCTAssertEqual(focus.highlightedNodeIDs, ["alice", "user", "chat:g1"])
        XCTAssertEqual(focus.highlightedEdgeIDs, [
            GraphEdge(nodeIDA: "user", nodeIDB: "alice", source: .imessage, reason: .oneToOneThread, strength: 1, involvesUser: true).id,
            GraphEdge(nodeIDA: "alice", nodeIDB: "chat:g1", source: .imessage, reason: .groupMembership, strength: 1, involvesUser: false).id,
        ])
        // Bob is a fellow group member, reached only via the group, not a direct neighbor.
        XCTAssertFalse(focus.highlightedNodeIDs.contains("bob"), "a shared group's other members must not be highlighted")
        XCTAssertFalse(focus.highlightedNodeIDs.contains("carol"))
    }

    func testFocusingGroupExcludesItsOwnUserGroupMembershipEdge() {
        let focus = FocusSet.compute(graph: fixtureGraph(), focusedNodeID: "chat:g1")

        XCTAssertEqual(focus.highlightedNodeIDs, ["chat:g1", "alice", "bob", "carol"])
        XCTAssertFalse(focus.highlightedNodeIDs.contains("user"), "a group's own involvesUser edge is not part of its highlight, only a person's is")
        for edgeID in focus.highlightedEdgeIDs {
            XCTAssertFalse(edgeID.contains("user"), "no involvesUser edge should be highlighted for a group focus")
        }
        XCTAssertEqual(focus.highlightedEdgeIDs.count, 3)
    }

    func testFocusingUserLightsAllInvolvesUserEdges() {
        let focus = FocusSet.compute(graph: fixtureGraph(), focusedNodeID: "user")

        XCTAssertEqual(focus.highlightedNodeIDs, ["user", "alice", "bob", "chat:g1"])
        XCTAssertEqual(focus.highlightedEdgeIDs.count, 3, "all 3 involvesUser edges: alice, bob, chat:g1")
        XCTAssertFalse(focus.highlightedNodeIDs.contains("carol"), "carol has no involvesUser edge of her own")
    }

    func testUnknownIDReturnsEmptyFocusSet() {
        let focus = FocusSet.compute(graph: fixtureGraph(), focusedNodeID: "nobody")

        XCTAssertTrue(focus.highlightedNodeIDs.isEmpty)
        XCTAssertTrue(focus.highlightedEdgeIDs.isEmpty)
    }
}
