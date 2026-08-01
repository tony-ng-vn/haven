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

/// Where the step-7 model pass is, for the toolbar's quiet status chip. `running`'s `total`
/// counts only non-cached candidates (a resync's whole point is that most keys are already
/// cached and never even become work); `done` increments only on a successful onGuess, so a
/// badResponse-skipped target never counts toward it -- the chip can sit a little short of
/// its own total right up until `.finished` lands, which is expected, not a hang.
enum GuessingState: Equatable {
    case idle
    case running(done: Int, total: Int)
    case providerUnavailable
    case finished
}

/// Where the "Sync people" button is, for the toolbar's own status chip -- same shape as
/// GuessingState (idle/running/done/error) so the two chips read consistently, but this one
/// carries a short message rather than a count: sync_polygres.py's own outcomes (skip, append,
/// or the known-blocked case) are prose, not a done/total progress number.
enum SyncState: Equatable {
    case idle
    case syncing
    case done(message: String)
    case failed(message: String)
}

/// Plain, real counts from the pipeline's own two await boundaries -- never a modeled
/// percentage. MappingView reads this to show "what has actually happened so far" during
/// onboarding's "Map relationships" step.
enum MappingPhase: Equatable {
    case idle
    case extracting
    case extracted(messages: Int, contacts: Int)
    case building
    case built(people: Int, groups: Int)
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
    /// The acquaintance layer's per-chat activity for the current graph (PLAN.md, "The
    /// acquaintance layer"): what the group-node context menu reads to find a clicked group's
    /// roster (for the "everyone here knows each other" toggle) and what the Sky JSON export
    /// hands to GraphJSON, so the viewer renders the same derivation the app computes.
    private(set) var lastGroupChatActivity: [GroupChatActivity] = []
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
    /// PLAN.md build order step 7: the model pass. Drives the toolbar's quiet status chip.
    private(set) var guessingState: GuessingState = .idle
    /// The "Sync people" button's own state. Drives the toolbar's sync status chip.
    private(set) var syncState: SyncState = .idle

    // MARK: - Onboarding (welcome -> authorize -> readyToMap -> mapping -> sky)

    /// Where the onboarding flow is. The transition table itself (Onboarding.next) is pure
    /// and unit-tested in GraphCore; this is just the one live instance of it, moved by the
    /// interaction methods below.
    private(set) var onboardingStep: OnboardingStep
    /// Live probe result, not cached across launches -- Authorize always shows the truth as
    /// of the last check, including the very first one performed in init.
    private(set) var messagesAccessGranted = false
    private(set) var contactsAccessState: ContactsAccessState = .noData
    /// Plain counts from the pipeline's own two await boundaries (post-extract, post-derive),
    /// never an invented percentage: MappingView shows exactly what has actually happened
    /// so far, nothing modeled.
    private(set) var mappingPhase: MappingPhase = .idle
    /// Sky (the in-app WKWebView) is the default post-onboarding view; the toolbar's toggle
    /// flips this. Lives on the model, not view-local @State, for the same reason
    /// focusedNodeID does (see its own doc comment) -- a rebuild tears GraphView down and
    /// would otherwise silently flip the toggle back.
    private(set) var showNativeGraphView = false
    /// Where the built sky HTML lives on disk, if it has ever been built. Non-nil does not
    /// mean the file still exists right now (see hasBuiltSky in Onboarding.initialStep's
    /// caller) -- callers that care check FileManager themselves.
    private(set) var skyHTMLURL: URL?

    private static let onboardingCompletedKey = "onboardingCompleted"

    private static func readOnboardingCompleted() -> Bool {
        UserDefaults.standard.bool(forKey: onboardingCompletedKey)
    }

