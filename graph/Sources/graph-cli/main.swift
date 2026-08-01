import Foundation
import GraphCore

private func printUsage() {
    FileHandle.standardError.write(
        Data(
            "usage: graph-cli <stats|people|filter|killlist|graph|json|acquaintances|guess> --chat-db PATH [--contacts-db PATH ...]\n"
                .utf8
        )
    )
}

private func fail(_ message: String) -> Never {
    // No path or database content in this message: CLI output must stay journal-safe (constraint 7).
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

private struct ParsedArgs {
    var chatDBPath: String?
    var contactsDBPaths: [String] = []
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
        default:
            return nil
        }
    }
    return parsed
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

/// Masks all but the last 4 characters of an identifier with 'x'. Used only by `killlist`,
/// which is an on-screen review tool, not journal-safe output (see main.swift's doc note
/// at the bottom): a name or a partially masked identifier may appear, but never a full one.
private func maskIdentifier(_ identifier: String) -> String {
    let visibleSuffixLength = 4
    guard identifier.count > visibleSuffixLength else { return identifier }
    let maskedCount = identifier.count - visibleSuffixLength
    return String(repeating: "x", count: maskedCount) + identifier.suffix(visibleSuffixLength)
}

private func runKilllist(_ args: [String]) {
    guard let filterResult = resolveAndFilter(args) else {
        printUsage()
        exit(64)
    }

    for removedPerson in filterResult.removed {
        let label = removedPerson.person.name ?? maskIdentifier(removedPerson.person.id)
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
private func runJSON(_ args: [String]) {
    guard let (extract, filterResult) = resolveExtractAndFilter(args) else {
        printUsage()
        exit(64)
    }
    let built = GraphBuilder.buildDetailed(extract: extract, keptPeople: filterResult.kept)

    // Same overrides file `guess` writes to and the app reads/writes: a name guessed by
    // either one shows up (tilde-prefixed, per NodeLabel) in every later `json` export,
    // never just in the app's own in-memory session. The same load also supplies the
    // "everyone here knows each other" markers, so a chat marked in the app shows up
    // confirmed in this export too.
    let overridesStore = OverridesStore(fileURL: OverridesStore.defaultFileURL())
    let overrides = (try? overridesStore.load()) ?? Overrides()

    let data: Data
    do {
        data = try GraphJSON.encode(
            graph: built.graph,
            groupChatActivity: built.groupChatActivity,
            fullyAcquaintedRosterKeys: overrides.fullyAcquaintedRosterKeys,
            people: filterResult.kept,
            guesses: overrides.nameGuesses
        )
    } catch {
        fail("error: cannot encode graph")
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
    let pendingCount: Int

    init(overrides: Overrides, store: OverridesStore, pendingCount: Int) {
        self.overrides = overrides
        self.store = store
        self.pendingCount = pendingCount
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
    let overrides: Overrides
    do {
        overrides = try overridesStore.load()
    } catch {
        fail("error: cannot read overrides store")
    }

    let sources = GuessCandidateSelection.buildSources(graph: graph, keptPeople: filterResult.kept, extract: extract)
    let cache = overrides.nameGuesses
    let pendingSources = sources.filter { cache[$0.candidate.key] == nil }
    print("pending \(pendingSources.count)")

    guard !pendingSources.isEmpty else {
        print("guessed 0")
        print("failed 0")
        return
    }

    let candidates = pendingSources.map(\.candidate)
    let chatRowIDsByKey = Dictionary(uniqueKeysWithValues: pendingSources.map { ($0.candidate.key, $0.chatRowIDs) })
    let dbPath = chatDBPath
    let sink = GuessProgressSink(overrides: overrides, store: overridesStore, pendingCount: pendingSources.count)
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
        }
    )

    print("guessed \(sink.guessedCount)")
    print("failed \(pendingSources.count - sink.guessedCount)")
    print("outcome \(outcomeLabel(sink.outcome))")
}

let arguments = Array(CommandLine.arguments.dropFirst())
// `killlist` and `json` are the two subcommands that are not journal-safe by design:
// `killlist` prints real names and partially-masked identifiers to stdout for the lead's
// on-screen review of real data, and `json` prints real contact and group display names as
// stdout JSON for an external HTML viewer (per this step's brief). `stats`, `people`,
// `filter`, `graph`, and `acquaintances` remain counts-only.
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
case "guess":
    await runGuess(Array(arguments.dropFirst()))
default:
    printUsage()
    exit(64)
}
