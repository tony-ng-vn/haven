import Foundation
import Observation
import CoreGraphics
import GraphCore

/// Where the app is in loading its own data. `.ready` carries both the built Graph (for
/// static facts like node kind/name) and the already-ticking ForceSimulation (for position);
/// splitting them would mean re-deriving one from the other on every frame.
enum AppState {
    case loading
    case needsPermission(explanation: String)
    case ready(graph: Graph, simulation: ForceSimulation)
    case failed(message: String)
}

/// What the user has chosen to see, independent of the underlying data. `hiddenNodeIDs` is
/// handled entirely differently from the other two fields: it never triggers a rebuild (see
/// AppModel.hideNode) since it is a render-only concern, applied to what the view draws, not
/// to the simulation.
struct DisplayOptions: Equatable {
    var dateRange: ClosedRange<Date>?
    var showDeadGroups: Bool = false
    var hiddenNodeIDs: Set<String> = []
}

/// Orchestrates the one-time load and every later interaction re-derive: extract -> resolve
/// (once) -> filter -> build -> simulate (every time displayOptions.dateRange or
/// showDeadGroups changes). All of GraphCore's calls are synchronous and can block on disk
/// I/O or just be CPU work over hundreds of messages, so both the initial load and every
/// later rebuild run off the main actor and only the final state hop comes back.
@Observable
@MainActor
final class AppModel {
    private(set) var state: AppState = .loading
    private(set) var displayOptions = DisplayOptions()
    /// The full span of message dates in the raw (unfiltered) extract, for the toolbar's
    /// date pickers. nil until the first successful load, and nil forever if the account
    /// turns out to have no messages at all -- the toolbar's date pickers are expected to
    /// disable themselves in that case rather than show a meaningless range.
    private(set) var messageDateBounds: ClosedRange<Date>?
    /// Which node is focused, if any. Lives here rather than in GraphView's own @State: the
    /// toolbar's Focus chip is chrome hoisted above GraphView (see ContentView), and a
    /// rebuild tears GraphView down and reconstructs it (a fresh assembly animation, PLAN.md-
    /// intended behavior) -- view-local state would be silently wiped on every date-range or
    /// dead-groups change, taking the chip with it.
    private(set) var focusedNodeID: String?
    /// The most recent successfully-built graph, kept around after `state` moves back to
    /// `.loading` for a rebuild. Toolbar chrome (the Focus chip's name) is hoisted above
    /// GraphView and would otherwise flicker away for the fraction of a second a rebuild's
    /// `.loading` flash is visible; reading this instead of `state` directly avoids that.
    private(set) var lastReadyGraph: Graph?

    private let chatDBPath: String
    private let contactsDBPaths: [String]
    private var hasStartedLoading = false

    /// Cached from the first successful load so every later interaction change (time filter,
    /// dead-group toggle) re-derives from memory and never re-reads a database. Identity
    /// resolution in particular has no reason to rerun on a rebuild: it depends only on
    /// handles and contacts, neither of which a time filter or dead-group toggle touches.
    private var cachedExtract: ChatExtract?
    private var cachedPeople: [Person]?
    private var lastWindowSize = CGSize(width: 1200, height: 900)

    init() {
        let home = NSHomeDirectory()
        self.chatDBPath = home + "/Library/Messages/chat.db"
        self.contactsDBPaths = Self.discoverContactsDatabasePaths(home: home)
    }

    /// The real Contacts store is not one database: a top-level AddressBook-v22.abcddb plus
    /// one more per linked account under Sources/<id>/ (found the hard way, in pass 1's
    /// build-order step 2 -- see JOURNAL.md). Missing directories are not an error here, just
    /// an empty result: Contacts data is an enrichment, not a requirement for the graph itself.
    private static func discoverContactsDatabasePaths(home: String) -> [String] {
        let fileManager = FileManager.default
        let addressBookRoot = home + "/Library/Application Support/AddressBook"
        var paths: [String] = []

        let topLevelPath = addressBookRoot + "/AddressBook-v22.abcddb"
        if fileManager.fileExists(atPath: topLevelPath) {
            paths.append(topLevelPath)
        }

        let sourcesDirectory = addressBookRoot + "/Sources"
        if let entries = try? fileManager.contentsOfDirectory(atPath: sourcesDirectory) {
            for entry in entries.sorted() {
                let candidate = sourcesDirectory + "/" + entry + "/AddressBook-v22.abcddb"
                if fileManager.fileExists(atPath: candidate) {
                    paths.append(candidate)
                }
            }
        }

        return paths
    }

