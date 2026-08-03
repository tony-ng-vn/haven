import Foundation

/// PLAN.md, "The acquaintance layer": how confident the derivation (or the user) is that two
/// people know each other. No raw value on purpose, matching NodeKind/EdgeReason -- a new case
/// must fail every switch over this type to compile until given a label, rather than silently
/// falling through to nothing in an export.
public enum AcquaintanceTier: Sendable, Equatable, CaseIterable {
    /// The user vouched for the pair via the per-chat "everyone here knows each other" marker.
    /// Never produced by scoring alone.
    case confirmed
    case strong
    case likely
}

/// One shared group chat's contribution to a pair's acquaintance score, kept for the "why do
/// you think these two know each other" answer (PLAN.md).
public struct AcquaintanceEvidence: Sendable, Equatable {
    public let chatId: String
    public let chatName: String?
    /// Distinct resolved members in that chat, the user excluded.
    public let memberCount: Int
    /// The RAW (uncapped) count of days both people were active in this chat -- a fact, unlike
    /// the capped count AcquaintanceScoring actually adds to the score.
    public let coActiveDays: Int
    /// Tapback/reply interactions between this pair observed in THIS chat only -- a fact, like
    /// coActiveDays, never itself capped or weighted (AcquaintanceScoring.
    /// interactionPromotionThreshold compares against the pair's TOTAL across every chat, on
    /// Acquaintance itself, not this per-chat figure).
    public let interactionCount: Int

    public init(chatId: String, chatName: String?, memberCount: Int, coActiveDays: Int, interactionCount: Int = 0) {
        self.chatId = chatId
        self.chatName = chatName
        self.memberCount = memberCount
        self.coActiveDays = coActiveDays
        self.interactionCount = interactionCount
    }
}

/// A derived person-to-person edge: "who appears to know whom", with explicit confidence and
/// inspectable evidence (PLAN.md). Distinct from GraphEdge -- this never replaces the bipartite
/// group-membership record, it summarizes it.
public struct Acquaintance: Sendable, Equatable {
    /// Person node ids, canonically ordered a < b lexicographically (PLAN.md's JSON schema),
    /// the same convention GraphEdge.init already uses for nodeIDA/nodeIDB, so a caller can
    /// never build a pair with the order reversed.
    public let a: String
    public let b: String
    public let tier: AcquaintanceTier
    public let score: Double
    public let evidence: [AcquaintanceEvidence]
    /// Sum of every evidence entry's interactionCount -- the total tapback/reply count across
    /// every shared chat, the figure AcquaintanceScoring.interactionPromotionThreshold compares
    /// against. Set once at derivation, not recomputed from evidence at read time, the same
    /// posture `score` itself already has.
    public let interactionCount: Int

    public init(
        a: String,
        b: String,
        tier: AcquaintanceTier,
        score: Double,
        evidence: [AcquaintanceEvidence],
        interactionCount: Int = 0
    ) {
        if a <= b {
            self.a = a
            self.b = b
        } else {
            self.a = b
            self.b = a
        }
        self.tier = tier
        self.score = score
        self.evidence = evidence
        self.interactionCount = interactionCount
    }
}
