import XCTest
@testable import GraphCore

final class ContactsDatabaseExtractionTests: XCTestCase {

    private let contactEntityID: Int64 = 1

    // Test 11: first+last+phone, email-only, and organization-only all extract with the
    // right phones/emails attached via ZOWNER; a fully empty record is excluded.
    func testMixedRecordShapesExtractCorrectly() throws {
        let fixture = try ContactsDBFixture()
        defer { fixture.close() }

        try fixture.insertEntity(entityID: contactEntityID, name: "ABCDContact")

        try fixture.insertRecord(recordID: 1, entityID: contactEntityID, uniqueID: "uid-1", firstName: "Jane", lastName: "Doe")
        try fixture.insertPhoneNumber(recordID: 10, ownerID: 1, fullNumber: "+15551230000")

        try fixture.insertRecord(recordID: 2, entityID: contactEntityID, uniqueID: "uid-2")
        try fixture.insertEmailAddress(recordID: 20, ownerID: 2, address: "person@example.com")

        try fixture.insertRecord(recordID: 3, entityID: contactEntityID, uniqueID: "uid-3", organization: "Acme Corp")

        // Fully empty record: no name, no organization, no phone, no email.
        try fixture.insertRecord(recordID: 4, entityID: contactEntityID, uniqueID: "uid-4")

        fixture.close()

        let records = try ContactsDatabase.extract(path: fixture.url.path)
        XCTAssertEqual(records.count, 3)
        XCTAssertFalse(records.contains { $0.recordID == 4 })

        let janeDoe = try XCTUnwrap(records.first { $0.recordID == 1 })
        XCTAssertEqual(janeDoe.firstName, "Jane")
        XCTAssertEqual(janeDoe.lastName, "Doe")
        XCTAssertEqual(janeDoe.phoneNumbers, ["+15551230000"])
        XCTAssertTrue(janeDoe.emails.isEmpty)

        let emailOnly = try XCTUnwrap(records.first { $0.recordID == 2 })
        XCTAssertNil(emailOnly.firstName)
        XCTAssertNil(emailOnly.lastName)
        XCTAssertNil(emailOnly.organization)
        XCTAssertEqual(emailOnly.emails, ["person@example.com"])
        XCTAssertTrue(emailOnly.phoneNumbers.isEmpty)

        let organizationOnly = try XCTUnwrap(records.first { $0.recordID == 3 })
        XCTAssertEqual(organizationOnly.organization, "Acme Corp")
        XCTAssertNil(organizationOnly.firstName)
        XCTAssertTrue(organizationOnly.phoneNumbers.isEmpty)
        XCTAssertTrue(organizationOnly.emails.isEmpty)
    }

    // ZABCDRECORD is a Core Data table shared by several entities. A row that carries a
    // name and a phone but belongs to a non-ABCDContact entity (e.g. ABCDInfo bookkeeping)
    // must never be extracted as a contact, even though it has the exact same column shape.
    func testRecordFromNonContactEntityIsExcludedEvenWithNameAndPhone() throws {
        let fixture = try ContactsDBFixture()
        defer { fixture.close() }

        let infoEntityID: Int64 = 2
        try fixture.insertEntity(entityID: contactEntityID, name: "ABCDContact")
        try fixture.insertEntity(entityID: infoEntityID, name: "ABCDInfo")

        // A non-contact entity row with a name and a phone: must be excluded.
        try fixture.insertRecord(recordID: 1, entityID: infoEntityID, uniqueID: "uid-1", firstName: "Ghost", lastName: "Bookkeeping")
        try fixture.insertPhoneNumber(recordID: 100, ownerID: 1, fullNumber: "+15550009999")

        // A real ABCDContact row with the same shape: must be included.
        try fixture.insertRecord(recordID: 2, entityID: contactEntityID, uniqueID: "uid-2", firstName: "Real", lastName: "Person")
        try fixture.insertPhoneNumber(recordID: 101, ownerID: 2, fullNumber: "+15551112222")

        fixture.close()

        let records = try ContactsDatabase.extract(path: fixture.url.path)

        XCTAssertEqual(records.count, 1)
        XCTAssertFalse(records.contains { $0.recordID == 1 }, "a non-ABCDContact entity row leaked in as a contact")

        let realPerson = try XCTUnwrap(records.first { $0.recordID == 2 })
        XCTAssertEqual(realPerson.firstName, "Real")
        XCTAssertEqual(realPerson.phoneNumbers, ["+15551112222"])
    }

