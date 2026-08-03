import XCTest
@testable import GraphCore

/// The step-8 acceptance test (PLAN.md, verbatim): "User curation survives resync. Hidden
/// nodes stay hidden, removed nodes stay removed, answered merge questions are never
/// re-asked." Runs the FULL pipeline twice against two independently-built chat.db fixtures
/// -- the second with every ROWID shifted +100, simulating the real renumbering that makes
/// row-id keying wrong -- with an OverridesStore round-tripped through disk in between.
final class EndToEndResyncSurvivalTests: XCTestCase {

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func appleEpochNanoseconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSinceReferenceDate * 1_000_000_000)
    }

    // Fixture people, by local (un-offset) handle number:
    // 1 = P1 (hidden), 2 = P2 (removed), 3 = P3 (merges with P6), 4 = P4 (candidate, answered
    // separate), 5 = P5 (candidate, answered separate), 6 = P6 (merges with P3).
    private let phoneNumbers: [Int64: String] = [
        1: "+14155550101",
        2: "+14155550102",
        3: "+14155550103",
        4: "+14155550104",
        5: "+14155550105",
        6: "+14155550106",
    ]

    /// Builds one chat.db-shaped fixture. `rowIDOffset` simulates a resync's renumbering (0
    /// for the "before" database, 100 for "after"); guids and phone numbers -- the things
    /// that are actually stable across a real resync -- are identical either way.
    /// `addExtraMessages`, used only for the "after" database, adds one more message per
    /// chat on a THIRD day: every chat here already meets the 2-distinct-day live threshold
    /// from its first two messages, so this proves the pipeline copes with more real history
    /// without silently flipping any liveness verdict, rather than accidentally testing that.
    private func buildChatFixture(rowIDOffset: Int64, addExtraMessages: Bool) throws -> ChatDBFixture {
        let fixture = try ChatDBFixture()
        let day1 = utcDate(2024, 6, 1)
        let day2 = utcDate(2024, 6, 2)
        let day3 = utcDate(2024, 6, 3)

        for localHandleID in phoneNumbers.keys.sorted() {
            try fixture.insertHandle(
                rowID: localHandleID + rowIDOffset,
                id: phoneNumbers[localHandleID]!,
                service: "iMessage"
            )
        }

        // One one-to-one thread per person: two messages on two distinct days, one of them
        // outbound, so nobody trips neverReplied or notLive.
        for localHandleID in phoneNumbers.keys.sorted() {
            let handleRowID = localHandleID + rowIDOffset
            let chatRowID = (10 + localHandleID) + rowIDOffset
            try fixture.insertChat(
                rowID: chatRowID,
                guid: "one-to-one-\(localHandleID)",
                style: 45,
                chatIdentifier: phoneNumbers[localHandleID]
            )
            try fixture.insertChatHandleJoin(chatID: chatRowID, handleID: handleRowID)

            let inboundMessageID = (100 + localHandleID * 10 + 1) + rowIDOffset
            let outboundMessageID = (100 + localHandleID * 10 + 2) + rowIDOffset
            try fixture.insertMessage(
                rowID: inboundMessageID, handleID: handleRowID, service: "iMessage",
                dateNanoseconds: appleEpochNanoseconds(day1), isFromMe: false
            )
            try fixture.insertChatMessageJoin(chatID: chatRowID, messageID: inboundMessageID)
            try fixture.insertMessage(
                rowID: outboundMessageID, handleID: nil, service: "iMessage",
                dateNanoseconds: appleEpochNanoseconds(day2), isFromMe: true
            )
            try fixture.insertChatMessageJoin(chatID: chatRowID, messageID: outboundMessageID)

            if addExtraMessages {
                let extraMessageID = (100 + localHandleID * 10 + 3) + rowIDOffset
                try fixture.insertMessage(
                    rowID: extraMessageID, handleID: handleRowID, service: "iMessage",
                    dateNanoseconds: appleEpochNanoseconds(day3), isFromMe: false
                )
                try fixture.insertChatMessageJoin(chatID: chatRowID, messageID: extraMessageID)
            }
        }

        // A live 3-member group: P3, P4, P5.
        let groupChatRowID: Int64 = 20 + rowIDOffset
        try fixture.insertChat(rowID: groupChatRowID, guid: "group-guid-1", style: 43, displayName: "Trio")
        for localHandleID: Int64 in [3, 4, 5] {
            try fixture.insertChatHandleJoin(chatID: groupChatRowID, handleID: localHandleID + rowIDOffset)
        }
        let groupMessage1: Int64 = 201 + rowIDOffset
        let groupMessage2: Int64 = 202 + rowIDOffset
        try fixture.insertMessage(
            rowID: groupMessage1, handleID: 3 + rowIDOffset, service: "iMessage",
            dateNanoseconds: appleEpochNanoseconds(day1), isFromMe: false
        )
        try fixture.insertChatMessageJoin(chatID: groupChatRowID, messageID: groupMessage1)
        try fixture.insertMessage(
            rowID: groupMessage2, handleID: 4 + rowIDOffset, service: "iMessage",
            dateNanoseconds: appleEpochNanoseconds(day2), isFromMe: false
        )
        try fixture.insertChatMessageJoin(chatID: groupChatRowID, messageID: groupMessage2)

        if addExtraMessages {
            let groupMessage3: Int64 = 203 + rowIDOffset
            try fixture.insertMessage(
                rowID: groupMessage3, handleID: 5 + rowIDOffset, service: "iMessage",
                dateNanoseconds: appleEpochNanoseconds(day3), isFromMe: false
            )
            try fixture.insertChatMessageJoin(chatID: groupChatRowID, messageID: groupMessage3)
        }

        return fixture
    }

    /// P3 and P6 share a card-derived name ("Jordan Rivera") on two disjoint cards, forming
    /// the merge candidate the user will answer .merged. P4 and P5 do the same with "Taylor
    /// Kim", forming the candidate the user will answer .separate. Contacts is a different
    /// database from chat.db and does not renumber the same way a resync's chat.db does, so
    /// this fixture (and its extracted [ContactRecord]) is built once and reused for both
    /// pipeline runs.
    private func buildContactsFixture() throws -> ContactsDBFixture {
        let fixture = try ContactsDBFixture()
        let contactEntityID: Int64 = 1
        try fixture.insertEntity(entityID: contactEntityID, name: "ABCDContact")

        try fixture.insertRecord(recordID: 1, entityID: contactEntityID, uniqueID: "card-p3", firstName: "Jordan", lastName: "Rivera")
        try fixture.insertPhoneNumber(recordID: 10, ownerID: 1, fullNumber: phoneNumbers[3]!)

        try fixture.insertRecord(recordID: 2, entityID: contactEntityID, uniqueID: "card-p6", firstName: "Jordan", lastName: "Rivera")
        try fixture.insertPhoneNumber(recordID: 20, ownerID: 2, fullNumber: phoneNumbers[6]!)

        try fixture.insertRecord(recordID: 3, entityID: contactEntityID, uniqueID: "card-p4", firstName: "Taylor", lastName: "Kim")
        try fixture.insertPhoneNumber(recordID: 30, ownerID: 3, fullNumber: phoneNumbers[4]!)

        try fixture.insertRecord(recordID: 4, entityID: contactEntityID, uniqueID: "card-p5", firstName: "Taylor", lastName: "Kim")
        try fixture.insertPhoneNumber(recordID: 40, ownerID: 4, fullNumber: phoneNumbers[5]!)

        return fixture
    }

    func testHiddenRemovedAndMergedCurationSurvivesAFullResync() throws {
        // ---- "Before": first ever load, no overrides saved yet. ----
        let chatFixtureA = try buildChatFixture(rowIDOffset: 0, addExtraMessages: false)
        defer { chatFixtureA.close() }
        let contactsFixture = try buildContactsFixture()
        defer { contactsFixture.close() }

        let extractA = try ChatDatabase.extract(path: chatFixtureA.url.path)
        let contacts = try ContactsDatabase.extract(path: contactsFixture.url.path)

        let identityA = IdentityResolution.resolve(handles: extractA.handles, contacts: contacts)
        let filterResultA = PersonFilter.apply(extract: extractA, people: identityA.people, calendar: utc)
        let graphA = GraphBuilder.build(extract: extractA, keptPeople: filterResultA.kept, calendar: utc)

        // Sanity on the fixture itself, before any curation is layered on: all 6 people
        // survive PersonFilter's own rules (every thread is live and replied-to), and both
        // same-name pairs show up as merge candidates -- otherwise the rest of this test
        // would be proving something about the overrides machinery using a fixture that was
        // never exercising it in the first place.
        XCTAssertEqual(Set(filterResultA.kept.map(\.id)), Set(phoneNumbers.values))
        XCTAssertEqual(graphA.nodes.filter { $0.kind == .person }.count, 6)
        XCTAssertEqual(identityA.mergeCandidates.count, 2)

        guard let jordanCandidate = identityA.mergeCandidates.first(where: { $0.sharedName == "Jordan Rivera" }),
              let taylorCandidate = identityA.mergeCandidates.first(where: { $0.sharedName == "Taylor Kim" }) else {
            return XCTFail("expected both same-name merge candidates from the fixture")
        }

        // ---- Simulate curation: hide P1 and the Trio group, remove P2, merge Jordan's pair, keep Taylor's pair separate. ----
        let overrides = Overrides(
            hiddenPersonIdentifiers: [phoneNumbers[1]!],
            hiddenGroupGUIDs: ["group-guid-1"],
            removedPersonIdentifiers: [phoneNumbers[2]!],
            mergeAnswers: [
                MergeAnswer(identifierA: taylorCandidate.personID1, identifierB: taylorCandidate.personID2, decision: .separate),
                MergeAnswer(identifierA: jordanCandidate.personID1, identifierB: jordanCandidate.personID2, decision: .merged),
            ]
        )

        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EndToEndResyncSurvivalTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let storeFileURL = storeDirectory.appendingPathComponent("overrides.json")

        try OverridesStore(fileURL: storeFileURL).save(overrides)

        // ---- "After": a resync, from a completely different chat.db with every ROWID shifted +100. ----
        let chatFixtureB = try buildChatFixture(rowIDOffset: 100, addExtraMessages: true)
        defer { chatFixtureB.close() }
        let extractB = try ChatDatabase.extract(path: chatFixtureB.url.path)

        // A fresh store instance pointed at the same file: nothing here is held over in
        // memory from the "before" half of this test, exactly as a real relaunch would see it.
        let reloadedOverrides = try OverridesStore(fileURL: storeFileURL).load()
        XCTAssertEqual(reloadedOverrides, overrides, "the store must round-trip exactly what was saved")

        let assertedMerges = reloadedOverrides.mergeAnswers
            .filter { $0.decision == .merged }
            .map { ($0.identifierA, $0.identifierB) }

        let identityB = IdentityResolution.resolve(handles: extractB.handles, contacts: contacts, assertedMerges: assertedMerges)
        let filterResultB = PersonFilter.apply(extract: extractB, people: identityB.people, calendar: utc)
        let keptAfterRemovalB = RemovedPeopleOverride.apply(
            filterResultB.kept,
            removedPersonIdentifiers: reloadedOverrides.removedPersonIdentifiers
        )
        let graphB = GraphBuilder.build(extract: extractB, keptPeople: keptAfterRemovalB, calendar: utc)
        let hiddenIDsB = HiddenNodeOverride.nodeIDs(
            people: keptAfterRemovalB,
            graph: graphB,
            hiddenPersonIdentifiers: reloadedOverrides.hiddenPersonIdentifiers,
            hiddenGroupGUIDs: reloadedOverrides.hiddenGroupGUIDs
        )

        // Hidden nodes stay hidden -- both a person (keyed by identifier) and a group
        // (keyed by guid, the stable-across-resync key PLAN.md calls out by name).
        XCTAssertTrue(hiddenIDsB.contains(phoneNumbers[1]!), "P1 must still be in the hidden mapping after resync")
        XCTAssertTrue(hiddenIDsB.contains("chat:group-guid-1"), "the Trio group must still be in the hidden mapping after resync")

        // Removed nodes stay removed: gone from the kept list AND from the rebuilt graph's
        // own nodes, not merely absent from some intermediate step.
        XCTAssertFalse(keptAfterRemovalB.contains { $0.id == phoneNumbers[2]! }, "P2 must not be kept after resync")
        XCTAssertFalse(graphB.nodes.contains { $0.id == phoneNumbers[2]! }, "P2 must not appear as a node after resync")

        // The user-asserted merge collapsed P3 and P6 into one person, and it stayed collapsed.
        let mergedPerson = identityB.people.first {
            $0.identifiers.contains(phoneNumbers[3]!) || $0.identifiers.contains(phoneNumbers[6]!)
        }
        XCTAssertEqual(
            identityB.people.filter { $0.identifiers.contains(phoneNumbers[3]!) || $0.identifiers.contains(phoneNumbers[6]!) }.count,
            1,
            "P3 and P6 must resolve to exactly one Person after resync"
        )
        XCTAssertEqual(mergedPerson?.identifiers, [phoneNumbers[3]!, phoneNumbers[6]!])

        // P4 and P5 are still two separate people.
        XCTAssertTrue(identityB.people.contains { $0.id == phoneNumbers[4]! })
        XCTAssertTrue(identityB.people.contains { $0.id == phoneNumbers[5]! })

        // Answered merge questions are never re-asked: the Taylor/Taylor candidate must have
        // been regenerated (proving suppression is actually removing something, not just
        // finding nothing to remove), and then suppressed.
        XCTAssertTrue(
            identityB.mergeCandidates.contains { $0.personID1 == phoneNumbers[4]! && $0.personID2 == phoneNumbers[5]! },
            "the fixture must still generate the Taylor/Taylor candidate before suppression, or suppression is not being tested"
        )
        let suppressedCandidatesB = MergeCandidateSuppression.apply(
            candidates: identityB.mergeCandidates,
            people: identityB.people,
            answers: reloadedOverrides.mergeAnswers
        )
        XCTAssertFalse(
            suppressedCandidatesB.contains { $0.personID1 == phoneNumbers[4]! && $0.personID2 == phoneNumbers[5]! },
            "the answered Taylor/Taylor candidate must never resurface"
        )
        // The Jordan/Jordan pair produces no candidate at all post-merge: there is only one
        // Person left to pair, not a stale entry suppression happens to catch.
        XCTAssertFalse(identityB.mergeCandidates.contains { $0.personID1 == phoneNumbers[3]! || $0.personID2 == phoneNumbers[3]! })
    }
}
