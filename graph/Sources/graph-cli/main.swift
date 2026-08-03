import Foundation
import GraphCore

private func printUsage() {
    let usage = "usage: graph-cli <stats|people|filter|killlist|graph|json|acquaintances|contacts|guess> "
        + "--chat-db PATH [--contacts-db PATH ...] [--timings] [--reguess]\n"
    FileHandle.standardError.write(Data(usage.utf8))
}

private func fail(_ message: String) -> Never {
    // No path or database content in this message: CLI output must stay journal-safe (constraint 7).
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

private struct ParsedArgs {
    var chatDBPath: String?
    var contactsDBPaths: [String] = []
    var timings: Bool = false
    /// `guess` only: drop every cached name guess (and only name guesses -- see
    /// GuessCacheRepair) before running the pass, so every previously-guessed candidate is
    /// reconsidered fresh under the current prompt/grounding rules. Repairs a cache poisoned by
    /// an earlier, more permissive prompt without hand-editing the overrides JSON file.
    var reguess: Bool = false
}

private func parseArgs(_ args: [String]) -> ParsedArgs? {
    var parsed = ParsedArgs()
    var index = 0
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--chat-db":
            guard index + 1 < args.count else { return nil }
            parsed.chatDBPath = args[index + 1]
            index += 2
        case "--contacts-db":
            guard index + 1 < args.count else { return nil }
            parsed.contactsDBPaths.append(args[index + 1])
            index += 2
        case "--timings":
            parsed.timings = true
            index += 1
        case "--reguess":
            parsed.reguess = true
            index += 1
        default:
            return nil
        }
    }
    return parsed
}

/// Stage timing for `json --timings`: numbers only to stderr, no path or database content
/// (constraint 7's journal-safe posture applies here too, not just to killlist/json's stdout).
/// Wall-clock via ContinuousClock, not a CPU-time API: the thing worth reporting is what the
/// user actually waits on.
private func timed<T>(_ label: String, enabled: Bool, _ block: () -> T) -> T {
    guard enabled else { return block() }
    let clock = ContinuousClock()
    let start = clock.now
    let result = block()
    let elapsed = clock.now - start
    let ms = Double(elapsed.components.seconds) * 1000.0 + Double(elapsed.components.attoseconds) * 1e-15
    FileHandle.standardError.write(Data("timing \(label) \(String(format: "%.1f", ms))ms\n".utf8))
    return result
}

private func printStats(_ stats: ExtractStats) {
    print("messageCount \(stats.messageCount)")
    print("fromMeCount \(stats.fromMeCount)")
    print("toMeCount \(stats.toMeCount)")
    print("handleRowCount \(stats.handleRowCount)")
    print("distinctIdentifierCount \(stats.distinctIdentifierCount)")
    print("chatCount \(stats.chatCount)")
    print("oneToOneChatCount \(stats.oneToOneChatCount)")
    print("groupChatCount \(stats.groupChatCount)")
    print("oneToOneChatsWithMessages \(stats.oneToOneChatsWithMessages)")
    print("emptyOneToOneChats \(stats.emptyOneToOneChats)")
    print("neverRepliedOneToOneChats \(stats.neverRepliedOneToOneChats)")
    print("twoMemberGroupStyleChats \(stats.twoMemberGroupStyleChats)")
    print("shortcodeHandleCount \(stats.shortcodeHandleCount)")
    print("groupSizeDistributionMin \(stats.groupSizeDistribution.min.map(String.init) ?? "none")")
    print("groupSizeDistributionMax \(stats.groupSizeDistribution.max.map(String.init) ?? "none")")
    for size in stats.groupSizeDistribution.countBySize.keys.sorted() {
        print("groupSizeDistribution[\(size)] \(stats.groupSizeDistribution.countBySize[size]!)")
    }
    for service in stats.serviceMix.keys.sorted() {
        print("serviceMix[\(service)] \(stats.serviceMix[service]!)")
    }
}

private func runStats(_ args: [String]) {
    guard let parsed = parseArgs(args), let chatDBPath = parsed.chatDBPath else {
        printUsage()
        exit(64)
    }

    let extract: ChatExtract
    do {
        extract = try ChatDatabase.extract(path: chatDBPath)
    } catch {
        fail("error: cannot read chat database")
    }

    let stats = ExtractStats.compute(extract)
    print("unjoinedMessageCount \(extract.unjoinedMessageCount)")
    printStats(stats)

    guard !parsed.contactsDBPaths.isEmpty else { return }

    var totalContacts = 0
    var withPhone = 0
    var withEmail = 0
    for contactsDBPath in parsed.contactsDBPaths {
        let records: [ContactRecord]
        do {
            records = try ContactsDatabase.extract(path: contactsDBPath)
        } catch {
            fail("error: cannot read contacts database")
        }
        totalContacts += records.count
        withPhone += records.filter { !$0.phoneNumbers.isEmpty }.count
        withEmail += records.filter { !$0.emails.isEmpty }.count
    }
    print("contactRecordCount \(totalContacts)")
    print("contactsWithPhone \(withPhone)")
    print("contactsWithEmail \(withEmail)")
}

