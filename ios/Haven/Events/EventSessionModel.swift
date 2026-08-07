import Foundation
import SwiftUI

@MainActor
final class EventSessionModel: ObservableObject {
    @Published private(set) var active: HavenEvent?
    @Published private(set) var failure: String?

    let userId: String
    private let store: EventStore

    init(userId: String, store: EventStore = .forApp()) {
        self.userId = userId
        self.store = store
        active = store.active(for: userId)
    }

    var isActive: Bool { active != nil }

    @discardableResult
    func start(title: String, startedAt: Date = Date()) -> Bool {
        failure = nil
        do {
            active = try store.start(
                title: title,
                ownerUserId: userId,
                startedAt: startedAt
            )
            return true
        } catch EventStoreError.blankTitle {
            failure = "Give the event a name first."
        } catch EventStoreError.titleTooLong {
            failure = "Keep the event name under 200 characters."
        } catch EventStoreError.alreadyActive {
            failure = "End the current event before starting another one."
        } catch {
            failure = "Haven could not start that event. Try again."
        }
        return false
    }

    @discardableResult
    func end(endedAt: Date = Date()) -> Bool {
        guard let active else { return false }
        failure = nil
        do {
            _ = try store.end(
                eventId: active.id,
                ownerUserId: userId,
                endedAt: endedAt
            )
            self.active = nil
            return true
        } catch {
            failure = "Haven could not end that event. Try again."
            return false
        }
    }
}
