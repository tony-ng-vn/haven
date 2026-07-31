import Foundation
import CoreGraphics

/// One edge worth drawing: both endpoints resolved to a screen position already, so the view
/// never has to look anything up mid-render.
public struct VisibleEdge: Sendable, Equatable {
    public let id: String
    public let from: CGPoint
    public let to: CGPoint
    public let strength: Double

    public init(id: String, from: CGPoint, to: CGPoint, strength: Double) {
        self.id = id
        self.from = from
        self.to = to
        self.strength = strength
    }
}

/// Which edges the rest-state render draws: non-user edges between two currently visible
/// (positioned) nodes. A dead group's edges have no position on either side (ForceSimulation
/// excludes dead groups from `positions` entirely) and so drop out here for free, without
/// this needing to know anything about liveness itself.
public enum EdgeRenderList {
    public static func visibleEdges(graph: Graph, positions: [String: CGPoint]) -> [VisibleEdge] {
        graph.edges
            .filter { !$0.involvesUser }
            .compactMap { edge in
                guard let from = positions[edge.nodeIDA], let to = positions[edge.nodeIDB] else { return nil }
                return VisibleEdge(id: edge.id, from: from, to: to, strength: edge.strength)
            }
            .sorted { $0.id < $1.id }
    }
}
