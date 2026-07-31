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
            CREATE TABLE ZABCDRECORD (
                Z_PK INTEGER PRIMARY KEY,
                ZFIRSTNAME TEXT,
                ZLASTNAME TEXT,
                ZORGANIZATION TEXT,
                ZNICKNAME TEXT
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

    func insertRecord(
        recordID: Int64,
        firstName: String? = nil,
        lastName: String? = nil,
        organization: String? = nil,
        nickname: String? = nil
    ) throws {
        try builder.run(
            """
            INSERT INTO ZABCDRECORD (Z_PK, ZFIRSTNAME, ZLASTNAME, ZORGANIZATION, ZNICKNAME)
            VALUES (?, ?, ?, ?, ?)
            """
        ) { statement in
            sqlite3_bind_int64(statement, 1, recordID)
            Self.bindOptionalText(statement, 2, firstName)
            Self.bindOptionalText(statement, 3, lastName)
            Self.bindOptionalText(statement, 4, organization)
            Self.bindOptionalText(statement, 5, nickname)
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
