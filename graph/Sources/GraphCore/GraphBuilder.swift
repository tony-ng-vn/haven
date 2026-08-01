import Foundation

/// buildDetailed's return: the Graph plus the per-(chat, person) day activity the acquaintance
/// layer needs (PLAN.md, "The acquaintance layer"). A separate type from Graph itself: nodes
/// and edges are the stable public contract every existing caller relies on, and activity data
/// is an addition only the acquaintance derivation and its callers need to see.
public struct GraphBuildResult: Sendable, Equatable {
    public let graph: Graph
    public let groupChatActivity: [GroupChatActivity]

    public init(graph: Graph, groupChatActivity: [GroupChatActivity]) {
        self.graph = graph
        self.groupChatActivity = groupChatActivity
    }
}

public enum GraphBuilder {
    public static func build(
        extract: ChatExtract,
        keptPeople: [Person],
        calendar: Calendar = .current
    ) -> Graph {
        buildDetailed(extract: extract, keptPeople: keptPeople, calendar: calendar).graph
    }

    /// Same derivation as `build`, plus GroupChatActivity. A separate entry point rather than
    /// changing `build`'s own return type: `build` has ~30 existing call sites across the app,
    /// CLI, and test target that only ever wanted a Graph, and none of them should have to
    /// change just because one new caller (the acquaintance layer) also wants activity data.
    public static func buildDetailed(
        extract: ChatExtract,
        keptPeople: [Person],
        calendar: Calendar = .current
    ) -> GraphBuildResult {
        // Only kept people resolve to a node/edge: a removed person's handle appearing in a
        // roster simply fails this lookup and produces nothing for them.
        let handleToPersonID = Dictionary(
            uniqueKeysWithValues: keptPeople.flatMap { person in person.handleRowIDs.map { ($0, person.id) } }
        )
        let personByID = Dictionary(uniqueKeysWithValues: keptPeople.map { ($0.id, $0) })
        let chatKindByRowID = ChatClassification.classify(chats: extract.chats, handleToPersonID: handleToPersonID)

        var messagesByChat: [Int64: [RawMessage]] = [:]
        for message in extract.messages {
            messagesByChat[message.chatRowID, default: []].append(message)
        }

        // Person -> the one-to-one-classified chat rowIDs whose roster includes their handle.
        // A merged, multi-service person can own several (a different single-handle roster
        // for each service), which is exactly why this is a person-to-chats map, not 1:1.
        var oneToOneChatRowIDsByPersonID: [String: Set<Int64>] = [:]
        for chat in extract.chats {
            guard chatKindByRowID[chat.rowID] == .oneToOne else { continue }
            for personID in ChatRoster.resolvedPersonIDs(chat, handleToPersonID: handleToPersonID) {
                oneToOneChatRowIDsByPersonID[personID, default: []].insert(chat.rowID)
            }
        }

        var edgesByID: [String: GraphEdge] = [:]

        // oneToOneThread edges: one per kept person who has at least one such thread.
        // Sorted iteration so "insert if absent" ordering (irrelevant here, ids are unique
        // per person) is still deterministic end to end.
        for personID in oneToOneChatRowIDsByPersonID.keys.sorted() {
            let chatRowIDs = oneToOneChatRowIDsByPersonID[personID] ?? []
            let combinedMessages = chatRowIDs.sorted().flatMap { messagesByChat[$0] ?? [] }
            let edge = GraphEdge(
                nodeIDA: "user",
                nodeIDB: personID,
                source: .imessage,
                reason: .oneToOneThread,
                strength: Double(distinctDays(combinedMessages, calendar: calendar)),
                involvesUser: true
            )
            if edgesByID[edge.id] == nil {
                edgesByID[edge.id] = edge
            }
        }

        // Group nodes: one per style-43 chat classified as .group (2+ distinct resolved
        // people, per ChatClassification). A dead group (few days of activity, isLive below)
        // is still built -- liveness alone never decides whether a node exists.
        //
        // A group where every member was filtered out (bulk/spam rosters: shortcode senders,
        // never-replied handles, etc., 16-20 "members" apiece in real data) is different:
        // handleToPersonID above contains only KEPT people, so an all-filtered roster resolves
        // to 0 distinct people and never reaches .group classification at all -- no node is
        // built for it. This is an intentional behavior change from the old raw-roster-count
        // rule, which built a node for any 3+-handle roster regardless of who survived
        // filtering: an empty group connected to nothing but the user was noise, not signal.
        // Verified against real data: 22 such all-filtered groups stopped rendering when this
        // fix landed, alongside 33 real groups (previously miscounted as one-to-one, 3 of
        // them losing a real user-set name in the process) that started rendering correctly.
        var groupNodes: [GraphNode] = []
        var groupChatActivity: [GroupChatActivity] = []
        let groupChats = extract.chats.filter { chatKindByRowID[$0.rowID] == .group }

        for merged in mergedGroupChats(groupChats, handleToPersonID: handleToPersonID) {
            let groupID = merged.id
            // Union at the message level: flatten every merged chat's messages into one array
            // first, then compute distinctDays/filters once, so a day the user texted on both
            // iMessage and SMS is never counted twice.
            let combinedMessages = merged.chatRowIDs.sorted().flatMap { messagesByChat[$0] ?? [] }
            let isLive = distinctDays(combinedMessages, calendar: calendar) >= 2

            groupNodes.append(
                GraphNode(
                    id: groupID,
                    kind: .group,
                    name: merged.name,
                    thumbnailImageData: nil,
                    hasContactCard: false,
                    isLive: isLive,
                    degree: 0 // filled in by finalize()
                )
            )

            // groupMembership: every kept member, even a lurker with zero messages of their
            // own (roster is historical truth from chat_handle_join, not message activity).
            // activeDaysByPersonID is collected in the same pass: the acquaintance layer
            // (AcquaintanceDerivation) needs each member's day SET, not just its count, and
            // this is the one place that per-member message activity is already being walked.
            var activeDaysByPersonID: [String: Set<Date>] = [:]
            for personID in merged.roster.sorted() {
                guard let person = personByID[personID] else { continue }
                let ownMessages = combinedMessages.filter {
                    guard let handleRowID = $0.handleRowID else { return false }
                    return person.handleRowIDs.contains(handleRowID)
                }
                let daySet = ActivityDays.daySet(ownMessages, calendar: calendar)
                activeDaysByPersonID[personID] = daySet
                let edge = GraphEdge(
                    nodeIDA: personID,
                    nodeIDB: groupID,
                    source: .imessage,
                    reason: .groupMembership,
                    strength: Double(daySet.count),
                    involvesUser: false
                )
                if edgesByID[edge.id] == nil {
                    edgesByID[edge.id] = edge
                }
            }
            groupChatActivity.append(
                GroupChatActivity(chatId: groupID, name: merged.name, roster: merged.roster, activeDaysByPersonID: activeDaysByPersonID)
            )

            // userGroupMembership: one per group node, always, strength from the user's own
            // is_from_me activity across the union of merged chats.
            let fromMeMessages = combinedMessages.filter(\.isFromMe)
            let userEdge = GraphEdge(
                nodeIDA: "user",
                nodeIDB: groupID,
                source: .imessage,
                reason: .userGroupMembership,
                strength: Double(distinctDays(fromMeMessages, calendar: calendar)),
                involvesUser: true
            )
            if edgesByID[userEdge.id] == nil {
                edgesByID[userEdge.id] = userEdge
            }
        }

        var nodes: [GraphNode] = [
            GraphNode(id: "user", kind: .user, name: nil, thumbnailImageData: nil, hasContactCard: false, isLive: false, degree: 0)
        ]
        for person in keptPeople {
            nodes.append(
                GraphNode(
                    id: person.id,
                    kind: .person,
                    name: person.name,
                    thumbnailImageData: person.thumbnailImageData,
                    hasContactCard: person.hasContactCard,
                    isLive: false,
                    degree: 0
                )
            )
        }
        nodes.append(contentsOf: groupNodes)

        return GraphBuildResult(
            graph: finalized(nodes: nodes, edges: Array(edgesByID.values)),
            // Already sorted: mergedGroupChats itself returns sorted by id, and this loop
            // appends in that same order -- sorted again here so that contract is never
            // something a future edit to mergedGroupChats could silently break.
            groupChatActivity: groupChatActivity.sorted { $0.chatId < $1.chatId }
        )
    }

