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
    /// Handles whose save answers `handleDropped: true` -- the account could
    /// not fit under the 8-handle cap on the person it landed on.
    var handleDropping: Set<String> = []
    /// Handles whose first save answers "conflict" -- every later drain pass
    /// answers "created" instead. Models the underlying identity disagreement
    /// being resolved without changing the queued capture's attach choice.
    var conflictingOnce: Set<String> = []
    /// Handles whose every save answers "conflict", proving the drain never
    /// reroutes the capture by changing its attach choice.
    var alwaysConflicting: Set<String> = []
    private var callCounts: [String: Int] = [:]
    /// Handles whose save takes far longer than this test could ever wait out
    /// before it answers -- standing in for a connection that never comes
    /// back. Long on purpose, now that `Task.value(within:)` is actually
    /// bounded: what these tests below have to prove is that `CaptureDrain`
    /// returns while this is still running, not that it eventually finishes.
    var hangingFor: [String: Duration] = [:]

    func saveProfile(_ profile: QueuedCapture.Profile) async throws -> SharedProfileOutcome {
        profiles.append(profile)
        let handle = profile.link.handle
        if let delay = hangingFor[handle] {
            try? await Task.sleep(for: delay)
        }
        if failing.contains(handle) { throw SinkError.refused }
        return outcome(for: handle)
    }

    func saveManual(_ manual: QueuedCapture.Manual) async throws -> SharedProfileOutcome {
        manuals.append(manual)
        let handle = manual.handleValue
        if failing.contains(handle) { throw SinkError.refused }
        return outcome(for: handle)
    }

    func saveScreenshot(_ image: Data) async throws {
        screenshots.append(image)
        if failing.contains("screenshot") { throw SinkError.refused }
    }

    private func outcome(for handle: String) -> SharedProfileOutcome {
        callCounts[handle, default: 0] += 1
        let isFirstCall = callCounts[handle] == 1
        if alwaysConflicting.contains(handle) || (conflictingOnce.contains(handle) && isFirstCall) {
            return SharedProfileOutcome(status: "conflict", personId: "true-owner-\(handle)", noteTruncated: false)
        }
        return SharedProfileOutcome(
            status: "created",
            personId: "person-\(handle)",
            noteTruncated: truncating.contains(handle),
            handleDropped: handleDropping.contains(handle)
        )
    }

    enum SinkError: Error { case refused }
}

private final class EventFakeSink: EventCaptureSink, @unchecked Sendable {
    var links: [(EventReference, String)] = []
    var screenshots: [(Data, EventReference?)] = []
    var linkFails = false

    func saveProfile(_ profile: QueuedCapture.Profile) async throws -> SharedProfileOutcome {
        SharedProfileOutcome(
            status: "created", personId: "person-\(profile.link.handle)", noteTruncated: false
        )
    }

    func saveManual(_ manual: QueuedCapture.Manual) async throws -> SharedProfileOutcome {
        SharedProfileOutcome(
            status: "created", personId: "person-\(manual.handleValue)", noteTruncated: false
        )
    }

    func saveScreenshot(_ image: Data) async throws {
        screenshots.append((image, nil))
    }

    func saveScreenshot(_ image: Data, event: EventReference) async throws {
        screenshots.append((image, event))
    }

    func link(_ event: EventReference, to personId: String) async throws {
        if linkFails { throw SinkError.refused }
        links.append((event, personId))
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
    note: String? = nil,
    attachToPersonId: String? = nil
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
                attachToPersonId: attachToPersonId
            )
        )
    )
}

private func manual(
    _ handleValue: String,
    platform: String = "whatsapp",
    at seconds: TimeInterval,
    note: String = "met at the Hanoi meetup",
    attachToPersonId: String? = nil
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
                attachToPersonId: attachToPersonId
            )
        )
    )
}

@Suite("Draining the capture queue")
struct CaptureDrainTests {
    @Test("an event link must land before its person capture leaves the queue")
    func linksEventBeforeRemoval() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        let event = EventReference(
            clientKey: "event-1",
            title: "Community night",
            startedAt: Date(timeIntervalSince1970: 90)
        )
        let capture = profile("maya", at: 100)
        try queue.enqueue(
            QueuedCapture(
                id: capture.id,
                capturedAt: capture.capturedAt,
                payload: capture.payload,
                event: event
            )
        )
        let sink = EventFakeSink()

