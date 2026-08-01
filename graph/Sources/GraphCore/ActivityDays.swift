import Foundation

/// How many distinct calendar days a set of messages spans, in the caller's calendar. The one
/// definition of "distinct active days" shared by GraphBuilder (edge strength, liveness) and
/// PersonFilter (removal facts, liveness) -- previously three separate copies of the same
/// `Set(messages.map { calendar.startOfDay(for: $0.date) }).count` line.
public enum ActivityDays {
    /// The day set itself, not just its count: the acquaintance layer (AcquaintanceDerivation)
    /// needs to intersect two people's active days within one chat, which a bare count cannot
    /// support. distinctDays stays the thin wrapper every existing caller already uses.
    public static func daySet(_ messages: [RawMessage], calendar: Calendar) -> Set<Date> {
        Set(messages.map { calendar.startOfDay(for: $0.date) })
    }

    public static func distinctDays(_ messages: [RawMessage], calendar: Calendar) -> Int {
        daySet(messages, calendar: calendar).count
    }
}