/// Shared by every subcommand past `stats`: load chat.db, throw a journal-safe error on
/// failure rather than echoing the path (constraint 7).
private func loadChatExtract(_ path: String) -> ChatExtract {
    do {
        return try ChatDatabase.extract(path: path)
    } catch {
        fail("error: cannot read chat database")
    }
}

private func loadContacts(_ paths: [String]) -> [ContactRecord] {
    var contacts: [ContactRecord] = []
    for path in paths {
        do {
            contacts += try ContactsDatabase.extract(path: path)
        } catch {
            fail("error: cannot read contacts database")
        }
    }
    return contacts
}

private func reasonLabel(_ reason: RemovalReason) -> String {
    switch reason {
    case .shortcode: return "shortcode"
    case .alphanumericSender: return "alphanumericSender"
    case .neverReplied: return "neverReplied"
    case .notLive: return "notLive"
    }
}

private func runPeople(_ args: [String]) {
    guard let parsed = parseArgs(args), let chatDBPath = parsed.chatDBPath else {
        printUsage()
        exit(64)
    }

    let extract = loadChatExtract(chatDBPath)
    let contacts = loadContacts(parsed.contactsDBPaths)
    let result = IdentityResolution.resolve(handles: extract.handles, contacts: contacts)

    let personCount = result.people.count
    let peopleWithContactCard = result.people.filter(\.hasContactCard).count
    let peopleWithoutContactCard = personCount - peopleWithContactCard
    let peopleWithPhoto = result.people.filter { $0.thumbnailImageData != nil }.count
    let multiIdentifierPeople = result.people.filter { $0.identifiers.count >= 2 }.count
    let identifiersPerPerson = Dictionary(grouping: result.people, by: { $0.identifiers.count })
        .mapValues(\.count)

    print("personCount \(personCount)")
    print("peopleWithContactCard \(peopleWithContactCard)")
    print("peopleWithoutContactCard \(peopleWithoutContactCard)")
    print("peopleWithPhoto \(peopleWithPhoto)")
    print("mergeCandidateCount \(result.mergeCandidates.count)")
    print("multiIdentifierPeople \(multiIdentifierPeople)")
    for count in identifiersPerPerson.keys.sorted() {
        print("identifiersPerPerson[\(count)] \(identifiersPerPerson[count]!)")
    }
}

/// Shared by `filter`, `killlist`, and `graph`: load, resolve identity, apply the filter.
private func resolveExtractAndFilter(_ args: [String]) -> (ChatExtract, FilterResult)? {
    guard let parsed = parseArgs(args), let chatDBPath = parsed.chatDBPath else {
        return nil
    }
    let extract = loadChatExtract(chatDBPath)
    let contacts = loadContacts(parsed.contactsDBPaths)
    let identity = IdentityResolution.resolve(handles: extract.handles, contacts: contacts)
    return (extract, PersonFilter.apply(extract: extract, people: identity.people))
}

private func resolveAndFilter(_ args: [String]) -> FilterResult? {
    resolveExtractAndFilter(args)?.1
}

// MARK: - Contact-only people (PLAN.md 2026-08-03)
//
// A contact card with no message evidence anywhere in chat.db gets a node too, marked
// hasNoMessageEvidence, merged into the exported Graph only at the last mile -- see
// ContactOnlyPeople.derive's own doc comment for why this never reaches GraphBuilder,
// keptPeople, or GuessCandidateSelection. Kept out of resolveExtractAndFilter/runGuess
// entirely: this file's own `guess` subcommand and its helper are someone else's live
// editing surface right now, and neither needs to know contact-only people exist.

private func contactOnlyExclusionReasonLabel(_ reason: ContactOnlyExclusionReason) -> String {
    switch reason {
    case .matchesExistingPerson: return "matchesExistingPerson"
    case .noHumanName: return "noHumanName"
    case .shortcode: return "shortcode"
    case .alphanumericSender: return "alphanumericSender"
    case .duplicateWithinContactOnly: return "duplicateWithinContactOnly"
    }
}

