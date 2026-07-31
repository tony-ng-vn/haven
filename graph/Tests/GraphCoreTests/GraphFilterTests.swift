import XCTest
@testable import GraphCore

final class GraphFilterTests: XCTestCase {

    private func node(id: String, kind: NodeKind, degree: Int) -> GraphNode {
        GraphNode(id: id, kind: kind, name: nil, thumbnailImageData: nil, hasContactCard: false, isLive: true, degree: degree)
    }

    private func edge(_ a: String, _ b: String, reason: EdgeReason, involvesUser: Bool) -> GraphEdge {
        GraphEdge(nodeIDA: a, nodeIDB: b, source: .imessage, reason: reason, strength: 1, involvesUser: involvesUser)
    }

    private func fixtureGraph() -> Graph {
        let nodes: [GraphNode] = [
            node(id: "user", kind: .user, degree: 2),
            node(id: "alice", kind: .person, degree: 2),
            node(id: "bob", kind: .person, degree: 1),
            node(id: "chat:g1", kind: .group, degree: 3),
        ]
        let edges: [GraphEdge] = [
            edge("user", "alice", reason: .oneToOneThread, involvesUser: true),
            edge("alice", "chat:g1", reason: .groupMembership, involvesUser: false),
            edge("bob", "chat:g1", reason: .groupMembership, involvesUser: false),
            edge("user", "chat:g1", reason: .userGroupMembership, involvesUser: true),
        ]
        return Graph(nodes: nodes, edges: edges)
    }

    func testHidingAGroupRemovesItsMembershipEdgesAndUpdatesDegree() {
        let filtered = fixtureGraph().excludingNodes(["chat:g1"])

        XCTAssertEqual(filtered.nodes.map(\.id), ["alice", "bob", "user"])
        XCTAssertEqual(filtered.edges.map(\.id), ["alice|user"], "only the one-to-one thread survives; both membership edges and the userGroupMembership edge are gone")

        let aliceDegree = filtered.nodes.first { $0.id == "alice" }?.degree
        let bobDegree = filtered.nodes.first { $0.id == "bob" }?.degree
        let userDegree = filtered.nodes.first { $0.id == "user" }?.degree
        XCTAssertEqual(aliceDegree, 1, "alice loses her groupMembership edge, keeps her oneToOneThread")
        XCTAssertEqual(bobDegree, 0, "bob's only edge was the one to the now-hidden group")
        XCTAssertEqual(userDegree, 1, "user loses the userGroupMembership edge, keeps the oneToOneThread")
    }

    func testHidingAnUnknownIDIsANoOp() {
        let original = fixtureGraph()
        let filtered = original.excludingNodes(["nobody"])

        XCTAssertEqual(filtered.nodes.map(\.id).sorted(), original.nodes.map(\.id).sorted())
        XCTAssertEqual(filtered.edges.map(\.id).sorted(), original.edges.map(\.id).sorted())
    }

    func testHidingAnEmptySetReturnsAnEquivalentGraph() {
        let original = fixtureGraph()
        let filtered = original.excludingNodes([])

        XCTAssertEqual(filtered.nodes.count, original.nodes.count)
        XCTAssertEqual(filtered.edges.count, original.edges.count)
    }
}
