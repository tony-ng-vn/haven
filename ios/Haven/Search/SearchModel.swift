import Combine
import ConvexMobile
import SwiftUI

/// What the search screen has to show.
enum SearchLoad: Equatable {
    case loading
    case ready([DirectoryPerson])
    /// The search could not be read. Said out loud with a way to try again,
    /// because a spinner that never ends is the one outcome with no way out.
    case unreachable
}

/// Which value each of the three chips is pinned to. Nil is "any".
struct SearchFilters: Equatable {
    var company: String?
    var city: String?
    var role: String?

    static let any = SearchFilters()

    var isEmpty: Bool { company == nil && city == nil && role == nil }
}

/// The chip values the caller's own directory offers, as
/// `people:directoryFacets` returns them.
struct DirectoryFacets: Decodable, Equatable {
    var companies: [Facet] = []
    var cities: [Facet] = []
    var roles: [Facet] = []

    static let empty = DirectoryFacets()

    struct Facet: Decodable, Equatable, Identifiable {
        let value: String
        let count: Int

        var id: String { value }
    }
}

/// What the screen is asking for: the typed words and the pinned chips.
///
/// One value so the view can watch a single id and reissue on any change,
/// rather than four separate observers that can fire in any order.
struct SearchKey: Equatable {
    var query: String
    var filters: SearchFilters
}

enum SearchRequest {
    /// The arguments `people:searchDirectory` takes for this key.
    ///
    /// Absent, never null. The query types every chip `v.optional(v.string())`,
    /// which accepts a missing key and rejects an explicit null, so a chip
    /// nobody set has to be left out of the dictionary entirely.
    static func arguments(for key: SearchKey) -> [String: ConvexEncodable?] {
        var arguments: [String: ConvexEncodable?] = [:]
        let keyword = key.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty { arguments["keyword"] = keyword }
        if let company = key.filters.company { arguments["company"] = company }
        if let city = key.filters.city { arguments["city"] = city }
        if let role = key.filters.role { arguments["role"] = role }
        return arguments
    }

    /// Whether the caller has actually narrowed anything.
    ///
    /// This is what separates "no matches" from "nobody saved yet". Both are an
    /// empty list, and only one of them is a dead end.
    static func isNarrowed(_ key: SearchKey) -> Bool {
        !key.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !key.filters.isEmpty
    }
}

/// Reads the caller's directory for a query and a set of chips.
@MainActor
final class SearchModel: ObservableObject {
    @Published var query = ""
    @Published var filters = SearchFilters.any
    @Published private(set) var load: SearchLoad = .loading
    @Published private(set) var facets = DirectoryFacets.empty

    private var results: AnyCancellable?
    private var facetsRead: AnyCancellable?
    private var generation = 0
    private var answered = false

    /// Whether this model is allowed to open a socket. The screen re-reads
    /// whenever its key changes, and a preview's key changes too, so the veto
    /// has to live here rather than at the one call site.
    private let isLive: Bool

    /// How long the field sits still before Haven reads anything.
    static let debounce: Duration = .milliseconds(300)

    init() {
        isLive = true
        readFacets()
    }

    /// A loaded screen that never opens a socket, for previews and tests.
    init(
        preview load: SearchLoad,
        facets: DirectoryFacets = .empty,
        query: String = "",
        filters: SearchFilters = .any
    ) {
        isLive = false
        self.load = load
        self.facets = facets
        self.query = query
        self.filters = filters
    }

    var key: SearchKey { SearchKey(query: query, filters: filters) }

    var people: [DirectoryPerson] {
        if case .ready(let people) = load { return people }
        return []
    }

    /// Opens a new read and returns the generation that owns it.
    ///
    /// Each query waits on its own answer, so the wait resets here. Carrying
    /// the previous query's answer forward would let a real timeout pass as
    /// though it had been answered.
    func beginSearch() -> Int {
        generation += 1
        answered = false
        return generation
    }

    /// Takes a result, unless the query that asked for it was abandoned.
    ///
    /// Typing opens a read per keystroke and they can land out of order, so a
    /// result is only allowed to land if it belongs to the query on screen.
    func apply(_ people: [DirectoryPerson], generation: Int) {
        guard generation == self.generation else { return }
        answered = true
        load = .ready(people)
    }

    /// Takes a silence, unless the query that asked for it was abandoned or
    /// already answered.
    ///
    /// A live subscription goes quiet between edits once it has answered, and
    /// the deadline fires on that quiet. Silence only means unreachable when
    /// nothing ever came back.
    func applySilence(generation: Int) {
        guard generation == self.generation, !answered else { return }
        load = .unreachable
    }

    func retry() {
        load = .loading
        search()
    }

    /// Waits for the field to settle, then reads.
    func searchAfterDebounce() async {
        do {
            try await Task.sleep(for: Self.debounce)
        } catch {
            return
        }
        search()
    }

    func search() {
        guard isLive else { return }
        let generation = beginSearch()
        // Assigning drops the previous cancellable, which cancels the read it
        // held. Without that, every abandoned query would keep its socket open
        // for the rest of the session.
        results = HavenNetwork.subscribe(
            to: "people:searchDirectory",
            with: SearchRequest.arguments(for: key),
            yielding: [DirectoryPerson].self
        ) { [weak self] people in
            self?.apply(people, generation: generation)
        } onSilence: { [weak self] in
            self?.applySilence(generation: generation)
        }
    }

    private func readFacets() {
        facetsRead = HavenNetwork.subscribe(
            to: "people:directoryFacets",
            yielding: DirectoryFacets.self
        ) { [weak self] facets in
            self?.facets = facets
        } onSilence: {
            // Chips are a convenience over a field that already works, so a
            // facet read that never lands leaves them dim rather than saying
            // anything. The results below are the screen's actual job.
        }
    }
}
