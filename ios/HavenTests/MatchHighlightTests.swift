import Foundation
import Testing
@testable import Haven

// Which part of a result gets lit. Presentation logic, not search: nothing here
// decides which people come back, only what the eye is drawn to once they do.

@Suite("Match highlight")
struct MatchHighlightTests {
    private func marked(_ text: String, _ query: String) -> [String] {
        MatchHighlight.ranges(in: text, matching: query).map { String(text[$0]) }
    }

    @Test("the matched run is what gets marked")
    func marksTheMatch() {
        #expect(marked("Maya Chen", "may") == ["May"])
        // Case is a property of how someone types, not of what they meant.
        #expect(marked("Maya Chen", "CHEN") == ["Chen"])
        #expect(marked("Maya Chen", "z").isEmpty)
    }

    // A search for "da nang" has to light up "Đà Nẵng", or the highlight
    // contradicts the result that came back for it.
    @Test("accents do not stop a match")
    func foldsAccents() {
        #expect(marked("Đà Nẵng", "da nang") == ["Đà", "Nẵng"])
        #expect(marked("Nguyen", "nguyễn") == ["Nguyen"])
    }

    // Terms are matched independently, so a two-word query lights up both words
    // wherever each lands rather than only an exact run of the whole thing.
    @Test("each term finds its own runs")
    func matchesEachTerm() {
        #expect(marked("Maya Chen", "chen maya") == ["Chen", "Maya"])
        #expect(marked("Maya Mai", "ma") == ["Ma", "Ma"])
    }

    // A query that is only spaces is not a query, and a run that matched
    // nothing must not mark the whole line.
    @Test("an empty query marks nothing")
    func emptyQuery() {
        #expect(marked("Maya Chen", "").isEmpty)
        #expect(marked("Maya Chen", "   ").isEmpty)
        #expect(marked("", "maya").isEmpty)
    }

    // Advancing past the start rather than the end is what makes overlapping
    // terms each find their runs; it is also what stops an empty match looping.
    @Test("repeated and overlapping matches terminate")
    func overlapping() {
        #expect(marked("aaa", "aa") == ["aa", "aa"])
        #expect(marked("banana", "an") == ["an", "an"])
    }

    @Test("the marked text keeps the original spelling")
    func keepsOriginal() {
        let attributed = MatchHighlight.attributed("Đà Nẵng", matching: "da")
        #expect(String(attributed.characters) == "Đà Nẵng")
    }
}
