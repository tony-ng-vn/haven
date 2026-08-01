import Foundation

/// How many distinct calendar days a set of messages spans, in the caller's calendar. The one
/// definition of "distinct active days" shared by GraphBuilder (edge strength, liveness) and
/// PersonFilter (removal facts, liveness) -- previously three separate copies of the same
/// `Set(messages.map { calendar.startOfDay(for: $0.date) }).count` line.
public enum ActivityDays {
    public static func distinctDays(_ messages: [RawMessage], calendar: Calendar) -> Int {
        Set(messages.map { calendar.startOfDay(for: $0.date) }).count
    }
}