/// Counts only (constraint 7), like `stats`/`people`/`filter`/`graph`/`acquaintances`: how
/// the real address book splits between "already a person via messages", "excluded as a
/// non-person", and "a genuine new contact-only node" -- plus the before/after node, edge,
/// and acquaintance-pair counts a reviewer needs to confirm nothing about the message-based
/// graph moved when contact-only nodes are merged in at the last mile.
private func runContacts(_ args: [String]) {
    guard let parsed = parseArgs(args), let chatDBPath = parsed.chatDBPath else {
        printUsage()
        exit(64)
    }
    let extract = loadChatExtract(chatDBPath)
    let contacts = loadContacts(parsed.contactsDBPaths)
    let identity = IdentityResolution.resolve(handles: extract.handles, contacts: contacts)
    let filterResult = PersonFilter.apply(extract: extract, people: identity.people)
    let built = GraphBuilder.buildDetailed(extract: extract, keptPeople: filterResult.kept)

    let derivation = ContactOnlyPeople.derive(
        contacts: contacts,
        matchedIdentifiers: ContactOnlyPeople.messageHandleIdentifiers(extract)
    )

    print("contactCardsTotal \(contacts.count)")
    for reason in ContactOnlyExclusionReason.allCases {
        let count = derivation.excluded.filter { $0.reason == reason }.count
        print("excluded[\(contactOnlyExclusionReasonLabel(reason))] \(count)")
    }
    print("contactOnlyNodesCreated \(derivation.people.count)")

    let overridesStore = OverridesStore(fileURL: OverridesStore.defaultFileURL())
    let fullyAcquaintedRosterKeys = (try? overridesStore.load())?.fullyAcquaintedRosterKeys ?? []
    let translatedRosterKeys = AcquaintanceRosterKey.resolve(stored: fullyAcquaintedRosterKeys, people: filterResult.kept)
    // Recomputed identically before/after: AcquaintanceDerivation reads groupChatActivity and
    // the roster keys only, never graph.nodes, so this proves the "unchanged" claim on the
    // record rather than assuming it from the derivation's own inputs being untouched.
    let acquaintancesBefore = AcquaintanceDerivation.derive(
        groupChatActivity: built.groupChatActivity,
        fullyAcquaintedRosterKeys: translatedRosterKeys
    )

    let contactOnlyNodes = ContactOnlyPeople.asGraphNodes(derivation.people)
    let graphAfter = Graph(nodes: built.graph.nodes + contactOnlyNodes, edges: built.graph.edges)
    let acquaintancesAfter = AcquaintanceDerivation.derive(
        groupChatActivity: built.groupChatActivity,
        fullyAcquaintedRosterKeys: translatedRosterKeys
    )

    print("personNodesBefore \(built.graph.nodes.filter { $0.kind == .person }.count)")
    print("personNodesAfter \(graphAfter.nodes.filter { $0.kind == .person }.count)")
    print("edgesBefore \(built.graph.edges.count)")
    print("edgesAfter \(graphAfter.edges.count)")
    print("acquaintancePairsBefore \(acquaintancesBefore.count)")
    print("acquaintancePairsAfter \(acquaintancesAfter.count)")
}

private func runFilter(_ args: [String]) {
    guard let filterResult = resolveAndFilter(args) else {
        printUsage()
        exit(64)
    }

    let keptCount = filterResult.kept.count
    let keptWithContactCard = filterResult.kept.filter(\.hasContactCard).count
    let keptWithoutContactCard = keptCount - keptWithContactCard

    print("keptCount \(keptCount)")
    print("keptWithContactCard \(keptWithContactCard)")
    print("keptWithoutContactCard \(keptWithoutContactCard)")
    for reason in RemovalReason.allCases {
        let count = filterResult.removed.filter { $0.reason == reason }.count
        print("removed[\(reasonLabel(reason))] \(count)")
    }
    print("removedTotalCount \(filterResult.removed.count)")
}

private func runKilllist(_ args: [String]) {
    guard let filterResult = resolveAndFilter(args) else {
        printUsage()
        exit(64)
    }

    for removedPerson in filterResult.removed {
        // A name or a partially masked identifier may appear here (killlist is an on-screen
        // review tool, not journal-safe output -- see main.swift's doc note at the bottom),
        // but never a full one: IdentifierMasking.mask is the same rule GraphJSON's name
        // disambiguator now shares.
        let label = removedPerson.person.name ?? IdentifierMasking.mask(removedPerson.person.id)
        let facts = removedPerson.facts
        print(
            "\(reasonLabel(removedPerson.reason)) \(label) "
                + "messageCount=\(facts.oneToOneMessageCount) "
                + "fromMeCount=\(facts.fromMeCount) "
                + "activeDays=\(facts.distinctActiveDays) "
                // Without this, a person kept alive only by group activity (a lurker in a
                // live group later removed for some other reason) would print as
                // messageCount=0 activeDays=0 and look completely inert on screen.
                + "groupMemberships=\(facts.groupMemberships)"
        )
    }
}

