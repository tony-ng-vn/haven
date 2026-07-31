import Foundation

/// Which nodes earn a permanent label at rest, per PLAN.md: "roughly the forty most
/// connected nodes carry labels; everything else labels on zoom." Pure selection logic so
/// the view stays a dumb renderer; the zoom-triggered label expansion is the view's own
/// concern and not modeled here.
public enum LabelBudget {
    public static func selectedNodeIDs(nodes: [GraphNode], limit: Int = 40) -> Set<String> {
        // The user is never a label candidate: PLAN.md's "forty most connected" is about
        // reading the social graph, and the user node carries no name to show anyway.
        let candidates = nodes.filter { $0.kind != .user }
        let ranked = candidates.sorted { lhs, rhs in
            // Degree descending; ties broken by id ascending so the selection is the same
            // set every time for the same graph, never order-of-construction dependent.
            if lhs.degree != rhs.degree {
                return lhs.degree > rhs.degree
            }
            return lhs.id < rhs.id
        }
        return Set(ranked.prefix(limit).map(\.id))
    }
}
