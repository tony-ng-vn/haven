import Foundation
import Testing
@testable import Haven

@Suite("Whether a saved handle is stale")
struct HandleStalenessTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let staleAfter: TimeInterval = 60 * 60 * 24 * 180

    private func millisecondsBeforeNow(_ interval: TimeInterval) -> Double {
        now.addingTimeInterval(-interval).timeIntervalSince1970 * 1000
    }

    // A row saved before this field existed has nothing to compare against --
    // that is silence, not staleness, and must never nag.
    @Test("no addedAt at all is never stale")
    func noAddedAt() {
        #expect(!HandleStaleness.isStale(addedAt: nil, comparedTo: now))
    }

    @Test("younger than 180 days is not stale")
    func fresh() {
        #expect(!HandleStaleness.isStale(addedAt: millisecondsBeforeNow(staleAfter - 1), comparedTo: now))
    }

    @Test("older than 180 days is stale")
    func stale() {
        #expect(HandleStaleness.isStale(addedAt: millisecondsBeforeNow(staleAfter + 1), comparedTo: now))
        #expect(HandleStaleness.isStale(addedAt: millisecondsBeforeNow(staleAfter * 4), comparedTo: now))
    }

    @Test("exactly 180 days is not yet stale")
    func boundary() {
        #expect(!HandleStaleness.isStale(addedAt: millisecondsBeforeNow(staleAfter), comparedTo: now))
    }

    // Defensive: a clock skew or a server timestamp that has not landed yet
    // must not read as ancient.
    @Test("a timestamp in the future is never stale")
    func future() {
        let future = now.addingTimeInterval(1_000_000).timeIntervalSince1970 * 1000
        #expect(!HandleStaleness.isStale(addedAt: future, comparedTo: now))
    }
}