private func edgeReasonLabel(_ reason: EdgeReason) -> String {
    switch reason {
    case .oneToOneThread: return "oneToOneThread"
    case .groupMembership: return "groupMembership"
    case .userGroupMembership: return "userGroupMembership"
    }
}

private func median(_ values: [Int]) -> Double {
    let sorted = values.sorted()
    let mid = sorted.count / 2
    if sorted.count % 2 == 0 {
        return Double(sorted[mid - 1] + sorted[mid]) / 2.0
    }
    return Double(sorted[mid])
}

private func runGraph(_ args: [String]) {
    guard let (extract, filterResult) = resolveExtractAndFilter(args) else {
        printUsage()
        exit(64)
    }
    let graph = GraphBuilder.build(extract: extract, keptPeople: filterResult.kept)

    let userNodes = graph.nodes.filter { $0.kind == .user }.count
    let personNodes = graph.nodes.filter { $0.kind == .person }.count
    let liveGroupNodes = graph.nodes.filter { $0.kind == .group && $0.isLive }.count
    let deadGroupNodes = graph.nodes.filter { $0.kind == .group && !$0.isLive }.count

    print("userNodes \(userNodes)")
    print("personNodes \(personNodes)")
    print("liveGroupNodes \(liveGroupNodes)")
    print("deadGroupNodes \(deadGroupNodes)")

    for reason in EdgeReason.allCases {
        let count = graph.edges.filter { $0.reason == reason }.count
        print("edges[\(edgeReasonLabel(reason))] \(count)")
    }

    let totalEdges = graph.edges.count
    let edgesExcludingUser = graph.edges.filter { !$0.involvesUser }.count
    print("totalEdges \(totalEdges)")
    print("edgesExcludingUser \(edgesExcludingUser)")

    let degrees = graph.nodes.filter { $0.kind == .person || $0.kind == .group }.map(\.degree)
    print("personGroupDegreeMin \(degrees.min().map(String.init) ?? "none")")
    print("personGroupDegreeMedian \(degrees.isEmpty ? "none" : String(format: "%.1f", median(degrees)))")
    print("personGroupDegreeMax \(degrees.max().map(String.init) ?? "none")")

    // Renamed from the old "edgesPerNode": same computation as before (all non-user edges,
    // including userGroupMembership's absence but NOT oneToOneThread/groupMembership alone --
    // this is just edgesExcludingUser over the same denominator), clearer about what it is now
    // that a second, differently-defined density figure exists below. Guarded: an empty or
    // fully-filtered database has personNodes + liveGroupNodes == 0, and Double(0)/Double(0)
    // is NaN, which %.2f would print literally as "nan".
    let denominator = personNodes + liveGroupNodes
    let nonUserEdgesPerNode = denominator > 0 ? Double(edgesExcludingUser) / Double(denominator) : 0.0
    print(String(format: "nonUserEdgesPerNode %.2f", nonUserEdgesPerNode))

    // The plan's actual calibration figure (1.19, against a 1.04 reference): oneToOneThread
    // plus groupMembership edges only, over the same denominator. Not the same number as
    // nonUserEdgesPerNode above (journal iteration 4: the old line quietly compared apples to
    // oranges against the plan's own target).
    let edgesPerNodePlanComparable = DensityMetric.planComparable(graph: graph)
    print(String(format: "edgesPerNodePlanComparable %.2f", edgesPerNodePlanComparable))
}

