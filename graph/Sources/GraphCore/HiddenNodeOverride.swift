import Foundation

/// Maps the user's saved hidden-person/hidden-group overrides onto THIS graph's actual node
/// ids, feeding the existing render-only hidden mechanism (Graph.excludingNodes, applied by
/// the view). A person's node id is never stored directly: Person.id (the lexicographically
/// smallest identifier) can shift across a resync when a new, smaller identifier joins that
/// same person, so a person is hidden by ANY of their identifiers matching, never by a
/// possibly-stale id captured at hide time.
public enum HiddenNodeOverride {
    public static func nodeIDs(
        people: [Person],
        graph: Graph,
        hiddenPersonIdentifiers: Set<String>,
        hiddenGroupGUIDs: Set<String>
    ) -> Set<String> {
        var ids: Set<String> = []

        if !hiddenPersonIdentifiers.isEmpty {
            for person in people where !person.identifiers.isDisjoint(with: hiddenPersonIdentifiers) {
                ids.insert(person.id)
            }
        }

        // Unlike the person side, existence in THIS graph is checked explicitly: a group
        // guid the user hid can belong to a chat that no longer produces a node at all under
        // the current filters (dead-and-excluded, or simply gone), and there is no node id to
        // add to the hidden set for one that isn't there.
        if !hiddenGroupGUIDs.isEmpty {
            let graphNodeIDs = Set(graph.nodes.map(\.id))
            for guid in hiddenGroupGUIDs {
                let groupID = "chat:\(guid)"
                if graphNodeIDs.contains(groupID) {
                    ids.insert(groupID)
                }
            }
        }

        return ids
    }
}
