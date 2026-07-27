import ConvexMobile
import Testing

@testable import Haven

private func person(_ name: String) -> DirectoryPerson {
    DirectoryPerson(_id: "p_\(name)", name: name, company: nil, role: nil, city: nil)
}

/// Reads a string out of the argument dictionary, which holds an existential
/// and so cannot simply be compared.
private func string(_ args: [String: ConvexEncodable?], _ key: String) -> String? {
    guard let value = args[key] else { return nil }
    return value as? String
}

@Suite("Search arguments")
struct SearchArgumentsTests {
    /// `searchDirectory` types its chips `v.optional(v.string())`, which accepts
    /// a missing key and rejects an explicit null. A chip nobody set has to be
    /// absent from the dictionary, not present holding nil.
    @Test("an unset chip is left out rather than sent as null")
    func unsetChipsAreOmitted() {
        let args = SearchRequest.arguments(for: SearchKey(query: "maya", filters: .any))

        #expect(args["company"] == nil)
        #expect(args["city"] == nil)
        #expect(args["role"] == nil)
    }

    @Test("a pinned chip travels with its value")
    func pinnedChipsAreSent() {
        var filters = SearchFilters.any
        filters.company = "Haven"
        filters.city = "Da Nang"

        let args = SearchRequest.arguments(for: SearchKey(query: "", filters: filters))

        #expect(string(args, "company") == "Haven")
        #expect(string(args, "city") == "Da Nang")
        #expect(args["role"] == nil)
    }

    @Test("the keyword is trimmed, and a blank one is left out")
    func keywordIsTrimmed() {
        let padded = SearchRequest.arguments(for: SearchKey(query: "  maya  ", filters: .any))
        #expect(string(padded, "keyword") == "maya")

        let blank = SearchRequest.arguments(for: SearchKey(query: "   ", filters: .any))
        #expect(blank["keyword"] == nil)
    }

    /// Empty results mean two different things, and only one of them is a dead
    /// end: nobody saved yet, or nobody matching. The screen needs to tell them
    /// apart to say the right sentence.
    @Test("narrowing is either a typed word or a pinned chip")
    func narrowing() {
        #expect(SearchRequest.isNarrowed(SearchKey(query: "", filters: .any)) == false)
        #expect(SearchRequest.isNarrowed(SearchKey(query: "   ", filters: .any)) == false)
        #expect(SearchRequest.isNarrowed(SearchKey(query: "maya", filters: .any)))

        var filters = SearchFilters.any
        filters.role = "Founder"
        #expect(SearchRequest.isNarrowed(SearchKey(query: "", filters: filters)))
    }
}

@Suite("Search results arriving")
@MainActor
struct SearchResultsTests {
    /// Typing opens a read per keystroke, and they can land out of order. A
    /// result for a query nobody is looking at any more must not replace the
    /// one they are.
    @Test("a result for an abandoned query is ignored")
    func staleResultsAreIgnored() {
        let model = SearchModel(preview: .loading)
        let abandoned = model.beginSearch()
        let current = model.beginSearch()

        model.apply([person("Maya")], generation: abandoned)
        #expect(model.people.isEmpty)

        model.apply([person("Mai")], generation: current)
        #expect(model.people.map(\.name) == ["Mai"])
    }

    /// A live subscription that has already answered goes quiet between edits,
    /// and the deadline fires on that quiet. Silence only means unreachable
    /// when nothing ever came back.
    @Test("going quiet after an answer is not a failure")
    func silenceAfterAnAnswerIsIgnored() {
        let model = SearchModel(preview: .loading)
        let generation = model.beginSearch()

        model.apply([person("Maya")], generation: generation)
        model.applySilence(generation: generation)

        #expect(model.load == .ready([person("Maya")]))
    }

    @Test("silence with nothing behind it is unreachable")
    func silenceWithNoAnswerIsUnreachable() {
        let model = SearchModel(preview: .loading)

        model.applySilence(generation: model.beginSearch())

        #expect(model.load == .unreachable)
    }

    @Test("a silence belonging to an abandoned query is ignored")
    func staleSilenceIsIgnored() {
        let model = SearchModel(preview: .loading)
        let abandoned = model.beginSearch()
        _ = model.beginSearch()

        model.applySilence(generation: abandoned)

        #expect(model.load == .loading)
    }

    /// Each new query starts its own wait. Without resetting, the answer to the
    /// previous query would count as this one's and a real timeout would pass
    /// unnoticed.
    @Test("a new query waits on its own answer")
    func answeringResetsPerQuery() {
        let model = SearchModel(preview: .loading)
        model.apply([person("Maya")], generation: model.beginSearch())

        model.applySilence(generation: model.beginSearch())

        #expect(model.load == .unreachable)
    }
}
