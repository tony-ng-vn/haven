import Foundation
import Testing
@testable import Haven

/// A queue in a directory of its own, thrown away when the test ends.
private func makeQueue() -> (queue: CaptureQueue, root: URL) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("haven-queue-\(UUID().uuidString)")
    return (CaptureQueue(directory: root), root)
}

private func profileCapture(
    handle: String,
    name: String,
    note: String? = nil,
    at capturedAt: Date = Date(timeIntervalSince1970: 0)
) -> QueuedCapture {
    QueuedCapture(
        id: UUID(),
        capturedAt: capturedAt,
        payload: .profile(
            QueuedCapture.Profile(
                link: ProfileLink(platform: .instagram, handle: handle),
                profileUrl: "https://instagram.com/\(handle)",
                name: name,
                note: note,
                attachToPersonId: nil
            )
        )
    )
}

@Suite("The capture queue")
struct CaptureQueueTests {
    // Capture never fails. The first share on a fresh install arrives before
    // anything has created the directory, and that one must not be the one
    // that is lost.
    @Test("the first ever capture creates the queue it is written into")
    func firstCapture() throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }

        try queue.enqueue(profileCapture(handle: "mai.makes", name: "Mai Tran"))
        #expect(queue.pending().count == 1)
    }

    @Test("a capture survives the round trip whole")
    func roundTrip() throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }

        let capture = profileCapture(
            handle: "mai.makes",
            name: "Mai Tran",
            note: "met at the Hanoi meetup, builds ceramics"
        )
        try queue.enqueue(capture)
        #expect(queue.pending() == [capture])
    }

    // The add sheet writes here before it writes to Convex, so a payload that
    // did not survive the file would be a person somebody typed out and lost.
    @Test("a person added by hand survives the round trip whole")
    func manualRoundTrip() throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }

        let capture = QueuedCapture(
            id: UUID(),
            capturedAt: Date(timeIntervalSince1970: 0),
            payload: .manual(
                QueuedCapture.Manual(
                    name: "Mai Tran",
                    platform: "telegram",
                    handleValue: "mai_makes",
                    profileUrl: "https://t.me/mai_makes",
                    note: "met at the Hanoi meetup, builds ceramics",
                    attachToPersonId: "j5701"
                )
            )
        )
        try queue.enqueue(capture)
        #expect(queue.pending() == [capture])
    }

    // The drain replays captures in the order they were made, because the
    // order decides the outcome: a second share of one account appends its
    // note to the person the first one created.
    @Test("captures come back in the order they were made")
    func order() throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }

        let second = profileCapture(
            handle: "b", name: "B", at: Date(timeIntervalSince1970: 200)
        )
        let first = profileCapture(
            handle: "a", name: "A", at: Date(timeIntervalSince1970: 100)
        )
        let third = profileCapture(
            handle: "c", name: "C", at: Date(timeIntervalSince1970: 300)
        )
        try queue.enqueue(second)
        try queue.enqueue(first)
        try queue.enqueue(third)

        #expect(queue.pending().map(\.id) == [first.id, second.id, third.id])
    }

    // One unreadable file must cost one capture, not the queue. This is the
    // whole reason a capture is a file rather than a row in one array: a
    // single truncated write would otherwise take everybody else with it.
    @Test("a corrupt file hides only itself")
    func corruptFile() throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }

        let good = profileCapture(handle: "mai.makes", name: "Mai Tran")
        try queue.enqueue(good)
        try Data("half a wri".utf8).write(
            to: root.appendingPathComponent("\(UUID().uuidString).json")
        )

        #expect(queue.pending() == [good])
    }

    // Anything else that lands in the container is not ours to read, and must
    // not stop the drain.
    @Test("a file that is not a capture is ignored")
    func foreignFile() throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }

        let good = profileCapture(handle: "mai.makes", name: "Mai Tran")
        try queue.enqueue(good)
        try Data("not json".utf8).write(to: root.appendingPathComponent("notes.txt"))

        #expect(queue.pending() == [good])
    }

    @Test("removing one capture leaves the rest")
    func remove() throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }

        let first = profileCapture(
            handle: "a", name: "A", at: Date(timeIntervalSince1970: 100)
        )
        let second = profileCapture(
            handle: "b", name: "B", at: Date(timeIntervalSince1970: 200)
        )
        try queue.enqueue(first)
        try queue.enqueue(second)

        try queue.remove(first)
        #expect(queue.pending() == [second])
    }

    // The drain deletes on success and can be interrupted between the mutation
    // and the delete, so it replays. Deleting what is already gone is the
    // normal case, not an error.
    @Test("removing a capture twice is not an error")
    func removeTwice() throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }

        let capture = profileCapture(handle: "mai.makes", name: "Mai Tran")
        try queue.enqueue(capture)
        try queue.remove(capture)
        try queue.remove(capture)
        #expect(queue.pending().isEmpty)
    }

    @Test("an empty queue is empty, not an error")
    func emptyQueue() {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(queue.pending().isEmpty)
    }

    // Provenance rides the same file a hand-typed add already writes -- if
    // `source`/`platformId` did not survive the round trip, the drain would
    // silently forward nothing to the server no matter what stamped them.
    @Test("source and platformId survive the round trip whole")
    func manualProvenanceRoundTrip() throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }

        let capture = QueuedCapture(
            id: UUID(),
            capturedAt: Date(timeIntervalSince1970: 0),
            payload: .manual(
                QueuedCapture.Manual(
                    name: "Mai Tran",
                    platform: "instagram",
                    handleValue: "mai.makes",
                    profileUrl: "https://instagram.com/mai.makes",
                    note: nil,
                    attachToPersonId: nil,
                    source: "typed",
                    platformId: "1234567890"
                )
            )
        )
        try queue.enqueue(capture)
        #expect(queue.pending() == [capture])
        guard case .manual(let manual) = queue.pending().first?.payload else {
            Issue.record("expected a manual capture")
            return
        }
        #expect(manual.source == "typed")
        #expect(manual.platformId == "1234567890")
    }

    // A capture file written by a build before this brief has neither key at
    // all, not the keys present with a null -- Codable's own backward
    // compatibility guarantee, pinned here rather than trusted blindly.
    @Test("a queue file written before source and platformId existed still decodes")
    func manualBackwardCompatible() throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // The enum case's single associated value is keyed "_0" -- this is
        // Swift's own synthesized shape for `case manual(Manual)`, confirmed
        // against a real `encoder.encode(...)` before being pinned by hand
        // here, not guessed at.
        let id = UUID()
        let json = """
            {
              "id": "\(id.uuidString)",
              "capturedAt": "1970-01-01T00:00:00Z",
              "payload": {
                "manual": {
                  "_0": {
                    "name": "Mai Tran",
                    "platform": "telegram",
                    "handleValue": "mai_makes",
                    "profileUrl": "https://t.me/mai_makes"
                  }
                }
              }
            }
            """
        try Data(json.utf8).write(to: root.appendingPathComponent("\(id.uuidString).json"))

        let pending = queue.pending()
        #expect(pending.count == 1)
        guard case .manual(let manual) = pending.first?.payload else {
            Issue.record("expected a manual capture")
            return
        }
        #expect(manual.name == "Mai Tran")
        #expect(manual.source == nil)
        #expect(manual.platformId == nil)
    }
}

