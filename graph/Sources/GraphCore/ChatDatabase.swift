import Foundation
import SQLite3

/// Reads chat.db metadata into a ChatExtract. Never selects message.text or
/// message.attributedBody, and never uses SELECT * (constraint 3).
public struct ChatDatabase: Sendable {
    private let path: String

    public init(path: String) {
        self.path = path
    }

    public static func extract(path: String) throws -> ChatExtract {
        try ChatDatabase(path: path).extract()
    }

    public func extract() throws -> ChatExtract {
        let connection = try SQLiteReadOnlyConnection(path: path)
        let handles = try Self.readHandles(connection)
        let memberMap = try Self.readChatMembers(connection)
        let chats = try Self.readChats(connection, memberMap: memberMap)
        let messages = try Self.readMessages(connection)
        let unjoinedCount = try Self.readUnjoinedMessageCount(connection)
        let interactions = try Self.readInteractions(connection)
        return ChatExtract(
            handles: handles,
            chats: chats,
            messages: messages,
            unjoinedMessageCount: unjoinedCount,
            interactions: interactions
        )
    }

    private static func readHandles(_ connection: SQLiteReadOnlyConnection) throws -> [RawHandle] {
        var handles: [RawHandle] = []
        try connection.query("SELECT ROWID, id, service FROM handle ORDER BY ROWID") { statement in
            handles.append(
                RawHandle(
                    rowID: statement.columnInt64(0),
                    identifier: statement.columnText(1) ?? "",
                    service: statement.columnText(2) ?? ""
                )
            )
        }
        return handles
    }

    /// Roster from chat_handle_join, not message activity: a silent member still appears here.
    private static func readChatMembers(_ connection: SQLiteReadOnlyConnection) throws -> [Int64: [Int64]] {
        var memberMap: [Int64: [Int64]] = [:]
        try connection.query(
            "SELECT chat_id, handle_id FROM chat_handle_join ORDER BY ROWID"
        ) { statement in
            let chatID = statement.columnInt64(0)
            let handleID = statement.columnInt64(1)
            memberMap[chatID, default: []].append(handleID)
        }
        return memberMap
    }

    private static func readChats(
        _ connection: SQLiteReadOnlyConnection,
        memberMap: [Int64: [Int64]]
    ) throws -> [RawChat] {
        var chats: [RawChat] = []
        try connection.query(
            """
            SELECT ROWID, guid, style, chat_identifier, service_name, display_name
            FROM chat
            ORDER BY ROWID
            """
        ) { statement in
            let rowID = statement.columnInt64(0)
            chats.append(
                RawChat(
                    rowID: rowID,
                    guid: statement.columnText(1) ?? "",
                    style: statement.columnInt(2),
                    chatIdentifier: statement.columnText(3),
                    serviceName: statement.columnText(4),
                    displayName: statement.columnText(5),
                    memberHandleRowIDs: memberMap[rowID] ?? []
                )
            )
        }
        return chats
    }

    /// message.date is nanoseconds since the Apple epoch, 2001-01-01 00:00:00 UTC,
    /// which is also Foundation's reference date: no extra Unix-epoch offset needed.
    private static func date(fromAppleEpochNanoseconds ns: Int64) -> Date {
        Date(timeIntervalSinceReferenceDate: Double(ns) / 1_000_000_000)
    }

    /// One RawMessage per (message, chat_message_join) row: a message can join more than one
    /// chat, and each chat needs it in its own per-chat activity view for the stats layer.
    private static func readMessages(_ connection: SQLiteReadOnlyConnection) throws -> [RawMessage] {
        var messages: [RawMessage] = []
        try connection.query(
            """
            SELECT message.ROWID, chat_message_join.chat_id, message.handle_id,
                   message.is_from_me, message.date
            FROM message
            JOIN chat_message_join ON chat_message_join.message_id = message.ROWID
            ORDER BY message.ROWID
            """
        ) { statement in
            let rawHandleID = statement.columnNullableInt64(2)
            let handleID: Int64? = (rawHandleID == nil || rawHandleID == 0) ? nil : rawHandleID
            messages.append(
                RawMessage(
                    rowID: statement.columnInt64(0),
                    chatRowID: statement.columnInt64(1),
                    handleRowID: handleID,
                    isFromMe: statement.columnInt(3) != 0,
                    date: date(fromAppleEpochNanoseconds: statement.columnInt64(4))
                )
            )
        }
        return messages
    }

    /// Tapback ADD types (a reaction being applied); REMOVE types (a reaction being retracted,
    /// >= 3000) are deliberately excluded -- a retracted reaction is not evidence anyone still
    /// endorses it.
    private static let tapbackAddTypeRange: ClosedRange<Int> = 2000...2999