    /// Runs the pipeline sized to the window the graph will render into. `force` distinguishes
    /// the initial on-appear call (never forced, so a spurious second call from `.task` is a
    /// no-op) from the permission view's Try Again (always forced, since by then a load has
    /// already run and failed).
    func load(windowSize: CGSize, force: Bool = false) {
        guard force || !hasStartedLoading else { return }
        hasStartedLoading = true
        state = .loading

        // A window can report a zero (or otherwise degenerate) size on first layout, before
        // its first real geometry pass. Every node's initial position is a fraction of this
        // size from center; at zero, every node starts stacked exactly on top of the user,
        // and the layout never spreads out from there. 400x300 is an arbitrary but sane floor
        // -- smaller than any real window this app would run in, big enough to actually
        // scatter nodes.
        let safeWindowSize = CGSize(width: max(windowSize.width, 400), height: max(windowSize.height, 300))
        lastWindowSize = safeWindowSize
        let chatDBPath = chatDBPath
        let contactsDBPaths = contactsDBPaths

        Task.detached(priority: .userInitiated) {
            let outcome = Self.extractAndResolve(chatDBPath: chatDBPath, contactsDBPaths: contactsDBPaths)
            await MainActor.run { [weak self] in
                guard let self else { return }
                switch outcome {
                case .needsPermission(let explanation):
                    self.state = .needsPermission(explanation: explanation)
                case .failed(let message):
                    self.state = .failed(message: message)
                case .success(let extract, let people):
                    self.cachedExtract = extract
                    self.cachedPeople = people
                    self.messageDateBounds = Self.dateBounds(of: extract)
                    self.rebuild()
                }
            }
        }
    }

    /// Re-derives graph + simulation from the cached extract/people using the current
    /// displayOptions (minus hiddenNodeIDs, which never reach this far -- see hideNode).
    /// Called once after the initial load, and again whenever dateRange or showDeadGroups
    /// changes: a fresh assembly animation on every such change is accepted, even desirable,
    /// behavior (PLAN.md's assembly is not a one-time intro, it is what settling looks like).
    func rebuild() {
        guard let extract = cachedExtract, let people = cachedPeople else { return }
        state = .loading
        let options = displayOptions
        let windowSize = lastWindowSize

        Task.detached(priority: .userInitiated) {
            let result = Self.derive(extract: extract, people: people, options: options, windowSize: windowSize)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.state = result
                // A time filter (or, less plausibly, a dead-groups toggle) can drop the
                // currently focused node from the rebuilt graph entirely. A focus chip
                // pointing at a node that no longer exists is worse than clearing it.
                if case .ready(let graph, _) = result {
                    self.lastReadyGraph = graph
                }
                if case .ready(let graph, _) = result,
                   let focusedNodeID = self.focusedNodeID,
                   !graph.nodes.contains(where: { $0.id == focusedNodeID }) {
                    self.focusedNodeID = nil
                }
            }
        }
    }

    nonisolated private static func derive(
        extract: ChatExtract,
        people: [Person],
        options: DisplayOptions,
        windowSize: CGSize
    ) -> AppState {
        let filteredExtract: ChatExtract
        if let range = options.dateRange {
            filteredExtract = TimeFilter.apply(extract: extract, from: range.lowerBound, to: range.upperBound)
        } else {
            filteredExtract = extract
        }
        let filterResult = PersonFilter.apply(extract: filteredExtract, people: people)
        let graph = GraphBuilder.build(extract: filteredExtract, keptPeople: filterResult.kept)
        let simulation = ForceSimulation(graph: graph, size: windowSize, includeDeadGroups: options.showDeadGroups)
        return .ready(graph: graph, simulation: simulation)
    }

    private static func dateBounds(of extract: ChatExtract) -> ClosedRange<Date>? {
        guard var minDate = extract.messages.first?.date else { return nil }
        var maxDate = minDate
        for message in extract.messages.dropFirst() {
            if message.date < minDate { minDate = message.date }
            if message.date > maxDate { maxDate = message.date }
        }
        return minDate...maxDate
    }

    // MARK: - Interaction

    func setDateRange(_ range: ClosedRange<Date>?) {
        guard displayOptions.dateRange != range else { return }
        displayOptions.dateRange = range
        rebuild()
    }

    func setShowDeadGroups(_ show: Bool) {
        guard displayOptions.showDeadGroups != show else { return }
        displayOptions.showDeadGroups = show
        rebuild()
    }

    /// Render-only: never rebuilds, so positions keep their current layout. GraphView applies
    /// Graph.excludingNodes to what it draws; the simulation itself never hears about this.
    func hideNode(_ id: String) {
        displayOptions.hiddenNodeIDs.insert(id)
        // A focus chip pointing at a node the user just hid is confusing, not useful.
        if focusedNodeID == id {
            focusedNodeID = nil
        }
    }

    func unhideAll() {
        displayOptions.hiddenNodeIDs = []
    }

    func setFocus(_ id: String?) {
        focusedNodeID = id
    }

    func clearFocus() {
        focusedNodeID = nil
    }

    private enum ExtractionOutcome {
        case needsPermission(explanation: String)
        case failed(message: String)
        case success(extract: ChatExtract, people: [Person])
    }

    nonisolated private static func extractAndResolve(
        chatDBPath: String,
        contactsDBPaths: [String]
    ) -> ExtractionOutcome {
        let extract: ChatExtract
        do {
            extract = try ChatDatabase.extract(path: chatDBPath)
        } catch SQLiteReadError.cannotOpen {
            return .needsPermission(
                explanation: "ConnectionGraph could not open your Messages database. "
                    + "This almost always means Full Disk Access has not been granted yet."
            )
        } catch {
            return .failed(message: "Could not read the Messages database: \(error)")
        }

        var contacts: [ContactRecord] = []
        for contactsDBPath in contactsDBPaths {
            do {
                contacts += try ContactsDatabase.extract(path: contactsDBPath)
            } catch {
                return .failed(message: "Could not read the Contacts database: \(error)")
            }
        }

        let identity = IdentityResolution.resolve(handles: extract.handles, contacts: contacts)
        return .success(extract: extract, people: identity.people)
    }
}