/// Not journal-safe, like `killlist` (see main.swift's doc note at the bottom): prints real
/// contact and group display names as JSON, for an external HTML viewer built in parallel
/// against the schema this produces.
///
/// With `--timings`, also prints each pipeline stage's wall-clock cost to stderr (numbers
/// only, journal-safe): chat.db extraction, Contacts extraction, identity resolution, person
/// filtering, graph build, acquaintance derivation, JSON encode, and the end-to-end total.
/// Acquaintance derivation normally runs INSIDE GraphJSON.encode (its only caller with a
/// reason to see the number); under `--timings` it additionally runs here, standalone, so its
/// own cost is reported apart from encode's -- one redundant pass, paid only in diagnostic
/// mode, rather than changing GraphJSON's public signature (App and SkyExportBuilder also
/// call it).
private func runJSON(_ args: [String]) {
    guard let parsed = parseArgs(args), let chatDBPath = parsed.chatDBPath else {
        printUsage()
        exit(64)
    }
    let timingsEnabled = parsed.timings
    let clock = ContinuousClock()
    let overallStart = clock.now

    let extract = timed("chatDBExtract", enabled: timingsEnabled) { loadChatExtract(chatDBPath) }
    let contacts = timed("contactsExtract", enabled: timingsEnabled) { loadContacts(parsed.contactsDBPaths) }
    let identity = timed("identityResolution", enabled: timingsEnabled) {
        IdentityResolution.resolve(handles: extract.handles, contacts: contacts)
    }
    let filterResult = timed("personFilter", enabled: timingsEnabled) {
        PersonFilter.apply(extract: extract, people: identity.people)
    }
    let built = timed("graphBuild", enabled: timingsEnabled) {
        GraphBuilder.buildDetailed(extract: extract, keptPeople: filterResult.kept)
    }
    // Merged into the exported nodes only, right before encode -- never into built.graph
    // itself, so nothing above this line (GraphBuilder, keptPeople) or below it that reads
    // built.graph directly (the acquaintance timing probe just under this) ever sees a
    // contact-only node (PLAN.md 2026-08-03; see ContactOnlyPeople.derive's own doc comment).
    let contactOnlyNodes = timed("contactOnlyPeople", enabled: timingsEnabled) {
        ContactOnlyPeople.asGraphNodes(
            ContactOnlyPeople.derive(
                contacts: contacts,
                matchedIdentifiers: ContactOnlyPeople.messageHandleIdentifiers(extract)
            ).people
        )
    }

    // Same overrides file `guess` writes to and the app reads/writes: a name guessed by
    // either one shows up (tilde-prefixed, per NodeLabel) in every later `json` export,
    // never just in the app's own in-memory session. The same load also supplies the
    // "everyone here knows each other" markers, so a chat marked in the app shows up
    // confirmed in this export too.
    let overridesStore = OverridesStore(fileURL: OverridesStore.defaultFileURL())
    let overrides = (try? overridesStore.load()) ?? Overrides()

    if timingsEnabled {
        let translatedRosterKeys = AcquaintanceRosterKey.resolve(
            stored: overrides.fullyAcquaintedRosterKeys,
            people: filterResult.kept
        )
        _ = timed("acquaintanceDerivation", enabled: true) {
            AcquaintanceDerivation.derive(
                groupChatActivity: built.groupChatActivity,
                fullyAcquaintedRosterKeys: translatedRosterKeys
            )
        }
    }

    let exportGraph = Graph(nodes: built.graph.nodes + contactOnlyNodes, edges: built.graph.edges)
    let encoded: Data? = timed("jsonEncode", enabled: timingsEnabled) {
        try? GraphJSON.encode(
            graph: exportGraph,
            groupChatActivity: built.groupChatActivity,
            fullyAcquaintedRosterKeys: overrides.fullyAcquaintedRosterKeys,
            people: filterResult.kept,
            guesses: overrides.nameGuesses
        )
    }
    guard let data = encoded else {
        fail("error: cannot encode graph")
    }

    if timingsEnabled {
        let totalElapsed = clock.now - overallStart
        let totalMs = Double(totalElapsed.components.seconds) * 1000.0 + Double(totalElapsed.components.attoseconds) * 1e-15
        FileHandle.standardError.write(Data("timing total \(String(format: "%.1f", totalMs))ms\n".utf8))
    }

    FileHandle.standardOutput.write(data)
}

private func tierLabel(_ tier: AcquaintanceTier) -> String {
    switch tier {
    case .confirmed: return "confirmed"
    case .strong: return "strong"
    case .likely: return "likely"
    }
}

/// Aggregate counts only, like `stats`/`people`/`filter`/`graph`: pairs per tier, the total,
/// and how many chats are currently marked "everyone here knows each other" -- never a name or
/// an identifier (constraint 7).
private func runAcquaintances(_ args: [String]) {
    guard let (extract, filterResult) = resolveExtractAndFilter(args) else {
        printUsage()
        exit(64)
    }
    let built = GraphBuilder.buildDetailed(extract: extract, keptPeople: filterResult.kept)

    let overridesStore = OverridesStore(fileURL: OverridesStore.defaultFileURL())
    let fullyAcquaintedRosterKeys = (try? overridesStore.load())?.fullyAcquaintedRosterKeys ?? []
    // Translated ONCE against the CURRENT people list: a stored key may still be built from a
    // member's now-stale Person.id (see AcquaintanceRosterKey.resolve), so exact equality
    // against the raw stored set would silently drop a real marking after a resync.
    let translatedRosterKeys = AcquaintanceRosterKey.resolve(stored: fullyAcquaintedRosterKeys, people: filterResult.kept)

    let acquaintances = AcquaintanceDerivation.derive(
        groupChatActivity: built.groupChatActivity,
        fullyAcquaintedRosterKeys: translatedRosterKeys
    )
    let markedChatCount = built.groupChatActivity.filter {
        translatedRosterKeys.contains(AcquaintanceRosterKey.canonicalize($0.roster))
    }.count

    // Declaration order (confirmed, strong, likely) matches the tier hierarchy, strongest
    // evidence first, not alphabetical.
    for tier in AcquaintanceTier.allCases {
        let count = acquaintances.filter { $0.tier == tier }.count
        print("acquaintances[\(tierLabel(tier))] \(count)")
    }
    print("acquaintancesTotal \(acquaintances.count)")
    print("markedChatCount \(markedChatCount)")
}