@Suite("Screenshots in the queue")
struct CaptureQueueImageTests {
    @Test("an image is copied into the container and found again")
    func storeImage() throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source.png")
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true
        )
        try Data("png bytes".utf8).write(to: source)

        let fileName = try queue.storeImage(copyingFrom: source)
        try FileManager.default.removeItem(at: source)

        // The extension's copy has to outlive the shared file, which the
        // sending app can revoke the moment the sheet closes.
        #expect(
            try Data(contentsOf: queue.imageURL(named: fileName))
                == Data("png bytes".utf8)
        )
    }

    // A drained screenshot whose image stayed behind is a leak nobody sees,
    // in a container with a quota.
    @Test("removing a screenshot capture removes its image")
    func removeTakesImage() throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true
        )
        let source = root.appendingPathComponent("source.png")
        try Data("png bytes".utf8).write(to: source)
        let fileName = try queue.storeImage(copyingFrom: source)

        let capture = QueuedCapture(
            id: UUID(),
            capturedAt: Date(timeIntervalSince1970: 0),
            payload: .screenshot(
                QueuedCapture.Screenshot(fileName: fileName, note: nil)
            )
        )
        try queue.enqueue(capture)
        try queue.remove(capture)

        #expect(queue.pending().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: queue.imageURL(named: fileName).path))
    }

    @Test("a screenshot capture survives the round trip whole")
    func screenshotRoundTrip() throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }

        let capture = QueuedCapture(
            id: UUID(),
            capturedAt: Date(timeIntervalSince1970: 0),
            payload: .screenshot(
                QueuedCapture.Screenshot(fileName: "abc.png", note: "the badge said Mai")
            )
        )
        try queue.enqueue(capture)
        #expect(queue.pending() == [capture])
    }

    // A file name is read back off disk, so it is treated as untrusted input
    // even though the extension is the only thing that writes one. This pins
    // containment only: a name carrying a climb resolves to a *different* file
    // than the one stored under it, which the round-trip test above is what
    // actually guards.
    @Test("a file name resolves inside the container whatever it says")
    func pathTraversal() {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }

        let escaped = queue.imageURL(named: "../../secrets.plist").standardizedFileURL
        #expect(escaped.path.hasPrefix(root.standardizedFileURL.path))
    }
}
