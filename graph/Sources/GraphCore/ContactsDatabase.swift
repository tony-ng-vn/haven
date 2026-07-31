import Foundation
import SQLite3

/// Thrown when the abcddb store does not match the schema shape this reader understands.
public enum ContactsDatabaseError: Error, Sendable, Equatable {
    /// ZABCDRECORD is a Core Data table shared by several entities (contacts, groups,
    /// containers, internal bookkeeping). Without a Z_PRIMARYKEY row named 'ABCDContact'
    /// there is no reliable way to tell which rows are contacts, so extraction stops
    /// rather than guessing from column shape.
    case contactEntityNotFound
}

/// Reads AddressBook-v22.abcddb metadata into ContactRecord values.
/// Same read-only discipline as ChatDatabase: SQLITE_OPEN_READONLY only.
public struct ContactsDatabase: Sendable {
    private let path: String

    public init(path: String) {
        self.path = path
    }

    public static func extract(path: String) throws -> [ContactRecord] {
        try ContactsDatabase(path: path).extract()
    }

    public func extract() throws -> [ContactRecord] {
        let connection = try SQLiteReadOnlyConnection(path: path)
        let contactEntityID = try Self.readContactEntityID(connection)
        let phonesByOwner = try Self.readPhoneNumbers(connection)
        let emailsByOwner = try Self.readEmailAddresses(connection)

        var records: [ContactRecord] = []
        // contactEntityID is an Int64 read back from this same database, not external
        // input, so interpolating it here carries no injection risk.
        try connection.query(
            """
            SELECT Z_PK, ZFIRSTNAME, ZLASTNAME, ZORGANIZATION, ZNICKNAME
            FROM ZABCDRECORD
            WHERE Z_ENT = \(contactEntityID)
            ORDER BY Z_PK
            """
        ) { statement in
            let recordID = statement.columnInt64(0)
            let firstName = statement.columnText(1)
            let lastName = statement.columnText(2)
            let organization = statement.columnText(3)
            let nickname = statement.columnText(4)
            let phones = phonesByOwner[recordID] ?? []
            let emails = emailsByOwner[recordID] ?? []

            let hasAnyField = firstName != nil || lastName != nil || organization != nil
                || nickname != nil || !phones.isEmpty || !emails.isEmpty
            guard hasAnyField else { return }

            records.append(
                ContactRecord(
                    recordID: recordID,
                    firstName: firstName,
                    lastName: lastName,
                    organization: organization,
                    nickname: nickname,
                    phoneNumbers: phones,
                    emails: emails
                )
            )
        }
        return records
    }

    /// Core Data assigns entity ids per database, so the ABCDContact Z_ENT cannot be
    /// hardcoded: it has to be looked up in Z_PRIMARYKEY on every open (constraint: never
    /// guess which rows are contacts from column shape alone).
    private static func readContactEntityID(_ connection: SQLiteReadOnlyConnection) throws -> Int64 {
        var entityID: Int64?
        try connection.query(
            "SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = 'ABCDContact'"
        ) { statement in
            entityID = statement.columnInt64(0)
        }
        guard let entityID else {
            throw ContactsDatabaseError.contactEntityNotFound
        }
        return entityID
    }

    private static func readPhoneNumbers(_ connection: SQLiteReadOnlyConnection) throws -> [Int64: [String]] {
        var byOwner: [Int64: [String]] = [:]
        try connection.query(
            "SELECT ZOWNER, ZFULLNUMBER FROM ZABCDPHONENUMBER ORDER BY Z_PK"
        ) { statement in
            let owner = statement.columnInt64(0)
            guard let number = statement.columnText(1) else { return }
            byOwner[owner, default: []].append(number)
        }
        return byOwner
    }

    private static func readEmailAddresses(_ connection: SQLiteReadOnlyConnection) throws -> [Int64: [String]] {
        var byOwner: [Int64: [String]] = [:]
        try connection.query(
            "SELECT ZOWNER, ZADDRESS FROM ZABCDEMAILADDRESS ORDER BY Z_PK"
        ) { statement in
            let owner = statement.columnInt64(0)
            guard let address = statement.columnText(1) else { return }
            byOwner[owner, default: []].append(address)
        }
        return byOwner
    }
}