/// Accumulates guesses and persists them through the same OverridesStore the app writes to,
/// after every single guess (not just at the end): a several-hundred-candidate run against a
/// local model can take many minutes, and a crash or Ctrl-C partway through should not lose
/// everything already guessed. @unchecked Sendable: guarded entirely by `lock`, the same
/// pattern GuessEngineTests' own ScriptedProvider uses -- GuessEngine calls onGuess serially
/// (one candidate awaited at a time), so the lock is defense in depth, not a real race.
private final class GuessProgressSink: @unchecked Sendable {
    private let lock = NSLock()
    private var overrides: Overrides
    private let store: OverridesStore
    private(set) var guessedCount = 0
    private(set) var outcome: GuessEngineOutcome = .completed
    // Per-candidate telemetry (GuessOutcome), counts only -- never a name or any snippet text
    // (constraint 7). `.accepted` is not tracked separately here: it is exactly `guessedCount`.
    private(set) var declinedCount = 0
    private(set) var rejectedUngroundedCount = 0
    private(set) var rejectedScopedCount = 0
    private(set) var noEvidenceCount = 0
    private(set) var providerErrorCount = 0
    let pendingCount: Int

    init(overrides: Overrides, store: OverridesStore, pendingCount: Int) {
        self.overrides = overrides
        self.store = store
        self.pendingCount = pendingCount
    }

    /// The current overrides value, including every guess recorded so far -- used once the run
    /// finishes to compute the "after" naming-coverage counts without re-reading from disk.
    var snapshotOverrides: Overrides {
        lock.lock(); defer { lock.unlock() }
        return overrides
    }

    func recordGuess(key: String, guess: NameGuess) {
        lock.lock()
        defer { lock.unlock() }
        overrides.nameGuesses[key] = guess
        guessedCount += 1
        // A save failure here (disk full, permissions) costs this run its durability
        // guarantee but not its progress: the guess is still in memory and future guesses
        // keep going, mirroring AppModel.saveOverrides' own "log and continue" posture.
        do {
            try store.save(overrides)
        } catch {
            FileHandle.standardError.write(Data("warning: could not save overrides\n".utf8))
        }
        // Progress only, never the guessed name or any snippet text: journal-safe (constraint 7).
        FileHandle.standardError.write(Data("guessed \(guessedCount)/\(pendingCount)\n".utf8))
    }

    func recordOutcome(_ outcome: GuessEngineOutcome) {
        lock.lock()
        defer { lock.unlock() }
        self.outcome = outcome
    }

    func recordCandidateOutcome(_ outcome: GuessOutcome) {
        lock.lock()
        defer { lock.unlock() }
        switch outcome {
        case .accepted:
            break // already counted via recordGuess
        case .declinedByModel:
            declinedCount += 1
        case .rejectedUngrounded:
            rejectedUngroundedCount += 1
        case .rejectedScoped:
            rejectedScopedCount += 1
        case .noEvidence:
            noEvidenceCount += 1
        case .providerError:
            providerErrorCount += 1
        }
    }
}

/// How many distinct names a guess cache collapses to, and the size of its largest group --
/// the exact shape of the original hallucination bug (240 guesses, 96 distinct names, one name
/// repeated 39 times). Counts only: never prints a name itself.
private func collisionStats(_ nameGuesses: [String: NameGuess]) -> (distinctNames: Int, largestGroup: Int) {
    guard !nameGuesses.isEmpty else { return (0, 0) }
    let countByName = Dictionary(grouping: nameGuesses.values, by: \.name).mapValues(\.count)
    return (countByName.count, countByName.values.max() ?? 0)
}

/// Same as collisionStats, but over PERSON guesses only ("group:"-prefixed keys excluded).
/// The "two distinct handles must not share a name" guarantee (GuessAttribution) is about
/// people/phone numbers specifically -- a report that mixes in group-name collisions (two
/// different unnamed group chats both guessed as, say, "Family") would make an unrelated,
/// out-of-scope coincidence look like this rule failed.
private func personCollisionStats(_ nameGuesses: [String: NameGuess]) -> (distinctNames: Int, largestGroup: Int) {
    collisionStats(nameGuesses.filter { !$0.key.hasPrefix("group:") })
}

