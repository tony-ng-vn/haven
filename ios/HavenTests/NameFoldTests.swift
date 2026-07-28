import Foundation
import Testing
@testable import Haven

@Suite("Names fold the same way the server folds them")
struct NameFoldCrossLanguageTests {
    @Test("every name folds to what normalizeName returns")
    func matchesTypeScript() {
        for (input, want) in foldNameCases {
            #expect(
                NameFold.normalize(input) == want,
                "normalize(\(input)): got \(NameFold.normalize(input)), want \(want)"
            )
        }
    }
}

@Suite("Name folding")
struct NameFoldTests {
    // The whole reason this exists: the share sheet asks "do you already know
    // them?" against a mirror the app wrote, and the answer has to be the one
    // the server's own search would give.
    @Test("accents and case never decide whether two names match")
    func accentsAndCase() {
        #expect(NameFold.normalize("Nguy\u{1ec5}n Mai") == NameFold.normalize("nguyen mai"))
        #expect(NameFold.normalize("Caf\u{e9}") == NameFold.normalize("CAFE"))
    }

    // D-with-stroke is its own letter rather than a d wearing an accent, so
    // Unicode folding leaves it alone and "da nang" would miss "\u{110}\u{e0} N\u{1eb5}ng".
    @Test("the Vietnamese D-stroke folds to a plain d")
    func dStroke() {
        #expect(NameFold.normalize("\u{110}\u{e0} N\u{1eb5}ng") == "da nang")
        #expect(NameFold.normalize("\u{111}\u{1ee9}c anh") == "duc anh")
    }

    // The server folds through a JS regex, whose \s is a fixed list rather
    // than the Unicode whitespace property. Two characters sit on the seam:
    // a byte-order mark is whitespace to JS and not to Unicode, and a NEL is
    // the other way round. Following Unicode here would silently disagree.
    @Test("whitespace is the set the server's regex matches, not Unicode's")
    func whitespaceSeam() {
        #expect(NameFold.normalize("Mai\u{feff}Tran") == "mai tran")
        #expect(NameFold.normalize("Mai\u{85}Tran") == "mai\u{85}tran")
    }

    // Folding has to happen before decomposing: lowercasing a dotted capital I
    // yields an i plus a combining dot, and only a later mark strip removes it.
    @Test("a dotted capital I loses its dot")
    func dottedCapitalI() {
        #expect(NameFold.normalize("\u{130}stanbul") == "istanbul")
    }

    @Test("runs of whitespace collapse and the edges are trimmed")
    func collapse() {
        #expect(NameFold.normalize("  MAI   TRAN  ") == "mai tran")
        #expect(NameFold.normalize("   ") == "")
        #expect(NameFold.normalize("") == "")
    }
}
