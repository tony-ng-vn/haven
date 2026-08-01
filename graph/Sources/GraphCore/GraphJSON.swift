import Foundation

/// Wire shape for GraphJSON.encode. A private DTO layer rather than Codable conformance on
/// GraphNode/GraphEdge themselves: the schema needs kind/reason spelled out as fixed strings
/// (not Swift's enum case names, which the external HTML viewer must never depend on), and
/// thumbnailImageData has no field here at all -- structurally impossible to leak, not just
/// behaviorally suppressed.
private struct JSONNode: Encodable {
    let id: String
    let kind: String
    let name: String?
    let hasContactCard: Bool
    let isLive: Bool
    let degree: Int

    private enum CodingKeys: String, CodingKey {
        case id, kind, name, hasContactCard, isLive, degree
    }

    // Hand-written, not synthesized: the synthesized Encodable calls encodeIfPresent for an
    // Optional and would silently omit the key for a nil name, but the schema promises JSON
    // null. container.encode(_:forKey:) on an Optional is what actually emits null.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(name, forKey: .name)
        try container.encode(hasContactCard, forKey: .hasContactCard)
        try container.encode(isLive, forKey: .isLive)
        try container.encode(degree, forKey: .degree)
    }
}

private struct JSONEdge: Encodable {
    let a: String
    let b: String
    let reason: String
    let strength: Double
}

private struct JSONGraph: Encodable {
    let nodes: [JSONNode]
    let edges: [JSONEdge]
}

/// Prints a built Graph as JSON for an external HTML viewer (a separate effort in parallel,
/// not part of this package). Pure presentation over GraphBuilder's output: no graph logic
/// is reimplemented here, only a label mapping and a stable ordering for the wire format.
public enum GraphJSON {
    /// `guesses` defaults to empty so every existing call site (and GraphJSONTests' own
    /// fixtures) keeps encoding node.name verbatim, unchanged. When passed, an unnamed node's
    /// name is filled in from the cache via NodeLabel.resolve -- the exact same rule the
    /// screen and image export already use, tilde-prefix and all, so this JSON export can
    /// never disagree with what the app itself shows for the same node.
    public static func encode(graph: Graph, guesses: [String: NameGuess] = [:]) throws -> Data {
        // Sorted here, not just left to .sortedKeys below: .sortedKeys only orders the keys
        // within one node/edge object, not the position of elements in the nodes/edges
        // arrays, which otherwise reflects whatever order the caller happened to build the
        // Graph in. Two runs on unchanged data must be byte-identical.
        let nodes = graph.nodes
            .sorted { $0.id < $1.id }
            .map {
                JSONNode(
                    id: $0.id,
                    kind: kindLabel($0.kind),
                    name: NodeLabel.resolve(node: $0, guesses: guesses),
                    hasContactCard: $0.hasContactCard,
                    isLive: $0.isLive,
                    degree: $0.degree
                )
            }
        let edges = graph.edges
            .sorted { $0.id < $1.id }
            .map { JSONEdge(a: $0.nodeIDA, b: $0.nodeIDB, reason: reasonLabel($0.reason), strength: $0.strength) }

        let encoder = JSONEncoder()
        // Compact, not .prettyPrinted: this file is meant to be embedded in HTML.
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(JSONGraph(nodes: nodes, edges: edges))
    }

    // kindLabel/reasonLabel below have no default case on purpose: a new NodeKind or
    // EdgeReason member fails this file to compile until it is given a label here, instead
    // of silently falling through to nothing in the exported JSON.
    private static func kindLabel(_ kind: NodeKind) -> String {
        switch kind {
        case .user: return "user"
        case .person: return "person"
        case .group: return "group"
        }
    }

    private static func reasonLabel(_ reason: EdgeReason) -> String {
        switch reason {
        case .oneToOneThread: return "oneToOneThread"
        case .groupMembership: return "groupMembership"
        case .userGroupMembership: return "userGroupMembership"
        }
    }
}
