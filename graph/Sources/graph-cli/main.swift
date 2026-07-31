import Foundation
import GraphCore

private func printUsage() {
    FileHandle.standardError.write(
        Data(
            "usage: graph-cli <stats|people|filter|killlist> --chat-db PATH [--contacts-db PATH ...]\n"
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

private func resolveAndFilter(_ args: [String]) -> FilterResult? {
    guard let parsed = parseArgs(args), let chatDBPath = parsed.chatDBPath else {
        return nil
    }
    let extract = loadChatExtract(chatDBPath)
    let contacts = loadContacts(parsed.contactsDBPaths)
    let identity = IdentityResolution.resolve(handles: extract.handles, contacts: contacts)
    return PersonFilter.apply(extract: extract, people: identity.people)
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

let arguments = Array(CommandLine.arguments.dropFirst())
// `killlist` is the one subcommand that is not journal-safe by design: it prints real
// names and partially-masked identifiers to stdout for the lead's on-screen review of real
// data (per this step's brief). `stats`, `people`, and `filter` remain counts-only.
switch arguments.first {
case "stats":
    runStats(Array(arguments.dropFirst()))
case "people":
    runPeople(Array(arguments.dropFirst()))
case "filter":
    runFilter(Array(arguments.dropFirst()))
case "killlist":
    runKilllist(Array(arguments.dropFirst()))
default:
    printUsage()
    exit(64)
}
