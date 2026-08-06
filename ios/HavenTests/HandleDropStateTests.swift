import Foundation
import Testing
@testable import Haven

/// An isolated defaults suite per test, so bookkeeping tests never share
/// state with each other or with the real App Group suite -- the same
/// reason `ContactChangeStateTests` and `CaptureQueueTests` each get their
/// own throwaway store rather than touching a shared one.
private func freshDefaults() -> UserDefaults {
    let suiteName = "haven.tests.handleDropState.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private let sample = HandleDropState.Event(
    personId: "p1", personName: "Ada Lovelace", platform: "instagram", reason: .handleFull
)

private func event(_ personId: String) -> HandleDropState.Event {
    HandleDropState.Event(personId: personId, personName: "Person \(personId)", platform: "x", reason: .handleFull)
}

@Suite("Dropped-handle bookkeeping")
struct HandleDropStateTests {
    @Test("nothing pending before the first drop")
    func noneYet() {
        let state = HandleDropState(userId: "u1", defaults: freshDefaults())
        #expect(state.pending == nil)
    }

    @Test("a recorded drop round-trips whole, reason included")
    func recordRoundTrips() {
        let state = HandleDropState(userId: "u1", defaults: freshDefaults())
        state.record(sample)
        #expect(state.pending == sample)
    }

    // Y2(b): a batch drain can produce more than one notice in a single
    // pass -- a handle-cap drop and a final conflict can both land -- and
    // the old single-slot overwrite silently lost whichever came first.
    // Both are now queued, oldest surfaced first, the order they actually
    // happened in.
    @Test("a second drop before the first is dismissed queues behind it rather than replacing it")
    func secondDropQueuesBehindFirst() {
        let state = HandleDropState(userId: "u1", defaults: freshDefaults())
        state.record(sample)
        let second = HandleDropState.Event(personId: "p2", personName: "Mai Tran", platform: "x", reason: .conflict)
        state.record(second)
        // The first one recorded is still what shows -- nothing was lost to
        // the overwrite the single-slot design used to do.
        #expect(state.pending == sample)
    }

    // Z1's belt: `ConflictNoticeMarks` is what actually stops a replayed
    // conflict from getting this far, but two different captures that
    // happen to produce identical-looking events should not show the same
    // sentence twice either.
    @Test("recording an event identical to one already queued is ignored")
    func dedupeIdenticalEvent() {
        let state = HandleDropState(userId: "u1", defaults: freshDefaults())
        state.record(sample)
        state.record(sample)
        state.dismiss()
        // If the duplicate had been queued behind the first, dismissing it
        // would have surfaced the identical second copy instead of clearing
        // to nil.
        #expect(state.pending == nil)
    }

    // "Surface once, then the next one": dismissing does not just clear the
    // board, it advances the queue to whatever is behind the one just seen.
    @Test("dismissing surfaces the next queued event")
    func dismissSurfacesNext() {
        let state = HandleDropState(userId: "u1", defaults: freshDefaults())
        let second = HandleDropState.Event(personId: "p2", personName: "Mai Tran", platform: "x", reason: .conflict)
        state.record(sample)
        state.record(second)
        state.dismiss()
        #expect(state.pending == second)
    }

    @Test("dismissing the only pending event clears it")
    func dismissClears() {
        let state = HandleDropState(userId: "u1", defaults: freshDefaults())
        state.record(sample)
        state.dismiss()
        #expect(state.pending == nil)
    }

    @Test("dismissing with nothing pending is not an error")
    func dismissWithNothingPending() {
        let state = HandleDropState(userId: "u1", defaults: freshDefaults())
        state.dismiss()
        #expect(state.pending == nil)
    }

    // A dropped handle is not a standing judgment about a person the way a
    // turned-down contact suggestion is -- a fresh drop of the very same
    // person and platform, after the first was dismissed, is a fresh,
    // currently-true problem and gets surfaced again rather than being
    // remembered as permanently silenced.
    @Test("the same person and platform can be recorded again after being dismissed")
    func sameEventAfterDismissSurfacesAgain() {
        let state = HandleDropState(userId: "u1", defaults: freshDefaults())
        state.record(sample)
        state.dismiss()
        state.record(sample)
        #expect(state.pending == sample)
    }

    @Test("two accounts on one device keep separate pending drops")
    func scopedPerUser() {
        let defaults = freshDefaults()
        let mine = HandleDropState(userId: "mine", defaults: defaults)
        let theirs = HandleDropState(userId: "theirs", defaults: defaults)
        mine.record(sample)
        #expect(theirs.pending == nil)
    }

    // Capped in the single digits so a device nobody ever opens does not
    // grow this without bound: the oldest, least-actionable notice is what
    // gives way, not the newest.
    @Test("recording past capacity evicts the oldest, not the newest")
    func capacityEvictsOldest() {
        let state = HandleDropState(userId: "u1", defaults: freshDefaults())
        let events = (0..<(HandleDropState.capacity + 1)).map { event("p\($0)") }
        for event in events {
            state.record(event)
        }
        // The very first one recorded (p0) is the one that fell off; the
        // second one recorded (p1) is now the oldest still queued, and
        // therefore what surfaces.
        #expect(state.pending == events[1])
    }

    @Test("recording posts a change notification scoped to that user")
    func recordPostsNotification() {
        let userId = "record-\(UUID().uuidString)"
        let state = HandleDropState(userId: userId, defaults: freshDefaults())
        var received: String?
        let token = NotificationCenter.default.addObserver(
            forName: HandleDropState.didChangeNotification, object: nil, queue: nil
        ) { note in
            guard note.object as? String == userId else { return }
            received = userId
        }
        defer { NotificationCenter.default.removeObserver(token) }

        state.record(sample)

        #expect(received == userId)
    }

    @Test("dismissing posts a change notification too")
    func dismissPostsNotification() {
        let userId = "dismiss-\(UUID().uuidString)"
        let state = HandleDropState(userId: userId, defaults: freshDefaults())
        state.record(sample)
        var notified = false
        let token = NotificationCenter.default.addObserver(
            forName: HandleDropState.didChangeNotification, object: nil, queue: nil
        ) { note in
            guard note.object as? String == userId else { return }
            notified = true
        }
        defer { NotificationCenter.default.removeObserver(token) }

        state.dismiss()

        #expect(notified)
    }
}
