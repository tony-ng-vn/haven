import EventKit
import Foundation

actor AppleCalendarProvider: AppleCalendarProviding {
    static let shared = AppleCalendarProvider()
    private static let sourceIdLimit = 1_024

    private let store: EKEventStore

    init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    func accessStatus() -> AppleCalendarAccess {
        Self.access(from: EKEventStore.authorizationStatus(for: .event))
    }

    func requestFullAccess() async throws -> AppleCalendarAccess {
        let granted = try await store.requestFullAccessToEvents()
        return granted ? .fullAccess : .denied
    }

    func nearbyEvents(around date: Date) -> [CalendarEventCandidate] {
        let start = date.addingTimeInterval(-3 * 60 * 60)
        let end = date.addingTimeInterval(8 * 60 * 60)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let candidates = store.events(matching: predicate).compactMap {
            (event: EKEvent) -> CalendarEventCandidate? in
            guard Self.includes(status: event.status) else { return nil }
            let sourceId = Self.sourceId(for: event)
            guard !sourceId.isEmpty,
                  sourceId.utf16.count <= Self.sourceIdLimit,
                  event.endDate >= event.startDate else { return nil }
            return CalendarEventCandidate(
                id: sourceId,
                title: Self.title(for: event),
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay
            )
        }
        return Array(CalendarEventCandidate.ranked(candidates, around: date).prefix(12))
    }

    static func includes(status: EKEventStatus) -> Bool {
        status != .canceled
    }

    private static func sourceId(for event: EKEvent) -> String {
        let raw = event.eventIdentifier
            ?? "\(event.calendarItemIdentifier)#\(event.startDate.timeIntervalSinceReferenceDate)"
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func access(from status: EKAuthorizationStatus) -> AppleCalendarAccess {
        switch status {
        case .fullAccess, .authorized:
            return .fullAccess
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted, .writeOnly:
            return .denied
        @unknown default:
            return .denied
        }
    }

    private static func title(for event: EKEvent) -> String {
        nonBlank(event.title) ?? "Untitled event"
    }

    private static func nonBlank(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
