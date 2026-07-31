import Foundation

/// Chat style constants from the real chat.db schema (mirrors the small private copies in
/// ExtractStats and PersonFilter; each is file-local and not worth sharing across a module
/// boundary for two integer literals).
private enum ChatStyle {
    static let oneToOne = 45
    static let group = 43
}

/// A two-member style-43 chat is a one-to-one edge, never a group node (PLAN.md: a roster
/// of exactly the user plus one other renders as a one-to-one edge). 0-1 member rosters are
/// degenerate and contribute to neither kind.
private enum ChatKind {
    case oneToOne
    case group
}

public enum GraphBuilder {
    public static func build(
        extract: ChatExtract,
        keptPeople: [Person],
        calendar: Calendar = .current
    ) -> Graph {
        // Only kept people resolve to a node/edge: a removed person's handle appearing in a
        // roster simply fails this lookup and produces nothing for them.
        let handleToPersonID = Dictionary(
            uniqueKeysWithValues: keptPeople.flatMap { person in person.handleRowIDs.map { ($0, person.id) } }
        )
        let personByID = Dictionary(uniqueKeysWithValues: keptPeople.map { ($0.id, $0) })
        let chatKindByRowID = classifyChats(extract.chats)

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
            for personID in Set(chat.memberHandleRowIDs.compactMap({ handleToPersonID[$0] })) {
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

        // Group nodes: one per style-43 chat with a RAW roster of 3+, built unconditionally
        // (a dead group, or one with zero kept members, is still a real structural artifact
        // of message history; only person-level filtering decides whether an edge exists).
        var groupNodes: [GraphNode] = []
        let groupChats = extract.chats
            .filter { chatKindByRowID[$0.rowID] == .group }
            .sorted { $0.rowID < $1.rowID }

        for chat in groupChats {
            let groupID = "chat:\(chat.guid)"
            let chatMessages = messagesByChat[chat.rowID] ?? []
            let isLive = distinctDays(chatMessages, calendar: calendar) >= 2

            groupNodes.append(
                GraphNode(
                    id: groupID,
                    kind: .group,
                    name: chat.displayName,
                    thumbnailImageData: nil,
                    hasContactCard: false,
                    isLive: isLive,
                    degree: 0 // filled in by finalize()
                )
            )

            // groupMembership: every kept member, even a lurker with zero messages of their
            // own (roster is historical truth from chat_handle_join, not message activity).
            let memberPersonIDs = Set(chat.memberHandleRowIDs.compactMap { handleToPersonID[$0] })
            for personID in memberPersonIDs.sorted() {
                guard let person = personByID[personID] else { continue }
                let ownMessages = chatMessages.filter {
                    guard let handleRowID = $0.handleRowID else { return false }
                    return person.handleRowIDs.contains(handleRowID)
                }
                let edge = GraphEdge(
                    nodeIDA: personID,
                    nodeIDB: groupID,
                    source: .imessage,
                    reason: .groupMembership,
                    strength: Double(distinctDays(ownMessages, calendar: calendar)),
                    involvesUser: false
                )
                if edgesByID[edge.id] == nil {
                    edgesByID[edge.id] = edge
                }
            }

            // userGroupMembership: one per group node, always, strength from the user's own
            // is_from_me activity in that specific chat.
            let fromMeMessages = chatMessages.filter(\.isFromMe)
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

        return finalized(nodes: nodes, edges: Array(edgesByID.values))
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
        Set(messages.map { calendar.startOfDay(for: $0.date) }).count
    }

    private static func classifyChats(_ chats: [RawChat]) -> [Int64: ChatKind] {
        var kinds: [Int64: ChatKind] = [:]
        for chat in chats {
            switch chat.style {
            case ChatStyle.oneToOne:
                kinds[chat.rowID] = .oneToOne
            case ChatStyle.group:
                if chat.memberHandleRowIDs.count == 2 {
                    kinds[chat.rowID] = .oneToOne
                } else if chat.memberHandleRowIDs.count >= 3 {
                    kinds[chat.rowID] = .group
                }
                // 0 or 1 members: degenerate roster, ignored.
            default:
                break
            }
        }
        return kinds
    }
}
