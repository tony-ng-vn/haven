import Foundation

/// Folds a name into the form two names are compared in.
///
/// A port of `normalizeName` in `convex/nameSearch.ts`, and it has to stay one.
/// The share sheet asks "do you already know them?" against the local mirror,
/// and the answer has to be the answer the server's own search would give -- a
/// sheet that says nobody matches, followed by a save that lands on someone,
/// is worse than either outcome on its own.
///
/// The user's network is mostly Vietnamese, so this is accent-insensitive:
/// "dun" has to find a person stored as "Dun Dun" whether they typed the
/// D-stroke, the diacritics, or both.
///
/// Foundation only: this file is compiled into the share extension.
enum NameFold {
    /// Unicode NFD decomposes most Latin diacritics into a base letter plus
    /// combining marks, which the strip below removes. The Vietnamese D-stroke
    /// is not a base letter plus a diacritic under Unicode -- it is its own
    /// codepoint that NFD cannot split -- so it is mapped explicitly first.
    private static let dStrokeUpper: Character = "\u{0110}"
    private static let dStrokeLower: Character = "\u{0111}"

    static func normalize(_ name: String) -> String {
        let dFolded = String(
            name.map { character in
                switch character {
                case dStrokeUpper: return Character("D")
                case dStrokeLower: return Character("d")
                default: return character
                }
            }
        )
        // Lower-cased before decomposing, so a dotted capital I becomes an i
        // plus a combining dot that the mark strip then removes. The other
        // order would leave the dot behind.
        let decomposed = dFolded.lowercased().decomposedStringWithCanonicalMapping
        let stripped = String(String.UnicodeScalarView(
            decomposed.unicodeScalars.filter { !$0.isCombiningMark }
        ))
        return collapsingWhitespace(stripped)
    }

    /// Every run of whitespace becomes one space, and the edges are dropped --
    /// the server's `.replace(/\s+/g, " ").trim()`.
    private static func collapsingWhitespace(_ text: String) -> String {
        var out = ""
        var pendingSpace = false
        for character in text {
            if character.isJSWhitespace {
                // Held rather than written, so a trailing run leaves nothing
                // behind and the trim comes for free.
                pendingSpace = !out.isEmpty
                continue
            }
            if pendingSpace {
                out.append(" ")
                pendingSpace = false
            }
            out.append(character)
        }
        return out
    }
}

extension Unicode.Scalar {
    /// `\p{M}`: the three Unicode mark categories a JS regex matches, which is
    /// more than `CharacterSet.nonBaseCharacters` covers (it leaves out the
    /// spacing marks Vietnamese and the Indic scripts use).
    var isCombiningMark: Bool {
        switch properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return false
        }
    }
}
