import XCTest
@testable import GraphCore

/// Perf smoke for PersonFilter.apply, not a correctness check (PersonFilterTests covers that).
/// Guards against reintroducing the O(people x messages) full-array rescan this function used
/// to do once per person -- the dominant cost measured against the real database before this
/// fix landed. Same calibration-ratio technique as ForceSimulationPerfSmokeTests: comparing the
/// real workload against a same-process, same-instant CPU calibration cancels out "how fast is
/// this machine right now" and leaves only the algorithm's relative cost, so the threshold
/// survives a shared, variably loaded machine. Deterministic, synthetic data only -- never the
/// real database (PLAN.md's split: tune against real data, assert against fixtures).
final class PersonFilterPerfSmokeTests: XCTestCase {

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Roughly real-data scale (measured against the real database: ~2,166 handles, ~1,193
    /// one-to-one chats, ~130 group chats, ~110k messages): big enough that an
    /// O(people x messages) regression would blow through the threshold below, small enough
    /// that the current O(people + messages) cost runs in well under a second.
    private func syntheticRealScaleExtract() -> (extract: ChatExtract, people: [Person]) {
        let personCount = 2000
        let oneToOneChatCount = 1200
        let groupChatCount = 100
        let membersPerGroup = 12
        let messagesPerOneToOneChat = 60
        let messagesPerGroupChat = 400

        var handles: [RawHandle] = []
        var people: [Person] = []
        for i in 0..<personCount {
            let identifier = "+1415555\(String(format: "%04d", i))"
            handles.append(RawHandle(rowID: Int64(i), identifier: identifier, service: "iMessage"))
            people.append(
                Person(
                    id: identifier,
                    identifiers: [identifier],
                    handleRowIDs: [Int64(i)],
                    name: nil,
                    thumbnailImageData: nil,
                    contactCardIDs: [],
                    hasContactCard: false
                )
            )
        }

        var chats: [RawChat] = []
        var messages: [RawMessage] = []
        var messageRowID: Int64 = 0
        let baseDate = Date(timeIntervalSinceReferenceDate: 0)

        for i in 0..<oneToOneChatCount {
            let chatRowID = Int64(i)
            let handleID = Int64(i % personCount)
            chats.append(
                RawChat(
                    rowID: chatRowID, guid: "one-\(i)", style: 45, chatIdentifier: nil,
                    serviceName: nil, displayName: nil, memberHandleRowIDs: [handleID]
                )
            )
            for m in 0..<messagesPerOneToOneChat {
                messages.append(
                    RawMessage(
                        rowID: messageRowID,
                        chatRowID: chatRowID,
                        handleRowID: m % 2 == 0 ? handleID : nil,
                        isFromMe: m % 2 != 0,
                        date: baseDate.addingTimeInterval(Double(m) * 86_400)
                    )
                )
                messageRowID += 1
            }
        }

        for g in 0..<groupChatCount {
            let chatRowID = Int64(oneToOneChatCount + g)
            let members = (0..<membersPerGroup).map { Int64((g * membersPerGroup + $0) % personCount) }
            chats.append(
                RawChat(
                    rowID: chatRowID, guid: "group-\(g)", style: 43, chatIdentifier: nil,
                    serviceName: nil, displayName: "Group \(g)", memberHandleRowIDs: members
                )
            )
            for m in 0..<messagesPerGroupChat {
                let sender = members[m % members.count]
                messages.append(
                    RawMessage(
                        rowID: messageRowID,
                        chatRowID: chatRowID,
                        handleRowID: sender,
                        isFromMe: false,
                        date: baseDate.addingTimeInterval(Double(m) * 3_600)
                    )
                )
                messageRowID += 1
            }
        }

        let extract = ChatExtract(handles: handles, chats: chats, messages: messages, unjoinedMessageCount: 0)
        return (extract, people)
    }

    private func milliseconds(_ elapsed: Duration) -> Double {
        Double(elapsed.components.seconds) * 1000.0 + Double(elapsed.components.attoseconds) * 1e-15
    }

    /// Same fixed-cost calibration workload as ForceSimulationPerfSmokeTests: no relation to
    /// PersonFilter's own code, just a same-instant read of "how fast is this machine right
    /// now" to normalize against.
    private func calibrationMilliseconds() -> Double {
        let clock = ContinuousClock()
        var accumulator = 0.0
        let elapsed = clock.measure {
            for i in 0..<2_000_000 {
                let x = Double(i) * 0.0001
                accumulator += (x * x + 1.0).squareRoot() * cos(x)
            }
        }
        XCTAssertTrue(accumulator.isFinite)
        return milliseconds(elapsed)
    }

    func testPerfSmokePersonFilterAtRealDataScale() {
        let (extract, people) = syntheticRealScaleExtract()
        XCTAssertEqual(
            extract.messages.count, 1200 * 60 + 100 * 400,
            "fixture drifted from its target message count"
        )

        let clock = ContinuousClock()
        let trialCount = 3
        var bestRatio = Double.infinity
        var bestMs = Double.infinity

        for _ in 0..<trialCount {
            let before = calibrationMilliseconds()
            let elapsed = clock.measure {
                _ = PersonFilter.apply(extract: extract, people: people, calendar: utc)
            }
            let after = calibrationMilliseconds()

            let ms = milliseconds(elapsed)
            let calibrationMs = (before + after) / 2.0
            let ratio = ms / calibrationMs
            if ratio < bestRatio {
                bestRatio = ratio
                bestMs = ms
            }
        }

        print(
            "PERF_SMOKE PersonFilter.apply at \(people.count) people / \(extract.messages.count) messages: "
                + "\(bestMs) ms (best of \(trialCount)); ratio to calibration \(bestRatio)x"
        )

        // The old O(people x messages) full-array rescan made this fixture's cost scale with
        // people.count x messages.count (2000 x 112,000 = 224M closure calls); the current
        // O(people + messages) bucketing keeps this well under the calibration workload on any
        // machine this test has run on. 8.0x leaves generous headroom over ordinary noise while
        // still catching a reintroduced full scan, which would push the ratio into the hundreds.
        XCTAssertLessThan(
            bestRatio, 8.0,
            "PersonFilter.apply cost relative to calibration (\(bestRatio)x) exceeds the smoke "
                + "threshold -- likely a reintroduced O(people x messages) scan"
        )
    }
}
