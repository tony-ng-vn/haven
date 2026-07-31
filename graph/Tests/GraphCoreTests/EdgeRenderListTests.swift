import XCTest
@testable import GraphCore

final class EdgeRenderListTests: XCTestCase {

    private func edge(_ a: String, _ b: String, reason: EdgeReason, strength: Double, involvesUser: Bool) -> GraphEdge {
        GraphEdge(nodeIDA: a, nodeIDB: b, source: .imessage, reason: reason, strength: strength, involvesUser: involvesUser)
    }

    func testExcludesUserEdgesAndEdgesToNodesWithNoPosition() {
        let edges: [GraphEdge] = [
            edge("user", "person1", reason: .oneToOneThread, strength: 5, involvesUser: true),
            edge("person1", "chat:live", reason: .groupMembership, strength: 2, involvesUser: false),
            // "chat:dead" has no entry in `positions` below, standing in for a dead group
            // ForceSimulation excluded from its visible set.
            edge("person1", "chat:dead", reason: .groupMembership, strength: 9, involvesUser: false),
        ]
        let graph = Graph(nodes: [], edges: edges)
        let positions: [String: CGPoint] = [
            "user": CGPoint(x: 0, y: 0),
            "person1": CGPoint(x: 10, y: 10),
            "chat:live": CGPoint(x: 20, y: 20),
        ]

        let visible = EdgeRenderList.visibleEdges(graph: graph, positions: positions)

        XCTAssertEqual(visible.count, 1)
        let only = visible[0]
        XCTAssertEqual(only.id, "chat:live|person1")
        // GraphEdge canonically orders its pair "smaller|larger" by string, and "chat:live"
        // sorts before "person1", so nodeIDA/from is the group, nodeIDB/to is the person.
        XCTAssertEqual(only.from, CGPoint(x: 20, y: 20))
        XCTAssertEqual(only.to, CGPoint(x: 10, y: 10))
        XCTAssertEqual(only.strength, 2)
    }

    func testOrderIsDeterministicByID() {
        let edges: [GraphEdge] = [
            edge("z", "b", reason: .groupMembership, strength: 1, involvesUser: false),
            edge("a", "b", reason: .groupMembership, strength: 1, involvesUser: false),
        ]
        let graph = Graph(nodes: [], edges: edges)
        let positions: [String: CGPoint] = [
            "z": CGPoint(x: 0, y: 0),
            "a": CGPoint(x: 1, y: 1),
            "b": CGPoint(x: 2, y: 2),
        ]

        let visible = EdgeRenderList.visibleEdges(graph: graph, positions: positions)

        XCTAssertEqual(visible.map(\.id), ["a|b", "b|z"])
    }
}