    /// Resolved tapback/reply interactions: metadata only, message.text/attributedBody never
    /// selected (constraint 3). Two extra full-ish passes over `message` (a plain per-guid scan,
    /// then a WHERE-filtered scan helped by the real db's own indexes on thread_originator_guid
    /// and associated_message_guid IS NOT NULL) -- no O(people x messages) rescan.
    private static func readInteractions(_ connection: SQLiteReadOnlyConnection) throws -> [RawInteraction] {
        // Pass 1: every message's own guid -> (handleRowID, isFromMe), used only to resolve a
        // tapback/reply's TARGET (the message it points at). Built from the whole table, not
        // just joined rows: a target can in principle be a message this extractor otherwise
        // never surfaces (e.g. itself unjoined), and this map is purely a lookup, never emitted.
        var senderByGUID: [String: (handleRowID: Int64?, isFromMe: Bool)] = [:]
        try connection.query("SELECT guid, handle_id, is_from_me FROM message") { statement in
            guard let guid = statement.columnText(0) else { return }
            let rawHandleID = statement.columnNullableInt64(1)
            let handleID: Int64? = (rawHandleID == nil || rawHandleID == 0) ? nil : rawHandleID
            senderByGUID[guid] = (handleRowID: handleID, isFromMe: statement.columnInt(2) != 0)
        }

        var interactions: [RawInteraction] = []
        try connection.query(
            """
            SELECT message.ROWID, chat_message_join.chat_id, message.handle_id, message.is_from_me,
                   message.date, message.associated_message_guid, message.associated_message_type,
                   message.thread_originator_guid
            FROM message
            JOIN chat_message_join ON chat_message_join.message_id = message.ROWID
            WHERE (message.associated_message_type BETWEEN 2000 AND 2999 AND message.associated_message_guid IS NOT NULL)
               OR message.thread_originator_guid IS NOT NULL
            ORDER BY message.ROWID
            """
        ) { statement in
            let chatRowID = statement.columnInt64(1)
            let rawActorHandleID = statement.columnNullableInt64(2)
            let actorHandleRowID: Int64? = (rawActorHandleID == nil || rawActorHandleID == 0) ? nil : rawActorHandleID
            let associatedGuid = statement.columnText(5)
            let associatedType = statement.columnInt(6)
            let threadOriginatorGuid = statement.columnText(7)

            // A row that is BOTH a tapback add and a reply (unseen in practice, Apple's schema
            // does not forbid it) resolves via the tapback target only -- one interaction per
            // row, never two, so a single ambiguous row cannot double-count a pair.
            let targetGuid: String?
            if tapbackAddTypeRange.contains(associatedType), let associatedGuid {
                targetGuid = stripGUIDPrefix(associatedGuid)
            } else if let threadOriginatorGuid {
                targetGuid = stripGUIDPrefix(threadOriginatorGuid) // already bare; stripping is a no-op
            } else {
                targetGuid = nil
            }
            guard let targetGuid, let target = senderByGUID[targetGuid] else { return } // unresolvable: skip silently
            let targetHandleRowID: Int64? = target.isFromMe ? nil : target.handleRowID

            guard actorHandleRowID != targetHandleRowID else { return } // same raw handle (or both the user): self, dropped here

            interactions.append(
                RawInteraction(
                    chatRowID: chatRowID,
                    actorHandleRowID: actorHandleRowID,
                    targetHandleRowID: targetHandleRowID,
                    date: date(fromAppleEpochNanoseconds: statement.columnInt64(4))
                )
            )
        }
        return interactions
    }

    /// Apple prefixes a tapback's associated_message_guid with "p:0/", "p:1/", or "bp:";
    /// thread_originator_guid is already bare. Strip a "/"-prefixed form first (keep only the
    /// substring after the LAST "/"), else strip a leading "bp:", else use the guid as given --
    /// a bare guid matches neither rule and passes through unchanged either way.
    private static func stripGUIDPrefix(_ raw: String) -> String {
        if let slashIndex = raw.lastIndex(of: "/") {
            return String(raw[raw.index(after: slashIndex)...])
        }
        if raw.hasPrefix("bp:") {
            return String(raw.dropFirst(3))
        }
        return raw
    }

    private static func readUnjoinedMessageCount(_ connection: SQLiteReadOnlyConnection) throws -> Int {
        var count = 0
        try connection.query(
            """
            SELECT COUNT(*)
            FROM message
            WHERE NOT EXISTS (
                SELECT 1 FROM chat_message_join
                WHERE chat_message_join.message_id = message.ROWID
            )
            """
        ) { statement in
            count = statement.columnInt(0)
        }
        return count
    }
}
