import Foundation
import Testing
@testable import Haven

/// A sink that records what it was asked to send and answers however the test
/// needs it to.
private final class FakeSink: CaptureSink, @unchecked Sendable {
    var profiles: [QueuedCapture.Profile] = []
    var manuals: [QueuedCapture.Manual] = []
    var screenshots: [Data] = []
    /// Handles whose save throws, standing in for anything the server refuses
    /// or the network never reaches.
    var failing: Set<String> = []
    var truncating: Set<String> = []
    /// Handles whose save takes far longer than this test could ever wait out
    /// before it answers -- standing in for a connection that never comes
    /// back. Long on purpose, now that `Task.value(within:)` is actually
    /// bounded: what these tests below have to prove is that `CaptureDrain`
    /// returns while this is still running, not that it eventually finishes.
    var hangingFor: [String: Duration] = [:]

    func saveProfile(_ profile: QueuedCapture.Profile) async throws -> SharedProfileOutcome {
        profiles.append(profile)
        if let delay = hangingFor[profile.link.handle] {
            try? await Task.sleep(for: delay)
        }
        if failing.contains(profile.link.handle) { throw SinkError.refused }
        return SharedProfileOutcome(
            status: "created",
            personId: "person-\(profile.link.handle)",
            noteTruncated: truncating.contains(profile.link.handle)
        )
    }

    func saveManual(_ manual: QueuedCapture.Manual) async throws -> SharedProfileOutcome {
        manuals.append(manual)
        if failing.contains(manual.handleValue) { throw SinkError.refused }
        return SharedProfileOutcome(
            status: "created",
            personId: "person-\(manual.handleValue)",
            noteTruncated: truncating.contains(manual.handleValue)
        )
    }

    func saveScreenshot(_ image: Data) async throws {
        screenshots.append(image)
        if failing.contains("screenshot") { throw SinkError.refused }
    }

    enum SinkError: Error { case refused }
}

// withTestTimeout lives in TestTimeout.swift, shared with TaskDeadlineTests.

private func makeQueue() -> (queue: CaptureQueue, root: URL) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("haven-drain-\(UUID().uuidString)")
    return (CaptureQueue(directory: root), root)
}

private func profile(
    _ handle: String,
    at seconds: TimeInterval,
    note: String? = nil
) -> QueuedCapture {
    QueuedCapture(
        id: UUID(),
        capturedAt: Date(timeIntervalSince1970: seconds),
        payload: .profile(
            QueuedCapture.Profile(
                link: ProfileLink(platform: .instagram, handle: handle),
                profileUrl: "https://instagram.com/\(handle)",
                name: handle,
                note: note,
                attachToPersonId: nil
            )
        )
    )
}

private func manual(
    _ handleValue: String,
    platform: String = "whatsapp",
    at seconds: TimeInterval,
    note: String = "met at the Hanoi meetup"
) -> QueuedCapture {
    QueuedCapture(
        id: UUID(),
        capturedAt: Date(timeIntervalSince1970: seconds),
        payload: .manual(
            QueuedCapture.Manual(
                name: "Mai Tran",
                platform: platform,
                handleValue: handleValue,
                profileUrl: "",
                note: note,
                attachToPersonId: nil
            )
        )
    )
}

@Suite("Draining the capture queue")
struct CaptureDrainTests {
    // The offline rule for the in-app add: it writes to the queue and closes,
    // and whether there was a network at that moment is the drain's problem.
    @Test("a person added by hand is sent like any other capture")
    func sendsManual() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        try queue.enqueue(manual("+84901234567", at: 100))
        let sink = FakeSink()

        let result = await CaptureDrain(queue: queue, sink: sink).run()

