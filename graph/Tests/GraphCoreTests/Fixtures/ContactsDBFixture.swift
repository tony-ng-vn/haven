import Foundation
import SQLite3

/// Builds a synthetic AddressBook-v22.abcddb-shaped SQLite file in a temp directory.
final class ContactsDBFixture {
    private let builder: SQLiteFixtureBuilder
    var url: URL { builder.url }

    init() throws {
        builder = try SQLiteFixtureBuilder(fileName: "AddressBook-v22.abcddb")
        try builder.exec(
            """
            CREATE TABLE Z_PRIMARYKEY (
                Z_ENT INTEGER PRIMARY KEY,
                Z_NAME TEXT
            );
            CREATE TABLE ZABCDRECORD (
                Z_PK INTEGER PRIMARY KEY,
                Z_ENT INTEGER,
                ZUNIQUEID TEXT,
                ZFIRSTNAME TEXT,
                ZLASTNAME TEXT,
                ZORGANIZATION TEXT,
                ZNICKNAME TEXT,
                ZTHUMBNAILIMAGEDATA BLOB
            );
            CREATE TABLE ZABCDPHONENUMBER (
                Z_PK INTEGER PRIMARY KEY,
                ZOWNER INTEGER,
                ZFULLNUMBER TEXT
            );
            CREATE TABLE ZABCDEMAILADDRESS (
                Z_PK INTEGER PRIMARY KEY,
                ZOWNER INTEGER,
                ZADDRESS TEXT
            );
            """
        )
    }

    func close() {
        builder.close()
    }

    /// A Core Data entity row: ZABCDRECORD is shared by several entities (ABCDContact,
    /// ABCDInfo, ABCDGroup, CNCDContainer in the real store), distinguished only by Z_ENT.
    func insertEntity(entityID: Int64, name: String) throws {
        try builder.run(
            "INSERT INTO Z_PRIMARYKEY (Z_ENT, Z_NAME) VALUES (?, ?)"
        ) { statement in
            sqlite3_bind_int64(statement, 1, entityID)
            sqlite3_bind_text(statement, 2, name, -1, SQLITE_TRANSIENT)
        }
    }

    /// uniqueID is required (no default), not optional-with-a-default: every call site must
    /// say explicitly whether this row has a ZUNIQUEID, since a nil here is what the
    /// null-uniqueID-is-skipped test exercises.
    func insertRecord(
        recordID: Int64,
        entityID: Int64,
        uniqueID: String?,
        firstName: String? = nil,
        lastName: String? = nil,
        organization: String? = nil,
        nickname: String? = nil,
        thumbnailImageData: Data? = nil
    ) throws {
        try builder.run(
            """
            INSERT INTO ZABCDRECORD
                (Z_PK, Z_ENT, ZUNIQUEID, ZFIRSTNAME, ZLASTNAME, ZORGANIZATION, ZNICKNAME, ZTHUMBNAILIMAGEDATA)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """
        ) { statement in
            sqlite3_bind_int64(statement, 1, recordID)
            sqlite3_bind_int64(statement, 2, entityID)
            Self.bindOptionalText(statement, 3, uniqueID)
            Self.bindOptionalText(statement, 4, firstName)
            Self.bindOptionalText(statement, 5, lastName)
            Self.bindOptionalText(statement, 6, organization)
            Self.bindOptionalText(statement, 7, nickname)
            if let thumbnailImageData {
                thumbnailImageData.withUnsafeBytes { rawBuffer in
                    _ = sqlite3_bind_blob(
                        statement, 8, rawBuffer.baseAddress, Int32(rawBuffer.count), SQLITE_TRANSIENT
                    )
                }
            } else {
                sqlite3_bind_null(statement, 8)
            }
        }
    }

    func insertPhoneNumber(recordID: Int64, ownerID: Int64, fullNumber: String) throws {
        try builder.run(
            "INSERT INTO ZABCDPHONENUMBER (Z_PK, ZOWNER, ZFULLNUMBER) VALUES (?, ?, ?)"
        ) { statement in
            sqlite3_bind_int64(statement, 1, recordID)
            sqlite3_bind_int64(statement, 2, ownerID)
            sqlite3_bind_text(statement, 3, fullNumber, -1, SQLITE_TRANSIENT)
        }
    }

    func insertEmailAddress(recordID: Int64, ownerID: Int64, address: String) throws {
        try builder.run(
            "INSERT INTO ZABCDEMAILADDRESS (Z_PK, ZOWNER, ZADDRESS) VALUES (?, ?, ?)"
        ) { statement in
            sqlite3_bind_int64(statement, 1, recordID)
            sqlite3_bind_int64(statement, 2, ownerID)
            sqlite3_bind_text(statement, 3, address, -1, SQLITE_TRANSIENT)
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
