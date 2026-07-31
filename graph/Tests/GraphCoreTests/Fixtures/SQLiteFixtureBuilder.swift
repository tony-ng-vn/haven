import Foundation
import SQLite3

enum FixtureError: Error {
    case cannotCreate(code: Int32)
    case execFailed(String)
    case bindFailed
    case stepFailed(code: Int32)
}

/// sqlite3_bind_text with a nil destructor binds a dangling pointer; SQLITE_TRANSIENT
/// tells sqlite to copy the string immediately instead.
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A read-write SQLite file builder for test fixtures only. GraphCore's readers never
/// use this: they open SQLITE_OPEN_READONLY exclusively (constraint 2).
final class SQLiteFixtureBuilder {
    let url: URL
    private var db: OpaquePointer?

    init(fileName: String) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("graph-core-fixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent(fileName)

        var handle: OpaquePointer?
        let rc = sqlite3_open_v2(
            url.path,
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
            nil
        )
        guard rc == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw FixtureError.cannotCreate(code: rc)
        }
        db = handle
    }

    func exec(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if rc != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown sqlite error"
            sqlite3_free(errorMessage)
            throw FixtureError.execFailed(message)
        }
    }

    /// Runs a single parameterized statement, binding via the closure, then steps it once.
    func run(_ sql: String, bind: (OpaquePointer) -> Void = { _ in }) throws {
        var statement: OpaquePointer?
        let prepareRC = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard prepareRC == SQLITE_OK, let statement else {
            if let statement { sqlite3_finalize(statement) }
            throw FixtureError.bindFailed
        }
        defer { sqlite3_finalize(statement) }
        bind(statement)
        let stepRC = sqlite3_step(statement)
        guard stepRC == SQLITE_DONE else {
            throw FixtureError.stepFailed(code: stepRC)
        }
    }

    /// Closes the write handle so a later read-only open (and any byte-level hash check)
    /// sees a fully flushed, non-locked file.
    func close() {
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
    }
}
