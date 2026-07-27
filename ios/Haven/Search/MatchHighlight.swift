import SwiftUI

/// Marks the part of a result that matched what someone typed.
///
/// Presentation, not search: this decides what the eye is drawn to in a line of
/// text, and nothing here decides which people come back. Phase 3 wires the
/// query; this is what it will render with.
enum MatchHighlight {
    /// `text` with every run that matches `query` emphasized.
    ///
    /// Matching is accent- and case-insensitive, because a search for "da nang"
    /// has to light up "Đà Nẵng" or the highlight contradicts the result that
    /// came back for it. Folding is done on a per-character basis so the marked
    /// range still lines up with the original string.
    static func attributed(_ text: String, matching query: String) -> AttributedString {
        var attributed = AttributedString(text)
        for range in ranges(in: text, matching: query) {
            guard let marked = Range(range, in: attributed) else { continue }
            attributed[marked].foregroundColor = HavenColor.star
            attributed[marked].inlinePresentationIntent = .stronglyEmphasized
        }
        return attributed
    }

    /// Every range of `text` that matches `query`, ignoring case and accents.
    ///
    /// Whitespace-separated terms are matched independently, so "maya haven"
    /// lights up both words wherever each of them lands rather than only an
    /// exact "maya haven" run.
    static func ranges(in text: String, matching query: String) -> [Range<String.Index>] {
        let terms = foldDStroke(query)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !terms.isEmpty, !text.isEmpty else { return [] }

        let haystack = foldDStroke(text)
        var found: [Range<String.Index>] = []
        for term in terms {
            var searchFrom = haystack.startIndex
            while
                let range = haystack.range(
                    of: term,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchFrom..<haystack.endIndex
                )
            {
                if let mapped = mapRange(range, from: haystack, to: text) {
                    found.append(mapped)
                }
                // Advance past the start, not past the end: overlapping terms
                // ("an" and "ana") should each still find their own runs, and
                // an empty match would otherwise loop forever.
                searchFrom = haystack.index(after: range.lowerBound)
                if searchFrom >= haystack.endIndex { break }
            }
        }
        return found
    }

    /// Folds the one letter `.diacriticInsensitive` will not.
    ///
    /// D-with-stroke is a letter of its own rather than a d wearing an accent,
    /// so Unicode folding leaves it alone and a search for "da nang" would miss
    /// "Đà Nẵng" -- which the server, folding through `normalizeName` in
    /// `convex/nameSearch.ts`, would have matched. Highlighting has to agree
    /// with what came back. One character in, one character out, so positions
    /// in the result still name the same characters in the original.
    private static func foldDStroke(_ text: String) -> String {
        String(
            text.map { character in
                switch character {
                case "\u{0111}": return Character("d")
                case "\u{0110}": return Character("D")
                default: return character
                }
            }
        )
    }

    /// The same span of characters, in the unfolded string.
    private static func mapRange(
        _ range: Range<String.Index>,
        from folded: String,
        to original: String
    ) -> Range<String.Index>? {
        let start = folded.distance(from: folded.startIndex, to: range.lowerBound)
        let end = folded.distance(from: folded.startIndex, to: range.upperBound)
        guard end <= original.count else { return nil }
        return original.index(original.startIndex, offsetBy: start)
            ..< original.index(original.startIndex, offsetBy: end)
    }
}