    /// `prune` removes edges below `minStrength`, except:
    /// - it never removes a node's last remaining edge (checked incrementally, so removing
    ///   one candidate can correctly block the next one from also being removed);
    /// - edges with `involvesUser == true` are exempt entirely (never even candidates): they
    ///   are not rendered at rest, and pruning them would silently break focus mode.
    /// Degree is recomputed on the returned graph, since a Graph's node.degree must describe
    /// that same Graph's own edges, not a stale pre-prune count.
    public static func prune(graph: Graph, minStrength: Double) -> Graph {
        var degreeByNodeID = computeDegree(edges: graph.edges)
        var survivingEdgesByID = Dictionary(uniqueKeysWithValues: graph.edges.map { ($0.id, $0) })

        let candidates = graph.edges
            .filter { !$0.involvesUser && $0.strength < minStrength }
            .sorted { lhs, rhs in
                lhs.strength != rhs.strength ? lhs.strength < rhs.strength : lhs.id < rhs.id
            }

        for edge in candidates {
            let degreeA = degreeByNodeID[edge.nodeIDA] ?? 0
            let degreeB = degreeByNodeID[edge.nodeIDB] ?? 0
            guard degreeA > 1 && degreeB > 1 else { continue } // last-edge guard
            survivingEdgesByID.removeValue(forKey: edge.id)
            degreeByNodeID[edge.nodeIDA] = degreeA - 1
            degreeByNodeID[edge.nodeIDB] = degreeB - 1
        }

        return finalized(nodes: graph.nodes, edges: Array(survivingEdgesByID.values))
    }