        let result = await CaptureDrain(queue: queue, sink: sink).run()

        #expect(sink.links.count == 1)
        #expect(sink.links.first?.0 == event)
        #expect(sink.links.first?.1 == "person-maya")
        #expect(result.sent == 1)
        #expect(queue.pending().isEmpty)
    }

    @Test("a failed event link keeps the person capture for an idempotent retry")
    func failedEventLinkKeepsCapture() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        let capture = profile("maya", at: 100)
        try queue.enqueue(
            QueuedCapture(
                id: capture.id,
                capturedAt: capture.capturedAt,
                payload: capture.payload,
                event: EventReference(
                    clientKey: "event-2",
                    title: "Demo day",
                    startedAt: Date(timeIntervalSince1970: 90)
                )
            )
        )
        let sink = EventFakeSink()
        sink.linkFails = true

        let result = await CaptureDrain(queue: queue, sink: sink).run()

        #expect(result.kept == 1)
        #expect(result.sent == 0)
        #expect(queue.pending().count == 1)
    }

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

    // The caller explicitly chose who this capture belongs to. If the server
    // says the handle belongs to somebody else, changing that choice in the
    // background would put the note on the wrong person.
    @Test("a conflicted profile preserves the attach choice and stays queued")
    func conflictedProfileStaysQueued() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        try queue.enqueue(profile("mai.makes", at: 100, attachToPersonId: "wrong-person"))
        let sink = FakeSink()
        sink.conflictingOnce = ["mai.makes"]

        let result = await CaptureDrain(queue: queue, sink: sink).run()

        #expect(sink.profiles.count == 1)
        #expect(sink.profiles[0].attachToPersonId == "wrong-person")
        #expect(result.sent == 0)
        #expect(result.kept == 1)
        #expect(queue.pending().count == 1)
    }

    @Test("a conflicted manual add preserves the attach choice and stays queued")
    func conflictedManualStaysQueued() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        try queue.enqueue(manual("mai_makes", at: 100, attachToPersonId: "wrong-person"))
        let sink = FakeSink()
        sink.conflictingOnce = ["mai_makes"]

        let result = await CaptureDrain(queue: queue, sink: sink).run()

        #expect(sink.manuals.count == 1)
        #expect(sink.manuals[0].attachToPersonId == "wrong-person")
        #expect(result.sent == 0)
        #expect(result.kept == 1)
        #expect(queue.pending().count == 1)
    }

    // A capture that never asked to attach cannot conflict on the server
    // (conflict only fires when attachToPersonId disagrees with the handle's
    // owner), but the decision logic itself is guarded the same way either
    // way: no attach means no retry, ever.
    @Test("a non-conflict outcome is sent exactly once, untouched")
    func nonConflictUntouched() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        try queue.enqueue(profile("mai.makes", at: 100))
        let sink = FakeSink()

        let result = await CaptureDrain(queue: queue, sink: sink).run()

        #expect(sink.profiles.count == 1)
        #expect(result.sent == 1)
    }

    // A conflict is final for this pass. The queue item is the one copy of the
    // note, so it stays on the device instead of being rerouted or discarded.
    @Test("a conflict with an attach choice is final for this pass")
    func conflictWithAttachIsFinal() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        try queue.enqueue(profile("mai.makes", at: 100, attachToPersonId: "wrong-person"))
        let sink = FakeSink()
        sink.alwaysConflicting = ["mai.makes"]

        let result = await CaptureDrain(queue: queue, sink: sink).run()

        #expect(sink.profiles.count == 1)
        #expect(result.sent == 0)
        #expect(result.kept == 1)
        #expect(queue.pending().count == 1)
    }

    // A handle's stored value can also conflict without an attach choice.
    // Nothing landed, so the capture is kept, not sent.
    @Test("a conflict on a capture that never had an attach guess is also kept, not sent")
    func conflictWithNoAttachIsKept() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        try queue.enqueue(profile("mai.makes", at: 100))
        let sink = FakeSink()
        sink.alwaysConflicting = ["mai.makes"]

        let result = await CaptureDrain(queue: queue, sink: sink).run()

        // The server is asked exactly once.
        #expect(sink.profiles.count == 1)
        #expect(result.sent == 0)
        #expect(result.kept == 1)
        #expect(queue.pending().count == 1)
    }
}

