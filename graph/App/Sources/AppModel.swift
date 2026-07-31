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
/// no longer mutated directly (see AppModel.hideNode): it is re-derived from Overrides on
/// every rebuild, via HiddenNodeOverride, so the actual source of truth for what is hidden
/// lives in the overrides store, not here.
struct DisplayOptions: Equatable {
    var dateRange: ClosedRange<Date>?
    var showDeadGroups: Bool = false
    var hiddenNodeIDs: Set<String> = []
}

/// Orchestrates the one-time load and every later interaction re-derive: extract -> resolve
/// (with the overrides store's asserted merges) -> filter -> drop removed -> build ->
/// simulate. Unlike before step 8, resolve can no longer be cached across every rebuild: an
/// answered merge question changes IdentityResolution's own unions, so it has to re-run
/// whenever displayOptions OR overrides.mergeAnswers change. This is cheap (a union-find over
/// a few hundred strings), so there is no cache to invalidate here, only cachedExtract and
/// cachedContacts -- the two things that never change without a resync.
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
    /// The people the current graph was built from: post time-filter, post asserted-merge
    /// resolve, post removed-people drop. A GraphNode alone does not carry a person's full
    /// identifier set, so hideNode/removePerson need this to turn a clicked node id back into
    /// the identifiers Overrides actually keys on -- both only ever act on a node that is
    /// actually rendered, so it is correct for them to see the post-drop list.
    private(set) var lastKeptPeople: [Person] = []
    /// Every resolved person BEFORE PersonFilter/RemovedPeopleOverride, i.e. the same list
    /// mergeQueue's candidates were generated against. A MergeCandidate can name a person who
    /// does not survive filtering (both sides only need a contact card to become a candidate,
    /// which overrides rules 1-3 but not notLive) or who the user has since removed -- using
    /// lastKeptPeople here instead would silently fail to resolve that candidate's
    /// identifiers, and answerMerge's .separate branch would never actually suppress it.
    private(set) var lastResolvedPeople: [Person] = []
    /// Merge questions still open, after suppressing every one the user has already
    /// answered (MergeCandidateSuppression). Drives the toolbar's merge queue popover.
    private(set) var mergeQueue: [MergeCandidate] = []
    /// How many PEOPLE the removed-identifiers override actually dropped this rebuild, for
    /// the toolbar's "Removed: N" indicator -- deliberately not
    /// overrides.removedPersonIdentifiers.count, which counts raw identifier strings: a
    /// person with two identifiers (e.g. one just merged in) would read as 2 removed people.
    private(set) var removedPersonCount = 0
    /// The user's saved curation (PLAN.md build order step 8: hidden/removed/merge-answered
    /// state that must survive a resync). Loaded once at startup, mutated and saved by the
    /// interaction methods below, never edited directly by any view.
    private(set) var overrides = Overrides()

    private let chatDBPath: String
    private let contactsDBPaths: [String]
    private let overridesStore: OverridesStore
    private var hasStartedLoading = false

    /// Cached from the first successful load so every later interaction change (time filter,
    /// dead-group toggle, a merge answer) re-derives from memory and never re-reads a
    /// database -- only Resync does that (see resync()).
    private var cachedExtract: ChatExtract?
    private var cachedContacts: [ContactRecord]?
    private var lastWindowSize = CGSize(width: 1200, height: 900)

    init(overridesStore: OverridesStore = OverridesStore(fileURL: OverridesStore.defaultFileURL())) {
        let home = NSHomeDirectory()
        self.chatDBPath = home + "/Library/Messages/chat.db"
        self.contactsDBPaths = Self.discoverContactsDatabasePaths(home: home)
        self.overridesStore = overridesStore
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
    /// no-op) from the permission view's Try Again and the toolbar's Resync (both forced,
    /// since by then a load has already run at least once).
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
        let overridesStore = overridesStore

        Task.detached(priority: .userInitiated) {
            // Independent reads: a corrupt overrides file is reported even if extraction
            // would otherwise succeed, and vice versa -- neither masks the other.
            let overridesOutcome = Self.loadOverrides(store: overridesStore)
            let extractionOutcome = Self.extractRawData(chatDBPath: chatDBPath, contactsDBPaths: contactsDBPaths)

            await MainActor.run { [weak self] in
                guard let self else { return }

                if case .failed(let message) = overridesOutcome {
                    self.state = .failed(message: message)
                    return
                }
                if case .success(let overrides) = overridesOutcome {
                    self.overrides = overrides
                }

                switch extractionOutcome {
                case .needsPermission(let explanation):
                    self.state = .needsPermission(explanation: explanation)
                case .failed(let message):
                    self.state = .failed(message: message)
                case .success(let extract, let contacts):
                    self.cachedExtract = extract
                    self.cachedContacts = contacts
                    self.messageDateBounds = Self.dateBounds(of: extract)
                    self.rebuild()
                }
            }
        }
    }

    /// PLAN.md's "resync on demand": re-reads both databases from scratch (never the cached
    /// extract) and reloads the overrides store fresh from disk, then rebuilds. Every other
    /// interaction method below replays against the in-memory cache; this is the one that
    /// does not.
    func resync() {
        load(windowSize: lastWindowSize, force: true)
    }

    /// Re-derives graph + simulation (and the hidden-id mapping, and the merge queue) from
    /// the cached extract/contacts using the current displayOptions and overrides. Called
    /// once after the initial load, and again whenever dateRange, showDeadGroups, or a merge
    /// answer changes: a fresh assembly animation on every such change is accepted, even
    /// desirable, behavior (PLAN.md's assembly is not a one-time intro, it is what settling
    /// looks like).
    func rebuild() {
        guard let extract = cachedExtract, let contacts = cachedContacts else { return }
        state = .loading
        let options = displayOptions
        let currentOverrides = overrides
        let windowSize = lastWindowSize

        Task.detached(priority: .userInitiated) {
            let result = Self.derive(extract: extract, contacts: contacts, overrides: currentOverrides, options: options, windowSize: windowSize)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.state = result.state
                self.lastResolvedPeople = result.resolvedPeople
                self.lastKeptPeople = result.keptPeople
                self.mergeQueue = result.mergeQueue
                self.displayOptions.hiddenNodeIDs = result.hiddenNodeIDs
                self.removedPersonCount = result.removedPersonCount
                if case .ready(let graph, _) = result.state {
                    self.lastReadyGraph = graph
                }
                // A time filter (or, less plausibly, a dead-groups toggle or a merge) can drop
                // the currently focused node from the rebuilt graph entirely. A focus chip
                // pointing at a node that no longer exists is worse than clearing it.
                if case .ready(let graph, _) = result.state,
                   let focusedNodeID = self.focusedNodeID,
                   !graph.nodes.contains(where: { $0.id == focusedNodeID }) {
                    self.focusedNodeID = nil
                }
            }
        }
    }

    private struct DeriveResult {
        let state: AppState
        let resolvedPeople: [Person]
        let keptPeople: [Person]
        let mergeQueue: [MergeCandidate]
        let hiddenNodeIDs: Set<String>
        let removedPersonCount: Int
    }

    nonisolated private static func derive(
        extract: ChatExtract,
        contacts: [ContactRecord],
        overrides: Overrides,
        options: DisplayOptions,
        windowSize: CGSize
    ) -> DeriveResult {
        let filteredExtract: ChatExtract
        if let range = options.dateRange {
            filteredExtract = TimeFilter.apply(extract: extract, from: range.lowerBound, to: range.upperBound)
        } else {
            filteredExtract = extract
        }

        let assertedMerges = overrides.mergeAnswers
            .filter { $0.decision == .merged }
            .map { ($0.identifierA, $0.identifierB) }
        let identity = IdentityResolution.resolve(
            handles: filteredExtract.handles,
            contacts: contacts,
            assertedMerges: assertedMerges
        )

        let filterResult = PersonFilter.apply(extract: filteredExtract, people: identity.people)
        let keptPeople = RemovedPeopleOverride.apply(
            filterResult.kept,
            removedPersonIdentifiers: overrides.removedPersonIdentifiers
        )

        let graph = GraphBuilder.build(extract: filteredExtract, keptPeople: keptPeople)
        let simulation = ForceSimulation(graph: graph, size: windowSize, includeDeadGroups: options.showDeadGroups)

        let hiddenNodeIDs = HiddenNodeOverride.nodeIDs(
            people: keptPeople,
            graph: graph,
            hiddenPersonIdentifiers: overrides.hiddenPersonIdentifiers,
            hiddenGroupGUIDs: overrides.hiddenGroupGUIDs
        )
        let mergeQueue = MergeCandidateSuppression.apply(
            candidates: identity.mergeCandidates,
            people: identity.people,
            answers: overrides.mergeAnswers
        )

        return DeriveResult(
            state: .ready(graph: graph, simulation: simulation),
            resolvedPeople: identity.people,
            keptPeople: keptPeople,
            mergeQueue: mergeQueue,
            hiddenNodeIDs: hiddenNodeIDs,
            // Only what RemovedPeopleOverride itself dropped, not PersonFilter's own rules:
            // filterResult.kept has already had shortcode/neverReplied/etc. applied, so the
            // difference here is purely the override's doing.
            removedPersonCount: filterResult.kept.count - keptPeople.count
        )
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

    /// Render-only, same as before step 8: never rebuilds the simulation, positions keep
    /// their current layout. What changed is where the hidden set comes from -- this now
    /// records the person's identifiers (or the group's guid) into the overrides store and
    /// saves, so the hide survives a resync, then re-derives displayOptions.hiddenNodeIDs
    /// with the same HiddenNodeOverride mapping rebuild() itself uses (cheap: no database
    /// read, no simulation rebuild, just a small set computation).
    func hideNode(_ id: String) {
        if id.hasPrefix("chat:") {
            overrides.hiddenGroupGUIDs.insert(String(id.dropFirst("chat:".count)))
        } else if let person = lastKeptPeople.first(where: { $0.id == id }) {
            overrides.hiddenPersonIdentifiers.formUnion(person.identifiers)
        }
        saveOverrides()
        recomputeHiddenNodeIDs()
        // A focus chip pointing at a node the user just hid is confusing, not useful.
        if focusedNodeID == id {
            focusedNodeID = nil
        }
    }

    func unhideAll() {
        overrides.hiddenPersonIdentifiers = []
        overrides.hiddenGroupGUIDs = []
        saveOverrides()
        recomputeHiddenNodeIDs()
    }

    private func recomputeHiddenNodeIDs() {
        guard let graph = lastReadyGraph else { return }
        displayOptions.hiddenNodeIDs = HiddenNodeOverride.nodeIDs(
            people: lastKeptPeople,
            graph: graph,
            hiddenPersonIdentifiers: overrides.hiddenPersonIdentifiers,
            hiddenGroupGUIDs: overrides.hiddenGroupGUIDs
        )
    }

    /// Structural, unlike hideNode: a removed person drops out before GraphBuilder ever sees
    /// them, so this rebuilds the whole pipeline rather than just re-deriving what is hidden.
    func removePerson(_ id: String) {
        guard let person = lastKeptPeople.first(where: { $0.id == id }) else { return }
        overrides.removedPersonIdentifiers.formUnion(person.identifiers)
        saveOverrides()
        rebuild()
    }

    func restoreAllRemoved() {
        overrides.removedPersonIdentifiers = []
        saveOverrides()
        rebuild()
    }

    /// A .merged decision is an extra union in IdentityResolution -- the whole pipeline has
    /// to re-run. A .separate decision changes nothing about identity, filtering, or the
    /// graph: only the queue itself shrinks, so this re-applies suppression directly instead
    /// of paying for a full rebuild (and the assembly animation that comes with one) over an
    /// answer that has no structural effect.
    func answerMerge(_ candidate: MergeCandidate, decision: MergeDecision) {
        overrides.mergeAnswers.append(
            MergeAnswer(identifierA: candidate.personID1, identifierB: candidate.personID2, decision: decision)
        )
        saveOverrides()
        switch decision {
        case .merged:
            rebuild()
        case .separate:
            // lastResolvedPeople, not lastKeptPeople: a MergeCandidate only requires a
            // contact card on both sides (overrides PersonFilter rules 1-3, not notLive), so
            // a candidate can name someone who never made it into the kept/rendered graph at
            // all. Suppressing against the post-filter list would silently fail to resolve
            // that person's identifiers and leave the just-answered candidate in the queue.
            mergeQueue = MergeCandidateSuppression.apply(
                candidates: mergeQueue,
                people: lastResolvedPeople,
                answers: overrides.mergeAnswers
            )
        }
    }

    func setFocus(_ id: String?) {
        focusedNodeID = id
    }

    func clearFocus() {
        focusedNodeID = nil
    }

    /// The toolbar's Export button is enabled only in this state (GraphImageRenderer needs an
    /// actual graph + simulation to render from).
    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    enum ExportError: Error {
        case notReady
    }

    /// Renders THE CURRENT VIEW STATE per PLAN.md's export goal: the whole simulated layout
    /// at its native canvas-space positions (never the on-screen zoom/pan), always rest-state
    /// (no focus dimming, regardless of the current focusedNodeID), with whatever time filter/
    /// dead-group toggle/hidden nodes are already baked into the current `graph`/`simulation`/
    /// displayOptions. The actual rendering (rasterizing at scale 3 over hundreds of nodes,
    /// then PNG-encoding) is real CPU work, so it runs off the main actor -- but ForceSimulation
    /// itself is not Sendable, so positions/radii (plain Sendable dictionaries) are snapshotted
    /// here on the main actor first, and only those, plus the already-Sendable Graph, cross
    /// into the detached task.
    func exportImage(to url: URL) async throws {
        guard case .ready(let graph, let simulation) = state else {
            throw ExportError.notReady
        }
        let positions = simulation.positions
        let radii = simulation.radii
        let hiddenNodeIDs = displayOptions.hiddenNodeIDs
        let canvasSize = lastWindowSize

        try await Task.detached(priority: .userInitiated) {
            let image = GraphImageRenderer.render(
                graph: graph,
                positions: positions,
                radii: radii,
                hiddenNodeIDs: hiddenNodeIDs,
                canvasSize: canvasSize,
                scale: 3
            )
            try GraphImageExport.writePNG(image: image, to: url)
        }.value
    }

    private func saveOverrides() {
        do {
            try overridesStore.save(overrides)
        } catch {
            // A personal, single-user tool: a save failure here means the very latest action
            // might not survive a relaunch, but the in-memory session is unaffected and
            // every other action keeps working, so this is not worth a failed state over.
            print("ConnectionGraph: failed to save overrides to \(overridesStore.fileURL.path): \(error)")
        }
    }

    private enum ExtractionOutcome {
        case needsPermission(explanation: String)
        case failed(message: String)
        case success(extract: ChatExtract, contacts: [ContactRecord])
    }

    nonisolated private static func extractRawData(
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

        return .success(extract: extract, contacts: contacts)
    }

    private enum OverridesOutcome {
        case failed(message: String)
        case success(Overrides)
    }

    /// A missing overrides file is not an error (OverridesStore.load already treats it as
    /// fresh-install-empty); only a decode failure surfaces here, named with the file path
    /// so the failed state actually tells the user which file to go look at.
    nonisolated private static func loadOverrides(store: OverridesStore) -> OverridesOutcome {
        do {
            return .success(try store.load())
        } catch {
            return .failed(message: "Could not read your saved overrides at \(store.fileURL.path): \(error)")
        }
    }
}
