import Foundation

/// One candidate plus the chat rowIDs its snippets should come from. Public so both AppModel
/// (the interactive app) and graph-cli's `guess` subcommand (the headless pass) can build the
/// exact same candidate list from the exact same rule -- reimplementing this for the CLI would
/// have been a fourth hand-rolled copy of the one-to-one-vs-group question ChatClassification
/// already exists to answer once.
public struct GuessCandidateSource: Sendable, Equatable {
    public let candidate: GuessCandidate
    public let chatRowIDs: Set<Int64>

    public init(candidate: GuessCandidate, chatRowIDs: Set<Int64>) {
        self.candidate = candidate
        self.chatRowIDs = chatRowIDs
    }
}

/// One candidate per kept person with no real name (their one-to-one chat rowIDs -- a merged,
/// multi-service person can have several) and per live 3+ member group with no display name
/// (its own chat rowID).
public enum GuessCandidateSelection {
    public static func buildSources(
        graph: Graph,
        keptPeople: [Person],
        extract: ChatExtract
    ) -> [GuessCandidateSource] {
        var sources: [GuessCandidateSource] = []

        // Same mapping GraphBuilder itself builds from keptPeople: ChatClassification needs
        // it to tell a real 2-different-person group from a roster that only looks like one
        // until you check who is actually kept.
        let handleToPersonID = Dictionary(
            uniqueKeysWithValues: keptPeople.flatMap { person in person.handleRowIDs.map { ($0, person.id) } }
        )
        let chatKindByRowID = ChatClassification.classify(chats: extract.chats, handleToPersonID: handleToPersonID)

        for person in keptPeople where person.name == nil {
            let rowIDs = oneToOneChatRowIDs(for: person, chatKindByRowID: chatKindByRowID, extract: extract)
            guard !rowIDs.isEmpty else { continue }
            sources.append(GuessCandidateSource(
                candidate: GuessCandidate(key: person.id, context: .person(identifier: person.id)),
                chatRowIDs: rowIDs
            ))
        }

        let nodesByID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        for node in graph.nodes where node.kind == .group && node.isLive && node.name == nil {
            guard let rowID = chatRowID(forGroupNodeID: node.id, extract: extract) else { continue }
            // NodeLabel.groupGuessKey is the ONLY place this "chat:" -> "group:" transform is
            // written; calling it here (rather than rebuilding the string locally) is what
            // keeps this write side and NodeLabel's own read side from ever drifting apart.
            let key = NodeLabel.groupGuessKey(forNodeID: node.id)
            let memberNames = memberNames(forGroupNodeID: node.id, graph: graph, nodesByID: nodesByID)
            sources.append(GuessCandidateSource(
                candidate: GuessCandidate(key: key, context: .group(memberNames: memberNames)),
                chatRowIDs: [rowID]
            ))
        }

        return sources
    }

    private static func oneToOneChatRowIDs(
        for person: Person,
        chatKindByRowID: [Int64: ChatKind],
        extract: ChatExtract
    ) -> Set<Int64> {
        var rowIDs: Set<Int64> = []
        for chat in extract.chats {
            guard chatKindByRowID[chat.rowID] == .oneToOne else { continue }
            if chat.memberHandleRowIDs.contains(where: { person.handleRowIDs.contains($0) }) {
                rowIDs.insert(chat.rowID)
            }
        }
        return rowIDs
    }

    private static func chatRowID(forGroupNodeID nodeID: String, extract: ChatExtract) -> Int64? {
        guard nodeID.hasPrefix("chat:") else { return nil }
        let guid = String(nodeID.dropFirst("chat:".count))
        return extract.chats.first { $0.guid == guid }?.rowID
    }

    /// Only members with a real (already-known) name are worth telling the model about -- an
    /// unnamed fellow member is exactly as uninformative as the group itself is.
    private static func memberNames(
        forGroupNodeID nodeID: String,
        graph: Graph,
        nodesByID: [String: GraphNode]
    ) -> [String] {
        let memberIDs = graph.edges
            .filter { $0.reason == .groupMembership && ($0.nodeIDA == nodeID || $0.nodeIDB == nodeID) }
            .map { $0.nodeIDA == nodeID ? $0.nodeIDB : $0.nodeIDA }
        return memberIDs.compactMap { nodesByID[$0]?.name }.sorted()
    }
}
