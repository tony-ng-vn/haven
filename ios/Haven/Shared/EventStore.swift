import Foundation

enum EventSourceProvider: String, Codable, Equatable, Sendable {
    case appleCalendar
}

/// The minimum durable snapshot needed to distinguish a selected calendar
/// occurrence from another event with the same title. Haven keeps no attendee,
/// note, location, or calendar-account data.
struct EventSourceReference: Codable, Equatable, Sendable {
    let provider: EventSourceProvider
    let externalId: String
    let scheduledStartAt: Date
    let scheduledEndAt: Date
}

/// The event identity stamped onto a capture before the capture leaves the
/// device. It contains only what the backend needs to idempotently recreate the
/// event when the phone was offline at Start.
struct EventReference: Codable, Equatable, Sendable {
    let clientKey: String
    let title: String
    let startedAt: Date
    let source: EventSourceReference?

    init(
        clientKey: String,
        title: String,
        startedAt: Date,
        source: EventSourceReference? = nil
    ) {
        self.clientKey = clientKey
        self.title = title
        self.startedAt = startedAt
        self.source = source
    }
}

/// One local event session. The owner stays on device for account isolation;
/// Convex always derives ownership from the authenticated request instead.
struct HavenEvent: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let ownerUserId: String
    let title: String
    let startedAt: Date
    let source: EventSourceReference?
    var endedAt: Date?
    var needsSync: Bool

    var reference: EventReference {
        EventReference(
            clientKey: id.uuidString,
            title: title,
            startedAt: startedAt,
            source: source
        )
    }
}

enum EventStoreError: Error, Equatable {
    case blankTitle
    case titleTooLong
    case alreadyActive
    case endsBeforeStart
    case invalidSource
}

/// Durable event state shared with HavenShare.
///
/// One atomic file is safe here because only the app writes it. The extension
/// reads the active event while it writes a separate capture file, so it sees
/// either the previous complete snapshot or the next complete snapshot.
struct EventStore: Sendable {
    private let directory: URL
    private static let titleLimit = 200
    private static let historyLimit = 200

    init(directory: URL) {
        self.directory = directory
    }

    static func inAppGroup() -> EventStore? {
        guard let container = HavenAppGroup.containerURL else { return nil }
        return EventStore(directory: container.appendingPathComponent("events"))
    }

    static func forApp() -> EventStore {
        inAppGroup()
            ?? EventStore(directory: HavenAppGroup.appContainerURL.appendingPathComponent("events"))
    }

    static func drainable() -> [EventStore] {
        let privateStore = EventStore(
            directory: HavenAppGroup.appContainerURL.appendingPathComponent("events")
        )
        guard let shared = inAppGroup() else { return [privateStore] }
        return [shared, privateStore]
    }

    func active(for ownerUserId: String) -> HavenEvent? {
        load().events
            .filter { $0.ownerUserId == ownerUserId && $0.endedAt == nil }
            .max { $0.startedAt < $1.startedAt }
    }

    /// Used by the share extension, which cannot read Clerk. The newest active
    /// session is the one the app put on screen most recently.
    func currentActive() -> HavenEvent? {
        load().events
            .filter { $0.endedAt == nil }
            .max { $0.startedAt < $1.startedAt }
    }

    func needingSync(for ownerUserId: String) -> [HavenEvent] {
        load().events
            .filter { $0.ownerUserId == ownerUserId && $0.needsSync }
            .sorted { $0.startedAt < $1.startedAt }
    }

    @discardableResult
    func start(
        title rawTitle: String,
        ownerUserId: String,
        startedAt: Date = Date(),
        id: UUID = UUID(),
        source: EventSourceReference? = nil
    ) throws -> HavenEvent {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw EventStoreError.blankTitle }
        // JavaScript validates UTF-16 code units. Match it here so a title
        // accepted offline cannot become an event that Convex rejects forever.
        guard title.utf16.count <= Self.titleLimit else {
            throw EventStoreError.titleTooLong
        }
        if let source {
            guard !source.externalId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  source.externalId.utf16.count <= 1_024,
                  source.scheduledEndAt >= source.scheduledStartAt else {
                throw EventStoreError.invalidSource
            }
        }
        var snapshot = load()
        guard !snapshot.events.contains(where: {
            $0.ownerUserId == ownerUserId && $0.endedAt == nil
        }) else {
            throw EventStoreError.alreadyActive
        }
        let event = HavenEvent(
            id: id,
            ownerUserId: ownerUserId,
            title: title,
            startedAt: startedAt,
            source: source,
            endedAt: nil,
            needsSync: true
        )
        snapshot.events.append(event)
        trim(&snapshot.events)
        try save(snapshot)
        return event
    }

    @discardableResult
    func end(
        eventId: UUID,
        ownerUserId: String,
        endedAt: Date = Date()
    ) throws -> HavenEvent? {
        var snapshot = load()
        guard let index = snapshot.events.firstIndex(where: {
            $0.id == eventId && $0.ownerUserId == ownerUserId
        }) else { return nil }
        guard endedAt >= snapshot.events[index].startedAt else {
            throw EventStoreError.endsBeforeStart
        }
        snapshot.events[index].endedAt = endedAt
        snapshot.events[index].needsSync = true
        let event = snapshot.events[index]
        try save(snapshot)
        return event
    }

    @discardableResult
    func markSynced(
        eventId: UUID,
        ownerUserId: String,
        expectedEndedAt: Date?
    ) throws -> Bool {
        var snapshot = load()
        guard let index = snapshot.events.firstIndex(where: {
            $0.id == eventId && $0.ownerUserId == ownerUserId
        }) else { return true }
        guard snapshot.events[index].endedAt == expectedEndedAt else { return false }
        snapshot.events[index].needsSync = false
        try save(snapshot)
        return true
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private struct Snapshot: Codable {
        var events: [HavenEvent] = []
    }

    private var fileURL: URL { directory.appendingPathComponent("sessions.json") }

    private func load() -> Snapshot {
        guard let data = try? Data(contentsOf: fileURL) else { return Snapshot() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Snapshot.self, from: data)) ?? Snapshot()
    }

    private func save(_ snapshot: Snapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }

    private func trim(_ events: inout [HavenEvent]) {
        let completed = events
            .filter { $0.endedAt != nil }
            .sorted { $0.startedAt > $1.startedAt }
        let keepCompleted = Set(completed.prefix(Self.historyLimit).map(\.id))
        events.removeAll { $0.endedAt != nil && !keepCompleted.contains($0.id) }
    }
}
