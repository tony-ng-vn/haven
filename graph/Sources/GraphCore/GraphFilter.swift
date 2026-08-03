import Foundation

extension Graph {
    /// Removes the given nodes and every edge incident to any of them, recomputing degree so
    /// the returned Graph's own node.degree describes its own edges, not a stale count from
    /// before the removal. Used by hide-nodes, which is render-only (see AppModel): this is
    /// applied to what the renderer sees, never fed back into the simulation.
    public func excludingNodes(_ ids: Set<String>) -> Graph {
        guard !ids.isEmpty else { return self }

        let remainingNodes = nodes.filter { !ids.contains($0.id) }
        let remainingEdges = edges.filter { !ids.contains($0.nodeIDA) && !ids.contains($0.nodeIDB) }

        var degreeByID: [String: Int] = [:]
        for edge in remainingEdges {
            degreeByID[edge.nodeIDA, default: 0] += 1
            degreeByID[edge.nodeIDB, default: 0] += 1
        }

        let updatedNodes = remainingNodes.map { node in
            GraphNode(
                id: node.id,
                kind: node.kind,
                name: node.name,
                thumbnailImageData: node.thumbnailImageData,
                hasContactCard: node.hasContactCard,
                isLive: node.isLive,
                degree: degreeByID[node.id] ?? 0,
                firstMessageDate: node.firstMessageDate,
                lastMessageDate: node.lastMessageDate
            )
        }

        return Graph(
            nodes: updatedNodes.sorted { $0.id < $1.id },
            edges: remainingEdges.sorted { $0.id < $1.id }
        )
    }
}
