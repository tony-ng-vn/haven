import Foundation

struct CalendarEventCandidate: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool

    var source: EventSourceReference {
        EventSourceReference(
            provider: .appleCalendar,
            externalId: id,
            scheduledStartAt: start,
            scheduledEndAt: end
        )
    }

    static func ranked(
        _ candidates: [CalendarEventCandidate],
        around now: Date
    ) -> [CalendarEventCandidate] {
        candidates.sorted { left, right in
            let leftBucket = left.rankBucket(around: now)
            let rightBucket = right.rankBucket(around: now)
            if leftBucket != rightBucket { return leftBucket < rightBucket }

            let leftDate = left.rankDate(for: leftBucket)
            let rightDate = right.rankDate(for: rightBucket)
            if leftDate != rightDate {
                return leftBucket == 0 || leftBucket == 3
                    ? leftDate > rightDate
                    : leftDate < rightDate
            }

            let leftTitle = left.title.lowercased()
            let rightTitle = right.title.lowercased()
            if leftTitle != rightTitle { return leftTitle < rightTitle }
            return left.id < right.id
        }
    }

    private func rankBucket(around now: Date) -> Int {
        if isAllDay { return 2 }
        if start <= now, end >= now { return 0 }
        if start > now { return 1 }
        return 3
    }

    private func rankDate(for bucket: Int) -> Date {
        bucket == 3 ? end : start
    }
}
