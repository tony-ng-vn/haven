import Foundation

/// Restricts a ChatExtract to messages within an inclusive date range, leaving everything
/// else (handles, chat rosters, unjoinedMessageCount) untouched. Downstream (PersonFilter,
/// GraphBuilder) needs no changes: a person or group whose only activity falls outside the
/// window simply has no messages to count, and trips the existing neverReplied/notLive
/// rules on its own.
public enum TimeFilter {
    public static func apply(extract: ChatExtract, from: Date, to: Date) -> ChatExtract {
        ChatExtract(
            handles: extract.handles,
            chats: extract.chats,
            messages: extract.messages.filter { $0.date >= from && $0.date <= to },
            unjoinedMessageCount: extract.unjoinedMessageCount
        )
    }
}
