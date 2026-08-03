import Foundation

/// One merged group chat's identity and per-member day-level activity, as seen by the
/// acquaintance derivation (AcquaintanceDerivation.swift). Produced by
/// GraphBuilder.buildDetailed alongside the Graph itself, from the SAME merged-chat pass that
/// already computes groupMembership edge strength -- so the derivation needs no extra database
/// read, just the day sets that pass was already touching before collapsing them to a count.
public struct GroupChatActivity: Sendable, Equatable {
    /// The group node id ("chat:<guid>"), the same id GraphBuilder gives the group's GraphNode.
    public let chatId: String
    /// Same resolved display name the group's GraphNode carries; nil when unnamed.
    public let name: String?
    /// Resolved member person ids, the user excluded -- same set GraphBuilder used to build
    /// this chat's groupMembership edges.
    public let roster: Set<String>
    /// Per member, the calendar days they posted in this chat (union across every merged
    /// service-split row). A lurker maps to an empty set, never an absent key -- every roster
    /// member appears here, matching groupMembership's own "lurkers get an edge too".
    public let activeDaysByPersonID: [String: Set<Date>]
    /// Per pair, how many tapback/reply interactions were observed between them in this ONE
    /// chat (union across every merged service-split row, same as activeDaysByPersonID) --
    /// already resolved to person ids and already dropped of self/user-involved interactions by
    /// GraphBuilder, so AcquaintanceDerivation can read this as a plain fact. Keyed by
    /// PersonPairKey.make(a, b); a pair absent here simply had zero interactions in this chat.
    /// Defaults to empty so every existing call site keeps constructing this type unchanged.
    public let interactionCountByPair: [String: Int]

    public init(
        chatId: String,
        name: String?,
        roster: Set<String>,
        activeDaysByPersonID: [String: Set<Date>],
        interactionCountByPair: [String: Int] = [:]
    ) {
        self.chatId = chatId
        self.name = name
        self.roster = roster
        self.activeDaysByPersonID = activeDaysByPersonID
        self.interactionCountByPair = interactionCountByPair
    }
}
