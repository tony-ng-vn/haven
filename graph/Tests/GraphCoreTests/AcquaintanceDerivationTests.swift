import XCTest
@testable import GraphCore

final class AcquaintanceDerivationTests: XCTestCase {

    // MARK: - Fixture helpers

    private func utcDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func days(_ dates: [(Int, Int, Int)]) -> Set<Date> {
        Set(dates.map { utcDate($0.0, $0.1, $0.2) })
    }

    private func chat(
        _ chatId: String,
        name: String? = nil,
        roster: Set<String>,
        activeDaysByPersonID: [String: Set<Date>] = [:]
    ) -> GroupChatActivity {
        GroupChatActivity(chatId: chatId, name: name, roster: roster, activeDaysByPersonID: activeDaysByPersonID)
    }

    private func acquaintance(_ result: [Acquaintance], _ a: String, _ b: String) -> Acquaintance? {
        let sortedPair = [a, b].sorted()
        return result.first { $0.a == sortedPair[0] && $0.b == sortedPair[1] }
    }

    // MARK: - Test 1: two people alone (with the user) in a trio chat score exactly 1.0, strong

    func testTrioChatPairScoresOneAndLandsStrong() throws {
        let trio = chat("chat:trio", roster: ["+15550001", "+15550002"])

        let result = AcquaintanceDerivation.derive(groupChatActivity: [trio], fullyAcquaintedRosterKeys: [])

        XCTAssertEqual(result.count, 1)
        let pair = try XCTUnwrap(acquaintance(result, "+15550001", "+15550002"))
        XCTAssertEqual(pair.score, 1.0, accuracy: 1e-9, "n=2 -> base weight 1/(2-1) = 1.0, no co-active bonus needed")
        XCTAssertEqual(pair.tier, .strong)
        XCTAssertEqual(pair.evidence.count, 1)
        XCTAssertEqual(pair.evidence[0].chatId, "chat:trio")
        XCTAssertEqual(pair.evidence[0].memberCount, 2)
        XCTAssertEqual(pair.evidence[0].coActiveDays, 0)
    }

    // MARK: - Test 2: a pair sharing only one 20-person chat lands below likely and is dropped,
    // proven against a fixture that ALSO contains a pair that must survive (so the assertion
    // cannot pass vacuously against a stub that always returns nothing).

    func testPairInOnlyATwentyPersonChatIsDroppedWhileAnUnrelatedPairStillScores() {
        let twentyRoster = Set((1...20).map { "+1600\(String(format: "%04d", $0))" })
        let bigChat = chat("chat:big20", roster: twentyRoster)
        let trio = chat("chat:trio2", roster: ["+15559001", "+15559002"])

        let result = AcquaintanceDerivation.derive(groupChatActivity: [bigChat, trio], fullyAcquaintedRosterKeys: [])

        XCTAssertEqual(result.count, 1, "every pair drawn from the 20-person chat scores 1/19 ~= 0.053, below the 0.2 likely floor")
        XCTAssertNotNil(acquaintance(result, "+15559001", "+15559002"))
        let twentyMembers = Array(twentyRoster).sorted()
        XCTAssertNil(acquaintance(result, twentyMembers[0], twentyMembers[1]), "base weight alone in a 20-person chat must not clear likely")
    }

    // MARK: - Test 3: two chats, neither alone reaching likely, cross into likely together

    func testMultiChatAccumulationCrossesIntoLikely() throws {
        // personX/personY share TWO 11-person chats (base 1/10 = 0.1 each); every other member
        // is distinct between the two chats, so no other pair accumulates across both.
        let fillersA = (1...9).map { "+1700000\($0)" }
        let fillersB = (1...9).map { "+1800000\($0)" }
        let chatA = chat("chat:a11", roster: Set(["+15551111", "+15552222"] + fillersA))
        let chatB = chat("chat:b11", roster: Set(["+15551111", "+15552222"] + fillersB))

        let result = AcquaintanceDerivation.derive(groupChatActivity: [chatA, chatB], fullyAcquaintedRosterKeys: [])

        let pair = try XCTUnwrap(acquaintance(result, "+15551111", "+15552222"))
        XCTAssertEqual(pair.score, 0.2, accuracy: 1e-9, "0.1 from chat:a11 + 0.1 from chat:b11")
        XCTAssertEqual(pair.tier, .likely)
        XCTAssertEqual(pair.evidence.count, 2, "both contributing chats must be listed as evidence")
    }

    // MARK: - Test 4: the co-active-day cap. 6 shared days contribute +0.5, not +0.6, but the
    // RAW day count (6) is still what evidence reports -- the cap is a scoring rule, not a fact.

    func testCoActiveDayCapAppliesToScoreButEvidenceReportsTheRawCount() throws {
        let sixDays = days([(2024, 1, 1), (2024, 1, 2), (2024, 1, 3), (2024, 1, 4), (2024, 1, 5), (2024, 1, 6)])
        let trio = chat(
            "chat:trio3",
            roster: ["+15550003", "+15550004"],
            activeDaysByPersonID: ["+15550003": sixDays, "+15550004": sixDays]
        )

        let result = AcquaintanceDerivation.derive(groupChatActivity: [trio], fullyAcquaintedRosterKeys: [])

        let pair = try XCTUnwrap(acquaintance(result, "+15550003", "+15550004"))
        XCTAssertEqual(pair.score, 1.5, accuracy: 1e-9, "1.0 base + capped bonus min(6,5)*0.1 = 0.5, not 6*0.1 = 0.6")
        XCTAssertEqual(pair.evidence[0].coActiveDays, 6, "evidence reports the true observed count, uncapped")
    }

