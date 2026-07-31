import XCTest
@testable import GraphCore

final class DensityMetricTests: XCTestCase {

    private func node(id: String, kind: NodeKind, isLive: Bool = true) -> GraphNode {
        GraphNode(id: id, kind: kind, name: nil, thumbnailImageData: nil, hasContactCard: false, isLive: isLive, degree: 0)
    }

    private func edge(_ a: String, _ b: String, reason: EdgeReason, involvesUser: Bool) -> GraphEdge {
        GraphEdge(nodeIDA: a, nodeIDB: b, source: .imessage, reason: reason, strength: 1, involvesUser: involvesUser)
    }

    /// Pinned fixture: 2 person nodes, 1 live group, 1 dead group.
    /// oneToOneThread: user-alice (1).
    /// groupMembership: alice-liveGroup, bob-liveGroup, alice-deadGroup (3).
    /// userGroupMembership: user-liveGroup, user-deadGroup (2) -- these must NOT count in the
    /// numerator; PLAN.md's calibration figure never included user edges.
    /// Denominator: personNodes(2) + LIVE groupNodes(1) = 3 -- the dead group does not count.
    /// Expected: (1 oneToOneThread + 3 groupMembership) / 3 = 4/3.
    private func fixtureGraph() -> Graph {
        let nodes: [GraphNode] = [
            node(id: "user", kind: .user),
            node(id: "alice", kind: .person),
            node(id: "bob", kind: .person),
            node(id: "chat:live1", kind: .group, isLive: true),
            node(id: "chat:dead1", kind: .group, isLive: false),
        ]
        let edges: [GraphEdge] = [
            edge("user", "alice", reason: .oneToOneThread, involvesUser: true),
            edge("alice", "chat:live1", reason: .groupMembership, involvesUser: false),
            edge("bob", "chat:live1", reason: .groupMembership, involvesUser: false),
            edge("alice", "chat:dead1", reason: .groupMembership, involvesUser: false),
            edge("user", "chat:live1", reason: .userGroupMembership, involvesUser: true),
            edge("user", "chat:dead1", reason: .userGroupMembership, involvesUser: true),
        ]
        return Graph(nodes: nodes, edges: edges)
    }

    func testPlanComparableCountsOneToOneAndGroupMembershipOverPeoplePlusLiveGroups() {
        let result = DensityMetric.planComparable(graph: fixtureGraph())
        XCTAssertEqual(result, 4.0 / 3.0, accuracy: 0.0001)
    }

    func testPlanComparableExcludesUserGroupMembershipEdgesFromTheNumerator() {
        // Same fixture, but drop the two userGroupMembership edges: the result must be
        // unchanged, proving they were never part of the numerator to begin with.
        let graph = fixtureGraph()
        let withoutUserEdges = Graph(
            nodes: graph.nodes,
            edges: graph.edges.filter { $0.reason != .userGroupMembership }
        )
        XCTAssertEqual(DensityMetric.planComparable(graph: withoutUserEdges), 4.0 / 3.0, accuracy: 0.0001)
    }

    func testPlanComparableExcludesDeadGroupsFromTheDenominator() {
        // Same fixture, but drop the dead group node (and its edges): denominator becomes
        // personNodes(2) + liveGroupNodes(1) = 3 either way, so this must also be unchanged --
        // proving the dead group never contributed to the denominator.
        let graph = fixtureGraph()
        let withoutDeadGroup = Graph(
            nodes: graph.nodes.filter { $0.id != "chat:dead1" },
            edges: graph.edges.filter { $0.nodeIDA != "chat:dead1" && $0.nodeIDB != "chat:dead1" }
        )
        XCTAssertEqual(DensityMetric.planComparable(graph: withoutDeadGroup), 3.0 / 3.0, accuracy: 0.0001)
    }

    func testPlanComparableIsZeroWhenDenominatorIsZero() {
        let graph = Graph(nodes: [node(id: "user", kind: .user)], edges: [])
        XCTAssertEqual(DensityMetric.planComparable(graph: graph), 0.0)
    }
}
