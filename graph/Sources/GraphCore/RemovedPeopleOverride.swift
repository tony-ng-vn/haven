import Foundation

/// Drops any Person the user has explicitly removed (PLAN.md: "removed nodes stay removed"),
/// applied to PersonFilter's kept list before GraphBuilder ever sees it -- a removed person
/// gets no node or edge at all, structurally, same as anyone PersonFilter's own rules drop.
public enum RemovedPeopleOverride {
    /// Matches on ANY of the person's identifiers, not just their current id: Person.id
    /// (the lexicographically smallest identifier) can shift across a resync when a new,
    /// smaller identifier joins the same person, but identifiers themselves only ever get
    /// added, never removed -- so intersection is the only test that survives that shift.
    public static func apply(_ people: [Person], removedPersonIdentifiers: Set<String>) -> [Person] {
        guard !removedPersonIdentifiers.isEmpty else { return people }
        return people.filter { $0.identifiers.isDisjoint(with: removedPersonIdentifiers) }
    }
}