        #expect(sink.manuals.map(\.handleValue) == ["+84901234567"])
        #expect(result.sent == 1)
        #expect(queue.pending().isEmpty)
    }

    @Test("a person added by hand with no network stays for next time")
    func keepsManual() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        try queue.enqueue(manual("+84901234567", at: 100))
        let sink = FakeSink()
        sink.failing = ["+84901234567"]

        let result = await CaptureDrain(queue: queue, sink: sink).run()

        #expect(result.sent == 0)
        #expect(result.kept == 1)
        #expect(queue.pending().count == 1)
    }

    // Both kinds share one queue, and one kind failing must not strand the
    // other.
    @Test("manual adds and shares drain together, oldest first")
    func manualAndSharesInterleave() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        try queue.enqueue(profile("shared", at: 200))
        try queue.enqueue(manual("+84901234567", at: 100))
        let sink = FakeSink()

        let result = await CaptureDrain(queue: queue, sink: sink).run()

        #expect(sink.manuals.count == 1)
        #expect(sink.profiles.map(\.link.handle) == ["shared"])
        #expect(result.sent == 2)
        #expect(queue.pending().isEmpty)
    }

    @Test("a clipped note on a manual add is reported")
    func manualTruncation() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        try queue.enqueue(manual("+84901234567", at: 100))
        let sink = FakeSink()
        sink.truncating = ["+84901234567"]

        let result = await CaptureDrain(queue: queue, sink: sink).run()

        #expect(result.sent == 1)
        #expect(result.truncatedNotes == 1)
    }

    @Test("everything waiting is sent, oldest first")
    func sendsEverything() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        try queue.enqueue(profile("b", at: 200))
        try queue.enqueue(profile("a", at: 100))
        let sink = FakeSink()

        _ = await CaptureDrain(queue: queue, sink: sink).run()

        // Order is not cosmetic: a second share of one account appends its note
        // to the person the first one created, so replaying them backwards
        // files the notes against the wrong share.
        #expect(sink.profiles.map(\.link.handle) == ["a", "b"])
        #expect(queue.pending().isEmpty)
    }

    // The whole point of the queue. A capture made with no signal waits, and
    // is still there to send when there is some.
    @Test("a capture that could not be sent stays for next time")
    func keepsWhatFailed() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        try queue.enqueue(profile("a", at: 100))
        let sink = FakeSink()
        sink.failing = ["a"]

        let result = await CaptureDrain(queue: queue, sink: sink).run()

        #expect(result.sent == 0)
        #expect(result.kept == 1)
        #expect(queue.pending().count == 1)
    }

    // A hung mutation is not a fast throw, it is a call that never comes
    // back -- what a reconnecting client looks like from the drain's side.
    // Nothing here must wedge on that: CaptureSync.run()'s isRunning guard
    // only ever resets once this function returns, and a drain stuck on one
    // item is every future capture sync silently doing nothing for the rest
    // of the session.
    //
    // The sink is set to answer in an hour, comfortably longer than this
    // test or the whole suite runs for, so a passing result can only mean
    // CaptureDrain's own 0.05s deadline is what ended the wait -- not the
    // sink finishing on its own, which the first version of this test could
    // not tell apart from a real bound.
    @Test("a hung send is still kept, while the sink is still pending")
    func hungSendIsKept() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        try queue.enqueue(profile("a", at: 100))
        let sink = FakeSink()
        sink.hangingFor = ["a": .seconds(3600)]
        sink.failing = ["a"]

        // withTestTimeout is the test's own safety net, independent of
        // whatever CaptureDrain's own deadline does, so a regression here
        // fails this test rather than hanging the suite.
        let start = ContinuousClock.now
        let result = try await withTestTimeout {
            await CaptureDrain(queue: queue, sink: sink, deadline: 0.05).run()
        }
        let elapsed = ContinuousClock.now - start

        #expect(result.sent == 0)
        #expect(result.kept == 1)
        #expect(queue.pending().count == 1)
        // Generous above the 0.05s deadline for scheduling jitter, and far
        // below anything an hour-long sink could have produced -- the drain
        // did not wait for it.
        #expect(elapsed < .seconds(1), "\(elapsed)")
    }

    // The same failure, one item further back, must not leave the drain
    // stuck on the hung one before it ever reaches the item that would
    // have gone through cleanly.
    @Test("a hung send does not block a good one behind it")
    func hungSendDoesNotBlockTheRest() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        try queue.enqueue(profile("stuck", at: 100))
        try queue.enqueue(profile("good", at: 200))
        let sink = FakeSink()
        sink.hangingFor = ["stuck": .seconds(3600)]
        sink.failing = ["stuck"]

        let start = ContinuousClock.now
        let result = try await withTestTimeout {
            await CaptureDrain(queue: queue, sink: sink, deadline: 0.05).run()
        }
        let elapsed = ContinuousClock.now - start

        #expect(result.kept == 1)
        #expect(result.sent == 1)
        #expect(sink.profiles.map(\.link.handle) == ["stuck", "good"])
        #expect(elapsed < .seconds(1), "\(elapsed)")
    }

    // One capture the server will not take must not strand the ones behind
    // it, or a single bad item quietly blocks the queue forever.
    @Test("one failure does not hold up the rest")
    func failureDoesNotBlock() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        try queue.enqueue(profile("bad", at: 100))
        try queue.enqueue(profile("good", at: 200))
        let sink = FakeSink()
        sink.failing = ["bad"]

        let result = await CaptureDrain(queue: queue, sink: sink).run()

        #expect(sink.profiles.map(\.link.handle) == ["bad", "good"])
        #expect(result.sent == 1)
        #expect(queue.pending().map(\.id).count == 1)
    }

    // A note clipped at the cap is a save that did not save everything, and
    // the drain is the only thing that ever finds out.
    @Test("a clipped note is reported rather than reported as complete")
    func truncation() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        try queue.enqueue(profile("a", at: 100, note: "a very long note"))
        let sink = FakeSink()
        sink.truncating = ["a"]

        let result = await CaptureDrain(queue: queue, sink: sink).run()

        #expect(result.sent == 1)
        #expect(result.truncatedNotes == 1)
    }

    @Test("a screenshot is uploaded and then forgotten")
    func screenshot() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.png")
        try Data("png bytes".utf8).write(to: source)
        let fileName = try queue.storeImage(copyingFrom: source)
        try queue.enqueue(
            QueuedCapture(
                id: UUID(),
                capturedAt: Date(timeIntervalSince1970: 100),
                payload: .screenshot(
                    QueuedCapture.Screenshot(fileName: fileName, note: nil)
                )
            )
        )
        let sink = FakeSink()

        let result = await CaptureDrain(queue: queue, sink: sink).run()

        #expect(sink.screenshots == [Data("png bytes".utf8)])
        #expect(result.sent == 1)
        #expect(!FileManager.default.fileExists(atPath: queue.imageURL(named: fileName).path))
    }

    // An image that is gone can never be uploaded, so keeping the capture
    // would retry it on every launch for the life of the install.
    @Test("a screenshot whose image vanished is dropped rather than retried")
    func missingImage() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        try queue.enqueue(
            QueuedCapture(
                id: UUID(),
                capturedAt: Date(timeIntervalSince1970: 100),
                payload: .screenshot(
                    QueuedCapture.Screenshot(fileName: "gone.png", note: nil)
                )
            )
        )
        let sink = FakeSink()

        let result = await CaptureDrain(queue: queue, sink: sink).run()

        #expect(sink.screenshots.isEmpty)
        #expect(result.dropped == 1)
        #expect(queue.pending().isEmpty)
    }

    @Test("an empty queue is a no-op, not a round trip")
    func emptyQueue() async {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        let sink = FakeSink()

        let result = await CaptureDrain(queue: queue, sink: sink).run()

        #expect(sink.profiles.isEmpty)
        #expect(result == DrainResult())
    }
}
