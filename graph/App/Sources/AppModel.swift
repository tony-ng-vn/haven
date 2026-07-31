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

/// Orchestrates the one-time load: extract -> resolve -> filter -> build -> simulate. All of
/// GraphCore's extraction/resolution/filter/build calls are synchronous and can block on
/// disk I/O for a real chat.db, so the whole pipeline runs off the main actor and only the
/// final state hop comes back.
@Observable
@MainActor
final class AppModel {
    private(set) var state: AppState = .loading

    private let chatDBPath: String
    private let contactsDBPaths: [String]
    /// Guards against a second concurrent/duplicate load. `.task` is documented to fire once
    /// per view appearance, but that view's identity across the `.loading` -> `.ready`
    /// transition is not something this target can verify without launching the app, which
    /// is off limits here -- so this makes a re-fire structurally harmless (a no-op) instead
    /// of relying on an unverified claim about SwiftUI's view-identity behavior.
    private var hasStartedLoading = false

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
        let chatDBPath = chatDBPath
        let contactsDBPaths = contactsDBPaths

        Task.detached(priority: .userInitiated) {
            let result = Self.runPipeline(
                chatDBPath: chatDBPath,
                contactsDBPaths: contactsDBPaths,
                windowSize: safeWindowSize
            )
            await MainActor.run { [weak self] in
                self?.state = result
            }
        }
    }

    nonisolated private static func runPipeline(
        chatDBPath: String,
        contactsDBPaths: [String],
        windowSize: CGSize
    ) -> AppState {
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
        let filterResult = PersonFilter.apply(extract: extract, people: identity.people)
        let graph = GraphBuilder.build(extract: extract, keptPeople: filterResult.kept)
        let simulation = ForceSimulation(graph: graph, size: windowSize)
        return .ready(graph: graph, simulation: simulation)
    }
}