/// Counts only (constraint 7): how the current person/group population splits between a
/// card-derived name (from Contacts), a model-derived name (a cached guess), and no name at
/// all. This is what a future "N people need names" UI affordance would read, so it stays
/// cheap (one pass over already-loaded data) and honest (recomputed fresh every run, never
/// cached itself).
private func printNamingCoverage(keptPeople: [Person], graph: Graph, nameGuesses: [String: NameGuess]) {
    var personNamedFromContacts = 0
    var personNamedFromModel = 0
    var personUnnamed = 0
    for person in keptPeople {
        if person.name != nil {
            personNamedFromContacts += 1
        } else if nameGuesses[person.id] != nil {
            personNamedFromModel += 1
        } else {
            personUnnamed += 1
        }
    }
    print("personCandidatesTotal \(keptPeople.count)")
    print("personNamedFromContacts \(personNamedFromContacts)")
    print("personNamedFromModel \(personNamedFromModel)")
    print("personUnnamed \(personUnnamed)")

    // Only live groups are ever candidates (GuessCandidateSelection); a dead group chat was
    // never eligible for naming in the first place.
    let liveGroups = graph.nodes.filter { $0.kind == .group && $0.isLive }
    var groupNamedNatively = 0
    var groupNamedFromModel = 0
    var groupUnnamed = 0
    for node in liveGroups {
        if node.name != nil {
            groupNamedNatively += 1
        } else if nameGuesses[NodeLabel.groupGuessKey(forNodeID: node.id)] != nil {
            groupNamedFromModel += 1
        } else {
            groupUnnamed += 1
        }
    }
    print("groupCandidatesTotal \(liveGroups.count)")
    print("groupNamedNatively \(groupNamedNatively)")
    print("groupNamedFromModel \(groupNamedFromModel)")
    print("groupUnnamed \(groupUnnamed)")
}

private func outcomeLabel(_ outcome: GuessEngineOutcome) -> String {
    switch outcome {
    case .completed: return "completed"
    case .stoppedProviderUnreachable: return "providerUnreachable"
    case .cancelled: return "cancelled"
    }
}