    // An ABCDContact row whose only populated field is a phone number is still a real contact.
    func testABCDContactRecordWithOnlyPhoneIsIncluded() throws {
        let fixture = try ContactsDBFixture()
        defer { fixture.close() }

        try fixture.insertEntity(entityID: contactEntityID, name: "ABCDContact")
        try fixture.insertRecord(recordID: 1, entityID: contactEntityID, uniqueID: "uid-1")
        try fixture.insertPhoneNumber(recordID: 10, ownerID: 1, fullNumber: "+15553334444")
        fixture.close()

        let records = try ContactsDatabase.extract(path: fixture.url.path)

        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertNil(record.firstName)
        XCTAssertNil(record.lastName)
        XCTAssertNil(record.organization)
        XCTAssertEqual(record.phoneNumbers, ["+15553334444"])
    }

    // A store with no Z_PRIMARYKEY row named 'ABCDContact' is a schema we do not recognize:
    // stop with an error rather than guess which rows are contacts.
    func testMissingABCDContactEntityThrows() throws {
        let fixture = try ContactsDBFixture()
        defer { fixture.close() }

        // Some other entity exists, but never one named 'ABCDContact'.
        try fixture.insertEntity(entityID: 99, name: "ABCDInfo")
        fixture.close()

        XCTAssertThrowsError(try ContactsDatabase.extract(path: fixture.url.path))
    }

    // A record with a thumbnail blob round-trips it; a record with none yields nil.
    func testThumbnailImageDataRoundTripsAndNilWhenAbsent() throws {
        let fixture = try ContactsDBFixture()
        defer { fixture.close() }

        try fixture.insertEntity(entityID: contactEntityID, name: "ABCDContact")

        let photoBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46])
        try fixture.insertRecord(recordID: 1, entityID: contactEntityID, uniqueID: "uid-1", firstName: "Photo", thumbnailImageData: photoBytes)
        try fixture.insertRecord(recordID: 2, entityID: contactEntityID, uniqueID: "uid-2", firstName: "NoPhoto")

        fixture.close()

        let records = try ContactsDatabase.extract(path: fixture.url.path)

        let withPhoto = try XCTUnwrap(records.first { $0.recordID == 1 })
        XCTAssertEqual(withPhoto.thumbnailImageData, photoBytes)

        let withoutPhoto = try XCTUnwrap(records.first { $0.recordID == 2 })
        XCTAssertNil(withoutPhoto.thumbnailImageData)
    }

    // A row with a NULL ZUNIQUEID is not a real synced card (same posture as the entity
    // filter: do not guess), so it must be skipped even though it otherwise looks like a
    // perfectly good contact.
    func testRecordWithNullUniqueIDIsSkipped() throws {
        let fixture = try ContactsDBFixture()
        defer { fixture.close() }

        try fixture.insertEntity(entityID: contactEntityID, name: "ABCDContact")

        try fixture.insertRecord(recordID: 1, entityID: contactEntityID, uniqueID: nil, firstName: "No", lastName: "UniqueID")
        try fixture.insertPhoneNumber(recordID: 10, ownerID: 1, fullNumber: "+15559990000")

        try fixture.insertRecord(recordID: 2, entityID: contactEntityID, uniqueID: "uid-2", firstName: "Has", lastName: "UniqueID")

        fixture.close()

        let records = try ContactsDatabase.extract(path: fixture.url.path)

        XCTAssertEqual(records.count, 1)
        XCTAssertFalse(records.contains { $0.recordID == 1 }, "a NULL-ZUNIQUEID row leaked in as a contact")
        XCTAssertTrue(records.contains { $0.recordID == 2 })
    }
}
