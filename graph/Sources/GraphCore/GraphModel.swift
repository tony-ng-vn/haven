import Foundation

public enum NodeKind: Sendable, Equatable {
    case user
    case person
    case group
}

/// A node in the connection graph. Fields not meaningful for a given kind are left at
/// their neutral default (nil / false) rather than modeled as per-kind associated values:
/// a single flat, sortable, Equatable shape is what the renderer and the tests both want.
public struct GraphNode: Sendable, Equatable {
    public let id: String
    public let kind: NodeKind
    /// .person only: the card-derived display name.
    public let name: String?
    /// .person only.
    public let thumbnailImageData: Data?
    /// .person only.
    public let hasContactCard: Bool
    /// .group only: 2+ distinct calendar days of messages. Dead groups are still built,
    /// just flagged false: the plan hides them behind a toggle, never deletes them.
    public let isLive: Bool
    /// Incident edge count. The renderer sizes nodes by this, except the user's.
    public let degree: Int

    public init(
        id: String,
        kind: NodeKind,
        name: String?,
        thumbnailImageData: Data?,
        hasContactCard: Bool,
        isLive: Bool,
        degree: Int
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.thumbnailImageData = thumbnailImageData
        self.hasContactCard = hasContactCard
        self.isLive = isLive
        self.degree = degree
    }
}

/// Where an edge's evidence came from. An enum from day one so call history can arrive
/// later as a new ingest path (PLAN.md) rather than a reshape of this type.
public enum EdgeSource: Sendable, Equatable, CaseIterable {
    case imessage
}

public enum EdgeReason: Sendable, Equatable, CaseIterable {
    case oneToOneThread
    case groupMembership
    case userGroupMembership
}

public struct GraphEdge: Sendable, Equatable {
    /// Canonical "smaller|larger" pair id: stable dedup key and sort/tie-break key.
    public let id: String
    public let nodeIDA: String
    public let nodeIDB: String
    public let source: EdgeSource
    public let reason: EdgeReason
    public let strength: Double
    /// True for any edge touching the user node. The renderer excludes these from the
    /// force simulation and rest-state render; pruning exempts them entirely so focus
    /// mode never silently loses an edge.
    public let involvesUser: Bool

    public init(nodeIDA: String, nodeIDB: String, source: EdgeSource, reason: EdgeReason, strength: Double, involvesUser: Bool) {
        // Canonical ordering so the pair "A,B" and "B,A" are always the same edge.
        if nodeIDA <= nodeIDB {
            self.nodeIDA = nodeIDA
            self.nodeIDB = nodeIDB
        } else {
            self.nodeIDA = nodeIDB
            self.nodeIDB = nodeIDA
        }
        self.id = "\(self.nodeIDA)|\(self.nodeIDB)"
        self.source = source
        self.reason = reason
        self.strength = strength
        self.involvesUser = involvesUser
    }
}

public struct Graph: Sendable, Equatable {
    public let nodes: [GraphNode]
    public let edges: [GraphEdge]

    public init(nodes: [GraphNode], edges: [GraphEdge]) {
        self.nodes = nodes
        self.edges = edges
    }
}
