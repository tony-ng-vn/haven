import Foundation

/// Assigns a short, non-leaking disambiguator to every id whose resolved display name
/// (NodeLabel.resolve's output -- a real name, or a guess-derived tilde name) exactly matches
/// another id's, so two dots with the same label stop being indistinguishable in the sky's
/// text surfaces (PLAN.md's contacts-collision edge case). Absent entirely for a unique name:
/// GraphJSON's `encodeIfPresent` then omits the key, so the export does not grow for the
/// common case.
public enum NameDisambiguation {
    /// `namesByID` is every candidate id paired with its resolved name (already tilde-prefixed
    /// for a guess, exactly as it will be shown) -- comparison is case-insensitive, so "John"
    /// and "JOHN" still collide, but a guess ("~Alex") only collides with an identically
    /// resolved guess, never silently with an unrelated real "Alex" (different string).
    ///
    /// A colliding group's disambiguators are guaranteed pairwise DISTINCT within that group:
    /// two different ids can share the same base short suffix (two invented Gmail addresses,
    /// or two phone numbers ending in the same 4 digits), and a disambiguator that cannot
    /// actually tell two same-named people apart is worse than none. Ids sharing a base suffix
    /// get a numbered tiebreak instead, ordered by SORTED id (never by input/iteration order,
    /// which would break GraphJSON's determinism guarantee).
    public static func disambiguators(namesByID: [(id: String, name: String)]) -> [String: String] {
        var idsByLowercasedName: [String: [String]] = [:]
        for entry in namesByID {
            guard !entry.name.isEmpty else { continue }
            idsByLowercasedName[entry.name.lowercased(), default: []].append(entry.id)
        }

        var result: [String: String] = [:]
        for ids in idsByLowercasedName.values where ids.count >= 2 {
            // Sorted, not insertion order: this is the only thing that decides tiebreak
            // ordering below, so two runs over the same set (built in any order) must always
            // produce the same result.
            let sortedIDs = ids.sorted()

            var idsByBaseSuffix: [String: [String]] = [:]
            for id in sortedIDs {
                idsByBaseSuffix[IdentifierMasking.shortSuffix(id), default: []].append(id)
            }

            for (baseSuffix, idsSharingSuffix) in idsByBaseSuffix {
                if idsSharingSuffix.count == 1 {
                    result[idsSharingSuffix[0]] = baseSuffix
                } else {
                    // idsSharingSuffix inherited its order from sortedIDs above (each id was
                    // appended in that order), so this numbering is deterministic regardless of
                    // idsByBaseSuffix's own (hash-based, unordered) key iteration order.
                    for (index, id) in idsSharingSuffix.enumerated() {
                        result[id] = baseSuffix + " (\(index + 1))"
                    }
                }
            }
        }
        return result
    }
}