/// An isolated defaults suite per test, the same reason `HandleDropStateTests`
/// and `ContactChangeStateTests` each get their own throwaway store.
private func freshMarksDefaults() -> UserDefaults {
    let suiteName = "haven.tests.conflictNoticeMarks.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

// Z1: a capture kept for retry after a final conflict is retried on every
// later pass, on purpose -- but replaying the same unresolved conflict is
// not new information, and must not notify the person a second time.
@Suite("A replayed conflict notifies once, not on every pass")
struct ConflictNoticeSuppressionTests {
    @Test("a conflict that survives to a second drain pass does not record a second notice")
    func replayDoesNotNotifyAgain() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        try queue.enqueue(profile("mai.makes", at: 100, attachToPersonId: "wrong-person"))
        let sink = FakeSink()
        sink.alwaysConflicting = ["mai.makes"]
        let marksDefaults = freshMarksDefaults()

        // Two separate CaptureDrain instances sharing the same underlying
        // marks store, the same way CaptureSync.run(userId:) constructs a
        // fresh CaptureDrain per queue on every call but always scopes
        // ConflictNoticeMarks to the same userId.
        let first = await CaptureDrain(
            queue: queue, sink: sink, conflictMarks: ConflictNoticeMarks(userId: "u1", defaults: marksDefaults)
        ).run()
        let second = await CaptureDrain(
            queue: queue, sink: sink, conflictMarks: ConflictNoticeMarks(userId: "u1", defaults: marksDefaults)
        ).run()

        #expect(first.notices.count == 1)
        #expect(second.notices.isEmpty)
        // The retry itself is unaffected: still attempted, still kept, on
        // both passes -- only the notice is suppressed.
        #expect(second.kept == 1)
        #expect(queue.pending().count == 1)
    }

    @Test("dismissing a conflict notice is not undone by a later replay")
    func dismissalSurvivesReplay() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        try queue.enqueue(profile("mai.makes", at: 100, attachToPersonId: "wrong-person"))
        let sink = FakeSink()
        sink.alwaysConflicting = ["mai.makes"]
        let marksDefaults = freshMarksDefaults()
        let handleDrops = HandleDropState(userId: "u1", defaults: marksDefaults)

        let first = await CaptureDrain(
            queue: queue, sink: sink, conflictMarks: ConflictNoticeMarks(userId: "u1", defaults: marksDefaults)
        ).run()
        for event in first.notices { handleDrops.record(event) }
        handleDrops.dismiss()

        let second = await CaptureDrain(
            queue: queue, sink: sink, conflictMarks: ConflictNoticeMarks(userId: "u1", defaults: marksDefaults)
        ).run()
        for event in second.notices { handleDrops.record(event) }

        #expect(second.notices.isEmpty)
        #expect(handleDrops.pending == nil)
    }

    @Test("a capture that finally resolves clears its conflict mark")
    func resolutionClearsMark() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        let capture = profile("mai.makes", at: 100, attachToPersonId: "wrong-person")
        try queue.enqueue(capture)
        let sink = FakeSink()
        sink.alwaysConflicting = ["mai.makes"]
        let marksDefaults = freshMarksDefaults()
        let marks = ConflictNoticeMarks(userId: "u1", defaults: marksDefaults)

        _ = await CaptureDrain(queue: queue, sink: sink, conflictMarks: marks).run()
        #expect(marks.hasNotified(capture.id))

        // Whatever made this conflict is no longer true -- the next pass
        // resolves cleanly.
        sink.alwaysConflicting = []
        let resolved = await CaptureDrain(queue: queue, sink: sink, conflictMarks: marks).run()

        #expect(resolved.sent == 1)
        #expect(queue.pending().isEmpty)
        #expect(!marks.hasNotified(capture.id))
    }
}

// I5(b): decoded so the drain can log it, but there is no UI and no counter
// -- the note still landed, and the queue still has to clear the same as any
// other successful save.
@Suite("A dropped handle does not change what the drain does with the capture")
struct HandleDroppedTests {
    @Test("a capture whose handle was dropped is still sent and still clears the queue")
    func stillSentAndCleared() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        try queue.enqueue(profile("mai.makes", at: 100))
        let sink = FakeSink()
        sink.handleDropping = ["mai.makes"]

        let result = await CaptureDrain(queue: queue, sink: sink).run()

