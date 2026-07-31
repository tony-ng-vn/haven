import Foundation

/// What lights up when a node is focused: the node itself plus its direct neighbors, and
/// the edges that justify each highlight. An empty set (unknown id) means "no focus", not
/// "focus on nothing" -- callers should treat `highlightedNodeIDs.isEmpty` as "dim nothing".
public struct FocusSet: Sendable, Equatable {
    public let focusedNodeID: String
    public let highlightedNodeIDs: Set<String>
    public let highlightedEdgeIDs: Set<String>

    public init(focusedNodeID: String, highlightedNodeIDs: Set<String>, highlightedEdgeIDs: Set<String>) {
        self.focusedNodeID = focusedNodeID
        self.highlightedNodeIDs = highlightedNodeIDs
        self.highlightedEdgeIDs = highlightedEdgeIDs
    }

    /// Direct neighbors only, one hop: a shared group's other members are never highlighted
    /// by focusing a person, since no edge connects them to the focused node directly.
    ///
    /// involvesUser edges are excluded by default (they are not part of the rest-state
    /// world), with two exceptions:
    /// - the user node itself: its highlight IS every involvesUser edge (PLAN.md's answer
    ///   to "who connects to me").
    /// - a person's own edge to the user: focusing a person answers "how do I know them",
    ///   and their direct line to the user is part of that answer. A group's own
    ///   userGroupMembership edge gets no such exception -- only persons do.
    public static func compute(graph: Graph, focusedNodeID: String) -> FocusSet {
        guard let focusedNode = graph.nodes.first(where: { $0.id == focusedNodeID }) else {
            return FocusSet(focusedNodeID: focusedNodeID, highlightedNodeIDs: [], highlightedEdgeIDs: [])
        }

        if focusedNode.kind == .user {
            var nodeIDs: Set<String> = ["user"]
            var edgeIDs: Set<String> = []
            for edge in graph.edges where edge.involvesUser {
                edgeIDs.insert(edge.id)
                nodeIDs.insert(edge.nodeIDA)
                nodeIDs.insert(edge.nodeIDB)
            }
            return FocusSet(focusedNodeID: focusedNodeID, highlightedNodeIDs: nodeIDs, highlightedEdgeIDs: edgeIDs)
        }

        var nodeIDs: Set<String> = [focusedNodeID]
        var edgeIDs: Set<String> = []
        let includesOwnUserEdge = focusedNode.kind == .person

        for edge in graph.edges {
            guard edge.nodeIDA == focusedNodeID || edge.nodeIDB == focusedNodeID else { continue }
            if edge.involvesUser {
                guard includesOwnUserEdge else { continue }
            }
            edgeIDs.insert(edge.id)
            nodeIDs.insert(edge.nodeIDA)
            nodeIDs.insert(edge.nodeIDB)
        }

        return FocusSet(focusedNodeID: focusedNodeID, highlightedNodeIDs: nodeIDs, highlightedEdgeIDs: edgeIDs)
    }
}
