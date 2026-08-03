import Foundation
import SQLite3

/// Errors from opening or querying a read-only SQLite connection.
/// Carries no path or row data: only what step failed and the sqlite result code.
public enum SQLiteReadError: Error, Sendable, Equatable {
    case cannotOpen(code: Int32)
    case prepareFailed(code: Int32)
    case stepFailed(code: Int32)
    case busyTimedOut
}

/// A SQLite connection opened SQLITE_OPEN_READONLY only, never with CREATE, never immutable=1.
/// The real chat.db is a live WAL database; immutable silently drops the newest messages (constraint 2).
final class SQLiteReadOnlyConnection {
    private let db: OpaquePointer

    init(path: String) throws {
        var handle: OpaquePointer?
        let rc = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil)
        guard rc == SQLITE_OK, let handle else {
            if let handle {
                sqlite3_close(handle)
            }
            throw SQLiteReadError.cannotOpen(code: rc)
        }
        sqlite3_busy_timeout(handle, 5000)
        self.db = handle
    }

    deinit {
        sqlite3_close(db)
    }

    /// Runs a read-only SELECT, calling `row` once per result row. Retries on SQLITE_BUSY
    /// beyond the busy_timeout window rather than treating it as fatal.
    func query(_ sql: String, row: (OpaquePointer) throws -> Void) throws {
        var statement: OpaquePointer?
        let prepareRC = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard prepareRC == SQLITE_OK, let statement else {
            if let statement {
                sqlite3_finalize(statement)
            }
            throw SQLiteReadError.prepareFailed(code: prepareRC)
        }
        defer { sqlite3_finalize(statement) }

        var busyRetries = 0
        while true {
            let stepRC = sqlite3_step(statement)
            switch stepRC {
            case SQLITE_ROW:
                try row(statement)
            case SQLITE_DONE:
                return
            case SQLITE_BUSY:
                busyRetries += 1
                if busyRetries > 5 {
                    throw SQLiteReadError.busyTimedOut
                }
                usleep(100_000)
            default:
                throw SQLiteReadError.stepFailed(code: stepRC)
            }
        }
    }
}

extension OpaquePointer {
    /// Reads a nullable TEXT column, mapping SQL NULL to nil rather than an empty string.
    func columnText(_ index: Int32) -> String? {
        guard sqlite3_column_type(self, index) != SQLITE_NULL else { return nil }
        guard let cString = sqlite3_column_text(self, index) else { return nil }
        return String(cString: cString)
    }

    func columnInt64(_ index: Int32) -> Int64 {
        sqlite3_column_int64(self, index)
    }

    func columnNullableInt64(_ index: Int32) -> Int64? {
        guard sqlite3_column_type(self, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(self, index)
    }

    func columnInt(_ index: Int32) -> Int {
        Int(sqlite3_column_int(self, index))
    }

    /// Reads a nullable BLOB column (e.g. a contact photo) into Data, copying the bytes
    /// out before the statement is stepped again or finalized. A zero-length BLOB is
    /// distinct from SQL NULL: sqlite3_column_blob can return a NULL pointer for either,
    /// so length, not the pointer, decides whether to return empty Data or nil.
    func columnBlob(_ index: Int32) -> Data? {
        guard sqlite3_column_type(self, index) != SQLITE_NULL else { return nil }
        let length = Int(sqlite3_column_bytes(self, index))
        guard length > 0 else { return Data() }
        guard let bytes = sqlite3_column_blob(self, index) else { return Data() }
        return Data(bytes: bytes, count: length)
    }
}
