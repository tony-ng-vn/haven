import Foundation
import Testing
@testable import Haven

/// A sink that records what it was asked to send and answers however the test
/// needs it to.
private final class FakeSink: CaptureSink, @unchecked Sendable {
    var profiles: [QueuedCapture.Profile] = []
    var screenshots: [Data] = []
    /// Handles whose save throws, standing in for anything the server refuses
    /// or the network never reaches.
    var failing: Set<String> = []
    var truncating: Set<String> = []

    func saveProfile(_ profile: QueuedCapture.Profile) async throws -> SharedProfileOutcome {
        profiles.append(profile)
        if failing.contains(profile.link.handle) { throw SinkError.refused }
        return SharedProfileOutcome(
            status: "created",
            personId: "person-\(profile.link.handle)",
            noteTruncated: truncating.contains(profile.link.handle)
        )
    }

    func saveScreenshot(_ image: Data) async throws {
        screenshots.append(image)
        if failing.contains("screenshot") { throw SinkError.refused }
    }

    enum SinkError: Error { case refused }
}

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

@Suite("Draining the capture queue")
struct CaptureDrainTests {
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
