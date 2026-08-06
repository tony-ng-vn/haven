import Foundation
import Testing
@testable import Haven

@Suite("Levenshtein distance")
struct EditDistanceTests {
    @Test("identical strings are zero apart")
    func identical() {
        #expect(EditDistance.levenshtein("mai", "mai") == 0)
        #expect(EditDistance.levenshtein("", "") == 0)
    }

    @Test("one substitution is distance one")
    func substitution() {
        #expect(EditDistance.levenshtein("mai", "mae") == 1)
    }

    @Test("one insertion or deletion is distance one")
    func insertionDeletion() {
        #expect(EditDistance.levenshtein("mai", "mail") == 1)
        #expect(EditDistance.levenshtein("mail", "mai") == 1)
    }

    // The brief's own example: a transposed pair of letters at the end.
    // Plain Levenshtein (no transposition move) counts this as two
    // substitutions, not one swap -- which is exactly why the suggester's
    // threshold for a name this long is two, not one.
    @Test("a transposed pair costs two under plain Levenshtein")
    func transposition() {
        #expect(EditDistance.levenshtein("duogn", "duong") == 2)
    }

    @Test("an empty string against another is the other's length")
    func emptyAgainstNonEmpty() {
        #expect(EditDistance.levenshtein("", "mai") == 3)
        #expect(EditDistance.levenshtein("mai", "") == 3)
    }

    @Test("completely different strings are far apart")
    func unrelated() {
        #expect(EditDistance.levenshtein("mai tran", "ada lovelace") > 5)
    }
}

private func person(id: String, name: String, handles: [MirrorHandle] = []) -> MirrorPerson {
    MirrorPerson(id: id, name: name, handles: handles)
}

@Suite("Suggesting who a typed name might already be")
struct DirectoryMirrorNameSuggestionTests {
    @Test("a name that folds identically is an exact suggestion")
    func exactMatch() {
        let mirror = DirectoryMirror(
            refreshedAt: Date(timeIntervalSince1970: 0),
            people: [person(id: "p1", name: "Mai Tran")]
        )
        let suggestions = mirror.nameSuggestions(for: "mai tran")
        #expect(suggestions.map(\.person.id) == ["p1"])
        #expect(suggestions.first?.kind == .exact)
    }

    // Diacritics fold away before anything else happens, so this is exact,
    // not close -- the fold, not the distance check, is what answers it.
    @Test("accents and case do not turn an exact match into a close one")
    func diacriticsAreExactNotClose() {
        let mirror = DirectoryMirror(
            refreshedAt: Date(timeIntervalSince1970: 0),
            people: [person(id: "p1", name: "Nguy\u{1ec5}n Mai")]
        )
        let suggestions = mirror.nameSuggestions(for: "nguyen mai")
        #expect(suggestions.first?.kind == .exact)
    }

    // The brief's flagship case: a two-letter typo at the end of a long
    // enough name still surfaces the person it means.
    @Test("Dun Duogn surfaces Dun Duong as a close match")
    func closeMatchTypo() {
        let mirror = DirectoryMirror(
            refreshedAt: Date(timeIntervalSince1970: 0),
            people: [person(id: "p1", name: "Dun Duong")]
        )
        let suggestions = mirror.nameSuggestions(for: "Dun Duogn")
        #expect(suggestions.map(\.person.id) == ["p1"])
        #expect(suggestions.first?.kind == .close)
    }

    // A diacritic fold and a genuine typo stacked on top of each other: the
    // fold has to run before the distance check sees either name, or the
    // Vietnamese accent itself would be counted as part of the typo.
    @Test("a typo on top of a diacritic still surfaces as close, not unrelated")
    func diacriticPlusTypo() {
        let mirror = DirectoryMirror(
            refreshedAt: Date(timeIntervalSince1970: 0),
            people: [person(id: "p1", name: "Nguy\u{1ec5}n Mai")]
        )
        let suggestions = mirror.nameSuggestions(for: "Nguyen Mail")
        #expect(suggestions.map(\.person.id) == ["p1"])
        #expect(suggestions.first?.kind == .close)
    }

    // A hyphen dropped in favor of a space is a plausible, real typo, and
    // NameFold leaves hyphens alone -- the distance check is what has to
    // catch this one, not the fold.
    @Test("a hyphen typed as a space is a close match on a hyphenated name")
    func hyphenatedNameTypo() {
        let mirror = DirectoryMirror(
            refreshedAt: Date(timeIntervalSince1970: 0),
            people: [person(id: "p1", name: "Anne-Marie Tran")]
        )
        let suggestions = mirror.nameSuggestions(for: "Anne Marie Tran")
        #expect(suggestions.map(\.person.id) == ["p1"])
        #expect(suggestions.first?.kind == .close)
    }

    @Test("an exact hyphenated match is exact, not close")
    func hyphenatedExactMatch() {
        let mirror = DirectoryMirror(
            refreshedAt: Date(timeIntervalSince1970: 0),
            people: [person(id: "p1", name: "Anne-Marie Tran")]
        )
        let suggestions = mirror.nameSuggestions(for: "anne-marie tran")
        #expect(suggestions.first?.kind == .exact)
    }