    /// ~/Library/Application Support/ConnectionGraph/sky.html -- same directory OverridesStore
    /// already uses for overrides.json, so there is exactly one "where does this app keep its
    /// state" answer, not two.
    private static func skyHTMLURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("ConnectionGraph", isDirectory: true)
            .appendingPathComponent("sky.html", isDirectory: false)
    }

    /// Re-runs both live probes. Called from init and from Authorize's Re-check button --
    /// deliberately never cached, since the whole point of a live probe is that System
    /// Settings can change underneath the app at any moment.
    func refreshAccessState() {
        messagesAccessGranted = MessagesAccessProbe.check(path: chatDBPath)
        contactsAccessState = ContactsAccessProbe.check(paths: contactsDBPaths)
    }

    func continueFromWelcome() {
        onboardingStep = Onboarding.next(from: onboardingStep, event: .continueFromWelcome)
    }

    /// Authorize's Continue button. Re-checks live (a stale check from init or the last
    /// Re-check tap should never be trusted for the actual gate decision) and only advances
    /// if both checks still pass.
    func confirmPermissionsAndContinue() {
        refreshAccessState()
        guard Onboarding.canProceedFromAuthorize(
            messagesGranted: messagesAccessGranted,
            contactsState: contactsAccessState
        ) else { return }
        onboardingStep = Onboarding.next(from: onboardingStep, event: .permissionsConfirmed)
    }

    /// "Map relationships". Moves to `.mapping` and starts the real pipeline load -- moved
    /// here from ContentView's `.task` on purpose: the old on-appear load meant the app read
    /// chat.db before the user had ever seen Welcome, and "Map relationships" was then a
    /// no-op against an already-consumed `hasStartedLoading` guard.
    func startMapping(windowSize: CGSize) {
        onboardingStep = Onboarding.next(from: onboardingStep, event: .startMapping)
        mappingPhase = .extracting
        load(windowSize: windowSize, force: true) { [weak self] in
            self?.finishMapping()
        }
    }

    /// Fires once the real load AND (if one started) its guess pass have both settled --
    /// same onSettled idiom syncPeople() already uses, so the sky export includes whatever
    /// names the model pass found rather than a version built moments before they arrived.
    private func finishMapping() {
        guard onboardingStep == .mapping else { return }

        if case .needsPermission = state {
            // Access was revoked between Authorize's confirm and now (or the very first
            // real read still failed despite the live probe) -- back to Authorize, never
            // silently into a mapping state with no data behind it.
            onboardingStep = Onboarding.next(from: onboardingStep, event: .permissionsRevoked)
            return
        }
        guard case .ready(let graph, _) = state else {
            // .failed: leave onboardingStep at .mapping so MappingView's own failure
            // surfacing (via AppState.failed) stays visible instead of silently
            // advancing past a load that did not actually succeed.
            return
        }

        do {
            let json = try GraphJSON.encode(
                graph: graph,
                groupChatActivity: lastGroupChatActivity,
                fullyAcquaintedRosterKeys: overrides.fullyAcquaintedRosterKeys,
                people: lastKeptPeople,
                guesses: overrides.nameGuesses
            )
            let template = try String(contentsOf: Self.templateURL(), encoding: .utf8)
            // template-sky.html's viewer logic is already inline -- no separate core .mjs
            // resource to look up or splice in (SkyExportBuilder.build treats a template with
            // no __VIEWER_CORE_JS__ placeholder as a valid shape and a nil source as correct).
            let html = try SkyExportBuilder.build(template: template, viewerCoreSource: nil, graphJSON: json)
            let url = Self.skyHTMLURL()
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try html.write(to: url, atomically: true, encoding: .utf8)
            skyHTMLURL = url
            UserDefaults.standard.set(true, forKey: Self.onboardingCompletedKey)
            onboardingStep = Onboarding.next(from: onboardingStep, event: .mapCompleted)
        } catch {
            // A build/write failure here (e.g. an unwritable Application Support, or a
            // template resource that shipped without the placeholder) should not strand
            // the user off both onboarding AND a state view -- surface it exactly like any
            // other pipeline failure the rest of the app already knows how to show.
            state = .failed(message: "Could not build your sky view: \(error)")
        }
    }

    /// The bundled viewer/template-sky.html resource (the two-plane ringed sky). Xcode
    /// resolves this via project.yml's resource entry; nonisolated because SkyExportBuilder's
    /// caller runs on the main actor but the resource lookup itself has no actor affinity.
    nonisolated private static func templateURL() -> URL {
        guard let url = Bundle.main.url(forResource: "template-sky", withExtension: "html") else {
            // A missing bundled resource is a build/packaging bug, not a runtime condition a
            // user can fix -- fail loudly at the one call site that needs it rather than
            // letting every future caller re-discover the same nil.
            fatalError("template-sky.html was not found in the app bundle -- check project.yml's resources entry")
        }
        return url
    }

    func toggleGraphViewMode() {
        showNativeGraphView.toggle()
    }

    /// Whether the polygres CLI is present at all -- the toolbar hides "Sync people"
    /// entirely rather than showing a button that can only ever fail on a machine that
    /// never installed it (PLAN.md's own scripts/sync_polygres.py resolves the same path).
    var isPolygresAvailable: Bool {
        FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.local/bin/polygres")
    }

    private var guessTask: Task<Void, Never>?
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
        // GraphCore.ContactsPathDiscovery, not a private copy here: AuthorizeView's live
        // Contacts probe needs the exact same discovery AppModel's own extraction uses, or
        // the two could disagree about whether Contacts data exists at all.
        self.contactsDBPaths = ContactsPathDiscovery.discoverPaths(home: home)
        self.overridesStore = overridesStore
        self.onboardingStep = Onboarding.initialStep(
            hasCompletedOnboarding: Self.readOnboardingCompleted(),
            messagesGranted: MessagesAccessProbe.check(path: chatDBPath),
            hasBuiltSky: FileManager.default.fileExists(atPath: Self.skyHTMLURL().path)
        )
        self.skyHTMLURL = Self.skyHTMLURL()
        refreshAccessState()
    }

    /// Runs the pipeline sized to the window the graph will render into. `force` distinguishes
    /// the initial on-appear call (never forced, so a spurious second call from `.task` is a
    /// no-op) from the permission view's Try Again and the toolbar's Resync (both forced,
    /// since by then a load has already run at least once). `onSettled`, when given, fires
    /// once this whole load AND (if one starts) the guess pass it triggers have both finished
    /// -- syncPeople() is the only caller that needs that, to know when it is safe to hand the
    /// freshly-guessed graph to the sync script; every other caller passes nil and does not pay
    /// for the bookkeeping.
    func load(windowSize: CGSize, force: Bool = false, onSettled: (@MainActor () -> Void)? = nil) {
        guard force || !hasStartedLoading else {
            onSettled?()
            return
        }
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
                    onSettled?()
                    return
                }
                if case .success(let overrides) = overridesOutcome {
                    self.overrides = overrides
                }

                switch extractionOutcome {
                case .needsPermission(let explanation):
                    self.state = .needsPermission(explanation: explanation)
                    onSettled?()
                case .failed(let message):
                    self.state = .failed(message: message)
                    onSettled?()
                case .success(let extract, let contacts):
                    self.cachedExtract = extract
                    self.cachedContacts = contacts
                    self.messageDateBounds = Self.dateBounds(of: extract)
                    self.mappingPhase = .extracted(messages: extract.messages.count, contacts: contacts.count)
                    // Only a REAL load (this branch) starts a guess pass, never a plain
                    // option rebuild (setDateRange, setShowDeadGroups, ...): those re-derive
                    // from the exact same extract/contacts already scanned for candidates,
                    // and (re-)running the model pass on every toggle would be both pointless
                    // and, for a real Ollama server, slow.
                    self.rebuild(triggeringGuessPass: true, onSettled: onSettled)
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

    // MARK: - Sync people (Polygres)

    /// This source file's own location, at build time -- graph/App/Sources/AppModel.swift.
    /// Walking up two directories lands on the package root (graph/), where scripts/ lives.
    /// This app is a personal, single-checkout dev tool (never distributed as a standalone
    /// bundle elsewhere), so pinning the script path to "wherever this source file was built
    /// from" is a safe assumption here, not something a shipped app could rely on.
    nonisolated private static let repoRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AppModel.swift -> Sources/
            .deletingLastPathComponent() // Sources/ -> App/
            .deletingLastPathComponent() // App/ -> graph/
    }()

    /// Re-runs the real load (so any new messages/contacts are picked up), lets the existing
    /// post-load guess pass run to completion (via `load`'s `onSettled`, threaded through
    /// `rebuild` and `startGuessPassIfNeeded`), THEN hands the freshly-guessed graph to
    /// scripts/sync_polygres.py. Guarded against overlap the same way the guess pass itself
    /// is not: a second tap while already syncing is a no-op rather than a second Process.
    func syncPeople() {
        guard syncState != .syncing else { return }
        syncState = .syncing

        Task {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.load(windowSize: self.lastWindowSize, force: true) {
                    continuation.resume()
                }
            }
            await self.runPolygresSyncScript()
        }
    }

    /// Invokes `python3 scripts/sync_polygres.py`. The script itself writes `exports/graph.json`
    /// nowhere -- callers are expected to have exported it via `graph-cli json` first; for the
    /// app's own use here, the CLI export step is out of scope for this button (PLAN.md's own
    /// export path is the toolbar's separate Export... button, a PNG, not this JSON). This
    /// method's job is narrowly the sync step: re-derive names, then run the sync script
    /// against whatever exports/graph.json already exists on disk.
    private func runPolygresSyncScript() async {
        let scriptURL = Self.repoRoot.appendingPathComponent("scripts/sync_polygres.py")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptURL.path]
        process.currentDirectoryURL = Self.repoRoot

        var environment = ProcessInfo.processInfo.environment
        // A GUI app launched by launchd does not inherit a login shell's PATH, so `~/.local/bin`
        // (where `polygres` lives) is typically missing here. The script itself already
        // resolves polygres by an absolute path built from $HOME, so this is belt-and-suspenders,
        // not load-bearing -- but it costs nothing and matches the brief's explicit guidance.
        let existingPath = environment["PATH"] ?? "/usr/bin:/bin"
        environment["PATH"] = NSHomeDirectory() + "/.local/bin:" + existingPath
        process.environment = environment

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            syncState = .failed(message: "Could not start the sync script: \(error)")
            return
        }

        // readDataToEndOfFile blocks, so it runs off the main actor; waitUntilExit alongside
        // it (not before) avoids the classic deadlock where a pipe's buffer fills before the
        // parent process has started draining it.
        let outputData = await withCheckedContinuation { (continuation: CheckedContinuation<Data, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: data)
            }
        }

        // The script's own discipline (never printing row contents, only counts and which
        // path ran) is what makes surfacing its raw stdout here safe; see sync_polygres.py's
        // module docstring.
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let summary = Self.summarize(scriptOutput: output)

        if process.terminationStatus == 0 {
            syncState = .done(message: summary)
        } else {
            syncState = .failed(message: summary)
        }
    }

    /// The toolbar chip has room for a short line, not the script's full multi-line output
    /// (which, for the known-blocked mutation/removal case, is a whole explanatory paragraph).
    /// First line is always the path taken ("skip"/"append"/"blocked: ..."/"failed: ..."),
    /// which is the one line worth showing at a glance.
    nonisolated private static func summarize(scriptOutput: String) -> String {
        let firstLine = scriptOutput.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        return firstLine.isEmpty ? "No output from sync script" : firstLine
    }

    /// Re-derives graph + simulation (and the hidden-id mapping, and the merge queue) from
    /// the cached extract/contacts using the current displayOptions and overrides. Called
    /// once after the initial load, and again whenever dateRange, showDeadGroups, or a merge
    /// answer changes: a fresh assembly animation on every such change is accepted, even
    /// desirable, behavior (PLAN.md's assembly is not a one-time intro, it is what settling
    /// looks like). `triggeringGuessPass` is true only right after a REAL load (see load()):
    /// that is the only time new candidates could possibly exist to guess names for.
    func rebuild(triggeringGuessPass: Bool = false, onSettled: (@MainActor () -> Void)? = nil) {
        guard let extract = cachedExtract, let contacts = cachedContacts else {
            onSettled?()
            return
        }
        state = .loading
        mappingPhase = .building
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
                self.lastGroupChatActivity = result.groupChatActivity
                self.mergeQueue = result.mergeQueue
                self.displayOptions.hiddenNodeIDs = result.hiddenNodeIDs
                self.removedPersonCount = result.removedPersonCount
                if case .ready(let graph, _) = result.state {
                    self.lastReadyGraph = graph
                    let peopleCount = graph.nodes.filter { $0.kind == .person }.count
                    let groupCount = graph.nodes.filter { $0.kind == .group }.count
                    self.mappingPhase = .built(people: peopleCount, groups: groupCount)
                }
                if triggeringGuessPass {
                    self.startGuessPassIfNeeded(extract: extract, onSettled: onSettled)
                } else {
                    onSettled?()
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

    // MARK: - Model pass (PLAN.md build order step 7)

    /// Candidate selection itself moved to GraphCore.GuessCandidateSelection so graph-cli's
    /// headless `guess` subcommand can share the exact same rule instead of reimplementing it
    /// (see that type's own doc comment).

    /// Cancels any in-flight pass (a quick resync could otherwise overlap two), assembles
    /// this rebuild's candidates, and -- only if there is new, non-cached work -- starts a
    /// GuessEngine pass on a background task with an OllamaProvider. SnippetReader is only
    /// ever reached from inside snippetSource, called lazily by GuessEngine one candidate at
    /// a time, so message text lives only for the duration of one request (PLAN.md's
    /// transient-only discipline).
    private func startGuessPassIfNeeded(extract: ChatExtract, onSettled: (@MainActor () -> Void)? = nil) {
        guessTask?.cancel()
        guard case .ready(let graph, _) = state else {
            onSettled?()
            return
        }

        let sources = GuessCandidateSelection.buildSources(graph: graph, keptPeople: lastKeptPeople, extract: extract)
        let cache = overrides.nameGuesses
        let pendingCount = sources.filter { cache[$0.candidate.key] == nil }.count
        guard pendingCount > 0 else {
            guessingState = .idle
            onSettled?()
            return
        }

        let candidates = sources.map(\.candidate)
        let chatRowIDsByKey = Dictionary(uniqueKeysWithValues: sources.map { ($0.candidate.key, $0.chatRowIDs) })
        let dbPath = chatDBPath
        let provider = OllamaProvider()
        guessingState = .running(done: 0, total: pendingCount)

        guessTask = Task.detached(priority: .background) { [weak self] in
            // Unwrapped once here, not per-closure: a weak capture cannot itself be
            // re-captured weakly by the nested @MainActor Task blocks below (a Swift 6
            // strict-concurrency rule, not a real lifetime concern -- this whole pass exists
            // to update this specific AppModel, so holding a plain reference to it for the
            // rest of this detached task is the right call anyway).
            guard let self else { return }

            let snippetSource: @Sendable (String) -> [Snippet] = { key in
                guard let rowIDs = chatRowIDsByKey[key] else { return [] }
                // try?, not try: a snippet read failing (e.g. a transient busy-timeout) should
                // cost this one candidate an empty prompt, not abort the whole pass.
                return (try? SnippetReader.read(dbPath: dbPath, chatRowIDs: rowIDs)) ?? []
            }

            await GuessEngine.run(
                candidates: candidates,
                cache: cache,
                snippetSource: snippetSource,
                provider: provider,
                onGuess: { key, guess in
                    Task { @MainActor in
                        self.overrides.nameGuesses[key] = guess
                        self.saveOverrides()
                        if case .running(let done, let total) = self.guessingState {
                            self.guessingState = .running(done: done + 1, total: total)
                        }
                    }
                },
                completion: { outcome in
                    Task { @MainActor in
                        switch outcome {
                        case .completed:
                            self.guessingState = .finished
                            onSettled?()
                        case .stoppedProviderUnreachable:
                            self.guessingState = .providerUnavailable
                            onSettled?()
                        case .cancelled:
                            // A newer pass (or a resync) superseded this one -- deliberately
                            // NOT calling this cancelled run's own onSettled: whatever
                            // triggered the newer pass owns settling now (it either passed
                            // its own onSettled, or none at all), so firing this stale one
                            // too would let syncPeople's wait resolve before the pass that
                            // actually superseded it has finished.
                            break
                        }
                    }
                }
            )
        }
    }

    private struct DeriveResult {
        let state: AppState
        let resolvedPeople: [Person]
        let keptPeople: [Person]
        let groupChatActivity: [GroupChatActivity]
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

        let built = GraphBuilder.buildDetailed(extract: filteredExtract, keptPeople: keptPeople)
        let graph = built.graph
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
            groupChatActivity: built.groupChatActivity,
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

    // MARK: - Acquaintance layer: "everyone here knows each other" (PLAN.md)

    /// The canonical roster key PLAN.md's marker uses for a CURRENTLY-rendered group node --
    /// nil for anything that is not actually a group in the current graph (a stale id after a
    /// rebuild, or a person/user node), which every call site below treats as "not marked".
    private func rosterKey(forGroupNodeID id: String) -> [String]? {
        guard let activity = lastGroupChatActivity.first(where: { $0.chatId == id }) else { return nil }
        return AcquaintanceRosterKey.canonicalize(activity.roster)
    }

    /// Reads the override store directly (never any view-local state), so the context menu's
    /// checkmark reflects what actually survives a relaunch. Translates the stored keys
    /// against `lastKeptPeople` first: a mark captured before a resync may still be keyed by a
    /// member's now-stale Person.id, which exact equality against the raw stored set would
    /// silently fail to match -- see AcquaintanceRosterKey.resolve's own doc comment.
    func isFullyAcquainted(groupNodeID: String) -> Bool {
        guard let key = rosterKey(forGroupNodeID: groupNodeID) else { return false }
        let translatedRosterKeys = AcquaintanceRosterKey.resolve(stored: overrides.fullyAcquaintedRosterKeys, people: lastKeptPeople)
        return translatedRosterKeys.contains(key)
    }

    /// Nothing here changes what draws: the app does not render acquaintance edges yet
    /// (PLAN.md). Only the override store changes, keyed by the group's CURRENT roster so the
    /// marking survives both a resync and a service-split merge that reassigns the group's own
    /// node id -- see AcquaintanceRosterKey's own doc comment for why chat guid/row id cannot
    /// be used for this instead.
    func setFullyAcquainted(groupNodeID: String, isFullyAcquainted: Bool) {
        guard let key = rosterKey(forGroupNodeID: groupNodeID) else { return }
        if isFullyAcquainted {
            overrides.fullyAcquaintedRosterKeys.insert(key)
        } else {
            overrides.fullyAcquaintedRosterKeys.remove(key)
        }
        saveOverrides()
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
        let guesses = overrides.nameGuesses

        try await Task.detached(priority: .userInitiated) {
            let image = GraphImageRenderer.render(
                graph: graph,
                positions: positions,
                radii: radii,
                hiddenNodeIDs: hiddenNodeIDs,
                canvasSize: canvasSize,
                scale: 3,
                guesses: guesses
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
