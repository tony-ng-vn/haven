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
    let firstMessageDate: String?
    let lastMessageDate: String?

    private enum CodingKeys: String, CodingKey {
        case id, kind, name, hasContactCard, isLive, degree, firstMessageDate, lastMessageDate
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
        try container.encode(firstMessageDate, forKey: .firstMessageDate)
        try container.encode(lastMessageDate, forKey: .lastMessageDate)
    }
}

private struct JSONEdge: Encodable {
    let a: String
    let b: String
    let reason: String
    let strength: Double
}

/// Wire shape for one acquaintance's evidence (PLAN.md's JSON schema). Hand-written for the
/// same reason JSONNode is: chatName must encode JSON null for an unnamed chat, which
/// Encodable's synthesized encodeIfPresent would instead omit entirely.
private struct JSONAcquaintanceEvidence: Encodable {
    let chatId: String
    let chatName: String?
    let memberCount: Int
    let coActiveDays: Int

    private enum CodingKeys: String, CodingKey {
        case chatId, chatName, memberCount, coActiveDays
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(chatId, forKey: .chatId)
        try container.encode(chatName, forKey: .chatName)
        try container.encode(memberCount, forKey: .memberCount)
        try container.encode(coActiveDays, forKey: .coActiveDays)
    }
}

private struct JSONAcquaintance: Encodable {
    let a: String
    let b: String
    let tier: String
    let score: Double
    let evidence: [JSONAcquaintanceEvidence]
}

private struct JSONGraph: Encodable {
    let nodes: [JSONNode]
    let edges: [JSONEdge]
    let acquaintances: [JSONAcquaintance]
    let fullyAcquaintedChatIds: [String]
    /// True when at least one node carries a real firstMessageDate. Lets the viewer tell "this
    /// export has dates" from "this export predates the date feature" without inferring it from
    /// node contents (every node's dates being nil would otherwise be ambiguous either way).
    let hasHistory: Bool
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
    ///
    /// `groupChatActivity`/`fullyAcquaintedRosterKeys` default to empty for the same reason:
    /// every existing call site keeps encoding an empty acquaintances/fullyAcquaintedChatIds
    /// pair, unchanged, until it deliberately opts in.
    ///
    /// `people` is the CURRENT (post-filter) roster of known people, needed only to translate
    /// `fullyAcquaintedRosterKeys` (captured at mark time, so possibly built from a member's
    /// now-stale Person.id) into its current form before matching -- see
    /// AcquaintanceRosterKey.resolve's own doc comment. Defaults to empty like the other new
    /// parameters; with no people to translate against, every stored key is dormant, so a
    /// caller with real markings to honor must pass its real people list.
    public static func encode(
        graph: Graph,
        groupChatActivity: [GroupChatActivity] = [],
        fullyAcquaintedRosterKeys: Set<[String]> = [],
        people: [Person] = [],
        guesses: [String: NameGuess] = [:]
    ) throws -> Data {
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
                    degree: $0.degree,
                    firstMessageDate: isoString($0.firstMessageDate),
                    lastMessageDate: isoString($0.lastMessageDate)
                )
            }
        let edges = graph.edges
            .sorted { $0.id < $1.id }
            .map { JSONEdge(a: $0.nodeIDA, b: $0.nodeIDB, reason: reasonLabel($0.reason), strength: $0.strength) }

        // chatName echoes the SAME resolved name the nodes array above already computed for
        // that chat id (guess and tilde-prefix included), never GroupChatActivity's own raw
        // name -- built from `nodes`, not re-derived, so the two can never disagree.
        // uniquingKeysWith, not uniqueKeysWithValues: GraphBuilder's own output never repeats
        // an id, but `encode` is a public entry point taking an arbitrary Graph, and a
        // hand-built one with a duplicate id must not crash a JSON export over a formatting
        // concern -- first value wins, arbitrarily but deterministically.
        let resolvedNameByID: [String: String?] = Dictionary(nodes.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        // Defensive against a caller exporting a graph with hidden/removed nodes already
        // excluded (Graph.excludingNodes): an acquaintance pair whose PERSON endpoint has no
        // node here is dropped entirely; one whose evidence names an excluded group chat keeps
        // the pair (the two people still know each other) but drops just that evidence entry --
        // score stays the full observed sum, evidence lists only chats present in this export.
        let nodeIDs = Set(graph.nodes.map(\.id))
        // Translated ONCE, reused for both the tier decision below and the
        // fullyAcquaintedChatIds echo -- see AcquaintanceRosterKey.resolve's own doc comment
        // for why exact equality against the raw stored keys would silently detach a marking
        // the moment a member's Person.id shifts underneath it.
        let translatedRosterKeys = AcquaintanceRosterKey.resolve(stored: fullyAcquaintedRosterKeys, people: people)

        let acquaintances = AcquaintanceDerivation
            .derive(groupChatActivity: groupChatActivity, fullyAcquaintedRosterKeys: translatedRosterKeys)
            .filter { nodeIDs.contains($0.a) && nodeIDs.contains($0.b) }
            .map { acquaintance in
                JSONAcquaintance(
                    a: acquaintance.a,
                    b: acquaintance.b,
                    tier: tierLabel(acquaintance.tier),
                    score: acquaintance.score,
                    evidence: acquaintance.evidence
                        .filter { nodeIDs.contains($0.chatId) }
                        .map {
                            JSONAcquaintanceEvidence(
                                chatId: $0.chatId,
                                chatName: resolvedNameByID[$0.chatId] ?? nil,
                                memberCount: $0.memberCount,
                                coActiveDays: $0.coActiveDays
                            )
                        }
                )
            }
        let fullyAcquaintedChatIds = groupChatActivity
            .filter { nodeIDs.contains($0.chatId) && translatedRosterKeys.contains(AcquaintanceRosterKey.canonicalize($0.roster)) }
            .map(\.chatId)
            .sorted()

        let encoder = JSONEncoder()
        // Compact, not .prettyPrinted: this file is meant to be embedded in HTML.
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(
            JSONGraph(
                nodes: nodes,
                edges: edges,
                acquaintances: acquaintances,
                fullyAcquaintedChatIds: fullyAcquaintedChatIds,
                hasHistory: graph.nodes.contains { $0.firstMessageDate != nil }
            )
        )
    }

    // A fresh formatter per call, not a shared static: ISO8601DateFormatter is not Sendable,
    // and this file's public encode entry point has no actor isolation to lean on.
    private static func isoString(_ date: Date?) -> String? {
        guard let date else { return nil }
        return ISO8601DateFormatter().string(from: date)
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

    private static func tierLabel(_ tier: AcquaintanceTier) -> String {
        switch tier {
        case .confirmed: return "confirmed"
        case .strong: return "strong"
        case .likely: return "likely"
        }
    }
}