    @Test("unrelated names stay quiet")
    func unrelatedNamesStayQuiet() {
        let mirror = DirectoryMirror(
            refreshedAt: Date(timeIntervalSince1970: 0),
            people: [person(id: "p1", name: "Ada Lovelace")]
        )
        #expect(mirror.nameSuggestions(for: "Mai Tran").isEmpty)
    }

    // The short-name guard: a two- or three-letter query is exact-only, no
    // matter how close a longer or differently spelled name might read to a
    // person -- fuzzy-matching at that length would surface nearly everyone.
    @Test("a two-letter name never fuzzy-matches, even one edit away")
    func shortNameGuardTwoLetters() {
        let mirror = DirectoryMirror(
            refreshedAt: Date(timeIntervalSince1970: 0),
            people: [person(id: "p1", name: "Ali")]
        )
        #expect(mirror.nameSuggestions(for: "Al").isEmpty)
    }

    @Test("a three-letter name still does not fuzzy-match")
    func shortNameGuardThreeLetters() {
        let mirror = DirectoryMirror(
            refreshedAt: Date(timeIntervalSince1970: 0),
            people: [person(id: "p1", name: "Mae")]
        )
        #expect(mirror.nameSuggestions(for: "Mai").isEmpty)
    }

    // One letter longer than the guard: now a single-edit typo is allowed
    // through, which is the boundary the guard is drawn at.
    @Test("a four-letter name allows a single-edit typo")
    func fourLetterNameAllowsOneEdit() {
        let mirror = DirectoryMirror(
            refreshedAt: Date(timeIntervalSince1970: 0),
            people: [person(id: "p1", name: "Mayo")]
        )
        let suggestions = mirror.nameSuggestions(for: "Maya")
        #expect(suggestions.map(\.person.id) == ["p1"])
        #expect(suggestions.first?.kind == .close)
    }

    @Test("exact matches are listed ahead of close matches")
    func exactBeforeClose() {
        let mirror = DirectoryMirror(
            refreshedAt: Date(timeIntervalSince1970: 0),
            people: [
                person(id: "close", name: "Dun Duong"),
                person(id: "exact", name: "Dun Duogn"),
            ]
        )
        let suggestions = mirror.nameSuggestions(for: "Dun Duogn")
        #expect(suggestions.map(\.person.id) == ["exact", "close"])
    }

    @Test("a blank query suggests nobody")
    func blankQuery() {
        let mirror = DirectoryMirror(
            refreshedAt: Date(timeIntervalSince1970: 0),
            people: [person(id: "p1", name: "Mai Tran")]
        )
        #expect(mirror.nameSuggestions(for: "   ").isEmpty)
    }

    // The short-name guard is drawn in Unicode code points, and this is the
    // one case where that could silently disagree with counting UTF-16 code
    // units (JavaScript's `.length`, which the web side is being fixed away
    // from) -- U+20BB7 is outside the BMP and costs two UTF-16 units for one
    // character. Swift's `Character` count already agrees with the code-point
    // count here (confirmed directly, not assumed: neither U+7530/U+4EF2 nor
    // U+20BB7 combines with a neighbor, so no grapheme cluster spans more
    // than one scalar), so this three-character query stays under the
    // four-character fuzzy floor and only an exact fold match would surface
    // -- and the query (U+7530 U+4E2D) against the candidate (U+7530 U+4EF2)
    // is not one.
    @Test("a three-code-point astral name does not fuzzy-match a one-character difference")
    func astralNameStaysUnderTheFuzzyFloor() {
        let mirror = DirectoryMirror(
            refreshedAt: Date(timeIntervalSince1970: 0),
            people: [person(id: "p1", name: "\u{20BB7}\u{7530}\u{4EF2}")]
        )
        #expect(mirror.nameSuggestions(for: "\u{20BB7}\u{7530}\u{4E2D}").isEmpty)
    }
}

@Suite("Haven suggestions and contact import compose without a double answer")
struct NameSuggestionContactCompositionTests {
    // A same-key contact is suppressed from the "in your contacts" row set
    // by Brief 2's own dedup regardless of whether that person also shows up
    // here as a name suggestion -- the two mechanisms key on different
    // things (a handle vs a name) and neither has to know about the other
    // for this to hold.
    @Test("a contact whose handle already matches a Haven person is not also an import row")
    func handleDedupHoldsAlongsideNameSuggestion() {
        let known = person(
            id: "p1", name: "Dun Duong",
            handles: [MirrorHandle(platform: "phone", value: "+14155550132")]
        )
        let mirror = DirectoryMirror(refreshedAt: Date(timeIntervalSince1970: 0), people: [known])

        // Named closely enough to surface as a Haven suggestion...
        let nameHits = mirror.nameSuggestions(for: "Dun Duogn")
        #expect(nameHits.map(\.person.id) == ["p1"])

        // ...and the device contact holding the same phone this person is
        // already saved under is not offered as a separate import.
        let contact = AddressBookContact(
            id: "c1", name: "Dun Duong", phones: ["+1 (415) 555-0132"], emails: []
        )
        #expect(ContactImportMatching.importCandidates(from: [contact], mirror: mirror).isEmpty)
    }
}