    // MARK: - Test 5: a lurker pair gets base weight only, contrasted with an active pair
    // sharing the exact same chat so the comparison is meaningful, not just "score is nonzero".

    func testLurkerPairGetsBaseWeightOnlyWhileActivePairInSameChatScoresHigher() throws {
        let overlap = days([(2024, 2, 1), (2024, 2, 2)])
        let trioRoom = chat(
            "chat:trio-with-lurker",
            roster: ["A", "B", "C"],
            // A and B overlap on two days; C never posts at all (empty set, a pure lurker).
            activeDaysByPersonID: ["A": overlap, "B": overlap, "C": []]
        )

        let result = AcquaintanceDerivation.derive(groupChatActivity: [trioRoom], fullyAcquaintedRosterKeys: [])

        let ab = try XCTUnwrap(acquaintance(result, "A", "B"))
        let ac = try XCTUnwrap(acquaintance(result, "A", "C"))
        let bc = try XCTUnwrap(acquaintance(result, "B", "C"))

        XCTAssertEqual(ab.score, 0.7, accuracy: 1e-9, "base 0.5 (n=3) + 2 co-active days * 0.1")
        XCTAssertEqual(ac.score, 0.5, accuracy: 1e-9, "lurker C: base weight only, zero co-active days")
        XCTAssertEqual(bc.score, 0.5, accuracy: 1e-9, "lurker C: base weight only, zero co-active days")
        XCTAssertEqual(ac.evidence[0].coActiveDays, 0)
    }

    // MARK: - Test 6: dead groups still contribute (liveness is not this function's concern --
    // GroupChatActivity carries no isLive flag at all, so this pins that the derivation never
    // filters on it; the actual "a dead group is still present in GroupChatActivity" wiring is
    // proven at the GraphBuilder level in GroupChatActivityTests).

    func testDeadGroupActivityStillContributesToScore() throws {
        // A single-day chat (would be isLive == false on its GraphNode) still scores exactly
        // like any other chat once it reaches this function.
        let dead = chat("chat:dead", roster: ["+15550005", "+15550006"])

        let result = AcquaintanceDerivation.derive(groupChatActivity: [dead], fullyAcquaintedRosterKeys: [])

        let pair = try XCTUnwrap(acquaintance(result, "+15550005", "+15550006"))
        XCTAssertEqual(pair.score, 1.0, accuracy: 1e-9)
    }

    // MARK: - Test 7: marking a chat fully-acquainted confirms every pair, including lurkers
    // and pairs scoring below the likely floor -- proven on an 8-person chat (base 1/7 ~= 0.143,
    // sub-threshold) where NO pair would otherwise appear at all.

    func testMarkingAChatConfirmsEveryPairIncludingSubThresholdLurkers() {
        let eight = Set((1...8).map { "+1900000\($0)" })
        let bigChat = chat("chat:eight", roster: eight)
        let key = AcquaintanceRosterKey.canonicalize(eight)

        let unmarked = AcquaintanceDerivation.derive(groupChatActivity: [bigChat], fullyAcquaintedRosterKeys: [])
        XCTAssertTrue(unmarked.isEmpty, "1/7 ~= 0.143 is below the 0.2 likely floor, so nothing is recorded unmarked")

        let marked = AcquaintanceDerivation.derive(groupChatActivity: [bigChat], fullyAcquaintedRosterKeys: [key])
        XCTAssertEqual(marked.count, 28, "C(8,2) = 28 pairs, every one promoted")
        XCTAssertTrue(marked.allSatisfy { $0.tier == .confirmed })
        XCTAssertTrue(
            marked.allSatisfy { abs($0.score - (1.0 / 7.0)) < 1e-9 },
            "score is still computed and reported even though the tier comes from the marker, not the score"
        )
    }

    // MARK: - Test 8: unmarking demotes a pair back to whatever its observed score earns

    func testUnmarkingDemotesPairBackToItsObservedTier() throws {
        let trio = chat("chat:trio-mark", roster: ["+15550007", "+15550008"])
        let key = AcquaintanceRosterKey.canonicalize(["+15550007", "+15550008"])

        let markedResult = AcquaintanceDerivation.derive(groupChatActivity: [trio], fullyAcquaintedRosterKeys: [key])
        let markedPair = try XCTUnwrap(acquaintance(markedResult, "+15550007", "+15550008"))
        XCTAssertEqual(markedPair.tier, .confirmed)
        XCTAssertEqual(markedPair.score, 1.0, accuracy: 1e-9)

        let unmarkedResult = AcquaintanceDerivation.derive(groupChatActivity: [trio], fullyAcquaintedRosterKeys: [])
        let unmarkedPair = try XCTUnwrap(acquaintance(unmarkedResult, "+15550007", "+15550008"))
        XCTAssertEqual(unmarkedPair.tier, .strong, "score alone (1.0) already earns strong once the marker is gone")
        XCTAssertEqual(unmarkedPair.score, 1.0, accuracy: 1e-9, "unmarking changes the tier decision, never the observed score")
    }
}