        #expect(result.sent == 1)
        #expect(result.kept == 0)
        #expect(queue.pending().isEmpty)
    }

    // What `CaptureSync.run(userId:)` actually records into `HandleDropState`
    // -- the person and platform have to be right, not just the sent/cleared
    // bookkeeping above.
    @Test("a dropped profile reports the person and platform it happened on")
    func profileReportsTheEvent() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        try queue.enqueue(profile("mai.makes", at: 100))
        let sink = FakeSink()
        sink.handleDropping = ["mai.makes"]

        let result = await CaptureDrain(queue: queue, sink: sink).run()

        #expect(
            result.notices == [
                HandleDropState.Event(
                    personId: "person-mai.makes", personName: "mai.makes", platform: "instagram", reason: .handleFull
                )
            ]
        )
    }

    @Test("a dropped manual add reports the person and platform it happened on")
    func manualReportsTheEvent() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        try queue.enqueue(manual("+84901234567", platform: "whatsapp", at: 100))
        let sink = FakeSink()
        sink.handleDropping = ["+84901234567"]

        let result = await CaptureDrain(queue: queue, sink: sink).run()

        #expect(
            result.notices == [
                HandleDropState.Event(
                    personId: "person-+84901234567", personName: "Mai Tran", platform: "whatsapp", reason: .handleFull
                )
            ]
        )
    }

    @Test("a capture that was not dropped reports no event")
    func noEventWhenNotDropped() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        try queue.enqueue(profile("mai.makes", at: 100))
        let sink = FakeSink()

        let result = await CaptureDrain(queue: queue, sink: sink).run()

        #expect(result.notices.isEmpty)
    }
}

// Y1: a final conflict is not a loss the way the (now-fixed) old behavior
// made it -- it is reported the same way a dropped handle is, just with its
// own reason and copy, since "your handles are full" would be wrong here.
@Suite("A final conflict is reported like a dropped handle, with its own reason")
struct FinalConflictNoticeTests {
    @Test("a conflict reports the true owner as a conflict, not a drop")
    func conflictReportsEvent() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        try queue.enqueue(profile("mai.makes", at: 100, attachToPersonId: "wrong-person"))
        let sink = FakeSink()
        sink.alwaysConflicting = ["mai.makes"]

        let result = await CaptureDrain(queue: queue, sink: sink).run()

        #expect(
            result.notices == [
                HandleDropState.Event(
                    personId: "true-owner-mai.makes", personName: "mai.makes", platform: "instagram",
                    reason: .conflict
                )
            ]
        )
    }

    @Test("a conflict with no attach guess reports the same way")
    func noAttachConflictReportsEvent() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        try queue.enqueue(manual("mai_makes", platform: "instagram", at: 100))
        let sink = FakeSink()
        sink.alwaysConflicting = ["mai_makes"]

        let result = await CaptureDrain(queue: queue, sink: sink).run()

        #expect(
            result.notices == [
                HandleDropState.Event(
                    personId: "true-owner-mai_makes", personName: "Mai Tran", platform: "instagram",
                    reason: .conflict
                )
            ]
        )
    }
}

@Suite("Decoding what saveSharedProfile answers")
struct SharedProfileOutcomeTests {
    // The server always sends this key -- `handleDropped: v.boolean()` is not
    // optional in `saveSharedProfile`'s return validator -- so there is no
    // "response from before this field existed" to be lenient about, unlike
    // `Person.Handle`'s provenance fields, which really do predate some rows.
    // The `= false` default keeps the memberwise initializer useful in tests;
    // it does not make a missing JSON key decode successfully.
    @Test("handleDropped decodes true when the server sends it")
    func decodesTrue() throws {
        let json = """
            {"status":"created","personId":"p1","noteTruncated":false,"handleDropped":true}
            """
        let outcome = try JSONDecoder().decode(SharedProfileOutcome.self, from: Data(json.utf8))
        #expect(outcome.handleDropped)
    }

    @Test("handleDropped decodes false when the server sends it")
    func decodesFalse() throws {
        let json = """
            {"status":"created","personId":"p1","noteTruncated":false,"handleDropped":false}
            """
        let outcome = try JSONDecoder().decode(SharedProfileOutcome.self, from: Data(json.utf8))
        #expect(!outcome.handleDropped)
    }
}
