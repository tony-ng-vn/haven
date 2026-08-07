import Foundation
import Testing
@testable import Haven

@Suite("Event sessions")
struct EventSessionTests {
    @Test("an event survives relaunch and is scoped to its account")
    func activeEventPersists() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EventStore(directory: directory)
        let startedAt = Date(timeIntervalSince1970: 1_000)

        let event = try store.start(
            title: "  Founders dinner  ",
            ownerUserId: "user-one",
            startedAt: startedAt,
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )

        #expect(event.title == "Founders dinner")
        #expect(EventStore(directory: directory).active(for: "user-one") == event)
        #expect(EventStore(directory: directory).active(for: "user-two") == nil)
    }

    @Test("ending an event stops future captures and leaves a pending sync record")
    func endEvent() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EventStore(directory: directory)
        let event = try store.start(
            title: "Demo day",
            ownerUserId: "user-one",
            startedAt: Date(timeIntervalSince1970: 2_000)
        )

        let ended = try store.end(
            eventId: event.id,
            ownerUserId: "user-one",
            endedAt: Date(timeIntervalSince1970: 2_600)
        )

        #expect(store.active(for: "user-one") == nil)
        #expect(ended?.endedAt == Date(timeIntervalSince1970: 2_600))
        #expect(store.needingSync(for: "user-one") == ended.map { [$0] })
    }

    @Test("the capture queue stamps the active event at enqueue time")
    func captureStamp() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let eventStore = EventStore(directory: root.appendingPathComponent("events"))
        let queue = CaptureQueue(
            directory: root.appendingPathComponent("captures"),
            eventStore: eventStore,
            ownerUserId: { "user-one" }
        )
        let event = try eventStore.start(
            title: "Community night",
            ownerUserId: "user-one",
            startedAt: Date(timeIntervalSince1970: 3_000)
        )
        let capture = QueuedCapture(
            id: UUID(),
            capturedAt: Date(timeIntervalSince1970: 3_100),
            payload: .manual(
                .init(
                    name: "Maya",
                    platform: "instagram",
                    handleValue: "maya",
                    profileUrl: "https://instagram.com/maya",
                    note: nil,
                    attachToPersonId: nil
                )
            )
        )

        try queue.enqueue(capture)

        #expect(queue.pending().first?.event == event.reference)
    }

    @Test("an authenticated app capture never falls back to another account's event")
    func captureDoesNotCrossAccounts() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let eventStore = EventStore(directory: root.appendingPathComponent("events"))
        let queue = CaptureQueue(
            directory: root.appendingPathComponent("captures"),
            eventStore: eventStore,
            ownerUserId: { "user-two" }
        )
        _ = try eventStore.start(
            title: "Account one's event",
            ownerUserId: "user-one",
            startedAt: Date(timeIntervalSince1970: 4_000)
        )

        try queue.enqueue(QueuedCapture(
            id: UUID(),
            capturedAt: Date(timeIntervalSince1970: 4_100),
            payload: .manual(
                .init(
                    name: "Maya",
                    platform: "instagram",
                    handleValue: "maya",
                    profileUrl: "",
                    note: nil,
                    attachToPersonId: nil
                )
            )
        ))

        #expect(queue.pending().first?.event == nil)
    }

    @Test("acknowledging a start snapshot does not clear a newer pending end")
    func staleSyncAcknowledgement() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EventStore(directory: directory)
        let started = try store.start(
            title: "Launch night",
            ownerUserId: "user-one",
            startedAt: Date(timeIntervalSince1970: 5_000)
        )
        let ended = try #require(try store.end(
            eventId: started.id,
            ownerUserId: "user-one",
            endedAt: Date(timeIntervalSince1970: 5_500)
        ))

        try store.markSynced(
            eventId: started.id,
            ownerUserId: started.ownerUserId,
            expectedEndedAt: started.endedAt
        )

        #expect(store.needingSync(for: "user-one") == [ended])
    }

    @Test("event title length matches the backend UTF-16 limit")
    func titleUsesBackendLengthUnit() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let title = String(repeating: "\u{1F680}", count: 101)

        #expect(throws: EventStoreError.titleTooLong) {
            try EventStore(directory: directory).start(
                title: title,
                ownerUserId: "user-one"
            )
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-event-tests-\(UUID().uuidString)")
    }
}