    private static func finalized(nodes: [GraphNode], edges: [GraphEdge]) -> Graph {
        let degreeByNodeID = computeDegree(edges: edges)
        let nodesWithDegree = nodes.map { node in
            GraphNode(
                id: node.id,
                kind: node.kind,
                name: node.name,
                thumbnailImageData: node.thumbnailImageData,
                hasContactCard: node.hasContactCard,
                isLive: node.isLive,
                degree: degreeByNodeID[node.id] ?? 0
            )
        }
        return Graph(
            nodes: nodesWithDegree.sorted { $0.id < $1.id },
            edges: edges.sorted { $0.id < $1.id }
        )
    }

    private static func computeDegree(edges: [GraphEdge]) -> [String: Int] {
        var degree: [String: Int] = [:]
        for edge in edges {
            degree[edge.nodeIDA, default: 0] += 1
            degree[edge.nodeIDB, default: 0] += 1
        }
        return degree
    }

    private static func distinctDays(_ messages: [RawMessage], calendar: Calendar) -> Int {
        ActivityDays.distinctDays(messages, calendar: calendar)
    }

    /// One group node's worth of merged chats: their union roster/name, and the chat rowIDs
    /// whose messages get combined for liveness and edge strength.
    private struct MergedGroupChat {
        let id: String
        let name: String?
        let roster: Set<String>
        let chatRowIDs: [Int64]
    }

    /// Apple gives one human group a separate `chat` row per service (iMessage vs SMS/RCS), so
    /// group identity is keyed on the RESOLVED roster, not the chat row: chats whose resolved
    /// rosters are identical merge into one node.
    ///
    /// Name guard, because two chats CAN legitimately have the same roster and be different
    /// conversations: within a roster bucket, group by distinct non-nil (non-empty) display
    /// name. Zero distinct names -> merge everything, unnamed. Exactly one distinct name ->
    /// merge everything (named and unnamed alike) under that name. Two or more distinct names
    /// -> one merged node per name (same-named chats merge together), and each unnamed chat
    /// stands alone -- it cannot be attributed to one of several competing names.
    ///
    /// The merged node's id is `"chat:\(guid)"` for the lexicographically SMALLEST guid among
    /// the chats merged into it (min-by-guid, not min-by-rowID: rowID is a local sqlite
    /// artifact, not stable across a resync).
    private static func mergedGroupChats(
        _ groupChats: [RawChat],
        handleToPersonID: [Int64: String]
    ) -> [MergedGroupChat] {
        var chatsByRoster: [Set<String>: [RawChat]] = [:]
        for chat in groupChats {
            let roster = ChatRoster.resolvedPersonIDs(chat, handleToPersonID: handleToPersonID)
            chatsByRoster[roster, default: []].append(chat)
        }

        var merged: [MergedGroupChat] = []
        for (roster, chats) in chatsByRoster {
            let distinctNames = Set(chats.compactMap { chat -> String? in
                guard let name = chat.displayName, !name.isEmpty else { return nil }
                return name
            })

            func makeMerged(_ chats: [RawChat], name: String?) -> MergedGroupChat {
                let minGUID = chats.map(\.guid).min()!
                return MergedGroupChat(
                    id: "chat:\(minGUID)",
                    name: name,
                    roster: roster,
                    chatRowIDs: chats.map(\.rowID)
                )
            }

            switch distinctNames.count {
            case 0, 1:
                merged.append(makeMerged(chats, name: distinctNames.first))
            default:
                for name in distinctNames {
                    let named = chats.filter { $0.displayName == name }
                    merged.append(makeMerged(named, name: name))
                }
                for unnamed in chats where unnamed.displayName == nil || unnamed.displayName?.isEmpty == true {
                    merged.append(makeMerged([unnamed], name: nil))
                }
            }
        }

        return merged.sorted { $0.id < $1.id }
    }
}
