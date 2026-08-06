import Foundation

/// The fewest single-character insertions, deletions or substitutions to turn
/// one string into another.
///
/// Foundation only, and pure: this runs over already-folded names, entirely
/// offline, over the mirror the app already wrote to disk.
enum EditDistance {
    /// Classic Levenshtein, not Damerau-Levenshtein: a transposed pair of
    /// letters costs two substitutions here rather than one swap. That is
    /// deliberate rather than a simplification left half-finished --
    /// `DirectoryMirror.nameSuggestions`'s threshold for a name long enough
    /// to carry a transposition is already two, so the case this exists for
    /// ("Duogn" for "Duong") is caught either way, and the simpler algorithm
    /// is the one with nothing extra to get wrong.
    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a)
        let b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        // Two rows rather than a full matrix: only the previous row is ever
        // read while filling the current one.
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1, // deletion
                    current[j - 1] + 1, // insertion
                    previous[j - 1] + cost // substitution
                )
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}

/// Whether a suggested person's name folded to exactly what was typed, or
/// only close to it.
enum NameMatchKind: Equatable, Sendable {
    case exact
    case close
}

/// One person a typed name might already be.
struct NameSuggestion: Equatable, Sendable, Identifiable {
    let person: MirrorPerson
    let kind: NameMatchKind
    var id: String { person.id }
}

extension DirectoryMirror {
    /// Below this folded length, only an exact match counts.
    ///
    /// A short name is not a safer edit-distance bet, it is a more dangerous
    /// one: at two or three letters, a distance of one or two reaches nearly
    /// every other short name in a directory, and "close match" stops
    /// meaning anything. This is the line "Dun Duogn" surfacing "Dun Duong"
    /// is allowed to cross and "Al" surfacing "Ali" is not.
    private static let minimumFuzzyLength = 4

    /// Who a typed name might already be: exact matches first, then close
    /// ones -- small typos, caught by edit distance over the same fold
    /// `NameFold` already uses everywhere else a name is compared.
    ///
    /// Distance-checked names have to be within `limit` of each other in
    /// length before the full comparison runs at all: Levenshtein distance
    /// is never smaller than the length difference between two strings, so
    /// a pair already too far apart on length cannot pass regardless, and
    /// skipping them is an early exit rather than a separate rule.
    func nameSuggestions(for query: String, limit: Int = 5) -> [NameSuggestion] {
        let folded = NameFold.normalize(query)
        guard !folded.isEmpty else { return [] }
        let distanceLimit = Self.distanceLimit(forFoldedLength: folded.count)

        var exact: [NameSuggestion] = []
        var close: [NameSuggestion] = []
        for candidate in people {
            let candidateFolded = NameFold.normalize(candidate.name)
            guard !candidateFolded.isEmpty else { continue }
            if candidateFolded == folded {
                exact.append(NameSuggestion(person: candidate, kind: .exact))
                continue
            }
            guard
                distanceLimit > 0,
                abs(candidateFolded.count - folded.count) <= distanceLimit,
                EditDistance.levenshtein(folded, candidateFolded) <= distanceLimit
            else { continue }
            close.append(NameSuggestion(person: candidate, kind: .close))
        }
        return Array((exact + close).prefix(limit))
    }

    /// How many edits still count as "the same name, mistyped," scaled by
    /// how much of the name there is to go wrong: a longer name has more
    /// room for one wrong letter to still be recognizable, and a name below
    /// `minimumFuzzyLength` gets no fuzzy allowance at all.
    private static func distanceLimit(forFoldedLength length: Int) -> Int {
        switch length {
        case ..<minimumFuzzyLength: return 0
        case minimumFuzzyLength..<8: return 1
        default: return 2
        }
    }
}
