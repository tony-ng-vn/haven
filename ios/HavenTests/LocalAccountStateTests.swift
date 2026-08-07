import Foundation
import Testing
@testable import Haven

// What sign-out relies on to keep one account's directory and unsent
// captures from leaking into the next account signed in on the same phone.
// The Clerk sign-out call itself is not exercised here, the same way no test
// in this suite opens a real Convex connection -- see MyCardModel.signOut's
// own doc comment for where that half lives.

private func makeMirrorStore() -> (store: DirectoryMirrorStore, root: URL) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("haven-local-state-mirror-\(UUID().uuidString)")
    return (DirectoryMirrorStore(directory: root), root)
}

private func makeQueue() -> (queue: CaptureQueue, root: URL) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("haven-local-state-queue-\(UUID().uuidString)")
    return (CaptureQueue(directory: root), root)
}

private func manualCapture(_ handle: String) -> QueuedCapture {
    QueuedCapture(
        id: UUID(),
        capturedAt: Date(timeIntervalSince1970: 0),
        payload: .manual(
            QueuedCapture.Manual(
                name: "Someone",
                platform: "instagram",
                handleValue: handle,
                profileUrl: "",
                note: "met at a thing",
                attachToPersonId: nil
            )
        )
    )
}

@Suite("Clearing local account state")
struct LocalAccountStateTests {
    private let mirror = DirectoryMirror(
        refreshedAt: Date(timeIntervalSince1970: 0),
        people: [MirrorPerson(id: "p1", name: "Mai Tran", handles: [])]
    )

    @Test("clearing empties the mirror and every queue it is given")
    func clearsEverything() throws {
        let (store, storeRoot) = makeMirrorStore()
        defer { try? FileManager.default.removeItem(at: storeRoot) }
        let (queueOne, queueOneRoot) = makeQueue()
        defer { try? FileManager.default.removeItem(at: queueOneRoot) }
        let (queueTwo, queueTwoRoot) = makeQueue()
        defer { try? FileManager.default.removeItem(at: queueTwoRoot) }
        let eventRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("haven-local-state-events-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: eventRoot) }
        let events = EventStore(directory: eventRoot)

        try store.save(mirror)
        try queueOne.enqueue(manualCapture("left_behind_one"))
        try queueTwo.enqueue(manualCapture("left_behind_two"))
        _ = try events.start(title: "Private dinner", ownerUserId: "user-one")

        LocalAccountState.clear(
            mirror: store,
            queues: [queueOne, queueTwo],
            events: [events]
        )

        #expect(store.load() == nil)
        #expect(queueOne.pending().isEmpty)
        #expect(queueTwo.pending().isEmpty)
        #expect(events.currentActive() == nil)
    }

    // Most sessions on this phone never queue anything and never sync, so
    // this is the ordinary case, not the edge one -- a sign-out with nothing
    // to clear must not throw or leave a mess behind.
    @Test("clearing nothing is not a failure")
    func clearsNothingWithoutFailing() {
        let (store, storeRoot) = makeMirrorStore()
        defer { try? FileManager.default.removeItem(at: storeRoot) }
        let (queue, queueRoot) = makeQueue()
        defer { try? FileManager.default.removeItem(at: queueRoot) }

        LocalAccountState.clear(mirror: store, queues: [queue], events: [])

        #expect(store.load() == nil)
        #expect(queue.pending().isEmpty)
    }

    // The point of clearing at all: an account signing in after this one
    // must not inherit what was queued for the account that just signed out.
    @Test("a capture left by one account cannot drain into the next")
    func doesNotLeakBetweenAccounts() throws {
        let (queue, queueRoot) = makeQueue()
        defer { try? FileManager.default.removeItem(at: queueRoot) }

        try queue.enqueue(manualCapture("account_a_capture"))
        #expect(queue.pending().count == 1)

        LocalAccountState.clear(
            mirror: makeMirrorStore().store,
            queues: [queue],
            events: []
        )

        #expect(queue.pending().isEmpty, "a capture queued before sign-out must not survive it")
    }
}
