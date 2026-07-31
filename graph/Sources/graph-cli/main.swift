import Foundation
import GraphCore

private func printUsage() {
    FileHandle.standardError.write(
        Data("usage: graph-cli stats --chat-db PATH [--contacts-db PATH ...]\n".utf8)
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

let arguments = Array(CommandLine.arguments.dropFirst())
guard let subcommand = arguments.first, subcommand == "stats" else {
    printUsage()
    exit(64)
}
runStats(Array(arguments.dropFirst()))
