import Foundation

/// The durable identity of a group chat for the "everyone here knows each other" marker
/// (PLAN.md, "The acquaintance layer"): the chat's resolved member identifiers, sorted and
/// deduplicated. Never the chat guid or a row id -- both renumber and re-split across a
/// resync (a service-split merge can even change which guid is smallest), but the people
/// sharing the chat do not, so keying on them is what lets a marking survive both.
public enum AcquaintanceRosterKey {
    /// One identifier per resolved member (Person.id): canonicalized by sorting so the pair
    /// "A,B" and "B,A" key the same, and by deduplicating so a caller passing a Set or an
    /// Array with repeats still gets one canonical key either way.
    public static func canonicalize<S: Sequence>(_ identifiers: S) -> [String] where S.Element == String {
        Array(Set(identifiers)).sorted()
    }

    /// Translates every STORED key (captured at mark time via canonicalize(current roster),
    /// so built from whatever a member's Person.id happened to be THEN) into its CURRENT
    /// canonical form, for matching against a roster's LIVE Person.ids. Exact equality against
    /// the raw stored set is wrong: identifiers only ever get ADDED to a person, never removed
    /// (the same fact MergeAnswer's own doc comment relies on), so a resync that hands a
    /// member a new, smaller identifier changes their Person.id without ever removing the OLD
    /// one from their identifier set -- the stored key still names a real, current person, just
    /// by a name that is no longer their smallest.
    ///
    /// A stored key with an identifier that belongs to NO current person (removed since
    /// marking, or a hand-edited/corrupt file) is DORMANT: it translates to nothing and
    /// matches nothing this build. This function never mutates or drops anything from the
    /// caller's own stored set -- only the freshly-computed, ephemeral result of calling it.
    ///
    /// Two stored identifiers that now resolve to the SAME current person (their people were
    /// merged since marking) collapse to one shorter key via canonicalize's own dedup, which
    /// is correct: the marking now describes a smaller, merged roster.
    ///
    /// Pure and deterministic: only `people`'s current identifier sets, no database read.
    public static func resolve(stored: Set<[String]>, people: [Person]) -> Set<[String]> {
        guard !stored.isEmpty else { return [] }

        // Every identifier belongs to at most one current person (IdentityResolution's own
        // union-find guarantees disjoint identifier sets across people), so this flatten never
        // collides -- the same guarantee GraphBuilder's own handleToPersonID map relies on.
        let personIDByIdentifier = Dictionary(
            uniqueKeysWithValues: people.flatMap { person in person.identifiers.map { ($0, person.id) } }
        )

        return Set(stored.compactMap { key -> [String]? in
            var currentIDs: [String] = []
            for identifier in key {
                guard let personID = personIDByIdentifier[identifier] else {
                    return nil // dormant: at least one stored identifier belongs to nobody current
                }
                currentIDs.append(personID)
            }
            // canonicalize's own dedup is what collapses two stored identifiers that now
            // resolve to the same merged person into one shorter key.
            return canonicalize(currentIDs)
        })
    }
}