/// Headless model pass: load the graph exactly like `json` does, find every unnamed
/// person/live-group candidate (GuessCandidateSelection, shared with the app), skip anything
/// already in the overrides cache (the incremental, resync-cheap contract GuessEngine itself
/// enforces), guess the rest with a local Ollama model, and persist through the SAME
/// OverridesStore file the app reads and writes -- so a headless run and an app session never
/// fight over or duplicate work.
private func runGuess(_ args: [String]) async {
    guard let parsed = parseArgs(args), let chatDBPath = parsed.chatDBPath else {
        printUsage()
        exit(64)
    }
    guard let (extract, filterResult) = resolveExtractAndFilter(args) else {
        printUsage()
        exit(64)
    }
    let graph = GraphBuilder.build(extract: extract, keptPeople: filterResult.kept)

    let overridesStore = OverridesStore(fileURL: OverridesStore.defaultFileURL())
    var overrides: Overrides
    do {
        overrides = try overridesStore.load()
    } catch {
        fail("error: cannot read overrides store")
    }

    // The cache as it stood before any repair or new guessing this run -- the baseline the
    // owner needs to see whether a fix (or --reguess) actually helped. Counts only.
    let before = collisionStats(overrides.nameGuesses)
    let personBefore = personCollisionStats(overrides.nameGuesses)
    print("guessesBefore \(overrides.nameGuesses.count)")
    print("distinctNamesBefore \(before.distinctNames)")
    print("largestCollisionGroupBefore \(before.largestGroup)")
    print("personLargestCollisionGroupBefore \(personBefore.largestGroup)")

    if parsed.reguess {
        let (purged, droppedCount) = GuessCacheRepair.purgingNameGuesses(from: overrides)
        do {
            try overridesStore.save(purged)
        } catch {
            fail("error: cannot write overrides store")
        }
        overrides = purged
        print("purgedGuesses \(droppedCount)")
    }

    let sources = GuessCandidateSelection.buildSources(graph: graph, keptPeople: filterResult.kept, extract: extract)
    let cache = overrides.nameGuesses
    let pendingSources = sources.filter { cache[$0.candidate.key] == nil }
    print("pending \(pendingSources.count)")

    let sink = GuessProgressSink(overrides: overrides, store: overridesStore, pendingCount: pendingSources.count)

    if !pendingSources.isEmpty {
        let candidates = pendingSources.map(\.candidate)
        let chatRowIDsByKey = Dictionary(uniqueKeysWithValues: pendingSources.map { ($0.candidate.key, $0.chatRowIDs) })
        let dbPath = chatDBPath
        let provider = OllamaProvider()

        let snippetSource: @Sendable (String) -> [Snippet] = { key in
            guard let rowIDs = chatRowIDsByKey[key] else { return [] }
            return (try? SnippetReader.read(dbPath: dbPath, chatRowIDs: rowIDs)) ?? []
        }

        await GuessEngine.run(
            candidates: candidates,
            cache: cache,
            snippetSource: snippetSource,
            provider: provider,
            onGuess: { key, guess in
                sink.recordGuess(key: key, guess: guess)
            },
            completion: { outcome in
                sink.recordOutcome(outcome)
            },
            onOutcome: { outcome in
                sink.recordCandidateOutcome(outcome)
            }
        )
    }

    print("guessed \(sink.guessedCount)")
    // NOT a failure count: this is everything that did not end up with a name -- correctly
    // abstained, correctly rejected as ungrounded, or never asked at all for lack of evidence.
    // The breakdown below names which of those it actually is; a bare "failed" label would
    // misread abstention and rejection (the intended, correct outcomes of this fix) as errors.
    print("notNamed \(pendingSources.count - sink.guessedCount)")
    print("outcome \(outcomeLabel(sink.outcome))")

    // Of everything actually sent to the model (excludes noEvidence, which never reached it,
    // and anything left untried after a providerUnreachable stop): how many came back grounded,
    // how many the model itself declined, how many it guessed but failed grounding outright, and
    // how many it guessed a name that WAS grounded but only in a message someone else sent
    // (rejectedScoped -- this run's own fix; see GuessAttribution/GuessEngine). Reported
    // separately from rejectedUngrounded and from duplicateNameKeysDropped below specifically so
    // the two fixes' effects (scoping vs. uniqueness) are never conflated into one number.
    let prompted = sink.guessedCount + sink.declinedCount + sink.rejectedUngroundedCount + sink.rejectedScopedCount + sink.providerErrorCount
    print("prompted \(prompted)")
    print("noEvidence \(sink.noEvidenceCount)")
    print("declined \(sink.declinedCount)")
    print("rejectedUngrounded \(sink.rejectedUngroundedCount)")
    print("rejectedScoped \(sink.rejectedScopedCount)")
    print("providerError \(sink.providerErrorCount)")

    // Attribution: grounding (per candidate) does not imply the name is actually about THAT
    // candidate rather than a third party mentioned in their conversation -- see GuessAttribution's
    // own doc comment for the measured mechanism. This is a full-cache correction, not scoped to
    // this run's new guesses: it also cleans up a collision that predates this rule entirely.
    let (attributed, duplicateKeys) = GuessAttribution.resolvingDuplicatePersonNames(in: sink.snapshotOverrides.nameGuesses)
    var finalOverrides = sink.snapshotOverrides
    finalOverrides.nameGuesses = attributed
    do {
        try overridesStore.save(finalOverrides)
    } catch {
        fail("error: cannot write overrides store")
    }
    print("duplicateNameKeysDropped \(duplicateKeys.count)")

    let after = collisionStats(finalOverrides.nameGuesses)
    let personAfter = personCollisionStats(finalOverrides.nameGuesses)
    print("guessesAfter \(finalOverrides.nameGuesses.count)")
    print("distinctNamesAfter \(after.distinctNames)")
    print("largestCollisionGroupAfter \(after.largestGroup)")
    // The DoD target ("largest collision group must reach 1") is about people/handles
    // specifically -- two different unnamed GROUP chats coincidentally guessed the same display
    // name is a real but unrelated coincidence, not the misattribution this fix targets, so it
    // is reported separately rather than conflated into the combined number above.
    print("personLargestCollisionGroupAfter \(personAfter.largestGroup)")

    printNamingCoverage(keptPeople: filterResult.kept, graph: graph, nameGuesses: finalOverrides.nameGuesses)
}

let arguments = Array(CommandLine.arguments.dropFirst())
// `killlist` and `json` are the two subcommands that are not journal-safe by design:
// `killlist` prints real names and partially-masked identifiers to stdout for the lead's
// on-screen review of real data, and `json` prints real contact and group display names as
// stdout JSON for an external HTML viewer (per this step's brief). `stats`, `people`,
// `filter`, `graph`, `acquaintances`, and `contacts` remain counts-only.
switch arguments.first {
case "stats":
    runStats(Array(arguments.dropFirst()))
case "people":
    runPeople(Array(arguments.dropFirst()))
case "filter":
    runFilter(Array(arguments.dropFirst()))
case "killlist":
    runKilllist(Array(arguments.dropFirst()))
case "graph":
    runGraph(Array(arguments.dropFirst()))
case "json":
    runJSON(Array(arguments.dropFirst()))
case "acquaintances":
    runAcquaintances(Array(arguments.dropFirst()))
case "contacts":
    runContacts(Array(arguments.dropFirst()))
case "guess":
    await runGuess(Array(arguments.dropFirst()))
default:
    printUsage()
    exit(64)
}
