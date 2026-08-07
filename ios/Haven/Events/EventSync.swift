import ConvexMobile
import SwiftUI

struct EventSyncRequest {
    var run: () async -> Void = {}
}

private struct EventSyncRequestKey: EnvironmentKey {
    static let defaultValue = EventSyncRequest()
}

extension EnvironmentValues {
    var requestEventSync: EventSyncRequest {
        get { self[EventSyncRequestKey.self] }
        set { self[EventSyncRequestKey.self] = newValue }
    }
}

/// Sends locally durable event lifecycle changes to Convex. A failed pass does
/// not clear needsSync, so launch and foreground retry without asking the user
/// to reconstruct an event that already ended.
@MainActor
final class EventSync: ObservableObject {
    private let store: EventStore
    private var isRunning = false
    private var runAgain = false

    init(store: EventStore = .forApp()) {
        self.store = store
    }

    func run(userId: String) async {
        guard !isRunning else {
            runAgain = true
            return
        }
        isRunning = true
        defer { isRunning = false }

        repeat {
            runAgain = false
            for event in store.needingSync(for: userId) {
                var args = event.reference.convexArguments
                if let endedAt = event.endedAt {
                    args["endedAt"] = endedAt.timeIntervalSince1970 * 1_000
                }
                let arguments = args
                let work = Task { () throws -> EventUpsertOutcome in
                    try await convex.mutation("events:upsert", with: arguments)
                }
                guard await work.value(within: .seconds(HavenNetwork.deadline)) != nil else {
                    continue
                }
                do {
                    let matched = try store.markSynced(
                        eventId: event.id,
                        ownerUserId: userId,
                        expectedEndedAt: event.endedAt
                    )
                    if !matched { runAgain = true }
                } catch {
                    // The local record stays pending and the next launch or
                    // foreground pass retries it.
                }
            }
        } while runAgain
    }
}

private struct EventUpsertOutcome: Decodable {
    let status: String
    let eventId: String
}
