import Foundation
import SQLite3

/// Builds a synthetic chat.db-shaped SQLite file in a temp directory, mirroring the
/// real schema subset from GOAL.md, including text/attributedBody so extraction
/// provably ignores them (constraint 3, test case 9).
final class ChatDBFixture {
    private let builder: SQLiteFixtureBuilder
    var url: URL { builder.url }

    init() throws {
        builder = try SQLiteFixtureBuilder(fileName: "chat.db")
        try builder.exec(
            """
            CREATE TABLE handle (
                ROWID INTEGER PRIMARY KEY,
                id TEXT,
                country TEXT,
                service TEXT
            );
            CREATE TABLE chat (
                ROWID INTEGER PRIMARY KEY,
                guid TEXT,
                style INTEGER,
                chat_identifier TEXT,
                service_name TEXT,
                display_name TEXT
            );
            CREATE TABLE chat_handle_join (
                chat_id INTEGER,
                handle_id INTEGER,
                UNIQUE(chat_id, handle_id)
            );
            CREATE TABLE message (
                ROWID INTEGER PRIMARY KEY,
                guid TEXT,
                text TEXT,
                attributedBody BLOB,
                handle_id INTEGER,
                service TEXT,
                date INTEGER,
                is_from_me INTEGER,
                associated_message_guid TEXT,
                associated_message_type INTEGER DEFAULT 0,
                thread_originator_guid TEXT
            );
            CREATE TABLE chat_message_join (
                chat_id INTEGER,
                message_id INTEGER,
                message_date INTEGER
            );
            """
        )
    }

    func close() {
        builder.close()
    }

    func insertHandle(rowID: Int64, id: String, service: String, country: String? = nil) throws {
        try builder.run(
            "INSERT INTO handle (ROWID, id, country, service) VALUES (?, ?, ?, ?)"
        ) { statement in
            sqlite3_bind_int64(statement, 1, rowID)
            sqlite3_bind_text(statement, 2, id, -1, SQLITE_TRANSIENT)
            if let country {
                sqlite3_bind_text(statement, 3, country, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 3)
            }
            sqlite3_bind_text(statement, 4, service, -1, SQLITE_TRANSIENT)
        }
    }

    func insertChat(
        rowID: Int64,
        guid: String,
        style: Int,
        chatIdentifier: String? = nil,
        serviceName: String? = nil,
        displayName: String? = nil
    ) throws {
        try builder.run(
            """
            INSERT INTO chat (ROWID, guid, style, chat_identifier, service_name, display_name)
            VALUES (?, ?, ?, ?, ?, ?)
            """
        ) { statement in
            sqlite3_bind_int64(statement, 1, rowID)
            sqlite3_bind_text(statement, 2, guid, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(statement, 3, Int64(style))
            Self.bindOptionalText(statement, 4, chatIdentifier)
            Self.bindOptionalText(statement, 5, serviceName)
            Self.bindOptionalText(statement, 6, displayName)
        }
    }

    func insertChatHandleJoin(chatID: Int64, handleID: Int64) throws {
        try builder.run(
            "INSERT INTO chat_handle_join (chat_id, handle_id) VALUES (?, ?)"
        ) { statement in
            sqlite3_bind_int64(statement, 1, chatID)
            sqlite3_bind_int64(statement, 2, handleID)
        }
    }

    /// handleID nil mirrors a from-me row where handle_id is 0 or NULL in the real db.
    /// associatedMessageGuid/associatedMessageType model a tapback (ADD is 2000-2999, REMOVE is
    /// 3000+); threadOriginatorGuid models a threaded reply. Both default to "this is a plain
    /// message, neither a tapback nor a reply" so every existing call site is unaffected.
    func insertMessage(
        rowID: Int64,
        guid: String = UUID().uuidString,
        text: String? = nil,
        attributedBody: Data? = nil,
        handleID: Int64?,
        service: String,
        dateNanoseconds: Int64,
        isFromMe: Bool,
        associatedMessageGuid: String? = nil,
        associatedMessageType: Int = 0,
        threadOriginatorGuid: String? = nil
    ) throws {
        try builder.run(
            """
            INSERT INTO message (
                ROWID, guid, text, attributedBody, handle_id, service, date, is_from_me,
                associated_message_guid, associated_message_type, thread_originator_guid
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        ) { statement in
            sqlite3_bind_int64(statement, 1, rowID)
            sqlite3_bind_text(statement, 2, guid, -1, SQLITE_TRANSIENT)
            Self.bindOptionalText(statement, 3, text)
            if let attributedBody {
                attributedBody.withUnsafeBytes { rawBuffer in
                    _ = sqlite3_bind_blob(
                        statement, 4, rawBuffer.baseAddress, Int32(rawBuffer.count), SQLITE_TRANSIENT
                    )
                }
            } else {
                sqlite3_bind_null(statement, 4)
            }
            if let handleID {
                sqlite3_bind_int64(statement, 5, handleID)
            } else {
                sqlite3_bind_null(statement, 5)
            }
            sqlite3_bind_text(statement, 6, service, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(statement, 7, dateNanoseconds)
            sqlite3_bind_int64(statement, 8, isFromMe ? 1 : 0)
            Self.bindOptionalText(statement, 9, associatedMessageGuid)
            sqlite3_bind_int64(statement, 10, Int64(associatedMessageType))
            Self.bindOptionalText(statement, 11, threadOriginatorGuid)
        }
    }

    func insertChatMessageJoin(chatID: Int64, messageID: Int64, messageDate: Int64 = 0) throws {
        try builder.run(
            "INSERT INTO chat_message_join (chat_id, message_id, message_date) VALUES (?, ?, ?)"
        ) { statement in
            sqlite3_bind_int64(statement, 1, chatID)
            sqlite3_bind_int64(statement, 2, messageID)
            sqlite3_bind_int64(statement, 3, messageDate)
        }
    }

    private static func bindOptionalText(_ statement: OpaquePointer, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }
}
