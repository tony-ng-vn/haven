import Foundation
import SQLite3

/// One sampled message, kept only long enough to build one guess prompt (see GuessEngine):
/// never stored, never logged, never written anywhere. `text` is intentionally the only
/// place in this entire project that a message's actual words exist as a value.
public struct Snippet: Sendable, Equatable {
    public let text: String
    public let isFromMe: Bool

    public init(text: String, isFromMe: Bool) {
        self.text = text
        self.isFromMe = isFromMe
    }
}

// LOUD NOTICE: this is the ONLY file in the entire project allowed to SELECT message.text or
// message.attributedBody. Every other reader (ChatDatabase, ExtractStats, ...) deliberately
// never touches either column (constraint 3) so the working model can never carry message
// content. SnippetReader is the sole, explicit exception, and only for the duration of
// building one guess prompt (see GuessEngine, GuessPrompt): read here, used immediately,
// never persisted. attributedBody is decoded by AttributedBodyDecoder, a pure function with
// no I/O of its own -- decoding happens here, in the same transient scope, never earlier.
public enum SnippetReader {
    /// Reads up to `limit` of the most recent messages (by date, descending) across the given
    /// chats. `text` is preferred when present (the common case for the ~2% of messages Messages
    /// still stores as plain text); when it is NULL, `attributedBody` is decoded as a fallback
    /// (AttributedBodyDecoder, the ~98% case). A message that yields neither -- no plain text,
    /// no attributedBody, an attributedBody AttributedBodyDecoder cannot read, or one that
    /// decodes to blank -- is simply invisible to the model pass, not an error.
    public static func read(dbPath: String, chatRowIDs: Set<Int64>, limit: Int = 20) throws -> [Snippet] {
        guard !chatRowIDs.isEmpty else { return [] }
        let connection = try SQLiteReadOnlyConnection(path: dbPath)

        // chatRowIDs and limit are internally-generated Int64/Int values (AppModel's own
        // candidate assembly), never external/user input, so interpolating them here is the
        // same posture ContactsDatabase already takes with its own internally-read entity id.
        let idsClause = chatRowIDs.sorted().map(String.init).joined(separator: ",")
        var snippets: [Snippet] = []
        try connection.query(
            """
            SELECT DISTINCT message.text, message.attributedBody, message.is_from_me, message.date
            FROM message
            JOIN chat_message_join ON chat_message_join.message_id = message.ROWID
            WHERE chat_message_join.chat_id IN (\(idsClause))
              AND (message.text IS NOT NULL OR message.attributedBody IS NOT NULL)
            ORDER BY message.date DESC
            LIMIT \(limit)
            """
        ) { statement in
            // DISTINCT includes message.date precisely so the same message, joined into two
            // of the requested chats (a merged, multi-service person can own several -- see
            // ChatDatabase's own "a message can join more than one chat" note), is not
            // sampled twice: text+is_from_me+date together identify one real message.
            let text = resolvedText(statement)
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            snippets.append(Snippet(text: text, isFromMe: statement.columnInt(2) != 0))
        }
        // LIMIT is applied by the query above (on rows read from the table, before this
        // resolution step), not re-applied here: a row that turns out to carry no usable text
        // after decoding simply yields fewer snippets than `limit`, it does not get replaced by
        // the next-oldest row -- the same trade the old NULL-text WHERE clause already made.
        return snippets
    }

    private static func resolvedText(_ statement: OpaquePointer) -> String? {
        if let plain = statement.columnText(0) {
            return plain
        }
        guard let blob = statement.columnBlob(1) else { return nil }
        return AttributedBodyDecoder.decodeMessageText(from: blob)
    }
}
