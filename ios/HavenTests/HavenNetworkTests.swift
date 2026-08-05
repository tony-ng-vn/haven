import Combine
import Foundation
import Testing
@testable import Haven

// LiveSubscription.attach is HavenNetwork.subscribe's live-subscription path,
// pulled out so its timing can be driven by a plain publisher instead of a
// deployment. This is the fix for the gap between the People and Search
// tabs: DirectoryModel opens one long-lived subscription and never reopens
// it, so if this timing is wrong, a directory that sits quiet for longer
// than the deadline stops receiving pushes for the rest of the session with
// nothing on screen saying so.

private enum TestSilence: Error {
    case dropped
}

@MainActor
@Suite("A live subscription's deadline")
struct HavenNetworkTests {
    // The one thing this fix exists for. Before it, `.timeout` wrapped the
    // whole stream and reset on every element, so a value followed by a
    // quiet stretch past the deadline silently ended the subscription --
    // exactly what DirectoryModel does between the moment someone opens the
    // People tab and the next time they add someone.
    @Test("a value, then quiet past the deadline, does not count as silence")
    func quietAfterAnAnswerIsNotSilence() async throws {
        let subject = PassthroughSubject<Int, TestSilence>()
        var values: [Int] = []
        var silences = 0

        let subscription = LiveSubscription.attach(
            to: subject,
            deadline: 0.05,
            onValue: { values.append($0) },
            onSilence: { silences += 1 }
        )

        subject.send(1)
        // Well past the 50ms deadline, with nothing else happening on the
        // stream -- the shape of a directory nobody has touched in a while.
        try await withTestTimeout {
            try? await Task.sleep(for: .milliseconds(200))
        }

        #expect(values == [1])
        #expect(silences == 0)
        subscription.cancel()
    }

    // The subscription is still open on the far side of the old deadline,
    // not merely quiet without having noticed it died: a push that arrives
    // late still has to land.
    @Test("a later push still arrives after the deadline has passed")
    func aLaterPushStillArrives() async throws {
        let subject = PassthroughSubject<Int, TestSilence>()
        var values: [Int] = []

        let subscription = LiveSubscription.attach(
            to: subject,
            deadline: 0.05,
            onValue: { values.append($0) },
            onSilence: {}
        )

        subject.send(1)
        try await withTestTimeout {
            try? await Task.sleep(for: .milliseconds(150))
        }
        subject.send(2)
        try await withTestTimeout {
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(values == [1, 2])
        subscription.cancel()
    }

    // The deadline still has a job: nothing ever answering at all is exactly
    // what it exists to catch.
    @Test("nothing arriving before the deadline is silence")
    func nothingBeforeTheDeadlineIsSilence() async throws {
        let subject = PassthroughSubject<Int, TestSilence>()
        var silences = 0

        let subscription = LiveSubscription.attach(
            to: subject,
            deadline: 0.05,
            onValue: { _ in },
            onSilence: { silences += 1 }
        )

        try await withTestTimeout {
            while silences == 0 { try? await Task.sleep(for: .milliseconds(5)) }
        }

        #expect(silences == 1)
        subscription.cancel()
    }

    // Any ending counts, not just a failure to ever start: a subscription
    // that answered once and then genuinely drops off the network is
    // unreachable now, not only "unreachable if nothing ever came first".
    @Test("the stream ending after an answer is still reported as silence")
    func endingAfterAnAnswerIsStillSilence() async throws {
        let subject = PassthroughSubject<Int, TestSilence>()
        var silences = 0

        let subscription = LiveSubscription.attach(
            to: subject,
            deadline: 5,
            onValue: { _ in },
            onSilence: { silences += 1 }
        )

        subject.send(1)
        subject.send(completion: .failure(.dropped))
        try await withTestTimeout {
            while silences == 0 { try? await Task.sleep(for: .milliseconds(5)) }
        }

        #expect(silences == 1)
        subscription.cancel()
    }

    // Cancelling has to stop the watchdog too, or a screen dismissed just
    // before the deadline would still call onSilence into a model nobody is
    // looking at.
    @Test("cancelling before the deadline suppresses it")
    func cancellingSuppressesTheWatchdog() async throws {
        let subject = PassthroughSubject<Int, TestSilence>()
        var silences = 0

        let subscription = LiveSubscription.attach(
            to: subject,
            deadline: 0.03,
            onValue: { _ in },
            onSilence: { silences += 1 }
        )
        subscription.cancel()

        try await withTestTimeout {
            try? await Task.sleep(for: .milliseconds(100))
        }

        #expect(silences == 0)
    }
}
