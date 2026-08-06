import Foundation
import Testing
@testable import Haven

@Suite("Whether a saved handle is stale")
struct HandleStalenessTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func monthsAgo(_ months: Int) -> Double {
        calendar.date(byAdding: .month, value: -months, to: now)!.timeIntervalSince1970 * 1000
    }

    // A row saved before this field existed has nothing to compare against --
    // that is silence, not staleness, and must never nag.
    @Test("no addedAt at all is never stale")
    func noAddedAt() {
        #expect(!HandleStaleness.isStale(addedAt: nil, comparedTo: now, calendar: calendar))
    }

    @Test("younger than six months is not stale")
    func fresh() {
        #expect(!HandleStaleness.isStale(addedAt: monthsAgo(1), comparedTo: now, calendar: calendar))
        #expect(!HandleStaleness.isStale(addedAt: monthsAgo(5), comparedTo: now, calendar: calendar))
    }

    @Test("older than six months is stale")
    func stale() {
        #expect(HandleStaleness.isStale(addedAt: monthsAgo(7), comparedTo: now, calendar: calendar))
        #expect(HandleStaleness.isStale(addedAt: monthsAgo(24), comparedTo: now, calendar: calendar))
    }

    @Test("exactly six months is not yet stale")
    func boundary() {
        #expect(!HandleStaleness.isStale(addedAt: monthsAgo(6), comparedTo: now, calendar: calendar))
    }

    // Defensive: a clock skew or a server timestamp that has not landed yet
    // must not read as ancient.
    @Test("a timestamp in the future is never stale")
    func future() {
        let future = now.addingTimeInterval(1_000_000).timeIntervalSince1970 * 1000
        #expect(!HandleStaleness.isStale(addedAt: future, comparedTo: now, calendar: calendar))
    }
}
