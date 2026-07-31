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
        return ChatExtract(
            handles: handles,
            chats: chats,
            messages: messages,
            unjoinedMessageCount: unjoinedCount
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
